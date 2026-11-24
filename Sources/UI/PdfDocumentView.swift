import FossifyCommons
import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// PDFPage that inverts itself for "Dark pages" (PDFView nightMode).
final class NightModePdfPage: PDFPage {
    nonisolated(unsafe) static var invert = false

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        super.draw(with: box, to: context)
        guard Self.invert else { return }
        context.saveGState()
        context.setBlendMode(.difference)
        context.setFillColor(UIColor.white.cgColor)
        context.fill(bounds(for: box))
        context.restoreGState()
    }
}

struct PdfOutlineEntry: Identifiable {
    let id: Int
    let title: String
    let page: Int
    let depth: Int
}

/// PdfDocumentScreen.kt state + PdfSearchState.kt, on PDFKit.
@MainActor
@Observable
final class PdfModel: NSObject, PDFDocumentDelegate {
    var document: PDFDocument?
    var isLoading = true
    var error: String?
    var passwordRequested = false
    var invalidPassword = false
    var pageCount = 0
    var currentPage = 0
    var outline: [PdfOutlineEntry] = []
    @ObservationIgnored weak var pdfView: PDFView?

    // Search
    var searchActive = false
    var query = ""
    var matches: [PDFSelection] = []
    var matchIndex = 0
    var searchInProgress = false
    var hasText = true
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    func load(_ url: URL, password: String? = nil) {
        isLoading = true
        error = nil
        guard let doc = PDFDocument(url: url) else {
            isLoading = false
            error = "Could not open this document."
            return
        }
        doc.delegate = self
        if doc.isLocked {
            guard let password, doc.unlock(withPassword: password) else {
                invalidPassword = password != nil
                passwordRequested = true
                isLoading = false
                return
            }
        }
        passwordRequested = false
        invalidPassword = false
        document = doc
        pageCount = doc.pageCount
        outline = Self.flatten(doc.outlineRoot)
        isLoading = false
    }

    nonisolated func classForPage() -> AnyClass { NightModePdfPage.self }

    private static func flatten(_ root: PDFOutline?) -> [PdfOutlineEntry] {
        var result: [PdfOutlineEntry] = []
        func walk(_ node: PDFOutline, depth: Int) {
            for i in 0..<node.numberOfChildren {
                guard let child = node.child(at: i) else { continue }
                let page = child.destination?.page.flatMap { child.document?.index(for: $0) } ?? -1
                result.append(PdfOutlineEntry(id: result.count, title: child.label ?? "", page: page, depth: depth))
                walk(child, depth: depth + 1)
            }
        }
        if let root { walk(root, depth: 0) }
        return result
    }

    func go(to page: Int) {
        guard let doc = document, let p = doc.page(at: min(max(page, 0), max(pageCount - 1, 0))) else { return }
        pdfView?.go(to: p)
    }

    // MARK: search (PdfSearchState)

    func updateQuery(_ value: String) {
        query = value
        matchIndex = 0
        runSearch()
    }

    func closeSearch() {
        searchActive = false
        updateQuery("")
    }

    func retrySearch() { runSearch() }

