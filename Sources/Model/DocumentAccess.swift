import Foundation
import UniformTypeIdentifiers

/// Security-scoped access to a picked file or folder: the iOS counterpart of a persisted
/// SAF URI permission (data/DocumentUriPermissions.kt). Released when deallocated.
final class ScopedAccess {
    let url: URL
    private var scoped: [URL] = []

    init(url: URL, scopes: [URL]) {
        self.url = url
        for s in scopes where s.startAccessingSecurityScopedResource() { scoped.append(s) }
    }

    deinit { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
}

/// data/DocumentUriPermissions.kt + DocumentProviderScanner.kt + DocumentLocationResolver.kt.
enum DocumentAccess {
    static func makeBookmark(_ url: URL) -> Data? {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolve(_ bookmark: Data?) -> URL? {
        guard let bookmark else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// Opens `url` through its own bookmark or the bookmark of a remembered folder that covers it (Uri.covers()).
    static func access(url: URL, bookmark: Data?, folders: [DocumentFolder]) -> ScopedAccess {
        var scopes: [URL] = []
        var target = url
        if let resolved = resolve(bookmark) {
            scopes.append(resolved)
            target = resolved
        }
        let path = normalizedPath(target)
        for folder in folders {
            guard let folderURL = resolve(folder.bookmark) ?? folder.url else { continue }
            let folderPath = normalizedPath(folderURL)
            if path == folderPath || path.hasPrefix(folderPath + "/") {
                scopes.append(folderURL)
                break
            }
        }
        scopes.append(url)
        return ScopedAccess(url: target, scopes: scopes)
    }

    static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if path.hasPrefix("/private/") { path.removeFirst("/private".count) }
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    static func isReadable(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
            && FileManager.default.isReadableFile(atPath: url.path)
    }

    static func isWritable(_ url: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: url.path)
    }

    // MARK: DocumentProviderScanner

    private static let keys: Set<URLResourceKey> = [.nameKey, .fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isHiddenKey]

    static func readDocument(_ url: URL, previous: DocumentEntry?) -> DocumentEntry {
        let values = try? url.resourceValues(forKeys: keys)
        let name = values?.name ?? previous?.name ?? url.lastPathComponent
        let mime = DocumentKind.mimeType(for: url)
        return DocumentEntry(
            uri: url.absoluteString,
            name: name,
            mimeType: mime.isEmpty ? previous?.mimeType ?? "" : mime,
            location: location(ofDocument: url).isEmpty ? previous?.location ?? "" : location(ofDocument: url),
            size: values?.fileSize.map(Int64.init) ?? previous?.size,
            lastModified: values?.contentModificationDate.map { Int64($0.timeIntervalSince1970 * 1000) } ?? previous?.lastModified,
            lastOpened: previous?.lastOpened ?? 0,
            lastPage: previous?.lastPage ?? 0,
            isFavorite: previous?.isFavorite ?? false,
            bookmark: previous?.bookmark
        )
    }

    static func readFolder(_ url: URL, previous: DocumentFolder?) -> DocumentFolder {
        DocumentFolder(
            uri: url.absoluteString,
            name: (try? url.resourceValues(forKeys: [.nameKey]))?.name ?? previous?.name ?? url.lastPathComponent,
            itemCount: folderItemCount(url),
            lastOpened: previous?.lastOpened ?? 0,
            bookmark: previous?.bookmark
        )
    }

    static func readFolderContent(_ url: URL, previous: DocumentFolder?) throws -> DocumentFolderContent {
        let children = try FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        let folderLocation = location(ofFolder: url)
        var folders: [DocumentFolder] = []
        var documents: [DocumentEntry] = []
        for child in children {
            let values = try? child.resourceValues(forKeys: keys)
            let name = values?.name ?? child.lastPathComponent
            if values?.isDirectory == true {
                folders.append(DocumentFolder(uri: child.absoluteString, name: name))
            } else {
                let mime = DocumentKind.mimeType(for: child)
                guard DocumentKind.fromName(name, mimeType: mime) != .other else { continue }
                documents.append(DocumentEntry(
                    uri: child.absoluteString, name: name, mimeType: mime, location: folderLocation,
                    size: values?.fileSize.map(Int64.init),
                    lastModified: values?.contentModificationDate.map { Int64($0.timeIntervalSince1970 * 1000) },
                    lastOpened: 0))
            }
        }
        let name = (try? url.resourceValues(forKeys: [.nameKey]))?.name ?? previous?.name ?? url.lastPathComponent
        return DocumentFolderContent(
            folder: DocumentFolder(uri: url.absoluteString, name: name, itemCount: folders.count + documents.count,
                                   lastOpened: previous?.lastOpened ?? 0, bookmark: previous?.bookmark),
            childFolders: folders.sorted { $0.name.lowercased() < $1.name.lowercased() },
            documents: documents.sorted { $0.name.lowercased() < $1.name.lowercased() }
        )
    }

    static func folderItemCount(_ url: URL) -> Int {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return 0 }
        return children.filter { child in
            (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                || DocumentKind.from(url: child) != .other
        }.count
    }

    // MARK: DocumentLocationResolver

    static func location(ofDocument url: URL) -> String {
        location(ofFolder: url.deletingLastPathComponent())
    }

    /// Files-app style path ("iCloud Drive/Work", "On My iPhone/Downloads") instead of the sandbox path.
    static func location(ofFolder url: URL) -> String {
        let parts = url.standardizedFileURL.pathComponents
        func after(_ marker: String, root: String) -> String? {
            guard let i = parts.firstIndex(of: marker) else { return nil }
            return ([root] + parts[(i + 1)...].filter { $0 != "/" }).joined(separator: "/")
        }
        if let s = after("com~apple~CloudDocs", root: "iCloud Drive") { return s }
        if let i = parts.firstIndex(of: "Mobile Documents"), i + 2 < parts.count {
            return (["iCloud Drive"] + parts[(i + 2)...].filter { $0 != "Documents" }).joined(separator: "/")
        }
        if let s = after("File Provider Storage", root: "On My iPhone") { return s }
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           normalizedPath(url).hasPrefix(normalizedPath(docs)) {
            let rest = normalizedPath(url).dropFirst(normalizedPath(docs).count)
            return "On My iPhone/Documents" + rest
        }
        return url.path
    }
}

/// A uniquely placed temporary file for the system "move to" picker (new files, saved copies).
enum TemporaryFile {
    static func make(name: String, data: Data) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = dir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
