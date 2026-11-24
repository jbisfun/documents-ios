import FossifyCommons
import Observation
import SwiftUI
import UIKit

enum Route: Hashable {
    case text(String, DocumentKind)
    case structured(String, DocumentKind)
    case pdf(String)
    case settings
    case customizeColors
    case about
}

@MainActor
@Observable
final class Router {
    var path: [Route] = []

    func push(_ r: Route) { path.append(r) }
    func pop() { if !path.isEmpty { path.removeLast() } }
}

/// The whole app as one view: the standalone app's window content, and what
/// the launcher presents. `openURL` is a document handed over by the launcher
/// (DocumentOpenActivity).
public struct DocumentsRoot: View {
    @State private var store = DocumentsStore()
    @State private var router = Router()
    private let openURL: URL?

    public init(openURL: URL? = nil) {
        self.openURL = openURL
    }

    public var body: some View {
        RootView(openURL: openURL)
            .environment(store)
            .environment(router)
            .environment(Config.shared)
            .fossifyTheme()
    }
}

struct RootView: View {
    @Environment(DocumentsStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var phase
    let openURL: URL?

    var body: some View {
        @Bindable var router = router
        @Bindable var store = store
        NavigationStack(path: $router.path) {
            MainView()
                .navigationDestination(for: Route.self) { route in
                    Group {
                        switch route {
                        case .text(let uri, let kind): TextDocumentView(uri: uri, kind: kind)
                        case .structured(let uri, let kind): StructuredDocumentView(uri: uri, kind: kind)
                        case .pdf(let uri): PdfDocumentView(uri: uri)
                        case .settings: SettingsView()
                        case .customizeColors: CustomizeColorsView()
                        case .about: AboutView(app: .documents)
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .paletteBackground()
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .toast($store.toast)
        .onOpenURL { open($0) }
        .onAppear { if let openURL { open(openURL) } }
        .onChange(of: phase) { _, p in
            // MainActivity.onResume(): refresh the visible folder.
            if p == .active && store.homeSection == .folder { store.refreshVisibleFolder() }
        }
    }

    /// DocumentOpenActivity: route an incoming file to its viewer.
    private func open(_ url: URL) {
        let kind = DocumentKind.from(url: url)
        guard kind != .other else {
            store.toast = "This document type is not supported yet."
            return
        }
        guard store.prepareDocument(url.absoluteString, picked: url) else {
            store.toast = "This document is no longer available. Open it again to restore access."
            return
        }
        router.path = []
        router.push(DocumentLauncher.route(url.absoluteString, kind))
    }
}

/// MainActivity.launchDocument().
enum DocumentLauncher {
    static func route(_ uri: String, _ kind: DocumentKind) -> Route {
        switch kind {
        case .pdf: return .pdf(uri)
        case .text, .markdown, .other: return .text(uri, kind)
        case .docx, .csv, .html: return .structured(uri, kind)
        }
    }
}
