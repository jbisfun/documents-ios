import FossifyCommons
import SwiftUI

extension Palette {
    /// primaryTintAlpha().
    var tintAlpha: Double { dark ? 0.25 : 0.14 }
    var primaryTint: Color { primaryColor.opacity(tintAlpha) }
    /// markdownNeutralSurfaceColor().
    func neutralSurface(_ alpha: Double) -> Color { backgroundColor.mix(with: textColor, by: alpha) }
}

/// DocumentIcons.kt DocumentKindIcon.
struct DocumentKindIcon: View {
    @Environment(\.palette) private var palette
    let kind: DocumentKind

    var body: some View {
        let (icon, container, content) = spec
        RoundedRectangle(cornerRadius: 8)
            .fill(container)
            .frame(width: 48, height: 48)
            .overlay {
                if kind == .markdown {
                    Text("M↓").font(.system(size: 16, weight: .bold)).foregroundStyle(content)
                } else {
                    Image(systemName: icon).font(.system(size: 22)).foregroundStyle(content)
                }
            }
    }

    private var spec: (String, Color, Color) {
        let dark = palette.dark
        func themed(_ icon: String, _ lc: UInt32, _ lt: UInt32, _ dc: UInt32, _ dt: UInt32) -> (String, Color, Color) {
            (icon, Color(argb: dark ? dc : lc), Color(argb: dark ? dt : lt))
        }
        switch kind {
        case .pdf: return themed("doc.richtext.fill", 0xFFF8DCDC, 0xFFE52620, 0xFF55302F, 0xFFFFDAD7)
        case .docx: return themed("doc.text.fill", 0xFFDCEAFF, 0xFF185ABD, 0xFF243F60, 0xFFD5E3FF)
        case .text: return ("doc.plaintext.fill", palette.primaryTint, palette.textColor)
        case .markdown: return ("doc.fill", palette.primaryTint, palette.primaryColor)
        case .csv: return themed("tablecells.fill", 0xFFD8F3E2, 0xFF167044, 0xFF1E4935, 0xFFB7E9C8)
        case .html: return themed("chevron.left.forwardslash.chevron.right", 0xFFFFE2D3, 0xFFB84218, 0xFF5A3525, 0xFFFFDBCA)
        case .other: return ("doc.fill", palette.textColor.opacity(dark ? 0.18 : 0.08), palette.textColor.opacity(0.72))
        }
    }
}

extension DocumentFilter {
    /// DocumentFilter.iconTint().
    func iconTint(_ palette: Palette) -> Color {
        switch self {
        case .pdf: return Color(argb: palette.dark ? 0xFFFFDAD7 : 0xFFE52620)
        case .docx: return Color(argb: palette.dark ? 0xFFD5E3FF : 0xFF185ABD)
        case .csv: return Color(argb: palette.dark ? 0xFFB7E9C8 : 0xFF167044)
        case .html: return Color(argb: palette.dark ? 0xFFFFDBCA : 0xFFB84218)
        case .text, .markdown: return palette.textColor
        }
    }

    var icon: String {
        switch self {
        case .pdf: return "doc.richtext.fill"
        case .docx, .text: return "doc.text.fill"
        case .markdown: return "doc.fill"
        case .csv: return "tablecells.fill"
        case .html: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct FolderIcon: View {
    @Environment(\.palette) private var palette

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(palette.primaryTint)
            .frame(width: 48, height: 48)
            .overlay(Image(systemName: "folder.fill").font(.system(size: 22)).foregroundStyle(palette.primaryColor))
    }
}

extension DocumentEntry {
    /// DocumentIcons.kt metaLine().
    func metaLine(showOpenedFallback: Bool = true) -> String {
        var parts: [String] = []
        if let lastModified, lastModified > 0 {
            parts.append(Date(timeIntervalSince1970: Double(lastModified) / 1000).formatted(date: .abbreviated, time: .omitted))
        } else if showOpenedFallback && lastOpened > 0 {
            let relative = RelativeDateTimeFormatter().localizedString(
                for: Date(timeIntervalSince1970: Double(lastOpened) / 1000), relativeTo: Date())
            parts.append("Opened \(relative)")
        }
        if let size { parts.append(size.formattedSize) }
        let line = parts.joined(separator: " · ")
        return line.isEmpty ? kind.shortLabel : line
    }
}

func folderItemCountText(_ count: Int) -> String { "\(count) \(count == 1 ? "item" : "items")" }

/// DocumentGridCards.kt SelectionBadge.
struct SelectionBadge: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Circle().fill(palette.primaryColor).frame(width: 24, height: 24)
            .overlay(Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.onPrimary))
    }
}

