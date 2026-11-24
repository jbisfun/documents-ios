import Foundation

/// ui/screens/MarkdownEditAction.kt, on NSString/UTF-16 ranges as used by UITextView.
enum MarkdownEditAction: CaseIterable {
    case heading, bold, italic, bullet, numberedList, quote, code

    var title: String {
        switch self {
        case .heading: return "Heading"
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .bullet: return "Bullet list"
        case .numberedList: return "Numbered list"
        case .quote: return "Quote"
        case .code: return "Code"
        }
    }

    var icon: String {
        switch self {
        case .heading: return "textformat.size"
        case .bold: return "bold"
        case .italic: return "italic"
        case .bullet: return "list.bullet"
        case .numberedList: return "list.number"
        case .quote: return "text.quote"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }

    func apply(text: String, selection: NSRange) -> (text: String, selection: NSRange) {
        let value = MarkdownEditValue(text: text as NSString, selection: selection)
        let result: MarkdownEditValue
        switch self {
        case .heading: result = value.toggleHeading()
        case .bold: result = value.wrapSelection("**", "**", placeholder: "bold")
        case .italic: result = value.wrapSelection("_", "_", placeholder: "italic")
        case .bullet: result = value.prefixSelectedLines("- ")
        case .numberedList: result = value.toggleNumberedList()
        case .quote: result = value.prefixSelectedLines("> ")
        case .code: result = value.codeSelection()
        }
        return (result.text as String, result.selection)
    }
}

private struct MarkdownEditValue {
    var text: NSString
    var selection: NSRange

    private static let headingPrefix = try! NSRegularExpression(pattern: "^#{1,6}\\s*")
    private static let numberedPrefix = try! NSRegularExpression(pattern: "^\\d+[.)]\\s+")

    func wrapSelection(_ prefix: String, _ suffix: String, placeholder: String) -> MarkdownEditValue {
        let start = selection.location, end = NSMaxRange(selection)
        let selected = text.substring(with: selection)
        let p = prefix as NSString, s = suffix as NSString
        if (selected as NSString).length >= p.length + s.length && selected.hasPrefix(prefix) && selected.hasSuffix(suffix) {
            let inner = (selected as NSString).substring(with: NSRange(location: p.length, length: (selected as NSString).length - p.length - s.length))
            return MarkdownEditValue(text: text.replacingCharacters(in: selection, with: inner) as NSString,
                                     selection: NSRange(location: start, length: (inner as NSString).length))
        }
        let outerStart = start - p.length, outerEnd = end + s.length
        if outerStart >= 0 && outerEnd <= text.length
            && text.substring(with: NSRange(location: outerStart, length: p.length)) == prefix
            && text.substring(with: NSRange(location: end, length: s.length)) == suffix {
            return MarkdownEditValue(
                text: text.replacingCharacters(in: NSRange(location: outerStart, length: outerEnd - outerStart), with: selected) as NSString,
                selection: NSRange(location: outerStart, length: (selected as NSString).length))
        }
        let content = selected.isEmpty ? placeholder : selected
        let replacement = prefix + content + suffix
        let newText = text.replacingCharacters(in: selection, with: replacement) as NSString
        let newSelection = selected.isEmpty
            ? NSRange(location: start + p.length, length: (placeholder as NSString).length)
            : NSRange(location: start, length: (replacement as NSString).length)
        return MarkdownEditValue(text: newText, selection: newSelection)
    }

    func prefixSelectedLines(_ prefix: String) -> MarkdownEditValue {
        transformSelectedLines { lines in
            lines.map { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : prefix + $0 }
        }
    }

    func toggleHeading() -> MarkdownEditValue {
        transformSelectedLines { lines in
            lines.map { line in
                if line.hasPrefix("# ") { return String(line.dropFirst(2)) }
                let ns = line as NSString
                return "# " + Self.headingPrefix.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: ns.length), withTemplate: "")
            }
        }
    }

    func toggleNumberedList() -> MarkdownEditValue {
        transformSelectedLines { lines in
            func strip(_ l: String) -> String {
                Self.numberedPrefix.stringByReplacingMatches(in: l, range: NSRange(location: 0, length: (l as NSString).length), withTemplate: "")
            }
            let remove = lines.allSatisfy { Self.numberedPrefix.firstMatch(in: $0, range: NSRange(location: 0, length: ($0 as NSString).length)) != nil }
            return lines.enumerated().map { i, line in remove ? strip(line) : "\(i + 1). \(strip(line))" }
        }
    }

    func transformSelectedLines(_ transform: ([String]) -> [String]) -> MarkdownEditValue {
        let start = selection.location, end = NSMaxRange(selection)
        var lineStart = 0
        if start > 0 {
            let r = text.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: start))
            lineStart = r.location == NSNotFound ? 0 : r.location + 1
        }
        let after = text.range(of: "\n", range: NSRange(location: end, length: text.length - end))
        let lineEnd = after.location == NSNotFound ? text.length : after.location
        let range = NSRange(location: lineStart, length: lineEnd - lineStart)
        let lines = text.substring(with: range).components(separatedBy: "\n")
        let replacement = transform(lines).joined(separator: "\n")
        let newText = text.replacingCharacters(in: range, with: replacement) as NSString
        let delta = (replacement as NSString).length - range.length
        return MarkdownEditValue(text: newText, selection: NSRange(location: min(max(end + delta, 0), newText.length), length: 0))
    }

    func codeSelection() -> MarkdownEditValue {
        let selected = text.substring(with: selection)
        return selected.contains("\n") ? wrapSelection("```\n", "\n```", placeholder: selected) : wrapSelection("`", "`", placeholder: "code")
    }
}

/// TextDocumentDisplay.kt.
let defaultDocumentTextZoom = 1.0
let minDocumentTextZoom = 0.75
let maxDocumentTextZoom = 3.0
let documentTextZoomStep = 0.15
let maxSearchHighlightCount = 5_000

func coerceDocumentTextZoom(_ zoom: Double) -> Double {
    zoom.isFinite ? min(max(zoom, minDocumentTextZoom), maxDocumentTextZoom) : defaultDocumentTextZoom
}

/// findTextMatches(): case-insensitive, non-overlapping, as UTF-16 ranges.
func findTextMatches(_ text: String, _ query: String) -> [NSRange] {
    guard !query.isEmpty, !text.isEmpty else { return [] }
    let ns = text as NSString
    var result: [NSRange] = []
    var from = 0
    while from < ns.length {
        let r = ns.range(of: query, options: .caseInsensitive, range: NSRange(location: from, length: ns.length - from))
        if r.location == NSNotFound { break }
        result.append(r)
        from = NSMaxRange(r)
    }
    return result
}

/// TextDocumentFormatters.kt documentStats().
func documentStats(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let words = trimmed.isEmpty ? 0 : trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    let chars = (text as NSString).length
    return "\(words) \(words == 1 ? "word" : "words"), \(chars) \(chars == 1 ? "char" : "chars")"
}

/// data/DocumentLinks.kt.
func isAllowedExternalDocumentLink(_ destination: String) -> Bool {
    guard let colon = destination.firstIndex(of: ":") else { return false }
    return ["http", "https", "mailto", "tel"].contains(destination[..<colon].lowercased())
}
