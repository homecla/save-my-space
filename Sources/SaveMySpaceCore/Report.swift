// SPDX-FileCopyrightText: 2026 homecla
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public struct CategoryTotal: Codable, Sendable, Identifiable {
    public var id: CleanupCategory { category }
    public let category: CleanupCategory
    public let size: Int64
    public let count: Int
}

/// Risultato di una scansione.
public struct ScanReport: Codable, Sendable {
    public let root: String
    public let scannedAt: Date
    public let duration: TimeInterval
    public let itemsScanned: Int
    /// Suggerimenti senza sovrapposizioni, ordinati per dimensione decrescente.
    public let findings: [Finding]
    public let categoryTotals: [CategoryTotal]
    /// Spazio totale degli elementi segnalati.
    public let totalSize: Int64
    /// Spazio recuperabile senza rischi: elementi "actionable" a rischio `safe`.
    public let reclaimableSize: Int64
    public let unreadableCount: Int
    public let unreadableSamples: [String]

    public init(
        root: String,
        scannedAt: Date,
        duration: TimeInterval,
        itemsScanned: Int,
        findings: [Finding],
        unreadableCount: Int,
        unreadableSamples: [String]
    ) {
        let clean = Self.removeOverlaps(findings).sorted { $0.size > $1.size }
        self.root = root
        self.scannedAt = scannedAt
        self.duration = duration
        self.itemsScanned = itemsScanned
        self.findings = clean
        self.totalSize = clean.reduce(0) { $0 + $1.size }
        self.reclaimableSize = clean.filter { $0.actionable && $0.risk == .safe }.reduce(0) { $0 + $1.size }
        self.categoryTotals = CleanupCategory.allCases.compactMap { cat in
            let items = clean.filter { $0.category == cat }
            guard !items.isEmpty else { return nil }
            return CategoryTotal(category: cat, size: items.reduce(0) { $0 + $1.size }, count: items.count)
        }.sorted { $0.size > $1.size }
        self.unreadableCount = unreadableCount
        self.unreadableSamples = unreadableSamples
    }

    public func filtered(
        categories: Set<CleanupCategory>? = nil,
        maxRisk: Risk = .caution,
        actionableOnly: Bool = false
    ) -> [Finding] {
        findings.filter { f in
            (categories?.contains(f.category) ?? true)
                && f.risk <= maxRisk
                && (!actionableOnly || f.actionable)
        }
    }

    /// Elimina i duplicati per percorso e gli elementi contenuti in un altro elemento segnalato,
    /// così che i totali non contino due volte lo stesso spazio.
    static func removeOverlaps(_ findings: [Finding]) -> [Finding] {
        // A parità di percorso, i duplicati sono più informativi dei "file grandi".
        let prioritized = findings.enumerated().sorted { a, b in
            let pa = a.element.category == .duplicates ? 0 : 1
            let pb = b.element.category == .duplicates ? 0 : 1
            return pa != pb ? pa < pb : a.offset < b.offset
        }.map(\.element)

        var byPath: [String: Finding] = [:]
        for f in prioritized where byPath[f.path] == nil {
            byPath[f.path] = f
        }

        let kept = Set(byPath.keys)
        return byPath.values.filter { f in
            var parent = (f.path as NSString).deletingLastPathComponent
            while parent.count > 1 {
                if kept.contains(parent) { return false }
                parent = (parent as NSString).deletingLastPathComponent
            }
            return true
        }
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
