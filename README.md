# documents-ios

[Fossify Documents](https://github.com/FossifyOrg/Documents) re-created for iOS in SwiftUI, on top of PDFKit and WebKit.

    idl build -c release     # -> build/release/FossifyDocuments.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyDocuments

Ported: home with recent, favorites and folders, "view all" lists, folder browsing with breadcrumbs, search, type filters, sorting, list/grid view, multi-select (favorite, share, select all, open with, remove); open file/folder and new text/Markdown file; PDF reader (vertical or horizontal paging, remembered page, page indicator, contents, find, go to page, zoom, dark pages, password, save a copy, print); text and Markdown editor (find with highlights, pinch/menu zoom, word/char stats, formatting toolbar, Markdown preview, encodings, read-only notices, save as / edit a copy, reopen to edit); DOCX and HTML reader with find (scripts and remote loads blocked); CSV table with edit as text; opening documents from other apps; colors and every setting.

Differences forced by iOS: picked files and folders are remembered through security-scoped bookmarks instead of persisted URI permissions; DOCX pages are rendered by WebKit/QuickLook instead of a mammoth HTML conversion; new files and copies are placed with the system "move to" picker; no in-app language switch or custom reader font.

GPL-3.0, like the original.
