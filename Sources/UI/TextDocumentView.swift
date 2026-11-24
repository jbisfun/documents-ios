import FossifyCommons
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// viewmodels/TextDocumentViewModel.kt.
@MainActor
@Observable
final class TextDocumentModel {
    var title = ""
    var kind: DocumentKind = .text
    var text = ""
    var isLoading = false
    var isLoaded = false
    var isSaving = false
    var isReadOnly = false
    var canSaveCopy = false
    var readOnlyReason: String?
    var isDirty = false
    var previewEnabled = false
    var error: String?

    @ObservationIgnored private(set) var uri = ""
    @ObservationIgnored private var encoding: TextDocumentEncoding?
    @ObservationIgnored private var originalText = ""
    /// Bumped whenever `text` is replaced from outside the editor (load, markdown action).
    var revision = 0

    var isMarkdown: Bool { kind == .markdown }

    func load(_ store: DocumentsStore, uri: String, kind: DocumentKind, force: Bool = false) {
        guard force || self.uri.isEmpty else { return }
        self.uri = uri
        self.kind = kind
        encoding = nil
        title = store.document(uri)?.name ?? URL(string: uri)?.lastPathComponent ?? ""
        isLoading = true
        isLoaded = false
        error = nil
        isDirty = false
        previewEnabled = kind == .markdown
        guard let access = store.access(uri), let data = try? Data(contentsOf: access.url) else {
            isLoading = false
            error = "Could not open this document."
            return
        }
        let decoded = TextDocumentCodec.decode(data)
        encoding = decoded.encoding
        originalText = decoded.text
        text = decoded.text
        revision += 1
        isLoading = false
        isLoaded = true
        isReadOnly = decoded.encoding == nil || !DocumentAccess.isWritable(access.url)
        canSaveCopy = decoded.encoding != nil
        readOnlyReason = decoded.encoding == nil ? "Read-only because this text encoding is not supported." : nil
        previewEnabled = previewEnabled && !decoded.text.isEmpty
    }

    func onTextChange(_ value: String) {
        text = value
        isDirty = value != originalText
    }

    func replaceText(_ value: String) {
        onTextChange(value)
        revision += 1
    }

    /// save(): writes back with the original encoding.
    @discardableResult
    func save(_ store: DocumentsStore) -> Bool {
        guard !isReadOnly, isLoaded, !isSaving, let encoding, let access = store.access(uri) else { return false }
        isSaving = true
        error = nil
        let saved = text
        defer { isSaving = false }
        do {
            try TextDocumentCodec.encode(saved, encoding).write(to: access.url, options: .atomic)
            originalText = saved
            isDirty = text != saved
            store.refreshDocumentMetadata(uri)
            isReadOnly = !DocumentAccess.isWritable(access.url)
            return true
        } catch {
            self.error = error.localizedDescription.isEmpty ? "Could not save this document." : error.localizedDescription
            return false
        }
    }

    var copyData: Data { TextDocumentCodec.encode(text, encoding ?? .utf8) }

    /// saveCopy(): the copy becomes the open document.
    func didSaveCopy(_ store: DocumentsStore, at url: URL) {
        let wasReadOnly = isReadOnly
        guard store.prepareDocument(url.absoluteString, picked: url) else {
            error = "Could not save this document."
            return
        }
        let current = text
        uri = url.absoluteString
        title = url.lastPathComponent
        originalText = current
        isDirty = false
        isReadOnly = !store.isDocumentWritable(uri)
        readOnlyReason = nil
        if wasReadOnly { previewEnabled = false }
    }
}

