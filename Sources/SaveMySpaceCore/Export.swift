// SPDX-FileCopyrightText: 2026 homecla
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Formati di esportazione dei report.
public enum ReportFormat: String, CaseIterable, Sendable {
    case json
    case markdown = "md"
    case csv

    /// Deduce il formato dall'estensione del file (`.json`, `.md`, `.csv`); default Markdown.
    public init(fileURL: URL) {
        switch fileURL.pathExtension.lowercased() {
        case "json": self = .json
        case "csv": self = .csv
        default: self = .markdown
        }
    }

    public var fileExtension: String { rawValue }
}

enum Encoding {
    static func json<T: Encodable>(_ value: T, pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                                          : [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func date(_ d: Date?) -> String { d.map(dateFormatter.string(from:)) ?? "" }

    static func csvField(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
            ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            : s
    }

    static func csvLine(_ fields: [String]) -> String { fields.map(csvField).joined(separator: ",") }

    static func md(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
}

// MARK: - Report della scansione

extension ScanReport {
    public func export(_ format: ReportFormat, findings selected: [Finding]? = nil) throws -> Data {
        let items = selected ?? findings
        switch format {
        case .json:
            return try jsonData()
        case .csv:
            var lines = [Encoding.csvLine(["path", "size_bytes", "size", "category", "risk", "actionable",
                                           "reason", "hint", "last_used"])]
            for f in items {
                lines.append(Encoding.csvLine([
                    f.path, String(f.size), SizeFormatter.string(f.size), f.category.rawValue,
                    f.risk.rawValue, f.actionable ? "yes" : "no", f.reason, f.hint ?? "",
                    Encoding.date(f.lastUsed),
                ]))
            }
            return Data((lines.joined(separator: "\n") + "\n").utf8)
        case .markdown:
            return Data(markdown(items).utf8)
        }
    }

    private func markdown(_ items: [Finding]) -> String {
        var out = """
        # \(tr("Save My Space report", "Report Save My Space"))

        - **\(tr("Scanned folder", "Cartella analizzata")):** `\(root)`
        - **\(tr("Date", "Data")):** \(Encoding.date(scannedAt))
        - **\(tr("Items scanned", "Elementi analizzati")):** \(itemsScanned.formatted()) \(tr("in", "in")) \(String(format: "%.1f", duration)) s
        - **\(tr("Total flagged", "Totale segnalato")):** \(SizeFormatter.string(totalSize))
        - **\(tr("Safe to delete", "Eliminabile senza rischi")):** \(SizeFormatter.string(reclaimableSize))

        ## \(tr("Summary by category", "Riepilogo per categoria"))

        | \(tr("Category", "Categoria")) | \(tr("Space", "Spazio")) | \(tr("Items", "Elementi")) |
        |---|---:|---:|

        """
        for t in categoryTotals {
            out += "| \(t.category.label) | \(SizeFormatter.string(t.size)) | \(t.count) |\n"
        }
        let header = "| \(tr("Size", "Dimensione")) | \(tr("Risk", "Rischio")) | \(tr("Path", "Percorso")) "
            + "| \(tr("Reason", "Motivo")) | \(tr("Suggestion", "Suggerimento")) |\n|---:|---|---|---|---|\n"
        for category in CleanupCategory.allCases {
            let group = items.filter { $0.category == category }
            guard !group.isEmpty else { continue }
            out += "\n## \(category.label)\n\n" + header
            for f in group {
                let hint = (f.hint ?? "") + (f.actionable ? "" : " _(\(tr("handle manually", "da gestire a mano")))_")
                out += "| \(SizeFormatter.string(f.size)) | \(f.risk.label) | `\(Encoding.md(f.path))` "
                    + "| \(Encoding.md(f.reason)) | \(Encoding.md(hint)) |\n"
            }
        }
        if unreadableCount > 0 {
            out += "\n> " + tr("\(unreadableCount) paths could not be read due to missing permissions.",
                               "\(unreadableCount) percorsi non leggibili per mancanza di permessi.") + "\n"
        }
        return out
    }
}

// MARK: - Resoconto di una pulizia

extension CleanResult {
    public func export(_ format: ReportFormat) throws -> Data {
        switch format {
        case .json:
            return try Encoding.json(self)
        case .csv:
            var lines = [Encoding.csvLine(["status", "path", "size_bytes", "size", "category", "risk",
                                           "trashed_to", "error"])]
            for t in trashed {
                let f = t.finding
                lines.append(Encoding.csvLine(["trashed", f.path, String(f.size), SizeFormatter.string(f.size),
                                               f.category.rawValue, f.risk.rawValue, t.trashedTo ?? "", ""]))
            }
            for e in failed {
                let f = e.finding
                lines.append(Encoding.csvLine(["failed", f.path, String(f.size), SizeFormatter.string(f.size),
                                               f.category.rawValue, f.risk.rawValue, "", e.message]))
            }
            return Data((lines.joined(separator: "\n") + "\n").utf8)
        case .markdown:
            var out = """
            # \(tr("Save My Space cleanup", "Pulizia Save My Space")) — \(Encoding.date(date))

            - **\(tr("Items moved to the Trash", "Elementi spostati nel Cestino")):** \(trashed.count) (\(SizeFormatter.string(freedBytes)))
            - **\(tr("Items not moved", "Elementi non spostati")):** \(failed.count)

            """
            if !trashed.isEmpty {
                out += "\n## \(tr("Moved to the Trash", "Spostati nel Cestino"))\n\n"
                    + "| \(tr("Size", "Dimensione")) | \(tr("Category", "Categoria")) "
                    + "| \(tr("Original path", "Percorso originale")) | \(tr("Now in the Trash", "Ora nel Cestino")) |\n"
                    + "|---:|---|---|---|\n"
                for t in trashed {
                    out += "| \(SizeFormatter.string(t.finding.size)) | \(t.finding.category.label) "
                        + "| `\(Encoding.md(t.finding.path))` | `\(Encoding.md(t.trashedTo ?? "?"))` |\n"
                }
            }
            if !failed.isEmpty {
                out += "\n## \(tr("Not moved", "Non spostati"))\n\n"
                    + "| \(tr("Path", "Percorso")) | \(tr("Reason", "Motivo")) |\n|---|---|\n"
                for e in failed {
                    out += "| `\(Encoding.md(e.finding.path))` | \(Encoding.md(e.message)) |\n"
                }
            }
            return Data(out.utf8)
        }
    }
}

// MARK: - Storico delle pulizie

/// Storico persistente delle pulizie, una riga JSON per pulizia.
/// Si trova in Application Support e non in ~/Library/Logs, che il programma stesso propone di pulire.
public struct CleanHistory: Sendable {
    public let fileURL: URL

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/save-my-space/history.jsonl")
    }

    public init(fileURL: URL = CleanHistory.defaultURL) {
        self.fileURL = fileURL
    }

    public func append(_ result: CleanResult) throws {
        guard !result.trashed.isEmpty || !result.failed.isEmpty else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        var line = try Encoding.json(result, pretty: false)
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: fileURL)
        }
    }

    /// Le pulizie registrate, dalla più vecchia alla più recente (righe illeggibili ignorate).
    public func load() -> [CleanResult] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = Encoding.decoder()
        return text.split(separator: "\n").compactMap {
            try? decoder.decode(CleanResult.self, from: Data($0.utf8))
        }
    }
}
