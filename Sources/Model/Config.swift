import Foundation
import Observation

/// Port of helpers/Config.kt (SharedPreferences -> UserDefaults); colors live in FossifyCommons.BaseConfig.
@Observable
final class Config {
    static let shared = Config()

    @ObservationIgnored private let d = UserDefaults.standard

    var documentViewMode: DocumentViewMode { didSet { d.set(documentViewMode.rawValue, forKey: "document_view_mode") } }
    var editorTextZoom: Double { didSet { d.set(editorTextZoom, forKey: "editor_text_zoom") } }
    var pdfDarkPages: Bool { didSet { d.set(pdfDarkPages, forKey: "pdf_dark_pages") } }
    var pdfHorizontalPaging: Bool { didSet { d.set(pdfHorizontalPaging, forKey: "pdf_horizontal_paging") } }
    var pdfPageIndicator: Bool { didSet { d.set(pdfPageIndicator, forKey: "pdf_page_indicator") } }
    var rememberPdfPage: Bool { didSet { d.set(rememberPdfPage, forKey: "remember_pdf_page") } }
    var showFileLocations: Bool { didSet { d.set(showFileLocations, forKey: "show_file_locations") } }

    /// JSON arrays, as upstream ("documents", "document_folders").
    var documentsJson: String { didSet { d.set(documentsJson, forKey: "documents") } }
    var documentFoldersJson: String { didSet { d.set(documentFoldersJson, forKey: "document_folders") } }

    private init() {
        documentViewMode = DocumentViewMode(rawValue: d.string(forKey: "document_view_mode") ?? "") ?? .list
        editorTextZoom = d.object(forKey: "editor_text_zoom") as? Double ?? 1
        pdfDarkPages = d.object(forKey: "pdf_dark_pages") as? Bool ?? false
        pdfHorizontalPaging = d.object(forKey: "pdf_horizontal_paging") as? Bool ?? false
        pdfPageIndicator = d.object(forKey: "pdf_page_indicator") as? Bool ?? true
        rememberPdfPage = d.object(forKey: "remember_pdf_page") as? Bool ?? true
        showFileLocations = d.object(forKey: "show_file_locations") as? Bool ?? false
        documentsJson = d.string(forKey: "documents") ?? "[]"
        documentFoldersJson = d.string(forKey: "document_folders") ?? "[]"
    }
}
