// SPDX-FileCopyrightText: 2026 homecla
// SPDX-License-Identifier: AGPL-3.0-or-later

import ArgumentParser
import Foundation
import SaveMySpaceCore

/// Punto d'ingresso: sceglie la lingua (`--lang`, `SMSPACE_LANG`, sistema) prima che vengano
/// costruiti i testi di aiuto, poi passa gli argomenti rimanenti ad ArgumentParser.
@main
enum Main {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        var explicit: String?
        if let i = args.firstIndex(where: { $0 == "--lang" }), i + 1 < args.count {
            explicit = args[i + 1]
            args.removeSubrange(i...(i + 1))
        } else if let i = args.firstIndex(where: { $0.hasPrefix("--lang=") }) {
            explicit = String(args[i].dropFirst("--lang=".count))
            args.remove(at: i)
        }
        if let explicit, Language(rawValue: explicit.lowercased()) == nil {
            FileHandle.standardError.write(Data("Unsupported language / lingua non supportata: \(explicit) (en, it)\n".utf8))
            exit(64)
        }
        L10n.language = L10n.detect(explicit: explicit)
        await SaveMySpace.main(args)
    }
}

/// Testo di aiuto localizzato per ArgumentParser.
func help(_ en: String, _ it: String) -> ArgumentHelp { ArgumentHelp(tr(en, it)) }

struct SaveMySpace: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "smspace",
            abstract: tr("Save My Space — analyzes your macOS home folder and suggests what to clean up.",
                         "Save My Space — analizza la tua home su macOS e suggerisce cosa pulire."),
            discussion: tr("""
                By default nothing is modified: `scan` only shows suggestions.
                `clean` moves the chosen items to the Trash, after explicit confirmation.
                Language: --lang en|it (or the SMSPACE_LANG environment variable).
                """, """
                Di default non modifica nulla: `scan` mostra solo i suggerimenti.
                `clean` sposta nel Cestino gli elementi scelti, dopo una conferma esplicita.
                Lingua: --lang en|it (oppure la variabile d'ambiente SMSPACE_LANG).
                """),
            version: "0.1.0",
            subcommands: [Scan.self, Clean.self, History.self, Restore.self, Gui.self],
            defaultSubcommand: Scan.self
        )
    }
}

// MARK: - Opzioni comuni

struct ScanArguments: ParsableArguments {
    @Option(name: .long, help: help("Folder to analyze.", "Cartella da analizzare."))
    var path: String = FileManager.default.homeDirectoryForCurrentUser.path

    @Option(name: .long, help: help("Threshold for large files (e.g. 500MB, 2G).",
                                    "Soglia per i file grandi (es. 500MB, 2G)."))
    var largeSize: String = "500MB"

    @Option(name: .long, help: help("Minimum size of a suggestion (e.g. 1MB).",
                                    "Dimensione minima di un suggerimento (es. 1MB)."))
    var minSize: String = "1MB"

    @Option(name: .long, help: help("Days of inactivity for downloads and projects (e.g. 90 or 90d).",
                                    "Giorni di inutilizzo per download e progetti (es. 90 o 90d)."))
    var olderThan: String = "90"

    @Flag(name: .long, help: help("Skip the duplicate search (faster).",
                                  "Salta la ricerca dei duplicati (più veloce)."))
    var noDuplicates = false

    @Option(name: .long, help: help(
        "Comma-separated categories: \(CleanupCategory.allCases.map(\.rawValue).joined(separator: ",")).",
        "Categorie, separate da virgola: \(CleanupCategory.allCases.map(\.rawValue).joined(separator: ","))."))
    var category: String?

