import Foundation
import Observation

struct SelectedDocument: Hashable {
    var document: DocumentEntry
    var selectionPrefix: String
}

let homeRecentLimit = 4
let homeFolderLimit = 4
let homeFavoritesLimit = 4
let homeRecentSelectionPrefix = "recent_"
let homeFavoriteSelectionPrefix = "favorite_"

/// data/DocumentsRepository.kt + DocumentsStore.kt + viewmodels/DocumentsViewModel.kt.
@MainActor
@Observable
final class DocumentsStore {
    @ObservationIgnored private let config = Config.shared

    private(set) var documents: [DocumentEntry] = []
    private(set) var folders: [DocumentFolder] = []

    var query = ""
    private(set) var selectedFilters: Set<DocumentFilter> = []
    private(set) var selectedSort: DocumentSort = .recent
    private(set) var homeSection: DocumentsHomeSection = .home
    private(set) var folderPath: [DocumentFolder] = []
    @ObservationIgnored private var folderOriginSection: DocumentsHomeSection = .home
    private(set) var selectedDocuments: [String: SelectedDocument] = [:]
    private(set) var selectedFolders: [String: DocumentFolder] = [:]

    // FolderContentState
    private(set) var folderContentURI: String?
    private(set) var folderContent: DocumentFolderContent?
    private(set) var isFolderLoading = false
    private(set) var folderError: String?
    @ObservationIgnored private var folderTask: Task<Void, Never>?

    var toast: String?

    init() {
        documents = decodeDocuments(config.documentsJson)
        folders = decodeFolders(config.documentFoldersJson)
        cleanUpStoredItems()
        refreshFolderCounts()
    }

    var selectedViewMode: DocumentViewMode { config.documentViewMode }
    var showFileLocations: Bool { config.showFileLocations }

    // MARK: persistence (DocumentsStore.kt)

    private static func entrySort(_ a: DocumentEntry, _ b: DocumentEntry) -> Bool {
        a.lastOpened != b.lastOpened ? a.lastOpened > b.lastOpened : a.name.lowercased() < b.name.lowercased()
    }

    private static func folderSort(_ a: DocumentFolder, _ b: DocumentFolder) -> Bool {
        a.lastOpened != b.lastOpened ? a.lastOpened > b.lastOpened : a.name.lowercased() < b.name.lowercased()
    }

    private func decodeDocuments(_ json: String) -> [DocumentEntry] {
        let list = (try? JSONDecoder().decode([DocumentEntry].self, from: Data(json.utf8))) ?? []
        return list.filter { !$0.uri.isEmpty && $0.kind != .other }.sorted(by: Self.entrySort)
    }

    private func decodeFolders(_ json: String) -> [DocumentFolder] {
        let list = (try? JSONDecoder().decode([DocumentFolder].self, from: Data(json.utf8))) ?? []
        return list.filter { !$0.uri.isEmpty }.sorted(by: Self.folderSort)
    }

