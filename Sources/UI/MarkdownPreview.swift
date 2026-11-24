import FossifyCommons
import SwiftUI

/// ui/screens/MarkdownPreview.kt.
struct MarkdownPreview: View {
    @Environment(\.palette) private var palette
    let markdown: String
    let zoom: Double
    let onZoom: (Double) -> Void
    @State private var pinchStart: Double?

    var body: some View {
        let blocks = MarkdownParser.parse(markdown, linkColor: palette.primaryColor, codeBackground: palette.neutralSurface(0.08))
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(blocks) { block in blockView(block) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .textSelection(.enabled)
        }
        .environment(\.openURL, OpenURLAction { url in
            isAllowedExternalDocumentLink(url.absoluteString) ? .systemAction : .discarded
        })
        .simultaneousGesture(MagnifyGesture()
            .onChanged { value in
                if pinchStart == nil { pinchStart = zoom }
                onZoom(coerceDocumentTextZoom((pinchStart ?? zoom) * value.magnification))
            }
            .onEnded { _ in pinchStart = nil })
    }

    private func z(_ size: CGFloat) -> CGFloat { size * zoom }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        let inner = blockContent(block)
        let quoted = inner.modifier(QuoteBars(depth: block.quoteDepth, color: palette.textColor.opacity(0.4)))
        if block.lists.isEmpty {
            quoted
        } else {
            HStack(alignment: .firstTextBaseline, spacing: z(8)) {
                ZStack(alignment: .trailing) {
                    if let level = block.lists.last, level.showsMarker {
                        if let task = block.task {
                            Image(systemName: task ? "checkmark.square.fill" : "square")
                                .font(.system(size: z(18)))
                                .foregroundStyle(palette.primaryColor)
                        } else {
                            Text(level.ordered ? "\(level.ordinal)." : "•")
                                .font(.system(size: z(16)))
                                .foregroundStyle(palette.primaryColor)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                }
                .frame(width: z(24), alignment: .trailing)
                quoted
            }
            .padding(.leading, CGFloat(block.lists.count - 1) * z(32))
            .padding(.vertical, z(2))
        }
    }

    @ViewBuilder
    private func blockContent(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(block.text)
                .font(.system(size: z(level == 1 ? 32 : level == 2 ? 28 : 22), weight: .semibold))
                .foregroundStyle(palette.textColor)
                .padding(.top, 12)
                .padding(.bottom, 6)
        case .paragraph:
            Text(block.text)
                .font(.system(size: z(16)))
                .lineSpacing(z(5))
                .foregroundStyle(palette.textColor)
                .padding(.vertical, block.lists.isEmpty ? 4 : 0)
        case .code:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.text)
                    .font(.system(size: z(14), design: .monospaced))
                    .lineSpacing(z(6))
                    .foregroundStyle(palette.textColor.opacity(0.8))
                    .fixedSize()
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.neutralSurface(0.06))
            .padding(.vertical, 8)
        case .thematicBreak:
            Divider().overlay(palette.divider).padding(.vertical, 12)
        case .table(let rows, let headerRows):
            MarkdownTable(rows: rows, headerRows: headerRows, zoom: zoom)
        }
    }
}

private struct QuoteBars: ViewModifier {
    let depth: Int
    let color: Color

    func body(content: Content) -> some View {
        if depth == 0 {
            content
        } else {
            HStack(alignment: .top, spacing: 0) {
                ForEach(0..<depth, id: \.self) { _ in
                    Rectangle().fill(color).frame(width: 3).padding(.trailing, 12)
                }
                content
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
        }
    }
}

/// MarkdownTable: bordered cells, min column width 144, horizontally scrollable.
private struct MarkdownTable: View {
    @Environment(\.palette) private var palette
    let rows: [[AttributedString]]
    let headerRows: Int
    let zoom: Double

    var body: some View {
        let columns = max(rows.map(\.count).max() ?? 1, 1)
        GeometryReader { geo in
            let width = max(geo.size.width, CGFloat(144 * columns))
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(rows.indices, id: \.self) { r in
                        GridRow {
                            ForEach(0..<columns, id: \.self) { c in
                                let header = r < headerRows
                                Text(rows[r].indices.contains(c) ? rows[r][c] : AttributedString())
                                    .font(.system(size: 14 * zoom, weight: header ? .semibold : .regular))
                                    .foregroundStyle(palette.textColor)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(width: width / CGFloat(columns), alignment: .leading)
                                    .frame(maxHeight: .infinity, alignment: .topLeading)
                                    .background(header ? palette.neutralSurface(0.1) : palette.backgroundColor)
                                    .border(palette.textColor.opacity(0.2), width: 0.5)
                            }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { g in Color.clear.preference(key: TableHeightKey.self, value: g.size.height) })
            }
        }
        .modifier(TableHeight())
        .padding(.vertical, 8)
    }
}

private struct TableHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// GeometryReader takes all offered height; size it to the table it measures.
private struct TableHeight: ViewModifier {
    @State private var height: CGFloat = 40

    func body(content: Content) -> some View {
        content.frame(height: height).onPreferenceChange(TableHeightKey.self) { height = max($0, 1) }
    }
}