    func options() throws -> ScanOptions {
        guard let large = SizeFormatter.parse(largeSize) else {
            throw ValidationError(tr("Invalid size: \(largeSize)", "Dimensione non valida: \(largeSize)"))
        }
        guard let min = SizeFormatter.parse(minSize) else {
            throw ValidationError(tr("Invalid size: \(minSize)", "Dimensione non valida: \(minSize)"))
        }
        let daysText = olderThan.lowercased().hasSuffix("d") ? String(olderThan.dropLast()) : olderThan
        guard let days = Int(daysText), days >= 0 else {
            throw ValidationError(tr("Invalid number of days: \(olderThan)", "Numero di giorni non valido: \(olderThan)"))
        }
        let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw ValidationError(tr("Folder does not exist: \(root.path)", "La cartella non esiste: \(root.path)"))
        }
        return ScanOptions(
            root: root, largeFileThreshold: large, olderThanDays: days,
            findDuplicates: !noDuplicates, duplicateMinSize: max(min, 1_000_000), minFindingSize: min
        )
    }

    func categories() throws -> Set<CleanupCategory>? {
        guard let category else { return nil }
        var result = Set<CleanupCategory>()
        for raw in category.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            guard let c = CleanupCategory(rawValue: raw) else {
                throw ValidationError(tr("Unknown category: \(raw)", "Categoria sconosciuta: \(raw)"))
            }
            result.insert(c)
        }
        return result
    }

    func runScan(quiet: Bool) async throws -> ScanReport {
        let scanner = Scanner(options: try options())
        let showProgress = !quiet && Terminal.stderrIsTTY
        let report = try await Task.detached(priority: .userInitiated) {
            try scanner.scan { p in
                guard showProgress else { return }
                Terminal.progress("\(p.phase)… \(p.itemsScanned.formatted()) \(tr("items", "elementi"))")
            }
        }.value
        if showProgress { Terminal.clearProgress() }
        return report
    }
}

extension Risk: ExpressibleByArgument {}

// MARK: - scan

struct Scan: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(abstract: tr("Analyze and show suggestions (changes nothing).",
                                          "Analizza e mostra i suggerimenti (non modifica nulla)."))
    }

    @OptionGroup var scan: ScanArguments

    @Option(name: .long, help: help("Maximum risk to show: safe, review, caution.",
                                    "Rischio massimo da mostrare: safe, review, caution."))
    var risk: Risk = .caution

    @Option(name: .shortAndLong, help: help("Maximum number of items listed.", "Numero massimo di elementi elencati."))
    var limit: Int = 30

    @Flag(name: .long, help: help("Print the report as JSON.", "Output in formato JSON."))
    var json = false

    @Option(name: [.short, .long], help: help("Save the report to a file (.md, .csv or .json).",
                                              "Salva il report in un file (.md, .csv o .json)."))
    var output: String?

    func run() async throws {
        let report = try await scan.runScan(quiet: json)
        let findings = report.filtered(categories: try scan.categories(), maxRisk: risk)
        var savedTo: URL?
        if let output {
            let format = ReportFormat(fileURL: Files.url(output))
            savedTo = try Files.write(try report.export(format, findings: findings), to: output)
        }
        if json {
            FileHandle.standardOutput.write(try report.jsonData())
            print()
            return
        }
        Output.summary(report)
        Output.findings(findings, limit: limit, root: report.root)
        print()
        if let savedTo {
            print(Terminal.dim(tr("Report saved to \(savedTo.path)", "Report salvato in \(savedTo.path)")))
        }
        if report.reclaimableSize > 0 {
            print(Terminal.dim(tr("To move the safe items to the Trash: smspace clean --risk safe",
                                  "Per spostare nel Cestino gli elementi sicuri: smspace clean --risk safe")))
        }
    }
}

// MARK: - clean