    private func updateDocuments(_ transform: ([DocumentEntry]) -> [DocumentEntry]) {
        var seen = Set<String>()
        let updated = transform(documents).filter { seen.insert($0.uri).inserted }.sorted(by: Self.entrySort)
        documents = updated
        config.documentsJson = String(data: (try? JSONEncoder().encode(updated)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
    }

    private func updateFolders(_ transform: ([DocumentFolder]) -> [DocumentFolder]) {
        var seen = Set<String>()
        let updated = transform(folders).filter { seen.insert($0.uri).inserted }.sorted(by: Self.folderSort)
        folders = updated
        config.documentFoldersJson = String(data: (try? JSONEncoder().encode(updated)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
    }

    // MARK: repository

    func document(_ uri: String) -> DocumentEntry? { documents.first { $0.uri == uri } }

    /// Read access to a stored or folder-listed document.
    func access(_ uri: String) -> ScopedAccess? {
        guard let url = URL(string: uri) else { return nil }
        return DocumentAccess.access(url: url, bookmark: document(uri)?.bookmark, folders: folders)
    }

    private func folderAccess(_ folder: DocumentFolder) -> ScopedAccess? {
        guard let url = folder.url else { return nil }
        let own = folders.first { $0.uri == folder.uri }?.bookmark ?? folder.bookmark
        return DocumentAccess.access(url: url, bookmark: own, folders: folders)
    }

    /// rememberDocument(): `picked` is a fresh security-scoped URL from a picker or "Open in".
    @discardableResult
    func rememberDocument(_ uri: String, picked: URL? = nil) -> DocumentEntry? {
        guard let url = picked ?? URL(string: uri) else { return nil }
        let previous = document(url.absoluteString)
        let access = picked.map { ScopedAccess(url: $0, scopes: [$0]) } ?? self.access(url.absoluteString)
        guard let access, DocumentAccess.isReadable(access.url) else { return nil }
        var metadata = DocumentAccess.readDocument(access.url, previous: previous)
        metadata.uri = url.absoluteString
        metadata.lastOpened = .nowMillis
        if picked != nil || metadata.bookmark == nil {
            metadata.bookmark = (try? access.url.bookmarkData()) ?? metadata.bookmark
        }
        updateDocuments { [metadata] + $0.filter { $0.uri != metadata.uri } }
        return metadata
    }

    func refreshDocumentMetadata(_ uri: String) {
        guard let previous = document(uri), let access = access(uri) else { return }
        var updated = DocumentAccess.readDocument(access.url, previous: previous)
        updated.uri = uri
        updateDocuments { [updated] + $0.filter { $0.uri != uri } }
    }

    func isDocumentReadable(_ uri: String) -> Bool {
        guard let access = access(uri) else { return false }
        return DocumentAccess.isReadable(access.url)
    }

    func isDocumentWritable(_ uri: String) -> Bool {
        guard let access = access(uri) else { return false }
        return DocumentAccess.isWritable(access.url)
    }

    func cleanUpStoredItems() {
        updateDocuments { docs in
            docs.filter { ($0.lastOpened > 0 || $0.isFavorite) && isDocumentReadable($0.uri) }
        }
        updateFolders { folders in
            folders.filter { folder in
                guard let access = folderAccess(folder) else { return false }
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: access.url.path, isDirectory: &isDir) && isDir.boolValue
            }
        }
    }

    /// foldersFlow.map(scanner::refreshFolderCount).
    func refreshFolderCounts() {
        updateFolders { folders in
            folders.map { folder in
                var f = folder
                if let access = folderAccess(folder) { f.itemCount = DocumentAccess.folderItemCount(access.url) }
                return f
            }
        }
    }

    func updateLastPage(_ uri: String, page: Int) {
        guard config.rememberPdfPage else { return }
        updateDocuments { $0.map { e in e.uri == uri ? { var c = e; c.lastPage = max(0, page); return c }() : e } }
    }

    func removeDocuments(_ uris: some Collection<String>) {
        let removed = Set(uris)
        guard !removed.isEmpty else { return }
        updateDocuments { $0.filter { !removed.contains($0.uri) } }
    }

    func setFavorites(_ selected: [DocumentEntry], favorite: Bool) {
        guard !selected.isEmpty else { return }
        let byURI = Dictionary(selected.map { ($0.uri, $0) }, uniquingKeysWith: { a, _ in a })
        updateDocuments { existing in
            let existingURIs = Set(existing.map(\.uri))
            var retained: [DocumentEntry] = []
            for entry in existing {
                if byURI[entry.uri] == nil {
                    retained.append(entry)
                } else if favorite || entry.lastOpened > 0 {
                    var e = entry
                    e.isFavorite = favorite
                    retained.append(e)
                }
            }
            if favorite {
                for doc in byURI.values where !existingURIs.contains(doc.uri) {
                    var e = doc
                    e.isFavorite = true
                    e.lastOpened = 0
                    if e.bookmark == nil, let access = access(e.uri) { e.bookmark = try? access.url.bookmarkData() }
                    retained.append(e)
                }
            }
            return retained
        }
    }

    func clearRecentDocuments() {
        updateDocuments { $0.filter(\.isFavorite).map { var e = $0; e.lastOpened = 0; return e } }
    }

    func rememberFolder(_ url: URL) {
        let access = ScopedAccess(url: url, scopes: [url])
        let previous = folders.first { $0.uri == url.absoluteString }
        var folder = DocumentAccess.readFolder(access.url, previous: previous)
        folder.lastOpened = .nowMillis
        folder.bookmark = (try? url.bookmarkData()) ?? previous?.bookmark
        updateFolders { [folder] + $0.filter { $0.uri != folder.uri } }
    }

    func removeFolders(_ uris: some Collection<String>) {
        let removed = Set(uris)
        guard !removed.isEmpty else { return }
        updateFolders { $0.filter { !removed.contains($0.uri) } }
        updateDocuments { $0.filter { isDocumentReadable($0.uri) } }
    }

    // MARK: folder content (folderContentState)

    private func loadFolderContent() {
        folderTask?.cancel()
        guard homeSection == .folder, let folder = folderPath.last else {
            folderContentURI = nil
            folderContent = nil
            isFolderLoading = false
            folderError = nil
            return
        }
        let uri = folder.uri
        folderContentURI = uri
        folderContent = nil
        isFolderLoading = true
        folderError = nil
        let access = folderAccess(folder)
        let previous = folders.first { $0.uri == uri }
        folderTask = Task { [weak self] in
            let result: Result<DocumentFolderContent, Error> = await Task.detached {
                guard let access else { return .failure(CocoaError(.fileReadNoPermission)) }
                return Result { try DocumentAccess.readFolderContent(access.url, previous: previous) }
            }.value
            guard let self, !Task.isCancelled, self.folderContentURI == uri else { return }
            self.isFolderLoading = false
            switch result {
            case .success(var content):
                content.folder.uri = uri
                self.folderContent = content
            case .failure:
                self.folderError = "Check that this folder is available, then try again."
            }
        }
    }

    func refreshVisibleFolder() { loadFolderContent() }

    // MARK: ui state

    private var activeFolderContent: DocumentFolderContent? {
        let requested = homeSection == .folder ? folderPath.last?.uri : nil
        return folderContentURI == requested ? folderContent : nil
    }

    var activeFolder: DocumentFolder? { activeFolderContent?.folder ?? folderPath.last }

    var activeFolderPath: [DocumentFolder] {
        guard homeSection == .folder else { return [] }
        if let content = activeFolderContent { return folderPath.dropLast() + [content.folder] }
        return folderPath
    }

    var recentDocuments: [DocumentEntry] {
        documents.filter { $0.lastOpened > 0 }.sorted(by: selectedSort.areInIncreasingOrder)
    }

    var favoriteDocuments: [DocumentEntry] {
        documents.filter(\.isFavorite).sorted(by: selectedSort.areInIncreasingOrder)
    }

    var sortedFolders: [DocumentFolder] {
        switch selectedSort {
        case .nameAscending: return folders.sorted { $0.name.lowercased() < $1.name.lowercased() }
        case .nameDescending: return folders.sorted { $0.name.lowercased() > $1.name.lowercased() }
        default: return folders
        }
    }

    private var sectionDocuments: [DocumentEntry] {
        switch homeSection {
        case .favorites: return documents.filter(\.isFavorite)
        case .folder: return activeFolderContent?.documents ?? []
        case .recent: return documents.filter { $0.lastOpened > 0 }
        case .home: return documents
        case .folders: return []
        }
    }

    var availableFilters: Set<DocumentFilter> {
        Set(sectionDocuments.compactMap { DocumentFilter.from($0.kind) }).union(selectedFilters)
    }

    var visibleDocuments: [DocumentEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return sectionDocuments
            .filter { e in selectedFilters.isEmpty || selectedFilters.contains { $0.accepts(e.kind) } }
            .filter { e in q.isEmpty || e.name.localizedCaseInsensitiveContains(q) || e.location.localizedCaseInsensitiveContains(q) }
            .sorted(by: selectedSort.areInIncreasingOrder)
    }

    var visibleFolders: [DocumentFolder] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let section: [DocumentFolder]
        switch homeSection {
        case .folder: section = activeFolderContent?.childFolders ?? []
        case .folders: section = folders
        default: section = []
        }
        let filtered = section.filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }
        return selectedSort == .nameDescending
            ? filtered.sorted { $0.name.lowercased() > $1.name.lowercased() }
            : filtered.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    var selectedDocumentKeys: Set<String> { Set(selectedDocuments.keys) }
    var selectedDocumentList: [DocumentEntry] { selectedDocuments.values.map(\.document) }
    var selectionCount: Int { selectedDocuments.count + selectedFolders.count }
    var hasSelection: Bool { selectionCount > 0 }
    var selectedDocumentsAreFavorites: Bool {
        !selectedDocuments.isEmpty && selectedDocuments.values.allSatisfy { $0.document.isFavorite }
    }
    var showsFilterChips: Bool { availableFilters.count >= 2 || !selectedFilters.isEmpty }
    var hasRecentDocuments: Bool { !recentDocuments.isEmpty }
    var isCollectionScreen: Bool { homeSection != .home }

    var screenTitle: String {
        switch homeSection {
        case .home: return "All documents"
        case .favorites: return "Favorites"
        case .folder: return activeFolder?.name ?? "Folders"
        case .folders: return "Folders"
        case .recent: return "Recent"
        }
    }

    // MARK: actions

    func onFilterSelected(_ filter: DocumentFilter) {
        if selectedFilters.contains(filter) { selectedFilters.remove(filter) } else { selectedFilters.insert(filter) }
    }

    func updateDisplayOptions(sort: DocumentSort? = nil, viewMode: DocumentViewMode? = nil) {
        if let sort { selectedSort = sort }
        if let viewMode { config.documentViewMode = viewMode }
    }

    func showSection(_ section: DocumentsHomeSection, folder: DocumentFolder? = nil) {
        let previous = homeSection
        if section == .folder && previous != .folder { folderOriginSection = previous }
        clearSelection()
        query = ""
        selectedFilters = []
        switch section {
        case .favorites, .folder, .folders: selectedSort = .nameAscending
        case .home, .recent: selectedSort = .recent
        }
        if section == .folder {
            // folderPathAfterOpening()
            if let folder { folderPath = previous == .folder ? folderPath + [folder] : [folder] }
        } else {
            folderPath = []
        }
        homeSection = section
        loadFolderContent()
        if section == .folders || section == .home { refreshFolderCounts() }
    }

    func navigateBack() {
        if !selectedDocuments.isEmpty || !selectedFolders.isEmpty {
            clearSelection()
        } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            query = ""
        } else if !selectedFilters.isEmpty {
            selectedFilters = []
        } else if homeSection == .folder && folderPath.count > 1 {
            // documentsBackDestination()
            folderPath.removeLast()
            loadFolderContent()
        } else if homeSection == .folder {
            showSection(folderOriginSection)
        } else {
            showSection(.home)
        }
    }

    func navigateToBreadcrumb(_ index: Int) {
        guard folderPath.indices.contains(index), index != folderPath.count - 1 else { return }
        clearSelection()
        query = ""
        selectedFilters = []
        folderPath = Array(folderPath.prefix(index + 1))
        loadFolderContent()
    }

    /// prepareDocument(): remembers the document and checks it can still be read.
    func prepareDocument(_ uri: String, picked: URL? = nil) -> Bool {
        let key = picked?.absoluteString ?? uri
        rememberDocument(key, picked: picked)
        let readable = picked.map { url in
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            return DocumentAccess.isReadable(url)
        } ?? isDocumentReadable(key)
        if !readable { removeDocuments([key]) }
        return readable
    }

    /// validateDocuments(): drops entries that can no longer be read.
    func validateDocuments(_ docs: [DocumentEntry]) -> (readable: [DocumentEntry], unavailable: Int) {
        var seen = Set<String>()
        let unique = docs.filter { seen.insert($0.uri).inserted }
        let readable = unique.filter { isDocumentReadable($0.uri) }
        let unavailable = unique.filter { d in !readable.contains { $0.uri == d.uri } }
        removeDocuments(unavailable.map(\.uri))
        return (readable, unavailable.count)
    }

    func toggleDocumentSelection(_ selectionKey: String, _ document: DocumentEntry) {
        selectedFolders = [:]
        if selectedDocuments[document.uri] != nil {
            selectedDocuments[document.uri] = nil
        } else {
            let prefix = selectionKey.hasSuffix(document.uri) ? String(selectionKey.dropLast(document.uri.count)) : selectionKey
            selectedDocuments[document.uri] = SelectedDocument(document: document, selectionPrefix: prefix)
        }
    }

    func toggleFolderSelection(_ folder: DocumentFolder) {
        selectedDocuments = [:]
        if selectedFolders[folder.uri] != nil { selectedFolders[folder.uri] = nil } else { selectedFolders[folder.uri] = folder }
    }

    /// DocumentsSelection.kt documentsForSelectAll() / foldersForSelectAll().
    func selectAllVisibleItems() {
        if !selectedDocuments.isEmpty {
            let prefixes = Set(selectedDocuments.values.map(\.selectionPrefix))
            var candidates: [String: SelectedDocument] = [:]
            if homeSection == .home && query.trimmingCharacters(in: .whitespaces).isEmpty && selectedFilters.isEmpty {
                if prefixes.contains(homeRecentSelectionPrefix) {
                    for d in recentDocuments.prefix(homeRecentLimit) {
                        candidates[d.uri] = SelectedDocument(document: d, selectionPrefix: homeRecentSelectionPrefix)
                    }
                }
                if prefixes.contains(homeFavoriteSelectionPrefix) {
                    for d in favoriteDocuments.prefix(homeFavoritesLimit) {
                        candidates[d.uri] = SelectedDocument(document: d, selectionPrefix: homeFavoriteSelectionPrefix)
                    }
                }
            } else if let prefix = selectedDocuments.values.first?.selectionPrefix {
                for d in visibleDocuments { candidates[d.uri] = SelectedDocument(document: d, selectionPrefix: prefix) }
            }
            if !candidates.isEmpty { selectedDocuments = candidates }
        } else if !selectedFolders.isEmpty {
            let candidates = homeSection == .home ? Array(sortedFolders.prefix(homeFolderLimit)) : visibleFolders
            if !candidates.isEmpty { selectedFolders = Dictionary(candidates.map { ($0.uri, $0) }, uniquingKeysWith: { a, _ in a }) }
        }
    }

    func clearSelection() {
        selectedDocuments = [:]
        selectedFolders = [:]
    }

    func toggleSelectedFavorites() {
        let docs = selectedDocumentList
        guard !docs.isEmpty else { return }
        let favorite = docs.contains { !$0.isFavorite }
        clearSelection()
        setFavorites(docs, favorite: favorite)
    }

    func removeSelectedItems() {
        let documentURIs = Array(selectedDocuments.keys)
        let folderURIs = Array(selectedFolders.keys)
        clearSelection()
        removeDocuments(documentURIs)
        removeFolders(folderURIs)
    }
}
