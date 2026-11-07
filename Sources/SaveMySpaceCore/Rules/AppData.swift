// SPDX-FileCopyrightText: 2026 homecla
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Cartelle di dati delle applicazioni (Application Support, giochi, cartelle nascoste come
/// `~/.ollama`) che superano la soglia dei file grandi. Vengono segnalate come unità intera:
/// cancellarne singoli file romperebbe l'app che li usa.
enum AppData {
    static let parents = ["Library/Application Support", "Library/Games"]

    static func candidates(root: URL) -> [URL] {
        let fm = FileManager.default
        let knownPaths = KnownLocation.all.map { root.appendingPathComponent($0.relativePath) }

        var result: [URL] = []
        for parent in parents {
            let dir = root.appendingPathComponent(parent)
            result += (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        }
        // Cartelle nascoste di primo livello (~/.ollama, ~/.local, ~/.rustup, ...).
        let top = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        result += top.filter { url in
            url.lastPathComponent.hasPrefix(".")
                && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        // Escludi le cartelle che contengono (o sono) posizioni note: hanno già suggerimenti più precisi.
        return result.filter { candidate in
            !knownPaths.contains { $0.isInside(candidate) }
        }
    }

    static func findings(root: URL, options: ScanOptions, errors: ErrorCollector) -> [Finding] {
        let urls = candidates(root: root)
        let sizes = LockedArray<Int64>(count: urls.count, initial: 0)
        DispatchQueue.concurrentPerform(iterations: urls.count) { i in
            sizes[i] = FileStats.allocatedSize(of: urls[i], errors: errors)
        }
        return zip(urls, sizes.values).compactMap { url, size in
            guard size >= options.largeFileThreshold else { return nil }
            let last = FileStats.lastUsedDate(url)
            let usage = daysAgo(last).map { tr(", last used \($0) days ago", ", ultimo uso \($0) giorni fa") } ?? ""
            let isSystem = url.lastPathComponent.hasPrefix("com.apple.")
            return Finding(
                path: url.path, size: size, category: .appData, risk: .caution,
                reason: tr("Data of the app “\(url.lastPathComponent)”\(usage)", "Dati dell'app «\(url.lastPathComponent)»\(usage)"),
                actionable: !isSystem,
                hint: isSystem
                    ? tr("Managed by macOS: do not delete it manually", "Dati gestiti da macOS: non eliminarli a mano")
                    : tr("If you no longer need the app, uninstall it or remove the data from its settings", "Se l'app non ti serve più, disinstallala o rimuovi i dati dalle sue impostazioni"),
                lastUsed: last
            )
        }
    }
}

/// Array a dimensione fissa scrivibile da più thread (ogni indice da un solo thread).
final class LockedArray<T>: @unchecked Sendable {
    private var storage: [T]
    private let lock = NSLock()

    init(count: Int, initial: T) { storage = Array(repeating: initial, count: count) }

    subscript(i: Int) -> T {
        get { lock.withLock { storage[i] } }
        set { lock.withLock { storage[i] = newValue } }
    }

    var values: [T] { lock.withLock { storage } }
}
