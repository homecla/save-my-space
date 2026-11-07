import Foundation

public struct CleanFailure: Codable, Sendable {
    public let finding: Finding
    public let message: String
}

/// Un elemento spostato nel Cestino, con la posizione in cui è finito (per poterlo ripristinare).
public struct TrashedItem: Codable, Sendable {
    public let finding: Finding
    public let trashedTo: String?
}

public struct CleanResult: Codable, Sendable {
    public var date = Date()
    public var root: String
    public var trashed: [TrashedItem] = []
    public var failed: [CleanFailure] = []
    public var freedBytes: Int64 { trashed.reduce(0) { $0 + $1.finding.size } }

    public init(root: String) { self.root = root }
}

/// Sposta nel Cestino gli elementi scelti. Non elimina mai definitivamente nulla.
public struct Cleaner: Sendable {
    /// Sposta un elemento nel Cestino e restituisce dove è finito.
    public typealias TrashFunction = @Sendable (URL) throws -> URL?

    public let root: URL
    private let trash: TrashFunction

    /// - Parameters:
    ///   - root: solo gli elementi al suo interno possono essere spostati (di norma la home).
    ///   - trash: funzione che sposta un elemento nel Cestino (iniettabile per i test).
    public init(
        root: URL = FileManager.default.homeDirectoryForCurrentUser,
        trash: @escaping TrashFunction = { url in
            var resulting: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            return resulting as URL?
        }
    ) {
        self.root = root.canonical
        self.trash = trash
    }

    /// Cartelle che non vanno mai spostate in blocco, anche se un suggerimento le indicasse.
    private var protectedPaths: Set<String> {
        Set(["", "Library", "Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music",
             "Applications", ".Trash", "Library/Caches", "Library/Mobile Documents"]
            .map { $0.isEmpty ? root.path : root.appendingPathComponent($0).path })
    }

    /// Controlla che un elemento possa essere spostato; restituisce il motivo se non è possibile.
    public func validate(_ finding: Finding) -> String? {
        guard finding.actionable else {
            return tr("report-only item", "elemento solo da segnalare") + (finding.hint.map { ": \($0)" } ?? "")
        }
        let url = URL(fileURLWithPath: finding.path).standardized
        // Risolve i symlink del percorso padre (non dell'elemento: un symlink viene spostato come tale).
        let resolved = url.deletingLastPathComponent().canonical
            .appendingPathComponent(url.lastPathComponent)
        guard resolved.isInside(root) else { return tr("outside \(root.path)", "fuori da \(root.path)") }
        guard !protectedPaths.contains(resolved.path) else { return tr("protected folder", "cartella protetta") }
        guard FileStats.exists(resolved) else { return tr("no longer exists", "non esiste più") }
        return nil
    }

    public func clean(_ findings: [Finding], onItem: ((Finding, String?) -> Void)? = nil) -> CleanResult {
        var result = CleanResult(root: root.path)
        for f in findings {
            if let problem = validate(f) {
                result.failed.append(CleanFailure(finding: f, message: problem))
                onItem?(f, problem)
                continue
            }
            do {
                let destination = try trash(URL(fileURLWithPath: f.path))
                result.trashed.append(TrashedItem(finding: f, trashedTo: destination?.path))
                onItem?(f, nil)
            } catch {
                result.failed.append(CleanFailure(finding: f, message: error.localizedDescription))
                onItem?(f, error.localizedDescription)
            }
        }
        return result
    }
}
