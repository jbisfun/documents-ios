import Foundation

/// models/DocumentEntry.kt. `uri` is the file URL string; iOS adds the security-scoped
/// `bookmark` that stands in for Android's persisted URI permission.
struct DocumentEntry: Codable, Hashable, Identifiable {
    var uri: String
    var name: String
    var mimeType: String
    var location: String
    var size: Int64?
    var lastModified: Int64?
    var lastOpened: Int64
    var lastPage: Int = 0
    var isFavorite: Bool = false
    var bookmark: Data?

    var id: String { uri }
    var kind: DocumentKind { DocumentKind.fromName(name, mimeType: mimeType) }
    var url: URL? { URL(string: uri) }

    enum CodingKeys: String, CodingKey {
        case uri, name, location, size, bookmark
        case mimeType = "mime_type"
        case lastModified = "last_modified"
        case lastOpened = "last_opened"
        case lastPage = "last_page"
        case isFavorite = "is_favorite"
    }

    init(uri: String, name: String, mimeType: String, location: String, size: Int64?, lastModified: Int64?,
         lastOpened: Int64, lastPage: Int = 0, isFavorite: Bool = false, bookmark: Data? = nil) {
        self.uri = uri
        self.name = name
        self.mimeType = mimeType
        self.location = location
        self.size = size
        self.lastModified = lastModified
        self.lastOpened = lastOpened
        self.lastPage = lastPage
        self.isFavorite = isFavorite
        self.bookmark = bookmark
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uri = try c.decodeIfPresent(String.self, forKey: .uri) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? (uri as NSString).lastPathComponent
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        size = try c.decodeIfPresent(Int64.self, forKey: .size)
        lastModified = try c.decodeIfPresent(Int64.self, forKey: .lastModified)
        lastOpened = try c.decodeIfPresent(Int64.self, forKey: .lastOpened) ?? 0
        lastPage = try c.decodeIfPresent(Int.self, forKey: .lastPage) ?? 0
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
    }
}

/// models/DocumentFolder.kt.
struct DocumentFolder: Codable, Hashable, Identifiable {
    var uri: String
    var name: String
    var itemCount: Int?
    var lastOpened: Int64 = 0
    var bookmark: Data?

    var id: String { uri }
    var url: URL? { URL(string: uri) }

    enum CodingKeys: String, CodingKey {
        case uri, name, bookmark
        case itemCount = "item_count"
        case lastOpened = "last_opened"
    }

    init(uri: String, name: String, itemCount: Int? = nil, lastOpened: Int64 = 0, bookmark: Data? = nil) {
        self.uri = uri
        self.name = name
        self.itemCount = itemCount
        self.lastOpened = lastOpened
        self.bookmark = bookmark
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uri = try c.decodeIfPresent(String.self, forKey: .uri) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? (uri as NSString).lastPathComponent
        itemCount = try c.decodeIfPresent(Int.self, forKey: .itemCount)
        lastOpened = try c.decodeIfPresent(Int64.self, forKey: .lastOpened) ?? 0
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
    }
}

/// DocumentsRepository.DocumentFolderContent.
struct DocumentFolderContent {
    var folder: DocumentFolder
    var childFolders: [DocumentFolder]
    var documents: [DocumentEntry]
}

extension Int64 {
    static var nowMillis: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}
