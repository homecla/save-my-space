// SPDX-FileCopyrightText: 2026 homecla
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import SaveMySpaceCore

enum Terminal {
    static let stdoutIsTTY = isatty(STDOUT_FILENO) == 1
    static let stderrIsTTY = isatty(STDERR_FILENO) == 1
    static let stdinIsTTY = isatty(STDIN_FILENO) == 1
    static let colors = stdoutIsTTY && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    private static func style(_ s: String, _ code: String) -> String {
        colors ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s
    }

    static func bold(_ s: String) -> String { style(s, "1") }
    static func dim(_ s: String) -> String { style(s, "2") }
    static func red(_ s: String) -> String { style(s, "31") }
    static func green(_ s: String) -> String { style(s, "32") }
    static func yellow(_ s: String) -> String { style(s, "33") }
    static func cyan(_ s: String) -> String { style(s, "36") }

    static func progress(_ text: String) {
        FileHandle.standardError.write(Data("\r\u{1B}[K\(text)".utf8))
    }

    static func clearProgress() {
        FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
    }

    static func confirm(_ question: String) -> Bool {
        print("\(question) " + tr("[y/N]", "[s/N]") + " ", terminator: "")
        guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        return ["s", "si", "sì", "y", "yes"].contains(answer)
    }
}

enum Output {
    /// Percorso abbreviato con `~` e reso sicuro per il terminale.
    static func shortPath(_ path: String, root: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return Sanitize.forTerminal("~" + path.dropFirst(home.count)) }
        return Sanitize.forTerminal(path)
    }

    static func riskLabel(_ risk: Risk) -> String {
        let text = "[\(risk.label)]".padding(toLength: 16, withPad: " ", startingAt: 0)
        switch risk {
        case .safe: return Terminal.green(text)
        case .review: return Terminal.yellow(text)
        case .caution: return Terminal.red(text)
        }
    }

    static func size(_ bytes: Int64) -> String {
        let s = SizeFormatter.string(bytes)
        return String(repeating: " ", count: max(0, 10 - s.count)) + s
    }

    static func summary(_ report: ScanReport) {
        let seconds = String(format: "%.1f", report.duration)
        print(Terminal.bold(tr("Analysis of ", "Analisi di ") + shortPath(report.root, root: report.root))
              + Terminal.dim(" — \(report.itemsScanned.formatted()) " + tr("items in", "elementi in") + " \(seconds) s"))
        print()
        guard !report.categoryTotals.isEmpty else {
            print(tr("No suggestions: your home folder is already tidy.", "Nessun suggerimento: la home è già in ordine."))
            return
        }
        print(Terminal.dim(tr("CATEGORY", "CATEGORIA").padding(toLength: 20, withPad: " ", startingAt: 0)
                           + tr("SPACE", "SPAZIO").leftPad(10) + "  " + tr("ITEMS", "ELEMENTI").leftPad(8)))
        for t in report.categoryTotals {
            print(t.category.label.padding(toLength: 20, withPad: " ", startingAt: 0)
                  + size(t.size) + "  " + String(t.count).leftPad(8))
        }
        print()
        print(tr("Total flagged: ", "Totale segnalato: ") + Terminal.bold(SizeFormatter.string(report.totalSize))
              + tr("   of which safe to delete: ", "   di cui sicuro da eliminare: ") + Terminal.bold(Terminal.green(SizeFormatter.string(report.reclaimableSize))))
        if report.unreadableCount > 0 {
            print(Terminal.dim(tr(
                "\(report.unreadableCount) unreadable paths: grant Full Disk Access to the Terminal "
                    + "(System Settings › Privacy & Security) for a complete analysis.",
                "\(report.unreadableCount) percorsi non leggibili: concedi l'Accesso completo al disco al Terminale "
                    + "(Impostazioni di Sistema › Privacy e sicurezza) per un'analisi completa.")))
        }
    }

    static func findings(_ findings: [Finding], limit: Int, root: String) {
        guard !findings.isEmpty else { return }
        print()
        print(Terminal.bold(tr("Top suggestions:", "Suggerimenti principali:")))
        for f in findings.prefix(limit) {
            finding(f, root: root)
        }
        if findings.count > limit {
            print(Terminal.dim(tr("… and \(findings.count - limit) more items (use --limit or --json).",
                                  "… e altri \(findings.count - limit) elementi (usa --limit o --json).")))
        }
    }

    static func finding(_ f: Finding, root: String) {
        print(size(f.size) + "  " + riskLabel(f.risk) + Terminal.cyan(shortPath(f.path, root: root)))
        print(String(repeating: " ", count: 28) + Terminal.dim(Sanitize.forTerminal(f.reason)))
        if let hint = f.hint {
            let prefix = f.actionable ? tr("tip", "suggerimento") : tr("do it manually", "da fare a mano")
            print(String(repeating: " ", count: 28) + Terminal.dim("→ \(prefix): " + Sanitize.forTerminal(hint)))
        }
    }
}

private extension String {
    func leftPad(_ width: Int) -> String {
        String(repeating: " ", count: max(0, width - count)) + self
    }
}
