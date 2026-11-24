import Foundation
import UniformTypeIdentifiers

/// models/DocumentKind.kt.
enum DocumentKind: String, Codable, Hashable, CaseIterable {
    case pdf = "PDF", docx = "DOCX", text = "TEXT", markdown = "MARKDOWN", csv = "CSV", html = "HTML", other = "OTHER"

    static func from(url: URL) -> DocumentKind {
        fromName(url.lastPathComponent, mimeType: mimeType(for: url))
    }

    static func fromName(_ fileName: String, mimeType: String) -> DocumentKind {
        let name = fileName.lowercased()
        let ext = name.contains(".") ? String(name[name.index(after: name.lastIndex(of: ".")!)...]) : ""
        let mime = mimeType.split(separator: ";").first.map { String($0).lowercased() } ?? ""
        if let kind = mimeKinds[mime] { return kind }
        if let kind = extensionKinds[ext] { return kind }
        if mime.hasPrefix("text/") || textApplicationMimeTypes.contains(mime) { return .text }
        return .other
    }

    /// Context.getMimeTypeFromUri(): from the file extension.
    static func mimeType(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? ""
    }

    private static let textExtensions = ["txt", "log", "json", "xml", "yaml", "yml", "toml", "ini", "conf", "cfg",
                                         "properties", "ics", "vcf", "srt", "org", "typ", "tex", "adoc", "asciidoc", "rst"]
    private static let extensionKinds: [String: DocumentKind] = {
        var map: [String: DocumentKind] = [
            "pdf": .pdf, "docx": .docx, "md": .markdown, "markdown": .markdown, "mdown": .markdown, "mkd": .markdown,
            "csv": .csv, "tsv": .csv, "html": .html, "htm": .html, "xhtml": .html,
        ]
        for ext in textExtensions { map[ext] = .text }
        return map
    }()
    private static let mimeKinds: [String: DocumentKind] = [
        "application/pdf": .pdf,
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document": .docx,
        "text/markdown": .markdown, "text/x-markdown": .markdown,
        "text/csv": .csv, "text/comma-separated-values": .csv, "text/tab-separated-values": .csv, "application/csv": .csv,
        "text/html": .html, "application/xhtml+xml": .html,
    ]
    private static let textApplicationMimeTypes: Set<String> = [
        "application/x-tex", "application/json", "application/xml", "application/yaml", "application/x-yaml", "application/toml",
    ]

    /// DocumentIcons.kt shortLabel().
    var shortLabel: String {
        switch self {
        case .pdf: return "PDF"
        case .docx: return "DOCX"
        case .text: return "TXT"
        case .markdown: return "MD"
        case .csv: return "CSV"
        case .html: return "HTML"
        case .other: return "DOC"
        }
    }

    /// Picker types of DocumentsViewModel.openDocumentIntent.
    static let openableTypes: [UTType] = {
        var types: [UTType] = [.pdf, .plainText, .text, .commaSeparatedText, .tabSeparatedText, .html, .json, .xml, .yaml]
        for ext in ["docx", "md", "markdown", "mdown", "mkd", "xhtml", "toml", "tex", "log", "csv", "tsv"] + textExtensions {
            if let t = UTType(filenameExtension: ext), !types.contains(t) { types.append(t) }
        }
        return types
    }()
}

/// models/DocumentFilter.kt.
enum DocumentFilter: String, CaseIterable, Hashable {
    case pdf, docx, text, markdown, csv, html

    func accepts(_ kind: DocumentKind) -> Bool { DocumentFilter.from(kind) == self }

    static func from(_ kind: DocumentKind) -> DocumentFilter? {
        switch kind {
        case .pdf: return .pdf
        case .docx: return .docx
        case .text: return .text
        case .markdown: return .markdown
        case .csv: return .csv
        case .html: return .html
        case .other: return nil
        }
    }

    var label: String {
        switch self {
        case .pdf: return "PDF"
        case .docx: return "DOCX"
        case .text: return "Text"
        case .markdown: return "Markdown"
        case .csv: return "CSV"
        case .html: return "HTML"
        }
    }
}

/// models/DocumentSort.kt.
enum DocumentSort: CaseIterable, Hashable {
    case recent, nameAscending, nameDescending, sizeAscending, sizeDescending

    var label: String {
        switch self {
        case .recent: return "Recent"
        case .nameAscending: return "Name (A-Z)"
        case .nameDescending: return "Name (Z-A)"
        case .sizeAscending: return "Size (Small to Large)"
        case .sizeDescending: return "Size (Large to Small)"
        }
    }

    /// DocumentsViewModel documentComparator().
    func areInIncreasingOrder(_ a: DocumentEntry, _ b: DocumentEntry) -> Bool {
        let an = a.name.lowercased(), bn = b.name.lowercased()
        switch self {
        case .recent:
            let ar = max(a.lastOpened, a.lastModified ?? 0), br = max(b.lastOpened, b.lastModified ?? 0)
            return ar != br ? ar > br : an < bn
        case .nameAscending: return an < bn
        case .nameDescending: return an > bn
        case .sizeAscending:
            let asz = a.size ?? .max, bsz = b.size ?? .max
            return asz != bsz ? asz < bsz : an < bn
        case .sizeDescending:
            let asz = a.size ?? .min, bsz = b.size ?? .min
            return asz != bsz ? asz > bsz : an < bn
        }
    }
}

/// models/DocumentViewMode.kt.
enum DocumentViewMode: String {
    case list = "LIST", grid = "GRID"
}

/// DocumentsViewModel.DocumentsHomeSection.
enum DocumentsHomeSection: Hashable {
    case home, recent, folders, favorites, folder
}
