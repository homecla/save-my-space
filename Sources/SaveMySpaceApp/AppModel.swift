// SPDX-FileCopyrightText: 2026 homecla
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Foundation
import Observation
import SaveMySpaceCore
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    var report: ScanReport?
    var findings: [Finding] = []
    var selection: Set<String> = []
    var isScanning = false
    var progressText = ""
    var maxRisk: Risk = .caution
    var lastMessage: String?
    var sidebarCategory: SidebarItem? = SidebarItem(category: nil)
    var confirmingTrash = false

    // Opzioni
    var largeSizeGB: Double = 0.5
    var olderThanDays = 90
    var findDuplicates = true

    // Lingua: `nil` = automatica (SMSPACE_LANG o lingua di sistema).
    private static let languageKey = "language"
    private(set) var language: Language = L10n.language
    var languagePreference: Language? {
        didSet {
            UserDefaults.standard.set(languagePreference?.rawValue, forKey: Self.languageKey)
            applyLanguage()
            if report != nil {
                lastMessage = tr("Analyze again to see the suggestions in the new language.",
                                 "Rianalizza per vedere i suggerimenti nella nuova lingua.")
            }
        }
    }

    private var scanTask: Task<Void, Never>?

    init() {
        languagePreference = UserDefaults.standard.string(forKey: Self.languageKey).flatMap(Language.init(rawValue:))
        applyLanguage()
    }

    private func applyLanguage() {
        L10n.language = languagePreference ?? L10n.detect()
        language = L10n.language
    }

    var root: URL { FileManager.default.homeDirectoryForCurrentUser }

    func findings(in category: CleanupCategory?) -> [Finding] {
        findings.filter { (category == nil || $0.category == category) && $0.risk <= maxRisk }
    }

    func total(of category: CleanupCategory?) -> Int64 {
        findings(in: category).reduce(0) { $0 + $1.size }
    }

    var selectedFindings: [Finding] {
        findings.filter { selection.contains($0.path) && $0.actionable }
    }

    var selectedSize: Int64 { selectedFindings.reduce(0) { $0 + $1.size } }

    func scan() {
        scanTask?.cancel()
        isScanning = true
        lastMessage = nil
        progressText = tr("Starting…", "Avvio…")
        let options = ScanOptions(
            root: root,
            largeFileThreshold: Int64(largeSizeGB * 1e9),
            olderThanDays: olderThanDays,
            findDuplicates: findDuplicates
        )
        scanTask = Task {
            let scanner = Scanner(options: options)
            do {
                let report = try await Task.detached(priority: .userInitiated) {
                    try scanner.scan { p in
                        let text = "\(p.phase)… \(p.itemsScanned.formatted()) " + tr("items", "elementi")
                        Task { @MainActor in self.progressText = text }
                    }
                }.value
                self.report = report
                self.findings = report.findings
                self.selection = []
            } catch is CancellationError {
                lastMessage = tr("Scan cancelled.", "Scansione annullata.")
            } catch {
                lastMessage = tr("Error: ", "Errore: ") + error.localizedDescription
            }
            isScanning = false
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func selectAllSafe(in category: CleanupCategory?) {
        for f in findings(in: category) where f.actionable && f.risk == .safe {
            selection.insert(f.path)
        }
    }

    func toggle(_ finding: Finding) {
        if selection.contains(finding.path) {
            selection.remove(finding.path)
        } else if finding.actionable {
            selection.insert(finding.path)
        }
    }

    func moveSelectionToTrash() {
        let cleaner = Cleaner(root: root)
        let result = cleaner.clean(selectedFindings)
        let trashedPaths = Set(result.trashed.map(\.finding.path))
        findings.removeAll { trashedPaths.contains($0.path) }
        selection.subtract(trashedPaths)
        let freed = SizeFormatter.string(result.freedBytes)
        var message = tr("Moved \(result.trashed.count) items to the Trash (\(freed)).",
                         "Spostati nel Cestino \(result.trashed.count) elementi (\(freed)).")
        if !result.failed.isEmpty {
            message += " " + tr("\(result.failed.count) not moved:", "\(result.failed.count) non spostati:")
            for failure in result.failed.prefix(3) {
                message += "\n• " + displayPath(failure.finding.path) + " — " + failure.message
            }
            if result.failed.count > 3 {
                message += "\n• " + tr("…and \(result.failed.count - 3) more (see the history).",
                                        "…e altri \(result.failed.count - 3) (vedi lo storico).")
            }
            message += "\n"
        }
        if !message.hasSuffix("\n") { message += " " }
        do {
            try CleanHistory().append(result)
            message += tr("Recorded in the history.", "Registrato nello storico.")
        } catch {
            message += tr("History not updated: ", "Storico non aggiornato: ") + error.localizedDescription
        }
        lastMessage = message
    }

    /// Salva su file i suggerimenti visibili (categoria e rischio correnti).
    func exportReport(category: CleanupCategory?) {
        guard let report else { return }
        let panel = NSSavePanel()
        panel.title = tr("Export report", "Esporta report")
        panel.nameFieldStringValue = "save-my-space-\(Self.fileDate.string(from: Date())).md"
        panel.allowedContentTypes = [.init(filenameExtension: "md")!, .commaSeparatedText, .json]
        panel.allowsOtherFileTypes = true
        panel.message = tr("The format depends on the extension: .md, .csv or .json",
                           "Il formato dipende dall'estensione: .md, .csv o .json")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report.export(ReportFormat(fileURL: url), findings: findings(in: category)).write(to: url, options: .atomic)
            lastMessage = tr("Report saved to ", "Report salvato in ") + displayPath(url.path) + "."
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            lastMessage = tr("Could not save: ", "Errore nel salvataggio: ") + error.localizedDescription
        }
    }

    /// Ripristina gli elementi dell'ultima pulizia registrata, dopo conferma.
    func restoreLastClean() {
        guard let last = CleanHistory().load().last else {
            lastMessage = tr("No cleanups recorded: nothing to restore.", "Nessuna pulizia registrata: niente da ripristinare.")
            return
        }
        let restorer = Restorer()
        let items = last.trashed.filter { restorer.state(of: $0, root: last.root) == .restorable }
        guard !items.isEmpty else {
            lastMessage = tr("No item of the last cleanup can still be restored.",
                             "Nessun elemento dell'ultima pulizia è ancora ripristinabile.")
            return
        }
        let size = SizeFormatter.string(items.reduce(0) { $0 + $1.finding.size })
        let date = L10n.dateTime(last.date)
        let alert = NSAlert()
        alert.messageText = tr("Restore \(items.count) items (\(size))?", "Ripristinare \(items.count) elementi (\(size))?")
        alert.informativeText = tr(
            "The items of the cleanup of \(date) will go back to their original location. Nothing is overwritten.",
            "Gli elementi della pulizia del \(date) torneranno nella posizione originale. Nulla viene sovrascritto.")
        alert.addButton(withTitle: tr("Restore", "Ripristina"))
        alert.addButton(withTitle: tr("Cancel", "Annulla"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let result = restorer.restore(items, root: last.root)
        let restored = SizeFormatter.string(result.restoredBytes)
        var message = tr("Restored \(result.restored.count) items (\(restored)).",
                         "Ripristinati \(result.restored.count) elementi (\(restored)).")
        if !result.failed.isEmpty {
            message += " " + tr("\(result.failed.count) not restored.", "\(result.failed.count) non ripristinati.")
        }
        if report != nil {
            message += " " + tr("Analyze again to refresh the list.", "Rianalizza per aggiornare l'elenco.")
        }
        lastMessage = message
    }

    func revealHistory() {
        let url = CleanHistory().fileURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            lastMessage = tr("No cleanups recorded yet.", "Nessuna pulizia registrata finora.")
        }
    }

    private static let fileDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func revealInFinder(_ finding: Finding) {
        NSWorkspace.shared.activateFileViewerSelecting([finding.url])
    }

    func displayPath(_ path: String) -> String {
        let home = root.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
