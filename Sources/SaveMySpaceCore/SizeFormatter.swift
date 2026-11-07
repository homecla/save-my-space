// SPDX-FileCopyrightText: 2026 homecla
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum SizeFormatter {
    public static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Interpreta dimensioni come `500MB`, `1.5G`, `200k`, `1024` (byte). Unità decimali, come il Finder.
    public static func parse(_ text: String) -> Int64? {
        let s = text.trimmingCharacters(in: .whitespaces).uppercased()
        let digits = s.prefix { $0.isNumber || $0 == "." || $0 == "," }
        guard let value = Double(digits.replacingOccurrences(of: ",", with: ".")), value >= 0 else {
            return nil
        }
        let unit = s.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
        let multiplier: Double
        switch unit {
        case "", "B": multiplier = 1
        case "K", "KB": multiplier = 1e3
        case "M", "MB": multiplier = 1e6
        case "G", "GB": multiplier = 1e9
        case "T", "TB": multiplier = 1e12
        default: return nil
        }
        return Int64(value * multiplier)
    }
}
