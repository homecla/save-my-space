// SPDX-FileCopyrightText: 2026 homecla
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Analizza la home e produce un `ScanReport` con i suggerimenti di pulizia.
/// La scansione è di sola lettura: non modifica né sposta alcun file.
public final class Scanner: @unchecked Sendable {
    public let options: ScanOptions
    private let errors = ErrorCollector()

    public init(options: ScanOptions = ScanOptions()) {
        self.options = options
    }

    /// Esegue la scansione. Va chiamata fuori dal main thread; rispetta la cancellazione del `Task`.
    public func scan(progress: (@Sendable (ScanProgress) -> Void)? = nil) throws -> ScanReport {
        let start = Date()
        let root = options.root
        var findings: [Finding] = []

        // 1. Posizioni note (cache, log, Xcode, ...), in parallelo.
        progress?(ScanProgress(phase: tr("Known locations", "Posizioni note"), itemsScanned: 0, currentPath: nil))
        let locations = KnownLocation.all
        let results = LockedArray<[Finding]>(count: locations.count, initial: [])
        DispatchQueue.concurrentPerform(iterations: locations.count) { i in
            results[i] = locations[i].findings(root: root, options: options, errors: errors)
        }
        findings += results.values.flatMap { $0 }

        progress?(ScanProgress(phase: tr("App data", "Dati delle app"), itemsScanned: 0, currentPath: nil))
        findings += AppData.findings(root: root, options: options, errors: errors)
        try Task.checkCancellation()

        // 2. Scansione generale della home.
        let walk = try walkHome(progress: progress)
        findings += walk.findings

        // 3. Duplicati.
        if options.findDuplicates {
            progress?(ScanProgress(phase: tr("Duplicates", "Duplicati"), itemsScanned: walk.itemsScanned, currentPath: nil))
            findings += Duplicates.find(
                walk.duplicateCandidates,
                downloadsDir: root.appendingPathComponent("Downloads"),
                isCancelled: { Task.isCancelled }
            )
            try Task.checkCancellation()
        }

        return ScanReport(
            root: root.path,
            scannedAt: start,
            duration: Date().timeIntervalSince(start),
            itemsScanned: walk.itemsScanned,
            findings: findings,
            unreadableCount: errors.count,
            unreadableSamples: errors.samples
        )
    }

    private struct WalkResult {
        var findings: [Finding] = []
        var duplicateCandidates: [Duplicates.Candidate] = []
        var itemsScanned = 0
    }

    private func walkHome(progress: (@Sendable (ScanProgress) -> Void)?) throws -> WalkResult {
        let root = options.root
        let cutoff = options.cutoffDate
        let downloads = root.appendingPathComponent("Downloads").path
        let excluded = Set(KnownLocation.walkExclusions.map { root.appendingPathComponent($0).path })
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .isPackageKey,
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        ]
        var result = WalkResult()

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { [errors] url, _ in
                errors.record(url)
                return true
            }
        ) else { return result }

        progress?(ScanProgress(phase: tr("Scanning home", "Scansione della home"), itemsScanned: 0, currentPath: root.path))

        for case let url as URL in enumerator {
            result.itemsScanned += 1
            if result.itemsScanned % 2000 == 0 {
                try Task.checkCancellation()
                progress?(ScanProgress(phase: tr("Scanning home", "Scansione della home"), itemsScanned: result.itemsScanned,
                                       currentPath: url.path))
            }

            let path = url.path
            // ~/Library e le cartelle nascoste sono coperte dalle regole mirate (posizioni note, dati delle app):
            // qui si analizzano solo le aree dell'utente.
            if url.deletingLastPathComponent().path == root.path,
               url.lastPathComponent == "Library" || url.lastPathComponent.hasPrefix(".") {
                enumerator.skipDescendants()
                continue
            }
            if excluded.contains(path) {
                enumerator.skipDescendants()
                continue
            }
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isSymbolicLink != true else {
                continue
            }
            let isDir = v.isDirectory == true
            let isPackage = v.isPackage == true
            if isPackage && url.pathExtension == "photoslibrary" { continue }

            // Elementi di primo livello in ~/Downloads.
            if url.deletingLastPathComponent().path == downloads {
                let size = isDir ? FileStats.allocatedSize(of: url, errors: errors)
                                 : Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                if let f = downloadFinding(url, size: size, cutoff: cutoff) {
                    result.findings.append(f)
                    if isDir { enumerator.skipDescendants() }
                    continue
                }
            }

            // Cartelle di progetto rigenerabili (node_modules, build, ...).
            if isDir && !isPackage {
                if let match = ProjectArtifacts.match(url) {
                    enumerator.skipDescendants()
                    let project = url.deletingLastPathComponent()
                    let last = ProjectArtifacts.lastActivity(ofProject: project)
                    if let last, last > cutoff { continue }
                    let size = FileStats.allocatedSize(of: url, errors: errors)
                    guard size >= options.minFindingSize else { continue }
                    let idle = daysAgo(last).map { tr("project idle for \($0) days", "progetto fermo da \($0) giorni") }
                        ?? tr("inactive project", "progetto inattivo")
                    result.findings.append(Finding(
                        path: path, size: size, category: .developer, risk: .review,
                        reason: "\(match.reason) (\(idle))", hint: match.hint, lastUsed: last
                    ))
                }
                continue
            }

            // File (o pacchetto trattato come unità, es. .app).
            let size = isPackage ? FileStats.allocatedSize(of: url, errors: errors)
                                 : Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            if size >= options.largeFileThreshold {
                let last = FileStats.lastUsedDate(url)
                let usage = daysAgo(last).map { tr(", last used \($0) days ago", ", ultimo uso \($0) giorni fa") } ?? ""
                result.findings.append(Finding(
                    path: path, size: size, category: .largeFiles, risk: .review,
                    reason: tr("Very large file\(usage)", "File molto grande\(usage)"), lastUsed: last
                ))
            }
            if !isPackage && v.isRegularFile == true && size >= options.duplicateMinSize {
                result.duplicateCandidates.append(.init(url: url, size: size))
            }
        }
        return result
    }

    private static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]

    private func downloadFinding(_ url: URL, size: Int64, cutoff: Date) -> Finding? {
        guard size >= options.minFindingSize else { return nil }
        let last = FileStats.lastUsedDate(url)
        if Self.installerExtensions.contains(url.pathExtension.lowercased()) {
            return Finding(
                path: url.path, size: size, category: .downloads, risk: .review,
                reason: tr("Disk image or installer: no longer needed if the app is already installed",
                           "Immagine disco o installer: se il programma è già installato non serve più"),
                lastUsed: last
            )
        }
        if let last, last < cutoff {
            return Finding(
                path: url.path, size: size, category: .downloads, risk: .review,
                reason: tr("Downloaded and unused for \(daysAgo(last) ?? 0) days",
                           "Scaricato e non usato da \(daysAgo(last) ?? 0) giorni"), lastUsed: last
            )
        }
        return nil
    }
}

