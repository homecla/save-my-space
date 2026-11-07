// SPDX-FileCopyrightText: 2026 homecla
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Quanto è rischioso eliminare un elemento.
public enum Risk: String, Codable, CaseIterable, Comparable, Sendable {
    /// Dati rigenerabili (cache, log, build): si possono eliminare senza pensarci.
    case safe
    /// Probabilmente inutili, ma da controllare prima.
    case review
    /// Possono contenere dati personali o difficili da ricreare.
    case caution

    public var label: String {
        switch self {
        case .safe: return tr("safe", "sicuro")
        case .review: return tr("review", "da verificare")
        case .caution: return tr("caution", "attenzione")
        }
    }

    private var order: Int {
        switch self {
        case .safe: return 0
        case .review: return 1
        case .caution: return 2
        }
    }

    public static func < (lhs: Risk, rhs: Risk) -> Bool { lhs.order < rhs.order }
}

/// Categoria di un suggerimento.
public enum CleanupCategory: String, Codable, CaseIterable, Sendable {
    case caches
    case logs
    case trash
    case developer
    case downloads
    case largeFiles = "large-files"
    case duplicates
    case iosBackups = "ios-backups"
    case messages
    case appData = "app-data"

    public var label: String {
        switch self {
        case .caches: return tr("Caches", "Cache")
        case .logs: return tr("Logs", "Log")
        case .trash: return tr("Trash", "Cestino")
        case .developer: return tr("Development", "Sviluppo")
        case .downloads: return tr("Old downloads", "Download vecchi")
        case .largeFiles: return tr("Large files", "File grandi")
        case .duplicates: return tr("Duplicates", "Duplicati")
        case .iosBackups: return tr("iOS backups", "Backup iOS")
        case .messages: return tr("Mail & Messages", "Mail e Messaggi")
        case .appData: return tr("App data", "Dati delle app")
        }
    }

    public var symbolName: String {
        switch self {
        case .caches: return "archivebox"
        case .logs: return "doc.text"
        case .trash: return "trash"
        case .developer: return "hammer"
        case .downloads: return "arrow.down.circle"
        case .largeFiles: return "externaldrive"
        case .duplicates: return "doc.on.doc"
        case .iosBackups: return "iphone"
        case .messages: return "envelope"
        case .appData: return "square.stack.3d.up"
        }
    }
}

/// Un elemento che si suggerisce di pulire.
public struct Finding: Codable, Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let size: Int64
    public let category: CleanupCategory
    public let risk: Risk
    public let reason: String
    /// Se `false` l'elemento va solo segnalato: il programma non lo sposta nel Cestino
    /// (per esempio il Cestino stesso, o dati gestiti da un'app).
    public let actionable: Bool
    /// Suggerimento alternativo (es. un comando da eseguire) quando è meglio non cancellare a mano.
    public let hint: String?
    public let lastUsed: Date?

    public init(
        path: String,
        size: Int64,
        category: CleanupCategory,
        risk: Risk,
        reason: String,
        actionable: Bool = true,
        hint: String? = nil,
        lastUsed: Date? = nil
    ) {
        self.path = path
        self.size = size
        self.category = category
        self.risk = risk
        self.reason = reason
        self.actionable = actionable
        self.hint = hint
        self.lastUsed = lastUsed
    }

    public var url: URL { URL(fileURLWithPath: path) }
}

/// Opzioni della scansione.
public struct ScanOptions: Sendable {
    public var root: URL
    /// Soglia per la categoria "File grandi".
    public var largeFileThreshold: Int64
    /// Età (in giorni) oltre la quale download e progetti sono considerati inutilizzati.
    public var olderThanDays: Int
    /// Ricerca dei duplicati (legge il contenuto dei file, è la parte più lenta).
    public var findDuplicates: Bool
    /// Dimensione minima dei file considerati per i duplicati.
    public var duplicateMinSize: Int64
    /// Dimensione minima perché un elemento venga suggerito.
    public var minFindingSize: Int64

    public init(
        root: URL = FileManager.default.homeDirectoryForCurrentUser,
        largeFileThreshold: Int64 = 500 * 1_000_000,
        olderThanDays: Int = 90,
        findDuplicates: Bool = true,
        duplicateMinSize: Int64 = 1_000_000,
        minFindingSize: Int64 = 1_000_000
    ) {
        self.root = root.canonical
        self.largeFileThreshold = largeFileThreshold
        self.olderThanDays = olderThanDays
        self.findDuplicates = findDuplicates
        self.duplicateMinSize = duplicateMinSize
        self.minFindingSize = minFindingSize
    }

    var cutoffDate: Date {
        Date().addingTimeInterval(-Double(olderThanDays) * 86_400)
    }
}

/// Avanzamento della scansione, per CLI e GUI.
public struct ScanProgress: Sendable {
    public let phase: String
    public let itemsScanned: Int
    public let currentPath: String?
}
