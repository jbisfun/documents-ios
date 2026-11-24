import Foundation

/// data/TextDocumentCodec.kt.
enum TextDocumentEncoding: CaseIterable {
    case utf8, utf8BOM, utf16LE, utf16BE

    var byteOrderMark: [UInt8] {
        switch self {
        case .utf8: return []
        case .utf8BOM: return [0xEF, 0xBB, 0xBF]
        case .utf16LE: return [0xFF, 0xFE]
        case .utf16BE: return [0xFE, 0xFF]
        }
    }

    var encoding: String.Encoding {
        switch self {
        case .utf8, .utf8BOM: return .utf8
        case .utf16LE: return .utf16LittleEndian
        case .utf16BE: return .utf16BigEndian
        }
    }
}

struct DecodedTextDocument {
    var text: String
    /// nil when the encoding isn't supported for editing (read-only).
    var encoding: TextDocumentEncoding?
}

enum TextDocumentCodec {
    private static let unsupportedByteOrderMarks: [[UInt8]] = [[0x00, 0x00, 0xFE, 0xFF], [0xFF, 0xFE, 0x00, 0x00]]

    static func decode(_ data: Data) -> DecodedTextDocument {
        let bytes = [UInt8](data)
        func starts(_ prefix: [UInt8]) -> Bool { bytes.count >= prefix.count && Array(bytes.prefix(prefix.count)) == prefix }
        let lossy = String(decoding: bytes, as: UTF8.self)
        if unsupportedByteOrderMarks.contains(where: starts) {
            return DecodedTextDocument(text: lossy, encoding: nil)
        }
        let encoding = TextDocumentEncoding.allCases.first { !$0.byteOrderMark.isEmpty && starts($0.byteOrderMark) } ?? .utf8
        if encoding == .utf8 && bytes.contains(0) {
            return DecodedTextDocument(text: lossy, encoding: nil)
        }
        // Strict decoding: String(data:encoding:) fails on malformed input.
        if let text = String(data: Data(bytes.dropFirst(encoding.byteOrderMark.count)), encoding: encoding.encoding) {
            return DecodedTextDocument(text: text, encoding: encoding)
        }
        return DecodedTextDocument(text: lossy, encoding: nil)
    }

    static func encode(_ text: String, _ encoding: TextDocumentEncoding) -> Data {
        Data(encoding.byteOrderMark) + (text.data(using: encoding.encoding) ?? Data())
    }
}

/// data/CsvDocumentParser.kt (Apache Commons CSV, CSVFormat.DEFAULT with a sniffed delimiter).
enum CsvDocumentParser {
    private static let delimiters: [Character] = [",", ";", "\t", "|"]

    static func parse(_ source: String, fileName: String = "") -> (rows: [[String]], columnCount: Int) {
        var text = source
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let delimiter: Character = fileName.lowercased().hasSuffix(".tsv") ? "\t" : delimiters.max { a, b in
            score(parseRows(text, a, limit: 24)) < score(parseRows(text, b, limit: 24))
        } ?? ","
        let rows = parseRows(text, delimiter)
        return (rows, rows.map(\.count).max() ?? 0)
    }

    private static func score(_ rows: [[String]]) -> Int {
        guard !rows.isEmpty else { return 0 }
        let widths = rows.map(\.count)
        var counts: [Int: Int] = [:]
        widths.forEach { counts[$0, default: 0] += 1 }
        guard let common = counts.max(by: { $0.value < $1.value }), common.key > 1 else { return 0 }
        return common.key * 100 + common.value * 10 - Set(widths).count
    }

    /// RFC 4180 records: quoted fields with doubled quotes, CRLF/LF/CR line ends, empty lines kept.
    static func parseRows(_ text: String, _ delimiter: Character, limit: Int = .max) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text)
        if chars.last == "\n" || chars.last == "\r" {
            while let last = chars.last, last == "\n" || last == "\r" { chars.removeLast() }
            if chars.isEmpty { return [] }
        }
        guard !chars.isEmpty else { return [] }
        var i = 0
        while i < chars.count && rows.count < limit {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" && field.isEmpty {
                inQuotes = true
            } else if c == delimiter {
                row.append(field)
                field = ""
            } else if c == "\n" || c == "\r" || c == "\r\n" {
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(c)
            }
            i += 1
        }
        if rows.count < limit {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
