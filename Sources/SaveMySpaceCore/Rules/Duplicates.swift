import CryptoKit
import Foundation

/// Trova file con contenuto identico: raggruppa per dimensione, poi per hash dei primi 64 KB,
/// infine per SHA-256 dell'intero file.
enum Duplicates {
    struct Candidate: Sendable {
        let url: URL
        let size: Int64
    }

    static func find(
        _ candidates: [Candidate],
        downloadsDir: URL,
        isCancelled: () -> Bool = { false }
    ) -> [Finding] {
        // 1. Stessa dimensione (ignorando gli hard link allo stesso inode).
        var bySize: [Int64: [Candidate]] = [:]
        var seenInodes = Set<String>()
        for c in candidates {
            if let ino = FileStats.inode(c.url) {
                guard seenInodes.insert(ino).inserted else { continue }
            }
            bySize[c.size, default: []].append(c)
        }
        let sizeGroups = bySize.values.filter { $0.count > 1 }

        var findings: [Finding] = []
        for group in sizeGroups {
            if isCancelled() { break }
            // 2. Hash parziale, 3. hash completo.
            let partial = Dictionary(grouping: group) { hash($0.url, limit: 64 * 1024) ?? UUID().uuidString }
            for sub in partial.values where sub.count > 1 {
                let full = Dictionary(grouping: sub) { hash($0.url, limit: nil) ?? UUID().uuidString }
                for same in full.values where same.count > 1 {
                    findings += findingsFor(identical: same, downloadsDir: downloadsDir)
                }
            }
        }
        return findings
    }

    /// Tiene la copia "migliore" (fuori da Download, percorso più corto) e segnala le altre.
    private static func findingsFor(identical: [Candidate], downloadsDir: URL) -> [Finding] {
        let sorted = identical.sorted { a, b in
            let aDl = a.url.isInside(downloadsDir), bDl = b.url.isInside(downloadsDir)
            if aDl != bDl { return !aDl }
            if a.url.path.count != b.url.path.count { return a.url.path.count < b.url.path.count }
            return a.url.path < b.url.path
        }
        let original = sorted[0]
        return sorted.dropFirst().map { copy in
            Finding(
                path: copy.url.path, size: copy.size, category: .duplicates, risk: .review,
                reason: tr("Identical copy of \(original.url.path)", "Copia identica di \(original.url.path)"),
                lastUsed: FileStats.lastUsedDate(copy.url)
            )
        }
    }

    static func hash(_ url: URL, limit: Int?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        let chunk = 1 << 20
        while remaining > 0 {
            let toRead = min(chunk, remaining)
            guard let data = try? handle.read(upToCount: toRead), !data.isEmpty else { break }
            hasher.update(data: data)
            remaining -= data.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
