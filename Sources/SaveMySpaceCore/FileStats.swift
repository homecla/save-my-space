import CoreServices
import Foundation

/// Raccoglie in modo thread-safe i percorsi non leggibili (tipicamente per i permessi TCC).
final class ErrorCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var count = 0
    private(set) var samples: [String] = []

    func record(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        if samples.count < 25 { samples.append(url.path) }
    }
}

enum FileStats {
    static let sizeKeys: [URLResourceKey] = [
        .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    /// Spazio occupato su disco da un file o da una cartella (ricorsivo, senza seguire i symlink).
    static func allocatedSize(of url: URL, errors: ErrorCollector? = nil) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return 0
        }
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory != true { return fileSize(url) }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: sizeKeys,
            options: [],
            errorHandler: { errURL, _ in
                errors?.record(errURL)
                return true
            }
        ) else { return 0 }

        var total: Int64 = 0
        for case let child as URL in enumerator {
            guard let v = try? child.resourceValues(forKeys: Set(sizeKeys)), v.isRegularFile == true else {
                continue
            }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func fileSize(_ url: URL) -> Int64 {
        let v = try? url.resourceValues(forKeys: Set(sizeKeys))
        return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
    }

    /// Data di ultimo utilizzo: usa Spotlight (`kMDItemLastUsedDate`) se disponibile,
    /// altrimenti la più recente fra data di accesso, modifica e aggiunta alla cartella.
    static func lastUsedDate(_ url: URL) -> Date? {
        if let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
           let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date {
            return date
        }
        let v = try? url.resourceValues(forKeys: [
            .contentAccessDateKey, .contentModificationDateKey, .addedToDirectoryDateKey,
        ])
        return [v?.contentAccessDate, v?.contentModificationDate, v?.addedToDirectoryDate]
            .compactMap { $0 }
            .max()
    }

    static func exists(_ url: URL) -> Bool {
        var st = stat()
        return lstat(url.path, &st) == 0
    }

    /// Identificativo (device, inode) per non scambiare gli hard link per duplicati.
    static func inode(_ url: URL) -> String? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        return "\(st.st_dev):\(st.st_ino)"
    }
}

extension URL {
    /// `true` se l'URL è uguale a `ancestor` o si trova al suo interno.
    public func isInside(_ ancestor: URL) -> Bool {
        let a = ancestor.standardized.path
        let p = standardized.path
        return p == a || p.hasPrefix(a.hasSuffix("/") ? a : a + "/")
    }
}

func daysAgo(_ date: Date?) -> Int? {
    guard let date else { return nil }
    return max(0, Int(Date().timeIntervalSince(date) / 86_400))
}

extension URL {
    /// Percorso canonico con `realpath(3)`: risolve i symlink del più profondo antenato esistente
    /// (anche se l'elemento stesso non esiste più) e riaggiunge il resto. A differenza di
    /// `resolvingSymlinksInPath()` tratta in modo coerente `/tmp` e `/private/tmp`.
    public var canonical: URL {
        var existing = standardized
        var rest: [String] = []
        while existing.path != "/" {
            if let real = realpath(existing.path, nil) {
                defer { free(real) }
                var url = URL(fileURLWithPath: String(cString: real))
                for c in rest.reversed() { url.appendPathComponent(c) }
                return url
            }
            rest.append(existing.lastPathComponent)
            existing.deleteLastPathComponent()
        }
        return standardized
    }
}
