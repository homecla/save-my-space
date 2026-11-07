// SPDX-FileCopyrightText: 2026 homecla
// SPDX-License-Identifier: AGPL-3.0-or-later
// Test cases for the rules in save-my-space.yml (`opengrep scan --test .opengrep/`).
import Foundation

func deleting(_ url: URL) throws {
    // ruleid: no-permanent-delete
    try FileManager.default.removeItem(at: url)
    // Trashing is not a permanent delete, but is still only allowed in Cleaner:
    // ruleid: file-move-outside-guarded-code
    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
}

func moving(_ a: URL, _ b: URL) throws {
    // ruleid: file-move-outside-guarded-code
    try FileManager.default.moveItem(at: a, to: b)
}

func normalizing(_ u: URL) -> String {
    // ruleid: unreliable-path-normalization
    let x = u.standardizedFileURL.path
    // ok: unreliable-path-normalization
    let y = u.standardized.path
    return x + y
}

func launching(_ p: Process, _ target: URL) {
    // ruleid: external-process-execution
    p.executableURL = target
}

func forcing(_ data: Data, _ any: Any) {
    // ruleid: force-try
    _ = try! JSONSerialization.jsonObject(with: data)
    // ok: force-try
    _ = try? JSONSerialization.jsonObject(with: data)
    // ruleid: force-cast
    _ = any as! String
    // ok: force-cast
    _ = any as? String
}

func locating() -> URL {
    // ruleid: argv0-as-path
    return URL(fileURLWithPath: CommandLine.arguments[0])
}