/// DocumentsHomeActions.kt DocumentsEmptyState.
struct DocumentsEmptyState<Actions: View>: View {
    @Environment(\.palette) private var palette
    let icon: String
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 24)
                .fill(palette.primaryTint)
                .frame(width: 84, height: 84)
                .overlay(Image(systemName: icon).font(.system(size: 38)).foregroundStyle(palette.primaryColor))
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(palette.textColor)
                .padding(.top, 22)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(palette.textColor.opacity(0.68))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            HStack(spacing: 12, content: actions).padding(.top, 24)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 44)
    }
}

extension DocumentsEmptyState where Actions == EmptyView {
    init(icon: String, title: String, message: String) {
        self.init(icon: icon, title: title, message: message, actions: { EmptyView() })
    }
}

/// FilledTonalButton.
struct TonalButton: View {
    @Environment(\.palette) private var palette
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textColor)
                .padding(.horizontal, 20)
                .frame(height: 40)
                .background(Capsule().fill(palette.primaryColor.opacity(palette.dark ? 0.3 : 0.18)))
        }
        .buttonStyle(.plain)
    }
}

/// TextDocumentStatusComponents.kt StatusStrip.
struct StatusStrip<Action: View>: View {
    @Environment(\.palette) private var palette
    let text: String
    let isError: Bool
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack {
            Text(text).font(.system(size: 14)).padding(.vertical, 8)
            Spacer(minLength: 8)
            action()
        }
        .foregroundStyle(isError ? Color(argb: palette.dark ? 0xFFFFDAD6 : 0xFF410002) : palette.textColor)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isError ? Color(argb: palette.dark ? 0xFF93000A : 0xFFFFDAD6) : palette.neutralSurface(0.1))
    }
}

extension StatusStrip where Action == EmptyView {
    init(text: String, isError: Bool) {
        self.init(text: text, isError: isError, action: { EmptyView() })
    }
}

struct StatusDocument: View {
    @Environment(\.palette) private var palette
    let text: String
    let isError: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 16))
            .foregroundStyle(isError ? Color(argb: 0xFFBA1A1A) : palette.secondaryText)
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LoadingDocument: View {
    var body: some View {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// TextDocumentControls.kt TextDocumentSearchField.
struct DocumentSearchField: View {
    @Environment(\.palette) private var palette
    @Binding var query: String
    let currentMatchNumber: Int
    let matchCount: Int
    let onNextMatch: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: $query, prompt: Text("Find in document").foregroundStyle(palette.secondaryText))
                .font(.system(size: 17))
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit(onNextMatch)
            if !query.isEmpty {
                Text("\(currentMatchNumber) / \(matchCount)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .onAppear { focused = true }
    }
}

/// Top bar of the document screens: back arrow, title or the find field, actions.
struct DocumentTopBar<Actions: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    let onBack: () -> Void
    var search: (query: Binding<String>, current: Int, count: Int, next: () -> Void)?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        if let search {
            HStack(spacing: 4) {
                Button(action: onBack) {
                    Image(systemName: "arrow.left").font(.system(size: 20)).frame(width: 48, height: 48)
                }
                DocumentSearchField(query: search.query, currentMatchNumber: search.current, matchCount: search.count,
                                    onNextMatch: search.next)
                actions()
            }
            .foregroundStyle(palette.textColor)
            .padding(.horizontal, 4)
            .frame(height: 56)
            .background(palette.backgroundColor)
        } else {
            TopBar(title: title, onBack: onBack, trailing: actions)
        }
    }
}
