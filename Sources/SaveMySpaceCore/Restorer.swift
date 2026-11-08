// SPDX-FileCopyrightText: 2026 homecla
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Stato di ripristino di un elemento spostato nel Cestino, ricavato dal file system.
public enum RestoreState: Equatable, Sendable {
    case restorable
    case alreadyRestored
    case goneFromTrash
    case conflict
    case invalid(String)

    public var label: String {
        switch self {
        case .restorable: return tr("restorable", "ripristinabile")
        case .alreadyRestored: return tr("already restored", "già ripristinato")
        case .goneFromTrash: return tr("no longer in the Trash (emptied?)", "non è più nel Cestino (Cestino svuotato?)")
        case .conflict: return tr("something already exists at the original location", "esiste già un elemento nella posizione originale")
        case .invalid(let reason): return reason
        }
    }
}

public struct RestoreFailure: Sendable {
    public let item: TrashedItem
    public let message: String
}

public struct RestoreResult: Sendable {
    public var restored: [TrashedItem] = []
    public var failed: [RestoreFailure] = []
    public var restoredBytes: Int64 { restored.reduce(0) { $0 + $1.finding.size } }
}

/// Rimette nella posizione originale gli elementi spostati nel Cestino da una pulizia registrata.
/// Non sovrascrive mai nulla: se la posizione originale è occupata l'elemento resta nel Cestino.
public struct Restorer: Sendable {
    public typealias MoveFunction = @Sendable (_ from: URL, _ to: URL) throws -> Void

    private let move: MoveFunction
    /// Unica cartella in cui è consentito ripristinare (di norma la home). Lo storico è un file
    /// modificabile: senza questo limite una voce manomessa potrebbe indicare qualunque radice.
    public let allowedRoot: URL

    public init(
        allowedRoot: URL = FileManager.default.homeDirectoryForCurrentUser,
        move: @escaping MoveFunction = { from, to in
            try FileManager.default.moveItem(at: from, to: to)
        }
    ) {
        self.allowedRoot = allowedRoot.canonical
        self.move = move
    }

    /// `true` se il percorso è in un Cestino dell'utente corrente: `<allowedRoot>/.Trash`,
    /// `~/.Trash` oppure `/Volumes/<disco>/.Trashes/<uid>` per i dischi esterni.
    private func isUserTrash(_ url: URL) -> Bool {
        let resolved = url.deletingLastPathComponent().canonical.appendingPathComponent(url.lastPathComponent)
        let homes = [allowedRoot, FileManager.default.homeDirectoryForCurrentUser.canonical]
        if homes.contains(where: { resolved.isInside($0.appendingPathComponent(".Trash")) && resolved != $0.appendingPathComponent(".Trash") }) {
            return true
        }
        let comps = resolved.pathComponents   // ["/", "Volumes", "<disco>", ".Trashes", "<uid>", ...]
        return comps.count > 5 && comps[1] == "Volumes" && comps[3] == ".Trashes" && comps[4] == String(getuid())
    }

    public func state(of item: TrashedItem, root: String) -> RestoreState {
        guard let trashedTo = item.trashedTo else {
            return .invalid(tr("unknown location in the Trash", "posizione nel Cestino sconosciuta"))
        }
        let trashURL = URL(fileURLWithPath: trashedTo).standardized
        guard isUserTrash(trashURL) else {
            return .invalid(tr("the recorded location is not in your Trash", "la posizione registrata non è nel tuo Cestino"))
        }
        let original = URL(fileURLWithPath: item.finding.path).standardized
        // Confronto su percorsi risolti (es. /private/tmp e /tmp indicano la stessa cartella).
        let resolvedRoot = URL(fileURLWithPath: root).canonical
        let resolvedOriginal = original.deletingLastPathComponent().canonical
            .appendingPathComponent(original.lastPathComponent)
        guard resolvedOriginal.isInside(resolvedRoot), resolvedOriginal.path != resolvedRoot.path else {
            return .invalid(tr("the original location is outside \(root)", "la posizione originale è fuori da \(root)"))
        }
        guard resolvedOriginal.isInside(allowedRoot), resolvedOriginal.path != allowedRoot.path else {
            return .invalid(tr("the original location is outside \(allowedRoot.path) (use --root to allow it)",
                               "la posizione originale è fuori da \(allowedRoot.path) (usa --root per consentirlo)"))
        }
        let inTrash = FileStats.exists(trashURL)
        let atOriginal = FileStats.exists(original)
        switch (inTrash, atOriginal) {
        case (true, false): return .restorable
        case (true, true): return .conflict
        case (false, true): return .alreadyRestored
        case (false, false): return .goneFromTrash
        }
    }

    public func restore(
        _ items: [TrashedItem],
        root: String,
        onItem: ((TrashedItem, String?) -> Void)? = nil
    ) -> RestoreResult {
        var result = RestoreResult()
        for item in items {
            let state = state(of: item, root: root)
            guard state == .restorable, let trashedTo = item.trashedTo else {
                result.failed.append(RestoreFailure(item: item, message: state.label))
                onItem?(item, state.label)
                continue
            }
            let original = URL(fileURLWithPath: item.finding.path)
            do {
                try FileManager.default.createDirectory(at: original.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try move(URL(fileURLWithPath: trashedTo), original)
                result.restored.append(item)
                onItem?(item, nil)
            } catch {
                result.failed.append(RestoreFailure(item: item, message: error.localizedDescription))
                onItem?(item, error.localizedDescription)
            }
        }
        return result
    }
}
