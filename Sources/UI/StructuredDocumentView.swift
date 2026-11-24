import FossifyCommons
import SwiftUI
import UIKit
import WebKit

/// viewmodels/StructuredDocumentViewModel.kt + data/StructuredDocumentLoader.kt.
@MainActor
@Observable
final class StructuredDocumentModel {
    enum Content {
        case web(html: String)
        case docx(URL)
        case table(rows: [[String]], columnCount: Int)
    }

    var title = ""
    var content: Content?
    var canEdit = false
    var isLoading = false
    var error: String?
    @ObservationIgnored private var loadedURI: String?

    func load(_ store: DocumentsStore, uri: String, kind: DocumentKind, force: Bool = false) {
        guard force || loadedURI != uri else { return }
        loadedURI = uri
        title = store.document(uri)?.name ?? URL(string: uri)?.lastPathComponent ?? ""
        isLoading = true
        error = nil
        guard let access = store.access(uri), DocumentAccess.isReadable(access.url) else {
            isLoading = false
            error = "This document is no longer available. Open it again to restore access."
            return
        }
        do {
            switch kind {
            case .docx:
                // WebKit renders Word documents itself (through QuickLook) from a local copy.
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("docx", isDirectory: true)
                try? FileManager.default.removeItem(at: dir)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let copy = dir.appendingPathComponent("document.docx")
                try FileManager.default.copyItem(at: access.url, to: copy)
                content = .docx(copy)
            case .csv:
                let decoded = TextDocumentCodec.decode(try Data(contentsOf: access.url))
                let table = CsvDocumentParser.parse(decoded.text, fileName: title)
                content = .table(rows: table.rows, columnCount: table.columnCount)
                canEdit = decoded.encoding != nil
            default:
                content = .web(html: TextDocumentCodec.decode(try Data(contentsOf: access.url)).text)
            }
        } catch {
            self.error = "Could not open this document."
        }
        isLoading = false
    }
}

