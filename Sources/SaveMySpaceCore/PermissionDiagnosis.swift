// SPDX-FileCopyrightText: 2026 homecla
// SPDX-License-Identifier: AGPL-3.0-or-later

import Darwin
import Foundation

/// Perché macOS ha impedito di spostare un elemento nel Cestino.
public enum PermissionProblem: Equatable, Sendable {
    /// L'elemento appartiene a un altro utente (di solito root).
    case ownedBy(String)
    /// L'elemento (o la cartella che lo contiene) è bloccato o ha un'ACL che ne vieta lo spostamento.
    case lockedBySystem
    /// Nessuna causa visibile nei permessi: tipicamente la privacy di macOS (TCC).
    case privacyProtected

    /// Spiegazione breve e localizzata, con il rimedio.
    public var message: String {
        switch self {
        case .ownedBy(let owner):
            return tr("permission denied: owned by \"\(owner)\", so only an administrator can move it "
                      + "(drag it to the Trash in the Finder, which asks for the password)",
                      "permesso negato: appartiene a \"\(owner)\", quindi solo un amministratore può spostarlo "
                      + "(trascinalo nel Cestino dal Finder, che chiede la password)")
        case .lockedBySystem:
            return tr("permission denied: macOS protects this item (locked or system access rule); "
                      + "it cannot be moved as a whole, clean its contents instead",
                      "permesso negato: macOS protegge questo elemento (bloccato o regola di accesso di sistema); "
                      + "non si può spostare in blocco, pulisci il suo contenuto")
        case .privacyProtected:
            return tr("permission denied by macOS privacy: grant Full Disk Access to the app you are using "
                      + "(System Settings › Privacy & Security › Full Disk Access)",
                      "permesso negato dalla privacy di macOS: concedi l'Accesso completo al disco all'app che stai usando "
                      + "(Impostazioni di Sistema › Privacy e sicurezza › Accesso completo al disco)")
        }
    }
}

enum PermissionDiagnosis {
    /// `true` se l'errore è un rifiuto per permessi (anche annidato).
    static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        switch (ns.domain, ns.code) {
        case (NSCocoaErrorDomain, NSFileWriteNoPermissionError),
             (NSCocoaErrorDomain, NSFileReadNoPermissionError),
             (NSPOSIXErrorDomain, Int(EACCES)),
             (NSPOSIXErrorDomain, Int(EPERM)):
            return true
        default:
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
                return isPermissionError(underlying)
            }
            return false
        }
    }

    /// Cerca la causa nei metadati dell'elemento e della cartella che lo contiene.
    static func diagnose(_ url: URL) -> PermissionProblem {
        var st = stat()
        if lstat(url.path, &st) == 0 {
            if st.st_uid != getuid() {
                return .ownedBy(userName(st.st_uid))
            }
            if isLocked(st) || hasACL(url) {
                return .lockedBySystem
            }
        }
        let parent = url.deletingLastPathComponent()
        var pst = stat()
        if lstat(parent.path, &pst) == 0, isLocked(pst) || hasACL(parent) || access(parent.path, W_OK) != 0 {
            return .lockedBySystem
        }
        return .privacyProtected
    }

    private static func isLocked(_ st: stat) -> Bool {
        let mask = UInt32(UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND)
        return st.st_flags & mask != 0
    }

    /// Le ACL che macOS applica alle cartelle di sistema della home (es. "everyone deny delete").
    private static func hasACL(_ url: URL) -> Bool {
        guard let acl = acl_get_link_np(url.path, ACL_TYPE_EXTENDED) else { return false }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        return acl_get_entry(acl, ACL_FIRST_ENTRY.rawValue, &entry) == 0
    }

    private static func userName(_ uid: uid_t) -> String {
        if let pw = getpwuid(uid), let name = pw.pointee.pw_name {
            return String(cString: name)
        }
        return String(uid)
    }
}
