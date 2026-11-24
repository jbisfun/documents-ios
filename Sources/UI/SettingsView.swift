import FossifyCommons
import SwiftUI

/// SettingsActivity / ui/screens/SettingsScreen.kt.
struct SettingsView: View {
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var config = config
        VStack(spacing: 0) {
            TopBar(title: "Settings")
            ScrollView {
                VStack(spacing: 0) {
                    Text("Color customization").sectionHeader(palette)
                    SettingsItem("Customize colors") { router.push(.customizeColors) }

                    Divider().overlay(palette.divider)
                    Text("Documents").sectionHeader(palette)
                    SettingsToggle("Show file locations", isOn: $config.showFileLocations)

                    Divider().overlay(palette.divider)
                    Text("PDF reading").sectionHeader(palette)
                    SettingsToggle("Scroll PDFs horizontally", isOn: $config.pdfHorizontalPaging)
                    SettingsToggle("Remember PDF page", isOn: $config.rememberPdfPage)
                    SettingsToggle("Floating page indicator", isOn: $config.pdfPageIndicator)
                }
                .padding(.bottom, 32)
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
    }
}

extension AppInfo {
    public static let documents = AppInfo(
        name: "Documents", icon: "doc.text", upstream: "Documents", port: "documents-ios", policy: "documents"
    )
}
