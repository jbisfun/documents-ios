import FossifyCommons
import SwiftUI

/// DocumentRows.kt DocumentRow.
struct DocumentRow: View {
    @Environment(\.palette) private var palette
    let document: DocumentEntry
    let showLocation: Bool
    let selected: Bool

    var body: some View {
        HStack(spacing: 16) {
            DocumentKindIcon(kind: document.kind)
            VStack(alignment: .leading, spacing: 0) {
                Text(document.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.textColor)
                    .lineLimit(1)
                Text(document.metaLine())
                    .font(.system(size: 14))
                    .foregroundStyle(palette.textColor.opacity(0.66))
                    .lineLimit(1)
                    .padding(.top, 3)
                if showLocation && !document.location.isEmpty {
                    Text(document.location)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textColor.opacity(0.58))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .background(selected ? palette.primaryTint : Color.clear)
        .animation(.easeInOut(duration: 0.18), value: selected)
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// DocumentRows.kt FolderRow.
struct FolderRow: View {
    @Environment(\.palette) private var palette
    let folder: DocumentFolder
    let selected: Bool

    var body: some View {
        HStack(spacing: 16) {
            FolderIcon()
            VStack(alignment: .leading, spacing: 0) {
                Text(folder.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.textColor)
                    .lineLimit(1)
                if let count = folder.itemCount {
                    Text(folderItemCountText(count))
                        .font(.system(size: 14))
                        .foregroundStyle(palette.textColor.opacity(0.66))
                        .lineLimit(1)
                        .padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .background(selected ? palette.primaryTint : Color.clear)
        .animation(.easeInOut(duration: 0.18), value: selected)
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// DocumentGridCards.kt DocumentGridCard.
struct DocumentGridCard: View {
    @Environment(\.palette) private var palette
    let document: DocumentEntry
    let showLocation: Bool
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DocumentKindIcon(kind: document.kind)
            Text(document.name)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.textColor)
                .lineLimit(1)
            Text(document.metaLine())
                .font(.system(size: 14))
                .foregroundStyle(palette.textColor.opacity(0.66))
                .lineLimit(1)
            if showLocation {
                Text(document.location.isEmpty ? " " : document.location)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textColor.opacity(0.58))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? palette.primaryTint : palette.backgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? palette.primaryColor : palette.textColor.opacity(0.14), lineWidth: 1))
        .overlay(alignment: .topTrailing) { if selected { SelectionBadge().padding(10) } }
        .animation(.easeInOut(duration: 0.18), value: selected)
        .contentShape(Rectangle())
    }
}

/// DocumentGridCards.kt FolderGridCard.
struct FolderGridCard: View {
    @Environment(\.palette) private var palette
    let folder: DocumentFolder
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            FolderIcon().overlay(alignment: .topTrailing) { if selected { SelectionBadge() } }
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.textColor)
                    .lineLimit(1)
                Text(folder.itemCount.map(folderItemCountText) ?? " ")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textColor.opacity(0.66))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? palette.primaryTint : palette.backgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? palette.primaryColor : palette.textColor.opacity(0.14), lineWidth: 1))
        .animation(.easeInOut(duration: 0.18), value: selected)
        .contentShape(Rectangle())
    }
}

/// DocumentsHomeChrome.kt SectionHeader with its "View all" action.
struct SectionHeader: View {
    @Environment(\.palette) private var palette
    let title: String
    let onViewAll: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.textColor)
                .lineLimit(1)
            Spacer()
            Button(action: onViewAll) {
                Text("View all").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.primaryColor)
                    .padding(.horizontal, 12).frame(height: 40)
            }
        }
        .padding(.leading, 24)
        .padding(.trailing, 16)
    }
}

/// DocumentsHomeChrome.kt DocumentFilterChips item.
struct FilterChip: View {
    @Environment(\.palette) private var palette
    let filter: DocumentFilter
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark" : filter.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? palette.textColor : filter.iconTint(palette))
                Text(filter.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textColor)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? palette.primaryColor.opacity(palette.dark ? 0.28 : 0.14) : palette.backgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.clear : palette.textColor.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// DocumentsSortViewMenu.kt SortAndViewRow.
struct SortAndViewRow: View {
    @Environment(DocumentsStore.self) private var store
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    let availableSorts: [DocumentSort]

    var body: some View {
        HStack {
            Menu {
                ForEach(availableSorts, id: \.self) { sort in
                    Button { store.updateDisplayOptions(sort: sort) } label: {
                        if sort == store.selectedSort { Label(sort.label, systemImage: "checkmark") } else { Text(sort.label) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Sort by:").foregroundStyle(palette.textColor.opacity(0.76))
                    Text(store.selectedSort.label).fontWeight(.semibold).foregroundStyle(palette.primaryColor).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textColor)
                }
                .font(.system(size: 14))
                .padding(.horizontal, 8)
                .frame(minHeight: 48)
            }
            Spacer()
            let target: DocumentViewMode = config.documentViewMode == .list ? .grid : .list
            IconButton(icon: target == .list ? "list.bullet" : "square.grid.2x2") {
                store.updateDisplayOptions(viewMode: target)
            }
            .accessibilityLabel(target == .list ? "List" : "Grid")
            .foregroundStyle(palette.textColor)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
    }
}

/// DocumentsFocusedChrome.kt DocumentsBreadcrumb.
struct DocumentsBreadcrumb: View {
    @Environment(DocumentsStore.self) private var store
    @Environment(\.palette) private var palette

    var body: some View {
        let path = store.activeFolderPath
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Image(systemName: store.homeSection == .folders ? "folder.fill" : "house.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(palette.primaryColor)
                    crumb("Folders", selected: store.homeSection == .folders,
                          action: store.homeSection == .folder ? { store.showSection(.folders) } : nil)
                    if store.homeSection == .folder {
                        if path.isEmpty {
                            separator
                            crumb(store.activeFolder?.name ?? "Folders", selected: true, action: nil)
                        }
                        ForEach(Array(path.enumerated()), id: \.offset) { index, folder in
                            separator
                            crumb(folder.name, selected: index == path.count - 1,
                                  action: index < path.count - 1 ? { store.navigateToBreadcrumb(index) } : nil)
                        }
                    }
                    Color.clear.frame(width: 1, height: 1).id("end")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .frame(minHeight: 52)
            }
            .onChange(of: path.last?.uri) { proxy.scrollTo("end", anchor: .trailing) }
            .onAppear { proxy.scrollTo("end", anchor: .trailing) }
        }
    }

    private var separator: some View {
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textColor.opacity(0.55))
    }

    @ViewBuilder
    private func crumb(_ text: String, selected: Bool, action: (() -> Void)?) -> some View {
        let label = Text(text)
            .font(.system(size: 16, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? palette.primaryColor : palette.textColor.opacity(0.72))
            .lineLimit(1)
        if let action {
            Button(action: action) { label.padding(.horizontal, 8).frame(height: 40) }.buttonStyle(.plain)
        } else {
            label.padding(.horizontal, 4).padding(.vertical, 8)
        }
    }
}
