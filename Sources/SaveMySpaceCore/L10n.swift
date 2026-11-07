// SPDX-FileCopyrightText: 2026 homecla
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Lingue supportate.
public enum Language: String, CaseIterable, Sendable {
    case en
    case it

    public var displayName: String {
        switch self {
        case .en: return "English"
        case .it: return "Italiano"
        }
    }
}

/// Localizzazione minimale: le due lingue sono scritte una accanto all'altra nel punto d'uso
/// (`tr("English", "Italiano")`), così non servono file di risorse da distribuire con la CLI.
public enum L10n {
    nonisolated(unsafe) public static var language: Language = detect()

    /// Priorità: argomento esplicito (`--lang`), variabile `SMSPACE_LANG`, lingue preferite di sistema.
    /// Se nessuna è supportata si usa l'inglese.
    public static func detect(
        explicit: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preferred: [String] = Locale.preferredLanguages
    ) -> Language {
        let candidates = [explicit, environment["SMSPACE_LANG"]].compactMap { $0 } + preferred
        for candidate in candidates {
            let code = candidate.lowercased().prefix(2)
            if let lang = Language(rawValue: String(code)) { return lang }
        }
        return .en
    }

    /// Locale coerente con la lingua scelta (per date e numeri).
    public static var locale: Locale {
        let current = Locale.current
        if current.language.languageCode?.identifier == language.rawValue { return current }
        return Locale(identifier: language == .it ? "it_IT" : "en_US")
    }

    public static func dateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

/// Restituisce il testo nella lingua corrente.
public func tr(_ en: String, _ it: String) -> String {
    L10n.language == .it ? it : en
}
