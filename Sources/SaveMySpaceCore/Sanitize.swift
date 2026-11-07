// SPDX-FileCopyrightText: 2026 homecla
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum Sanitize {
    /// Rende visibili i caratteri di controllo (C0, DEL, C1) di un testo destinato al terminale.
    /// I nomi dei file possono contenere sequenze di escape ANSI che, stampate così come sono,
    /// manipolerebbero il terminale (cancellare righe, cambiare il titolo, ...).
    public static func forTerminal(_ text: String) -> String {
        var out = ""
        out.unicodeScalars.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            if scalar.properties.generalCategory == .control {
                out += String(format: "\\x%02x", scalar.value)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// Evita che un foglio di calcolo interpreti una cella CSV come formula ("CSV injection").
    public static func forSpreadsheet(_ text: String) -> String {
        guard let first = text.first, "=+-@\t\r".contains(first) else { return text }
        return "'" + text
    }
}
