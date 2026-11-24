import Foundation
import SwiftUI

/// One rendered block of MarkdownPreview.kt, built from Foundation's CommonMark/GFM parser
/// (AttributedString(markdown:) with full syntax) instead of commonmark-java.
struct MarkdownBlock: Identifiable {
    enum Kind {
        case heading(Int)
        case paragraph
        case code
        case table([[AttributedString]], headerRows: Int)
        case thematicBreak
    }

    struct ListLevel {
        var ordered: Bool
        var ordinal: Int
        /// Only the first block of a list item draws its marker.
        var showsMarker: Bool
    }

    var id: Int
    var kind: Kind
    var text: AttributedString
    var lists: [ListLevel] = []
    var quoteDepth = 0
    var task: Bool?
}

enum MarkdownParser {
    static func parse(_ markdown: String, linkColor: Color, codeBackground: Color) -> [MarkdownBlock] {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            return [MarkdownBlock(id: 0, kind: .paragraph, text: AttributedString(markdown))]
        }
        var blocks: [MarkdownBlock] = []
        var seenItems = Set<Int>()
        var tableIndex: [Int: Int] = [:]
        var tableCells: [Int: [Int: [Int: AttributedString]]] = [:]
        var tableHeaders: [Int: Int] = [:]

        for (intent, range) in parsed.runs[\.presentationIntent] {
            var text = AttributedString(parsed[range])
            text.presentationIntent = nil
            style(&text, linkColor: linkColor, codeBackground: codeBackground)
            guard let intent else {
                blocks.append(MarkdownBlock(id: blocks.count, kind: .paragraph, text: text))
                continue
            }
            let components = intent.components
            // Tables: collect cells, emit one block per table.
            if let table = components.first(where: { if case .table = $0.kind { return true }; return false }) {
                var row = 0, column = 0, header = false
                for c in components {
                    switch c.kind {
                    case .tableCell(let col): column = col
                    case .tableRow(let r): row = r
                    case .tableHeaderRow: header = true
                    default: break
                    }
                }
                let rowKey = header ? 0 : row + 1
                if header { tableHeaders[table.identity] = 1 }
                tableCells[table.identity, default: [:]][rowKey, default: [:]][column, default: AttributedString()] += text
                if tableIndex[table.identity] == nil {
                    tableIndex[table.identity] = blocks.count
                    blocks.append(MarkdownBlock(id: blocks.count, kind: .table([], headerRows: 0), text: AttributedString()))
                }
                continue
            }
            var block = MarkdownBlock(id: blocks.count, kind: .paragraph, text: text)
            for c in components {
                switch c.kind {
                case .header(let level): block.kind = .heading(level)
                case .codeBlock:
                    block.kind = .code
                    block.text = AttributedString(String(text.characters).trimmingCharacters(in: .newlines))
                case .thematicBreak: block.kind = .thematicBreak
                case .blockQuote: block.quoteDepth += 1
                default: break
                }
            }
            // Lists, outermost first.
            for (index, c) in components.enumerated().reversed() {
                guard case .listItem(let ordinal) = c.kind else { continue }
                let parent = components.indices.contains(index + 1) ? components[index + 1].kind : nil
                var ordered = false
                if case .orderedList = parent { ordered = true }
                let first = seenItems.insert(c.identity).inserted
                block.lists.append(MarkdownBlock.ListLevel(ordered: ordered, ordinal: ordinal, showsMarker: first))
            }
            if let last = block.lists.last, last.showsMarker, case .paragraph = block.kind {
                let s = String(block.text.characters)
                for (prefix, checked) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where s.hasPrefix(prefix) {
                    block.task = checked
                    block.text.removeSubrange(block.text.startIndex..<block.text.index(block.text.startIndex, offsetByCharacters: prefix.count))
                }
            }
            blocks.append(block)
        }
        for (identity, index) in tableIndex {
            let rows = (tableCells[identity] ?? [:]).sorted { $0.key < $1.key }.map { _, cells in
                let width = (cells.keys.max() ?? -1) + 1
                return (0..<width).map { cells[$0] ?? AttributedString() }
            }
            blocks[index].kind = .table(rows, headerRows: tableHeaders[identity] ?? 0)
        }
        return blocks
    }

    /// MarkdownInlineContent.kt: code spans get a background, only http/https/mailto/tel links stay
    /// clickable, and bare URLs are autolinked (AutolinkExtension).
    private static func style(_ text: inout AttributedString, linkColor: Color, codeBackground: Color) {
        for run in text.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                text[run.range].backgroundColor = codeBackground
            }
            if let link = run.link {
                if isAllowedExternalDocumentLink(link.absoluteString) {
                    text[run.range].foregroundColor = linkColor
                    text[run.range].underlineStyle = .single
                } else {
                    text[run.range].link = nil
                }
            }
        }
        let plain = String(text.characters)
        guard plain.contains("://") || plain.contains("www."),
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }
        for match in detector.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
            guard let url = match.url, isAllowedExternalDocumentLink(url.absoluteString),
                  let r = Range(match.range, in: plain),
                  let lower = AttributedString.Index(r.lowerBound, within: text),
                  let upper = AttributedString.Index(r.upperBound, within: text),
                  text[lower..<upper].runs.allSatisfy({ $0.link == nil && $0.inlinePresentationIntent?.contains(.code) != true })
            else { continue }
            text[lower..<upper].link = url
            text[lower..<upper].foregroundColor = linkColor
            text[lower..<upper].underlineStyle = .single
        }
    }
}