/// StructuredDocumentActivity / ui/screens/StructuredDocumentScreen.kt: DOCX, HTML and CSV viewer.
struct StructuredDocumentView: View {
    @Environment(DocumentsStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let uri: String
    let kind: DocumentKind

    @State private var model = StructuredDocumentModel()
    @State private var search = WebSearch()
    @State private var searchActive = false
    @State private var appeared = false
    @State private var share: ShareItems?
    @State private var heldAccess: ScopedAccess?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                if model.isLoading {
                    LoadingDocument()
                } else if let error = model.error {
                    StatusDocument(text: error, isError: true)
                } else if let content = model.content {
                    switch content {
                    case .web(let html): WebDocument(source: .html(html), search: search)
                    case .docx(let url): WebDocument(source: .file(url), search: search)
                    case .table(let rows, let count): CsvTable(rows: rows, columnCount: count)
                    }
                } else {
                    StatusDocument(text: "Empty document", isError: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .onAppear {
            // Reloads after "Edit as text" returns.
            model.load(store, uri: uri, kind: kind, force: appeared)
            appeared = true
        }
        .sheet(item: $share, onDismiss: { heldAccess = nil }) { ShareSheet(items: $0.urls) }
    }

    private var isWeb: Bool {
        if case .table = model.content { return false }
        return model.content != nil && !model.isLoading
    }

    private func closeSearch() {
        searchActive = false
        search.update("")
    }

    private var topBar: some View {
        DocumentTopBar(
            title: model.title.isEmpty ? "Document" : model.title,
            onBack: { if searchActive { closeSearch() } else { dismiss() } },
            search: searchActive ? (Binding(get: { search.query }, set: { search.update($0) }), search.currentMatchNumber,
                                    search.matchCount, { search.move(forward: true) }) : nil
        ) {
            if searchActive {
                IconButton(icon: "chevron.up") { search.move(forward: false) }.disabled(search.matchCount == 0)
                IconButton(icon: "chevron.down") { search.move(forward: true) }.disabled(search.matchCount == 0)
            } else {
                if isWeb {
                    IconButton(icon: "magnifyingglass") { searchActive = true }
                }
                IconButton(icon: "square.and.arrow.up") {
                    guard let access = store.access(uri) else { return }
                    heldAccess = access
                    share = ShareItems([access.url])
                }
                if model.canEdit && kind == .csv {
                    IconButton(icon: "pencil") { router.push(.text(uri, .csv)) }
                        .accessibilityLabel("Edit as text")
                }
                IconButton(icon: "arrow.up.forward.app") {
                    guard let access = store.access(uri) else { return }
                    heldAccess = access
                    if !Launcher.openWith(access.url) { store.toast = "No valid app found" }
                }
                .accessibilityLabel("Open with")
            }
        }
    }
}

/// CsvTable: sticky header row, zebra rows, column widths from the longest value.
private struct CsvTable: View {
    @Environment(\.palette) private var palette
    let rows: [[String]]
    let columnCount: Int

    var body: some View {
        if rows.isEmpty || columnCount == 0 {
            StatusDocument(text: "Empty document", isError: false)
        } else {
            let widths = (0..<columnCount).map { c in
                CGFloat(min(max(rows.map { $0.indices.contains(c) ? $0[c].count : 0 }.max() ?? 0, 8), 28) * 8 + 24)
            }
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    row(rows[0], widths, header: true, shaded: false)
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(1..<rows.count, id: \.self) { i in
                                row(rows[i], widths, header: false, shaded: (i - 1) % 2 == 1)
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(_ values: [String], _ widths: [CGFloat], header: Bool, shaded: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(widths.indices, id: \.self) { i in
                Text(values.indices.contains(i) ? values[i] : "")
                    .font(.system(size: 14, weight: header ? .semibold : .regular))
                    .foregroundStyle(palette.textColor)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(width: widths[i], alignment: .leading)
                    .frame(minHeight: 48, maxHeight: .infinity, alignment: .leading)
                    .border(palette.textColor.opacity(0.2), width: 0.5)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(header ? palette.primaryTint : shaded ? palette.neutralSurface(0.06) : palette.backgroundColor)
    }
}

// MARK: web documents

/// WebDocumentSearchState.kt: find-in-page through a script in WebKit's isolated client world
/// (page scripts stay disabled).
@MainActor
@Observable
final class WebSearch {
    private(set) var query = ""
    private(set) var activeMatchIndex = 0
    private(set) var matchCount = 0
    @ObservationIgnored weak var webView: WKWebView?
    @ObservationIgnored var pageReady = false

    var currentMatchNumber: Int { matchCount > 0 ? activeMatchIndex + 1 : 0 }

    func update(_ value: String) {
        guard value != query else { return }
        query = value
        activeMatchIndex = 0
        matchCount = 0
        find()
    }

    func pageFinished() {
        pageReady = true
        if !query.isEmpty { find() }
    }

    func move(forward: Bool) {
        guard matchCount > 0 else { return }
        activeMatchIndex = ((activeMatchIndex + (forward ? 1 : -1)) % matchCount + matchCount) % matchCount
        focus()
    }

    private func find() {
        guard let webView, pageReady else { return }
        let q = query
        webView.callAsyncJavaScript(Self.findScript, arguments: ["q": q], in: nil, in: .defaultClient) { [weak self] result in
            guard let self, self.query == q else { return }
            self.matchCount = (try? result.get()) as? Int ?? 0
            self.activeMatchIndex = 0
            if self.matchCount > 0 { self.focus() }
        }
    }

    private func focus() {
        webView?.callAsyncJavaScript(Self.focusScript, arguments: ["i": activeMatchIndex], in: nil, in: .defaultClient)
    }

    private static let findScript = """
    document.querySelectorAll('mark.fossify-find').forEach(m => {
      const p = m.parentNode; p.replaceChild(document.createTextNode(m.textContent), m); p.normalize();
    });
    if (!q || !document.body) return 0;
    const lq = q.toLowerCase();
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, { acceptNode: n =>
      /^(SCRIPT|STYLE|NOSCRIPT|TITLE)$/.test(n.parentNode.nodeName) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT });
    const nodes = []; while (walker.nextNode()) nodes.push(walker.currentNode);
    let count = 0;
    for (const node of nodes) {
      const text = node.nodeValue, lower = text.toLowerCase();
      let i = lower.indexOf(lq); if (i < 0) continue;
      const frag = document.createDocumentFragment(); let last = 0;
      while (i >= 0) {
        frag.appendChild(document.createTextNode(text.slice(last, i)));
        const m = document.createElement('mark'); m.className = 'fossify-find'; m.textContent = text.slice(i, i + q.length);
        frag.appendChild(m); count++; last = i + q.length; i = lower.indexOf(lq, last);
      }
      frag.appendChild(document.createTextNode(text.slice(last)));
      node.parentNode.replaceChild(frag, node);
    }
    return count;
    """

    private static let focusScript = """
    const ms = document.querySelectorAll('mark.fossify-find');
    ms.forEach((m, n) => m.classList.toggle('current', n === i));
    if (ms[i]) ms[i].scrollIntoView({ block: 'center' });
    return ms.length;
    """
}

/// WebDocument: sanitized rendering with page scripts off and network loads blocked
/// (HtmlDocumentSanitizer.kt + WebView settings), themed through injected CSS (buildWebPage()).
private struct WebDocument: UIViewRepresentable {
    enum Source: Equatable {
        case html(String)
        case file(URL)
    }

    @Environment(\.palette) private var palette
    let source: Source
    let search: WebSearch

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        config.dataDetectorTypes = []
        config.userContentController.addUserScript(WKUserScript(
            source: "var s = document.createElement('style'); s.textContent = \(jsString(css)); (document.head || document.documentElement).appendChild(s);"
                + "if (!document.querySelector('meta[name=viewport]')) { var v = document.createElement('meta'); v.name = 'viewport'; v.content = 'width=device-width, initial-scale=1'; (document.head || document.documentElement).appendChild(v); }",
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.navigationDelegate = context.coordinator
        context.coordinator.search = search
        search.webView = web
        search.pageReady = false
        // Block every remote load (blockNetworkLoads); only inline data: images remain.
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "fossify-documents-offline",
            encodedContentRuleList: #"[{"trigger":{"url-filter":"^(https?|ftp|wss?)://","resource-type":["image","style-sheet","script","font","raw","svg-document","media","popup","ping","fetch","websocket","other"]},"action":{"type":"block"}}]"#
        ) { list, _ in
            if let list { web.configuration.userContentController.add(list) }
            load(web)
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        search.webView = web
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading()
    }

    private func load(_ web: WKWebView) {
        switch source {
        case .html(let html): web.loadHTMLString(html, baseURL: URL(string: "https://documents.fossify.local/"))
        case .file(let url): web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    private var css: String {
        func c(_ color: Color) -> String {
            let v = color.argb
            return String(format: "rgba(%d, %d, %d, %.3f)", (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF, Double((v >> 24) & 0xFF) / 255)
        }
        let bg = c(palette.backgroundColor), text = c(palette.textColor), accent = c(palette.primaryColor)
        let outline = c(palette.textColor.opacity(0.25)), code = c(palette.neutralSurface(0.08))
        let match = c(palette.primaryColor.opacity(0.18)), current = c(palette.primaryColor.opacity(0.5))
        return """
        :root { color-scheme: light dark; }
        html { background: \(bg); font-family: -apple-system, sans-serif; }
        body { box-sizing: border-box; max-width: 900px; min-height: 100vh; margin: 0 auto; padding: 20px;
          background: \(bg) !important; color: \(text) !important; font-size: 16px; line-height: 1.55; overflow-wrap: anywhere; }
        mark.fossify-find { background-color: \(match); color: \(text); }
        mark.fossify-find.current { background-color: \(current); color: \(text); }
        a { color: \(accent); }
        img { max-width: 100%; height: auto; }
        table { display: block; max-width: 100%; overflow-x: auto; border-collapse: collapse; }
        th, td { padding: 8px 10px; border: 1px solid \(outline); text-align: start; }
        blockquote { margin-inline: 0; padding-inline-start: 14px; border-inline-start: 3px solid \(accent); }
        pre { overflow-x: auto; padding: 12px; background: \(code); border-radius: 6px; }
        code { font-family: ui-monospace, monospace; }
        """
    }

    private func jsString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s])
        let array = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var search: WebSearch?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in self.search?.pageFinished() }
        }

        /// shouldOverrideUrlLoading(): in-page anchors stay, allowed links open outside, the rest is dropped.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated, let url = action.request.url else {
                decisionHandler(.allow)
                return
            }
            if url.fragment != nil, url.absoluteString.hasPrefix(webView.url?.absoluteString.components(separatedBy: "#").first ?? "\u{0}") {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            if isAllowedExternalDocumentLink(url.absoluteString) {
                Task { @MainActor in Launcher.open(url) }
            }
        }
    }
}