struct Clean: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(abstract: tr("Move the suggested items to the Trash, after confirmation.",
                                          "Sposta nel Cestino gli elementi suggeriti, dopo conferma."))
    }

    @OptionGroup var scan: ScanArguments

    @Option(name: .long, help: help("Maximum risk of the items to clean: safe, review, caution.",
                                    "Rischio massimo degli elementi da pulire: safe, review, caution."))
    var risk: Risk = .safe

    @Flag(name: .shortAndLong, help: help("Ask for confirmation item by item.", "Chiede conferma per ogni singolo elemento."))
    var interactive = false

    @Flag(name: .shortAndLong, help: help("Don't ask for confirmation (only allowed with --risk safe).",
                                          "Non chiede conferma (consentito solo con --risk safe)."))
    var yes = false

    @Flag(name: .long, help: help("Show what would be moved without doing it.",
                                  "Mostra cosa verrebbe spostato senza farlo."))
    var dryRun = false

    @Option(name: .long, help: help("Save the summary (or, with --dry-run, the proposal) to a .md, .csv or .json file.",
                                    "Salva il resoconto (o, con --dry-run, la proposta) in un file .md, .csv o .json."))
    var report: String?

    func validate() throws {
        if yes && risk > .safe {
            throw ValidationError(tr("--yes is only allowed with --risk safe: other items need a confirmation.",
                                     "--yes è consentito solo con --risk safe: per gli altri elementi serve una conferma."))
        }
    }

    func run() async throws {
        let scanReport = try await scan.runScan(quiet: false)
        var selected = scanReport.filtered(categories: try scan.categories(), maxRisk: risk, actionableOnly: true)
        guard !selected.isEmpty else {
            print(tr("Nothing to clean with the chosen filters.", "Nessun elemento da pulire con i filtri scelti."))
            return
        }

        if interactive {
            selected = selected.filter { f in
                Output.finding(f, root: scanReport.root)
                return Terminal.confirm(tr("  Move to the Trash?", "  Spostare nel Cestino?"))
            }
            guard !selected.isEmpty else {
                print(tr("No items selected.", "Nessun elemento selezionato."))
                return
            }
        } else {
            Output.findings(selected, limit: Int.max, root: scanReport.root)
        }

        let total = SizeFormatter.string(selected.reduce(0) { $0 + $1.size })
        print()
        if dryRun {
            print(tr("Dry run: \(selected.count) items (\(total)) would be moved to the Trash.",
                     "Dry run: verrebbero spostati nel Cestino \(selected.count) elementi (\(total))."))
            if let report {
                let format = ReportFormat(fileURL: Files.url(report))
                let url = try Files.write(try scanReport.export(format, findings: selected), to: report)
                print(Terminal.dim(tr("Proposal saved to \(url.path)", "Proposta salvata in \(url.path)")))
            }
            return
        }
        if !yes && !interactive {
            guard Terminal.stdinIsTTY else {
                throw ValidationError(tr("Interactive confirmation required (or --yes with --risk safe).",
                                         "Serve una conferma interattiva (oppure --yes con --risk safe)."))
            }
            guard Terminal.confirm(tr("Move \(selected.count) items (\(total)) to the Trash?",
                                      "Spostare nel Cestino \(selected.count) elementi (\(total))?")) else {
                print(tr("Cancelled, no files changed.", "Annullato, nessun file modificato."))
                return
            }
        }

        let cleaner = Cleaner(root: URL(fileURLWithPath: scanReport.root))
        let result = cleaner.clean(selected) { f, error in
            let path = Output.shortPath(f.path, root: scanReport.root)
            print(error.map { Terminal.red("  ✗ \(path): " + Sanitize.forTerminal($0)) } ?? Terminal.green("  ✓ \(path)"))
        }
        print()
        let freed = SizeFormatter.string(result.freedBytes)
        print(Terminal.bold(tr("Moved \(result.trashed.count) items to the Trash, \(freed) can be freed.",
                               "Spostati nel Cestino \(result.trashed.count) elementi, \(freed) liberabili.")))
        if !result.failed.isEmpty {
            print(Terminal.yellow(tr("\(result.failed.count) items not moved.", "\(result.failed.count) elementi non spostati.")))
        }
        print(Terminal.dim(tr("Space is actually freed when you empty the Trash; until then you can restore the files.",
                              "Lo spazio si libera davvero quando svuoti il Cestino; fino ad allora puoi ripristinare i file.")))

        let history = CleanHistory()
        do {
            try history.append(result)
            print(Terminal.dim(tr("Recorded in the history: \(history.fileURL.path) (smspace history)",
                                  "Registrato nello storico: \(history.fileURL.path) (smspace history)")))
        } catch {
            print(Terminal.yellow(tr("Could not update the history: \(error.localizedDescription)",
                                     "Impossibile aggiornare lo storico: \(error.localizedDescription)")))
        }
        if let report {
            let url = try Files.write(try result.export(ReportFormat(fileURL: Files.url(report))), to: report)
            print(Terminal.dim(tr("Summary saved to \(url.path)", "Resoconto salvato in \(url.path)")))
        }
    }
}

// MARK: - gui

