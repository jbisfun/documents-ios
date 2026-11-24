import FossifyCommons
import SwiftUI
import UniformTypeIdentifiers

/// MainActivity / ui/screens/MainScreen.kt: home, recent, favorites, folders and folder browsing.
struct MainView: View {
    @Environment(DocumentsStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette

    private enum Picker { case document, folder }

    @State private var focusedSearchActive = false
    @State private var picker: Picker = .document
    @State private var showPicker = false
    @State private var newFileKind: DocumentKind = .text
    @State private var newFile: URL?
    @State private var share: ShareItems?
    @State private var heldAccess: [ScopedAccess] = []

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            topBar
            ScrollView {
                LazyVStack(spacing: 0) {
                    if store.isCollectionScreen { focusedScreenItems } else { homeScreenItems }
                }
                .padding(.bottom, 104)
                .animation(.default, value: store.selectedDocumentKeys)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            if !store.hasSelection { importAction.padding(16) }
        }
        .onChange(of: store.homeSection) { if !store.isCollectionScreen { focusedSearchActive = false } }
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: picker == .folder ? [.folder] : DocumentKind.openableTypes) { result in
            guard case .success(let url) = result else { return }
            if picker == .folder {
                store.rememberFolder(url)
            } else {
                openPicked(url, kind: DocumentKind.from(url: url))
            }
        }
        .fileMover(isPresented: Binding(get: { newFile != nil }, set: { if !$0 { newFile = nil } }), file: newFile) { result in
            if case .success(let url) = result { openPicked(url, kind: newFileKind) }
        }
        .sheet(item: $share, onDismiss: { heldAccess = [] }) { ShareSheet(items: $0.urls) }
    }

    // MARK: launching

    private func pick(_ kind: Picker) {
        picker = kind
        showPicker = true
    }

    /// ACTION_CREATE_DOCUMENT: an empty file the user moves to a folder of their choice.
    private func createFile(_ kind: DocumentKind) {
        newFileKind = kind
        newFile = TemporaryFile.make(name: kind == .markdown ? "Untitled.md" : "Untitled.txt", data: Data())
    }

    private func openPicked(_ url: URL, kind: DocumentKind) {
        if store.prepareDocument(url.absoluteString, picked: url) {
            router.push(DocumentLauncher.route(url.absoluteString, kind))
        } else {
            store.toast = "This document is no longer available. Open it again to restore access."
        }
    }

    private func openDocument(_ document: DocumentEntry) {
        if store.prepareDocument(document.uri) {
            router.push(DocumentLauncher.route(document.uri, document.kind))
        } else {
            store.toast = "This document is no longer available. Open it again to restore access."
        }
    }

    private func openWith(_ document: DocumentEntry) {
        let (readable, unavailable) = store.validateDocuments([document])
        guard unavailable == 0, !readable.isEmpty, let access = store.access(document.uri) else {
            store.toast = "This document is no longer available. Open it again to restore access."
            return
        }
        heldAccess = [access]
        if !Launcher.openWith(access.url) { store.toast = "No valid app found" }
    }

    private func shareDocuments(_ documents: [DocumentEntry]) {
        let (readable, unavailable) = store.validateDocuments(documents)
        if unavailable > 0 { store.toast = "Some selected documents are no longer available." }
        let accesses = readable.compactMap { store.access($0.uri) }
        guard !accesses.isEmpty else { return }
        heldAccess = accesses
        share = ShareItems(accesses.map(\.url))
    }

    // MARK: top bars

    @ViewBuilder
    private var topBar: some View {
        if store.hasSelection {
            selectionTopBar
        } else if store.isCollectionScreen {
            focusedTopBar
        } else {
            searchSurface
        }
    }

    /// DocumentsHomeChrome.kt DocumentSearchSurface.
    private var searchSurface: some View {
        @Bindable var store = store
        return HStack(spacing: 0) {
            CloseAppButton()
            Image(systemName: "magnifyingglass").font(.system(size: 18)).frame(width: 44, height: 48)
            TextField("", text: $store.query, prompt: Text("Search documents").foregroundStyle(palette.textColor.opacity(0.56)))
                .font(.system(size: 16, weight: .medium))
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !store.query.trimmingCharacters(in: .whitespaces).isEmpty {
                IconButton(icon: "xmark") { store.query = "" }
            }
            Menu {
                ForEach(DocumentSort.allCases, id: \.self) { sort in
                    Button { store.updateDisplayOptions(sort: sort) } label: {
                        if sort == store.selectedSort { Label(sort.label, systemImage: "checkmark") } else { Text(sort.label) }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 18)).frame(width: 44, height: 48)
            }
            overflowMenu
        }
        .foregroundStyle(palette.textColor)
        .padding(.horizontal, 4)
        .background(Capsule().fill(palette.primaryColor.opacity(palette.dark ? 0.26 : 0.16)))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var overflowMenu: some View {
        OverflowMenu {
            Button("Settings") { router.push(.settings) }
            Button("About") { router.push(.about) }
            if store.hasRecentDocuments {
                Button("Clear recents") { store.clearRecentDocuments() }
            }
        }
    }

    /// DocumentsFocusedChrome.kt DocumentsFocusedTopBar.
    private var focusedTopBar: some View {
        @Bindable var store = store
        let showSearchField = focusedSearchActive || !store.query.trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(spacing: 4) {
            Button {
                if showSearchField {
                    store.query = ""
                    focusedSearchActive = false
                } else {
                    store.navigateBack()
                }
            } label: {
                Image(systemName: "arrow.left").font(.system(size: 20)).frame(width: 48, height: 48)
            }
            if showSearchField {
                FocusedSearchField(query: $store.query)
            } else {
                Text(store.screenTitle).font(.system(size: 21, weight: .semibold)).lineLimit(1)
                Spacer()
            }
            IconButton(icon: showSearchField ? "xmark" : "magnifyingglass") {
                if showSearchField {
                    store.query = ""
                    focusedSearchActive = false
                } else {
                    focusedSearchActive = true
                }
            }
            overflowMenu
        }
        .foregroundStyle(palette.textColor)
        .padding(.horizontal, 4)
        .frame(height: 56)
    }

    /// DocumentsSelectionTopBar.kt.
    private var selectionTopBar: some View {
        let single = store.selectionCount == 1 ? store.selectedDocumentList.first : nil
        let canRemove = store.homeSection != .folder
        return HStack(spacing: 4) {
            IconButton(icon: "xmark") { store.clearSelection() }
            Text("\(store.selectionCount) selected")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(palette.textColor)
                .lineLimit(1)
            Spacer()
            if !store.selectedDocuments.isEmpty {
                IconButton(icon: store.selectedDocumentsAreFavorites ? "star.fill" : "star") { store.toggleSelectedFavorites() }
                IconButton(icon: "square.and.arrow.up") { shareDocuments(store.selectedDocumentList) }
            }
            IconButton(icon: "checklist") { store.selectAllVisibleItems() }
            if single != nil || canRemove {
                OverflowMenu {
                    if let single {
                        Button("Open with") { openWith(single) }
                    }
                    if canRemove {
                        Button("Remove from Documents") { store.removeSelectedItems() }
                    }
                }
            }
        }
        .foregroundStyle(palette.primaryColor)
        .padding(.horizontal, 4)
        .frame(height: 56)
    }

    /// DocumentsHomeActions.kt ImportAction.
    private var importAction: some View {
        Menu {
            Button("New text file") { createFile(.text) }
            Button("New markdown file") { createFile(.markdown) }
            Button("Open file") { pick(.document) }
            Button("Open folder") { pick(.folder) }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(palette.onPrimary)
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 18).fill(palette.primaryColor))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
        .accessibilityLabel("Import")
    }

    // MARK: content

    @ViewBuilder
    private var homeScreenItems: some View {
        if store.showsFilterChips { filterChips }
        if !store.query.trimmingCharacters(in: .whitespaces).isEmpty || !store.selectedFilters.isEmpty {
            focusedDocuments
        } else if store.documents.isEmpty && store.folders.isEmpty {
            emptyDocumentsState
        } else {
            let recent = store.recentDocuments
            if !recent.isEmpty {
                SectionHeader(title: "Recent") { store.showSection(.recent) }
                documentRows(prefix: "recent", Array(recent.prefix(homeRecentLimit)), showLocation: false)
                Spacer().frame(height: 16)
            }
            let favorites = store.favoriteDocuments
            if !favorites.isEmpty {
                SectionHeader(title: "Favorites") { store.showSection(.favorites) }
                documentRows(prefix: "favorite", Array(favorites.prefix(homeFavoritesLimit)), showLocation: false)
                Spacer().frame(height: 16)
            }
            if !store.folders.isEmpty {
                SectionHeader(title: "Folders") { store.showSection(.folders) }
                folderRows(Array(store.sortedFolders.prefix(homeFolderLimit)))
                Spacer().frame(height: 16)
            }
        }
    }

    @ViewBuilder
    private var focusedScreenItems: some View {
        if store.homeSection == .folders || store.homeSection == .folder {
            DocumentsBreadcrumb()
        }
        if store.showsFilterChips { filterChips }
        SortAndViewRow(
            availableSorts: store.homeSection == .folders ? [.nameAscending, .nameDescending] : DocumentSort.allCases)
        if store.homeSection == .folders {
            focusedFolders
        } else {
            focusedDocuments
        }
    }

    private var emptyDocumentsState: some View {
        DocumentsEmptyState(icon: "doc.text.fill", title: "No documents found",
                            message: "Open a document or folder to get started.") {
            TonalButton(title: "Open document") { pick(.document) }
            TonalButton(title: "Open folder") { pick(.folder) }
        }
    }

    @ViewBuilder
    private var focusedFolders: some View {
        if store.visibleFolders.isEmpty {
            if store.query.trimmingCharacters(in: .whitespaces).isEmpty {
                DocumentsEmptyState(icon: "folder.fill", title: "No folders found",
                                    message: "Open a folder to browse supported documents.") {
                    TonalButton(title: "Open folder") { pick(.folder) }
                }
            } else {
                noResults
            }
        } else if config.documentViewMode == .grid {
            folderGrid(store.visibleFolders)
        } else {
            folderRows(store.visibleFolders)
        }
    }

    private var noResults: some View {
        DocumentsEmptyState(icon: "magnifyingglass", title: "No results found", message: "Try a different search or filter.")
    }

    @ViewBuilder
    private var focusedDocuments: some View {
        let showLocation = config.showFileLocations && store.homeSection != .folder
        let showChildFolders = store.homeSection == .folder && store.selectedFilters.isEmpty && !store.visibleFolders.isEmpty
        let docs = store.visibleDocuments
        let prefix = "document_\(store.homeSection)"
        if let error = store.folderError {
            DocumentsEmptyState(icon: "folder.fill", title: "Folder unavailable", message: error) {
                TonalButton(title: "Retry") { store.refreshVisibleFolder() }
            }
        } else if store.isFolderLoading {
            ProgressView().tint(palette.primaryColor).frame(maxWidth: .infinity).padding(.vertical, 56)
        } else {
            if showChildFolders {
                if config.documentViewMode == .grid {
                    folderGrid(store.visibleFolders, selectable: false)
                } else {
                    folderRows(store.visibleFolders, selectable: false)
                }
                if !docs.isEmpty {
                    Divider().overlay(palette.textColor.opacity(0.12)).padding(.horizontal, 24).padding(.vertical, 8)
                }
            }
            if docs.isEmpty && !showChildFolders {
                focusedEmptyState
            } else if !docs.isEmpty && config.documentViewMode == .grid {
                documentGrid(prefix: prefix + "_grid", docs, showLocation: showLocation)
            } else if !docs.isEmpty {
                documentRows(prefix: prefix, docs, showLocation: showLocation)
            }
        }
    }

    /// DocumentsFocusedEmptyStates.kt.
    @ViewBuilder
    private var focusedEmptyState: some View {
        if !store.query.trimmingCharacters(in: .whitespaces).isEmpty || !store.selectedFilters.isEmpty {
            noResults
        } else if store.homeSection == .favorites {
            DocumentsEmptyState(icon: "star.fill", title: "No favorites found", message: "Star documents to keep them within reach.")
        } else if store.homeSection == .recent {
            DocumentsEmptyState(icon: "doc.text.fill", title: "No recent documents", message: "Documents you open will appear here.")
        } else {
            emptyDocumentsState
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DocumentFilter.allCases.filter { store.availableFilters.contains($0) }, id: \.self) { filter in
                    FilterChip(filter: filter, selected: store.selectedFilters.contains(filter)) { store.onFilterSelected(filter) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: rows

    private func documentTap(_ key: String, _ document: DocumentEntry) {
        if store.hasSelection { store.toggleDocumentSelection(key, document) } else { openDocument(document) }
    }

    private func documentRows(prefix: String, _ documents: [DocumentEntry], showLocation: Bool) -> some View {
        ForEach(documents) { document in
            let key = "\(prefix)_\(document.uri)"
            DocumentRow(document: document, showLocation: showLocation, selected: store.selectedDocumentKeys.contains(document.uri))
                .onTapGesture { documentTap(key, document) }
                .onLongPressGesture { store.toggleDocumentSelection(key, document) }
        }
    }

    private func documentGrid(prefix: String, _ documents: [DocumentEntry], showLocation: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 12) {
            ForEach(documents) { document in
                let key = "\(prefix)_\(document.uri)"
                DocumentGridCard(document: document, showLocation: showLocation, selected: store.selectedDocumentKeys.contains(document.uri))
                    .onTapGesture { documentTap(key, document) }
                    .onLongPressGesture { store.toggleDocumentSelection(key, document) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private func folderTap(_ folder: DocumentFolder, selectable: Bool) {
        if selectable && store.hasSelection { store.toggleFolderSelection(folder) } else { store.showSection(.folder, folder: folder) }
    }

    private func folderRows(_ folders: [DocumentFolder], selectable: Bool = true) -> some View {
        ForEach(folders) { folder in
            FolderRow(folder: folder, selected: selectable && store.selectedFolders[folder.uri] != nil)
                .onTapGesture { folderTap(folder, selectable: selectable) }
                .onLongPressGesture { if selectable { store.toggleFolderSelection(folder) } }
        }
    }

    private func folderGrid(_ folders: [DocumentFolder], selectable: Bool = true) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 12) {
            ForEach(folders) { folder in
                FolderGridCard(folder: folder, selected: selectable && store.selectedFolders[folder.uri] != nil)
                    .onTapGesture { folderTap(folder, selectable: selectable) }
                    .onLongPressGesture { if selectable { store.toggleFolderSelection(folder) } }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
}

extension UTType {
    static var markdownText: UTType { UTType("net.daringfireball.markdown") ?? UTType(filenameExtension: "md") ?? .plainText }
}

private struct FocusedSearchField: View {
    @Environment(\.palette) private var palette
    @Binding var query: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $query, prompt: Text("Search documents").foregroundStyle(palette.textColor.opacity(0.56)))
            .font(.system(size: 21, weight: .semibold))
            .focused($focused)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onAppear { focused = true }
    }
}