/// TextDocumentActivity / ui/screens/TextDocumentScreen.kt: plain text and Markdown editor.
struct TextDocumentView: View {
    @Environment(DocumentsStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let uri: String
    let kind: DocumentKind

    @State private var model = TextDocumentModel()
    @State private var editor = EditorController()
    @State private var searchActive = false
    @State private var searchQuery = ""
    @State private var currentSearchIndex = 0
    @State private var showDiscardDialog = false
    @State private var showReopenDialog = false
    @State private var exportCopy: URL?
    @State private var reopenPicker = false
    @State private var heldAccess: ScopedAccess?

    private var matches: [NSRange] { findTextMatches(model.text, searchQuery) }
    private var normalizedIndex: Int { matches.isEmpty ? 0 : ((currentSearchIndex % matches.count) + matches.count) % matches.count }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .onAppear { model.load(store, uri: uri, kind: kind) }
        .onChange(of: searchQuery) { currentSearchIndex = 0; selectCurrentMatch() }
        .onChange(of: normalizedIndex) { selectCurrentMatch() }
        .onChange(of: matches.count) { selectCurrentMatch() }
        .alert("Unsaved changes", isPresented: $showDiscardDialog) {
            Button("Save") { if model.save(store) { dismiss() } }
            Button("Discard", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved changes. Save before exit?")
        }
        .alert("Reopen to edit", isPresented: $showReopenDialog) {
            Button("Open file") { reopenPicker = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Select this file again to request permission to save changes to it.")
        }
        .fileMover(isPresented: Binding(get: { exportCopy != nil }, set: { if !$0 { exportCopy = nil } }), file: exportCopy) { result in
            if case .success(let url) = result {
                model.didSaveCopy(store, at: url)
                store.toast = "Copy saved and opened"
            }
        }
        .fileImporter(isPresented: $reopenPicker, allowedContentTypes: DocumentKind.openableTypes) { result in
            guard case .success(let url) = result else { return }
            let newKind = DocumentKind.from(url: url)
            guard [.text, .markdown, .csv].contains(newKind) else {
                store.toast = "This document type is not supported yet."
                return
            }
            if store.prepareDocument(url.absoluteString, picked: url) {
                model.load(store, uri: url.absoluteString, kind: newKind, force: true)
            }
        }
    }

    private func requestClose() {
        if searchActive {
            closeSearch()
        } else if model.isDirty {
            showDiscardDialog = true
        } else {
            dismiss()
        }
    }

    private func closeSearch() {
        searchActive = false
        searchQuery = ""
        currentSearchIndex = 0
        editor.highlight([], current: 0, palette: palette)
    }

    private func selectCurrentMatch() {
        editor.highlight(matches, current: normalizedIndex, palette: palette)
        if matches.indices.contains(normalizedIndex) { editor.select(matches[normalizedIndex]) }
    }

    private func setZoom(_ zoom: Double) { config.editorTextZoom = coerceDocumentTextZoom(zoom) }

    // MARK: top bar

    private var topBar: some View {
        DocumentTopBar(
            title: model.title.isEmpty ? "Document" : model.title,
            onBack: requestClose,
            search: searchActive ? ($searchQuery, matches.isEmpty ? 0 : normalizedIndex + 1, matches.count, { currentSearchIndex = normalizedIndex + 1 }) : nil
        ) {
            if searchActive {
                IconButton(icon: "chevron.up") { currentSearchIndex = normalizedIndex - 1 }.disabled(matches.isEmpty)
                IconButton(icon: "chevron.down") { currentSearchIndex = normalizedIndex + 1 }.disabled(matches.isEmpty)
            } else {
                IconButton(icon: "magnifyingglass") {
                    if model.previewEnabled { model.previewEnabled = false }
                    searchActive = true
                }
                if !model.isReadOnly {
                    IconButton(icon: "square.and.arrow.down") { model.save(store) }
                        .opacity(model.isDirty ? 1 : 0.45)
                        .disabled(!model.isDirty || model.isSaving || model.isLoading)
                }
                overflowMenu
            }
        }
    }

    /// TextDocumentControls.kt TextDocumentOverflowMenu.
    private var overflowMenu: some View {
        OverflowMenu {
            Button(model.isReadOnly ? "Edit a copy" : "Save as") {
                exportCopy = TemporaryFile.make(name: model.title.isEmpty ? "Untitled.txt" : model.title, data: model.copyData)
            }
                .disabled(!(model.canSaveCopy && !model.isSaving))
            if model.isReadOnly && model.canSaveCopy {
                Button("Reopen to edit") { showReopenDialog = true }
            }
            Button("Open with") { openWith() }
            Button("Zoom in") { setZoom(config.editorTextZoom + documentTextZoomStep) }
                .disabled(config.editorTextZoom >= maxDocumentTextZoom)
            Button("Zoom out") { setZoom(config.editorTextZoom - documentTextZoomStep) }
                .disabled(config.editorTextZoom <= minDocumentTextZoom)
            Button("Reset zoom") { setZoom(defaultDocumentTextZoom) }
                .disabled(config.editorTextZoom == defaultDocumentTextZoom)
        }
    }

    private func openWith() {
        guard let access = store.access(model.uri) else { return }
        heldAccess = access
        if !Launcher.openWith(access.url) { store.toast = "No valid app found" }
    }

    // MARK: content

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            LoadingDocument()
        } else if !model.isLoaded, let error = model.error {
            StatusDocument(text: error, isError: true)
        } else {
            if model.isMarkdown { modeRow }
            notices
            Group {
                if model.previewEnabled && model.isMarkdown {
                    MarkdownPreview(markdown: model.text, zoom: config.editorTextZoom, onZoom: setZoom)
                } else {
                    DocumentTextView(controller: editor, model: model, zoom: config.editorTextZoom, onZoom: setZoom,
                                     onChange: { model.onTextChange($0); if searchActive { editor.highlight(matches, current: normalizedIndex, palette: palette) } })
                        .padding(.horizontal, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            statusBar
            if model.isMarkdown && !model.previewEnabled && !model.isReadOnly { formattingToolbar }
        }
    }

    /// MarkdownModeRow: Edit / Preview segmented buttons.
    private var modeRow: some View {
        Picker("", selection: Binding(get: { model.previewEnabled }, set: { model.previewEnabled = $0 })) {
            Text("Edit").tag(false)
            Text("Preview").tag(true)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// TextDocumentNotices.
    @ViewBuilder
    private var notices: some View {
        if model.isReadOnly {
            StatusStrip(text: model.readOnlyReason ?? "Read-only", isError: false) {
                if model.canSaveCopy && !model.isSaving {
                    Button("Reopen to edit") { showReopenDialog = true }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.primaryColor)
                }
            }
        }
        if let error = model.error { StatusStrip(text: error, isError: true) }
    }

    /// EditorStatusBar.
    private var statusBar: some View {
        let status = model.isReadOnly ? "Read-only" : model.isSaving ? "Saving…" : model.isDirty ? "Unsaved changes" : "Saved"
        return HStack {
            Text(documentStats(model.text)).font(.system(size: 14))
            Spacer()
            Text(status).font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(palette.textColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(palette.primaryTint)
    }

    /// MarkdownFormattingToolbar.kt.
    private var formattingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(MarkdownEditAction.allCases, id: \.self) { action in
                    Button {
                        let sel = editor.selection
                        let result = action.apply(text: model.text, selection: sel)
                        model.replaceText(result.text)
                        editor.setText(result.text, selection: result.selection)
                    } label: {
                        Image(systemName: action.icon).font(.system(size: 17)).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(action.title)
                    .foregroundStyle(palette.textColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
    }
}

/// Owns the UITextView so the screen can read and set the selection (markdown actions, find).
@MainActor
final class EditorController {
    weak var textView: UITextView?
    private var highlighted: [NSRange] = []

    var selection: NSRange { textView?.selectedRange ?? NSRange(location: 0, length: 0) }

    func setText(_ text: String, selection: NSRange) {
        guard let tv = textView else { return }
        tv.text = text
        tv.selectedRange = selection
        tv.scrollRangeToVisible(selection)
    }

    func select(_ range: NSRange) {
        guard let tv = textView, NSMaxRange(range) <= (tv.text as NSString).length else { return }
        tv.selectedRange = range
        tv.scrollRangeToVisible(range)
    }

    /// rememberSearchHighlighting(): background on every match, stronger on the current one.
    func highlight(_ matches: [NSRange], current: Int, palette: Palette) {
        guard let storage = textView?.textStorage else { return }
        let length = storage.length
        storage.beginEditing()
        for r in highlighted where NSMaxRange(r) <= length { storage.removeAttribute(.backgroundColor, range: r) }
        highlighted = []
        if (1...maxSearchHighlightCount).contains(matches.count) {
            let accent = UIColor(palette.primaryColor)
            for (i, r) in matches.enumerated() where NSMaxRange(r) <= length {
                storage.addAttribute(.backgroundColor, value: accent.withAlphaComponent(i == current ? 0.5 : 0.18), range: r)
                highlighted.append(r)
            }
        }
        storage.endEditing()
    }
}

/// BasicTextField editor with pinch-to-zoom (documentTextZoomGesture).
struct DocumentTextView: UIViewRepresentable {
    @Environment(\.palette) private var palette
    let controller: EditorController
    let model: TextDocumentModel
    let zoom: Double
    let onZoom: (Double) -> Void
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.autocorrectionType = .no
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 24, right: 0)
        tv.addGestureRecognizer(UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:))))
        controller.textView = tv
        tv.text = model.text
        context.coordinator.revision = model.revision
        apply(tv)
        if !model.isReadOnly && model.text.isEmpty { DispatchQueue.main.async { tv.becomeFirstResponder() } }
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        controller.textView = tv
        if context.coordinator.revision != model.revision {
            context.coordinator.revision = model.revision
            if tv.text != model.text { tv.text = model.text }
        }
        apply(tv)
    }

    private func apply(_ tv: UITextView) {
        tv.isEditable = !model.isReadOnly
        tv.tintColor = UIColor(palette.primaryColor)
        let font = UIFont.systemFont(ofSize: 16 * zoom)
        if tv.font != font {
            tv.font = font
            let style = NSMutableParagraphStyle()
            style.minimumLineHeight = 24 * zoom
            tv.typingAttributes = [.font: font, .foregroundColor: UIColor(palette.textColor), .paragraphStyle: style]
            let range = NSRange(location: 0, length: tv.textStorage.length)
            tv.textStorage.addAttributes([.font: font, .paragraphStyle: style], range: range)
        }
        tv.textColor = UIColor(palette.textColor)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: DocumentTextView
        var revision = 0
        private var startZoom = 1.0

        init(_ parent: DocumentTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) { parent.onChange(textView.text) }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began: startZoom = parent.zoom
            case .changed: parent.onZoom(coerceDocumentTextZoom(startZoom * Double(g.scale)))
            default: break
            }
        }
    }
}