struct Gui: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(abstract: tr("Open the graphical interface.", "Apre l'interfaccia grafica."))
    }

    func run() throws {
        // Percorso reale del binario: argv[0] contiene solo "smspace" quando il comando è trovato
        // tramite PATH, e verrebbe risolto rispetto alla cartella corrente (esecuzione di un
        // eventuale "SaveMySpaceApp" piazzato lì).
        var candidates: [URL] = []
        if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath(), exe.path.hasPrefix("/") {
            candidates.append(exe.deletingLastPathComponent().appendingPathComponent("SaveMySpaceApp"))
        }
        candidates += [
            URL(fileURLWithPath: "/Applications/Save My Space.app"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Save My Space.app"),
        ]
        guard let target = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw ValidationError(tr("Graphical interface not found. Build it with `swift build` or `make app`.",
                                     "Interfaccia grafica non trovata. Compilala con `swift build` o `make app`."))
        }
        let process = Process()
        // La lingua scelta da riga di comando viene passata anche all'app.
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["SMSPACE_LANG": L10n.language.rawValue]) { $1 }
        if target.pathExtension == "app" {
            // nosemgrep: external-process-execution -- percorso costante di sistema
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["--env", "SMSPACE_LANG=\(L10n.language.rawValue)", target.path]
        } else {
            // nosemgrep: external-process-execution -- target scelto fra percorsi fissi (binario reale, /Applications)
            process.executableURL = target
        }
        try process.run()
    }
}

// MARK: - history

struct History: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(abstract: tr("Show the history of past cleanups.", "Mostra lo storico delle pulizie eseguite."))
    }

    @Option(name: .shortAndLong, help: help("Number of cleanups to show (most recent first).",
                                            "Numero di pulizie da mostrare (le più recenti)."))
    var last: Int = 10

    @Flag(name: .shortAndLong, help: help("Also list each item and where it is in the Trash.",
                                          "Elenca anche i singoli elementi e dove si trovano nel Cestino."))
    var details = false

    @Option(name: [.short, .long], help: help("Export the cleanups shown to a file (.md, .csv or .json).",
                                              "Esporta le pulizie mostrate in un file (.md, .csv o .json)."))
    var output: String?

    func run() throws {
        let history = CleanHistory()
        let entries = Array(history.load().suffix(last))
        guard !entries.isEmpty else {
            print(tr("No cleanups recorded (\(history.fileURL.path)).",
                     "Nessuna pulizia registrata (\(history.fileURL.path))."))
            return
        }
        for (offset, entry) in entries.reversed().enumerated() {
            let failed = entry.failed.isEmpty ? ""
                : Terminal.yellow("  (" + tr("\(entry.failed.count) not moved", "\(entry.failed.count) non spostati") + ")")
            print(Terminal.bold("#\(offset + 1)  " + L10n.dateTime(entry.date))
                  + "  \(entry.trashed.count) \(tr("items", "elementi")), \(SizeFormatter.string(entry.freedBytes))"
                  + failed)
            guard details else { continue }
            for t in entry.trashed {
                print(Output.size(t.finding.size) + "  " + Output.shortPath(t.finding.path, root: entry.root))
                if let to = t.trashedTo {
                    let state = Restorer().state(of: t, root: entry.root)
                    let location = state == .restorable
                        ? tr("in the Trash: ", "nel Cestino: ") + Output.shortPath(to, root: entry.root)
                        : Sanitize.forTerminal(state.label)
                    print(String(repeating: " ", count: 12) + Terminal.dim(location))
                }
            }
            for f in entry.failed {
                print(Terminal.red("    ✗ \(Output.shortPath(f.finding.path, root: entry.root)): " + Sanitize.forTerminal(f.message)))
            }
        }
        print()
        print(Terminal.dim(tr("To restore: smspace restore [--entry N]", "Per ripristinare: smspace restore [--entry N]")))
        print(Terminal.dim(tr("Full history: \(history.fileURL.path)", "Storico completo: \(history.fileURL.path)")))

        if let output {
            let format = ReportFormat(fileURL: Files.url(output))
            var data = Data()
            if format == .json {
                data = try JSONEncoder.pretty.encode(entries)
            } else {
                for (i, entry) in entries.enumerated() {
                    var part = try entry.export(format)
                    // Nel CSV l'intestazione va ripetuta una sola volta.
                    if format == .csv && i > 0, let nl = part.firstIndex(of: 0x0A) {
                        part = part.subdata(in: part.index(after: nl)..<part.endIndex)
                    }
                    data.append(part)
                    if format == .markdown { data.append(Data("\n---\n\n".utf8)) }
                }
            }
            let url = try Files.write(data, to: output)
            print(Terminal.dim(tr("History exported to \(url.path)", "Storico esportato in \(url.path)")))
        }
    }
}

// MARK: - restore