    private func runSearch() {
        searchTask?.cancel()
        document?.cancelFindString()
        matches = []
        pdfView?.highlightedSelections = nil
        hasText = true
        searchInProgress = searchActive && !query.trimmingCharacters(in: .whitespaces).isEmpty
        guard searchInProgress else { return }
        let q = query
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled, self.query == q else { return }
            self.document?.beginFindString(q, withOptions: .caseInsensitive)
        }
    }

    nonisolated func didMatchString(_ instance: PDFSelection) {
        MainActor.assumeIsolated {
            instance.color = UIColor.systemYellow.withAlphaComponent(0.35)
            matches.append(instance)
            pdfView?.highlightedSelections = matches
            if matches.count == 1 { showMatch() }
        }
    }

    nonisolated func documentDidEndDocumentFind(_ notification: Notification) {
        MainActor.assumeIsolated {
            searchInProgress = false
            if matches.isEmpty, let doc = document {
                hasText = (0..<doc.pageCount).contains { !(doc.page(at: $0)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
        }
    }

    func changeMatch(_ direction: Int) {
        guard matches.indices.contains(matchIndex) else { return }
        matchIndex = ((matchIndex + direction) % matches.count + matches.count) % matches.count
        showMatch()
    }

    private func showMatch() {
        guard matches.indices.contains(matchIndex), let view = pdfView else { return }
        let selection = matches[matchIndex]
        view.setCurrentSelection(selection, animate: true)
        view.go(to: selection)
    }
}

/// PDFViewerActivity / ui/screens/PdfDocumentScreen.kt.
struct PdfDocumentView: View {
    @Environment(DocumentsStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let uri: String

    @State private var model = PdfModel()
    @State private var access: ScopedAccess?
    @State private var controlsVisible = true
    @State private var autoHidePending = true
    @State private var showOutline = false
    @State private var showGoToPage = false
    @State private var goToPageInput = ""
    @State private var passwordInput = ""
    @State private var exportCopy: URL?
    @State private var isCopying = false
    @State private var share: ShareItems?
    @State private var indicatorVisible = false
    @State private var title = ""

    var body: some View {
        ZStack {
            palette.neutralSurface(0.08).ignoresSafeArea()
            if let doc = model.document {
                PdfKitView(document: doc, model: model, startPage: startPage, horizontal: config.pdfHorizontalPaging,
                           nightMode: config.pdfDarkPages,
                           onTap: {
                               autoHidePending = false
                               if !model.searchActive { withAnimation { controlsVisible.toggle() } }
                           },
                           onPageChange: { page in
                               model.currentPage = page
                               store.updateLastPage(uri, page: page)
                               flashIndicator()
                           })
                    .id(config.pdfHorizontalPaging)
                    .ignoresSafeArea(edges: model.searchActive ? [] : .all)
            }
            if model.isLoading {
                ProgressView()
            } else if let error = model.error {
                Text(error).foregroundStyle(Color(argb: 0xFFBA1A1A)).padding(32)
            }
            if config.pdfPageIndicator && indicatorVisible && model.pageCount > 0 && !controlsVisible {
                Text("\(model.currentPage + 1) / \(model.pageCount)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.onPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(palette.primaryColor))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: config.pdfHorizontalPaging ? .bottom : .trailing)
                    .padding(16)
                    .transition(.opacity)
            }
            VStack(spacing: 0) {
                if controlsVisible {
                    VStack(spacing: 0) {
                        topBar
                        if isCopying || model.searchInProgress { ProgressView().progressViewStyle(.linear).tint(palette.primaryColor) }
                        searchStatus
                    }
                    .background(palette.backgroundColor.ignoresSafeArea(edges: .top))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                if controlsVisible && model.pageCount > 0 {
                    bottomControls.transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .statusBarHidden(!controlsVisible)
        .persistentSystemOverlays(controlsVisible ? .automatic : .hidden)
        .onAppear(perform: load)
        .onChange(of: config.pdfDarkPages) { NightModePdfPage.invert = config.pdfDarkPages }
        .onDisappear { model.document?.cancelFindString() }
        .alert("Enter password", isPresented: $model.passwordRequested) {
            SecureField("Password", text: $passwordInput)
            Button("OK") { if let access { model.load(access.url, password: passwordInput); afterLoad() } }
                .disabled(passwordInput.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) { dismiss() }
        } message: {
            if model.invalidPassword { Text("Incorrect password") }
        }
        .alert("Go to page", isPresented: $showGoToPage) {
            TextField("Page (1–\(model.pageCount))", text: $goToPageInput).keyboardType(.numberPad)
            Button("OK") { if let p = Int(goToPageInput), (1...max(model.pageCount, 1)).contains(p) { model.go(to: p - 1) } }
                .disabled(!(Int(goToPageInput).map { (1...max(model.pageCount, 1)).contains($0) } ?? false))
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showOutline) { outlineSheet }
        .sheet(item: $share) { ShareSheet(items: $0.urls) }
        .fileMover(isPresented: Binding(get: { exportCopy != nil }, set: { if !$0 { exportCopy = nil; isCopying = false } }), file: exportCopy) { result in
            isCopying = false
            switch result {
            case .success(let url):
                store.rememberDocument(url.absoluteString, picked: url)
                store.toast = "File saved successfully"
            case .failure:
                store.toast = "Could not save this document."
            }
        }
    }

    private var startPage: Int { config.rememberPdfPage ? store.document(uri)?.lastPage ?? 0 : 0 }

    private var copyData: Data {
        guard let access else { return Data() }
        return (try? Data(contentsOf: access.url)) ?? Data()
    }

    private func load() {
        guard model.document == nil else { return }
        NightModePdfPage.invert = config.pdfDarkPages
        title = store.document(uri)?.name ?? URL(string: uri)?.lastPathComponent ?? "Document"
        guard let access = store.access(uri) else {
            model.isLoading = false
            model.error = "Could not open this document."
            return
        }
        self.access = access
        model.currentPage = startPage
        model.load(access.url)
        afterLoad()
    }

    private func afterLoad() {
        guard model.document != nil else { return }
        store.rememberDocument(uri)
        // AutoHideInitialPdfControls.
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            if autoHidePending {
                autoHidePending = false
                withAnimation { controlsVisible = false }
            }
        }
    }

    private func flashIndicator() {
        guard config.pdfPageIndicator else { return }
        withAnimation { indicatorVisible = true }
        let page = model.currentPage
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if model.currentPage == page { withAnimation { indicatorVisible = false } }
        }
    }

    private func back() {
        if model.searchActive { model.closeSearch() } else { dismiss() }
    }

    private func print() {
        guard let access else { return }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.jobName = title
        info.outputType = .general
        controller.printInfo = info
        controller.printingItem = access.url
        controller.present(animated: true)
    }

    private func openWith() {
        guard let access else { return }
        if !Launcher.openWith(access.url) { store.toast = "No valid app found" }
    }

    // MARK: chrome (PdfViewerChrome.kt)

    private var topBar: some View {
        let loaded = model.document != nil
        return DocumentTopBar(
            title: title,
            onBack: back,
            search: model.searchActive
                ? (Binding(get: { model.query }, set: { model.updateQuery($0) }),
                   model.matches.indices.contains(model.matchIndex) ? model.matchIndex + 1 : 0,
                   model.matches.count, { model.changeMatch(1) })
                : nil
        ) {
            if model.searchActive {
                IconButton(icon: "chevron.up") { model.changeMatch(-1) }.disabled(model.matches.isEmpty)
                IconButton(icon: "chevron.down") { model.changeMatch(1) }.disabled(model.matches.isEmpty)
            } else {
                IconButton(icon: "magnifyingglass") {
                    model.pdfView?.clearSelection()
                    model.searchActive = true
                }
                .disabled(!loaded)
                IconButton(icon: "square.and.arrow.up") { if let access { share = ShareItems([access.url]) } }.disabled(!loaded)
                if !model.outline.isEmpty {
                    IconButton(icon: "list.bullet") { showOutline = true }.disabled(!loaded).accessibilityLabel("Contents")
                } else {
                    IconButton(icon: "printer") { print() }.disabled(!loaded)
                }
                readingMenu(loaded: loaded)
            }
        }
    }

    /// PdfReadingControls.kt PdfReadingMenu.
    private func readingMenu(loaded: Bool) -> some View {
        @Bindable var config = config
        return OverflowMenu {
            Button("Go to page") { goToPageInput = "\(model.currentPage + 1)"; showGoToPage = true }.disabled(!loaded)
            Toggle("Dark pages", isOn: $config.pdfDarkPages)
            Button("Save a copy") {
                isCopying = true
                exportCopy = TemporaryFile.make(name: title.lowercased().hasSuffix(".pdf") ? title : title + ".pdf", data: copyData)
            }.disabled(!loaded || isCopying)
            if !model.outline.isEmpty {
                Button("Print") { print() }.disabled(!loaded)
            }
            Button("Open with") { openWith() }
            Button("Settings") { router.push(.settings) }
        }
    }

    /// PdfSearchStatus.
    @ViewBuilder
    private var searchStatus: some View {
        if model.searchActive && !model.searchInProgress && !model.query.trimmingCharacters(in: .whitespaces).isEmpty {
            if !model.hasText {
                StatusStrip(text: "This PDF has no searchable text.", isError: false)
            } else if model.matches.isEmpty {
                StatusStrip(text: "No results found", isError: false)
            }
        }
    }

    /// PdfControls.
    private var bottomControls: some View {
        HStack(spacing: 2) {
            IconButton(icon: "chevron.left") { model.go(to: model.currentPage - 1) }
                .disabled(model.currentPage <= 0)
                .accessibilityLabel("Previous page")
            Button {
                goToPageInput = "\(model.currentPage + 1)"
                showGoToPage = true
            } label: {
                Text("\(model.currentPage + 1) / \(model.pageCount)")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 40)
            }
            .accessibilityLabel("Page \(model.currentPage + 1) of \(model.pageCount). Go to page.")
            IconButton(icon: "chevron.right") { model.go(to: model.currentPage + 1) }
                .disabled(model.currentPage >= model.pageCount - 1)
                .accessibilityLabel("Next page")
            Spacer()
            IconButton(icon: "minus.magnifyingglass") {
                if let v = model.pdfView { v.scaleFactor = max(v.scaleFactor - 0.5 * v.scaleFactorForSizeToFit, v.minScaleFactor) }
            }
            .accessibilityLabel("Zoom out")
            IconButton(icon: "plus.magnifyingglass") {
                if let v = model.pdfView { v.scaleFactor = min(v.scaleFactor + 0.5 * v.scaleFactorForSizeToFit, v.maxScaleFactor) }
            }
            .accessibilityLabel("Zoom in")
        }
        .foregroundStyle(palette.textColor)
        .padding(.horizontal, 8)
        .frame(height: 64)
        .background(palette.backgroundColor.shadow(color: .black.opacity(0.2), radius: 6).ignoresSafeArea(edges: .bottom))
    }

    /// PdfOutlineSheet.
    private var outlineSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Contents").font(.system(size: 22, weight: .medium)).padding(.horizontal, 24).padding(.vertical, 16)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.outline) { entry in
                        Button {
                            guard entry.page >= 0 else { return }
                            model.go(to: entry.page)
                            showOutline = false
                        } label: {
                            HStack(spacing: 16) {
                                Text(entry.title).font(.system(size: 16)).foregroundStyle(palette.textColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if entry.page >= 0 {
                                    Text("\(entry.page + 1)").foregroundStyle(palette.secondaryText)
                                }
                            }
                            .padding(.leading, 24 + 16 * CGFloat(entry.depth))
                            .padding(.trailing, 24)
                            .padding(.vertical, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(palette.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// PdfPageView.kt: PDFView in vertical continuous or horizontal paged mode.
private struct PdfKitView: UIViewRepresentable {
    let document: PDFDocument
    let model: PdfModel
    let startPage: Int
    let horizontal: Bool
    let nightMode: Bool
    let onTap: () -> Void
    let onPageChange: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.backgroundColor = .clear
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = horizontal ? .horizontal : .vertical
        view.displaysPageBreaks = true
        if horizontal { view.usePageViewController(true, withViewOptions: nil) }
        view.document = document
        context.coordinator.night = nightMode
        model.pdfView = view
        if let page = document.page(at: min(max(startPage, 0), max(document.pageCount - 1, 0))) {
            DispatchQueue.main.async { view.go(to: page) }
        }
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged(_:)),
                                               name: .PDFViewPageChanged, object: view)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        model.pdfView = view
        if context.coordinator.night != nightMode {
            // Re-render every page with the new inversion.
            context.coordinator.night = nightMode
            NightModePdfPage.invert = nightMode
            let page = view.currentPage
            view.document = nil
            view.document = document
            if let page { view.go(to: page) }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PdfKitView
        var night = false

        init(_ parent: PdfKitView) { self.parent = parent }

        @objc func pageChanged(_ n: Notification) {
            guard let view = n.object as? PDFView, let page = view.currentPage, let doc = view.document else { return }
            parent.onPageChange(doc.index(for: page))
        }

        @objc func tapped() { parent.onTap() }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