struct Restore: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            abstract: tr("Restore from the Trash the items of a recorded cleanup.",
                         "Ripristina dal Cestino gli elementi di una pulizia registrata."),
            discussion: tr("Nothing is ever overwritten: if the original location is taken, the item stays in the Trash.",
                           "Non sovrascrive mai nulla: se la posizione originale è occupata, l'elemento resta nel Cestino.")
        )
    }

    @Option(name: .shortAndLong, help: help("Cleanup to restore, numbered as in `history` (1 = most recent).",
                                            "Pulizia da ripristinare, numerata come in `history` (1 = la più recente)."))
    var entry: Int = 1

    @Option(name: .shortAndLong, help: help("Only restore items with this original path (or inside it). Repeatable.",
                                            "Ripristina solo gli elementi con questo percorso originale (o al suo interno). Ripetibile."))
    var path: [String] = []

    @Flag(name: .shortAndLong, help: help("Don't ask for confirmation.", "Non chiede conferma."))
    var yes = false

    @Flag(name: .long, help: help("Show what would be restored without doing it.",
                                  "Mostra cosa verrebbe ripristinato senza farlo."))
    var dryRun = false

    func validate() throws {
        if entry < 1 { throw ValidationError(tr("--entry must be at least 1.", "--entry deve essere almeno 1.")) }
    }

    func run() throws {
        let entries = CleanHistory().load()
        guard !entries.isEmpty else {
            print(tr("No cleanups recorded: nothing to restore.", "Nessuna pulizia registrata: niente da ripristinare."))
            return
        }
        guard entry <= entries.count else {
            throw ValidationError(tr("Only \(entries.count) cleanups are recorded.",
                                     "Ci sono solo \(entries.count) pulizie registrate."))
        }
        let chosen = entries[entries.count - entry]
        let filters = path.map { Files.url($0).standardized }
        let items = chosen.trashed.filter { item in
            filters.isEmpty || filters.contains { URL(fileURLWithPath: item.finding.path).isInside($0) }
        }
        guard !items.isEmpty else {
            print(tr("No item of cleanup #\(entry) matches the given paths.",
                     "Nessun elemento della pulizia #\(entry) corrisponde ai percorsi indicati."))
            return
        }

        let restorer = Restorer()
        print(Terminal.bold(tr("Cleanup #\(entry) of \(L10n.dateTime(chosen.date))",
                               "Pulizia #\(entry) del \(L10n.dateTime(chosen.date))")))
        var restorable: [TrashedItem] = []
        for item in items {
            let state = restorer.state(of: item, root: chosen.root)
            let line = Output.size(item.finding.size) + "  " + Output.shortPath(item.finding.path, root: chosen.root)
            if state == .restorable {
                restorable.append(item)
                print(line)
            } else {
                print(Terminal.dim(line + "  — " + Sanitize.forTerminal(state.label)))
            }
        }
        print()
        guard !restorable.isEmpty else {
            print(tr("No restorable items.", "Nessun elemento ripristinabile."))
            return
        }
        let total = SizeFormatter.string(restorable.reduce(0) { $0 + $1.finding.size })
        if dryRun {
            print(tr("Dry run: \(restorable.count) items (\(total)) would be restored.",
                     "Dry run: verrebbero ripristinati \(restorable.count) elementi (\(total))."))
            return
        }
        if !yes {
            guard Terminal.stdinIsTTY else {
                throw ValidationError(tr("Interactive confirmation required (or --yes).",
                                         "Serve una conferma interattiva (oppure --yes)."))
            }
            guard Terminal.confirm(tr("Restore \(restorable.count) items (\(total)) to their original location?",
                                      "Ripristinare \(restorable.count) elementi (\(total)) nella posizione originale?")) else {
                print(tr("Cancelled, no files changed.", "Annullato, nessun file modificato."))
                return
            }
        }
        let result = restorer.restore(restorable, root: chosen.root) { item, error in
            let p = Output.shortPath(item.finding.path, root: chosen.root)
            print(error.map { Terminal.red("  ✗ \(p): " + Sanitize.forTerminal($0)) } ?? Terminal.green("  ✓ \(p)"))
        }
        print()
        let restored = SizeFormatter.string(result.restoredBytes)
        print(Terminal.bold(tr("Restored \(result.restored.count) items (\(restored)).",
                               "Ripristinati \(result.restored.count) elementi (\(restored)).")))
        if !result.failed.isEmpty {
            print(Terminal.yellow(tr("\(result.failed.count) items not restored.",
                                     "\(result.failed.count) elementi non ripristinati.")))
        }
    }
}

// MARK: - file

enum Files {
    static func url(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    @discardableResult
    static func write(_ data: Data, to path: String) throws -> URL {
        let url = url(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
