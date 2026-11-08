// SPDX-FileCopyrightText: 2026 homecla
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import SaveMySpaceCore

/// Crea una "home" fittizia in una cartella temporanea.
final class FakeHome {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("save-my-space-tests-\(UUID().uuidString)")
            .canonical
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func file(_ relative: String, size: Int, byte: UInt8 = 0x41, modified: Date? = nil) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Contenuto non comprimibile per evitare che APFS riduca lo spazio allocato.
        var bytes = [UInt8](repeating: byte, count: size)
        var seed = UInt64(byte)
        for i in 0..<size {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            bytes[i] = UInt8(truncatingIfNeeded: seed >> 33)
        }
        try Data(bytes).write(to: url)
        if let modified {
            try FileManager.default.setAttributes(
                [.modificationDate: modified, .creationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    func setModified(_ relative: String, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date],
                                              ofItemAtPath: root.appendingPathComponent(relative).path)
    }
}

private let mb = 1_000_000
private let longAgo = Date().addingTimeInterval(-400 * 86_400)

private func scan(_ home: FakeHome, large: Int64 = 5_000_000) throws -> ScanReport {
    let options = ScanOptions(root: home.root, largeFileThreshold: large, olderThanDays: 90,
                              duplicateMinSize: 100_000, minFindingSize: 100_000)
    return try Scanner(options: options).scan()
}

@Test func findsCachesLogsAndDerivedData() throws {
    let home = try FakeHome()
    try home.file("Library/Caches/com.example.app/blob", size: 2 * mb)
    try home.file("Library/Caches/Homebrew/downloads/pkg.tar.gz", size: 1 * mb)
    try home.file("Library/Caches/tiny/x", size: 10)
    try home.file("Library/Logs/app.log", size: 1 * mb)
    try home.file("Library/Developer/Xcode/DerivedData/Proj-abc/Build/out.o", size: 1 * mb)

    let report = try scan(home)
    let byPath = Dictionary(uniqueKeysWithValues: report.findings.map { ($0.path, $0) })

    let cache = try #require(byPath[home.root.appendingPathComponent("Library/Caches/com.example.app").path])
    #expect(cache.category == .caches)
    #expect(cache.risk == .safe)
    #expect(cache.size >= Int64(2 * mb))

    let brew = try #require(byPath[home.root.appendingPathComponent("Library/Caches/Homebrew").path])
    #expect(brew.hint == "brew cleanup --prune=all")

    #expect(byPath[home.root.appendingPathComponent("Library/Caches/tiny").path] == nil)
    #expect(byPath[home.root.appendingPathComponent("Library/Logs").path]?.category == .logs)
    #expect(byPath[home.root.appendingPathComponent("Library/Developer/Xcode/DerivedData").path]?.category == .developer)
}

@Test func findsLargeFilesAndDuplicates() throws {
    let home = try FakeHome()
    try home.file("Movies/big.mov", size: 6 * mb, byte: 1)
    try home.file("Documents/report.pdf", size: 1 * mb, byte: 2)
    try home.file("Desktop/report copy.pdf", size: 1 * mb, byte: 2)
    try home.file("Documents/other.pdf", size: 1 * mb, byte: 3)

    let report = try scan(home)

    let large = report.filtered(categories: [.largeFiles])
    #expect(large.map(\.path) == [home.root.appendingPathComponent("Movies/big.mov").path])

    let dups = report.filtered(categories: [.duplicates])
    #expect(dups.count == 1)
    // Viene tenuto il percorso più corto, segnalata la copia.
    #expect(dups.first?.path == home.root.appendingPathComponent("Desktop/report copy.pdf").path)
    #expect(dups.first?.reason.contains("Documents/report.pdf") == true)
}

@Test func hardLinksAreNotDuplicates() throws {
    let home = try FakeHome()
    let original = try home.file("Documents/a.bin", size: 1 * mb, byte: 9)
    try FileManager.default.linkItem(at: original, to: home.root.appendingPathComponent("Documents/b.bin"))

    let report = try scan(home)
    #expect(report.filtered(categories: [.duplicates]).isEmpty)
}

@Test func findsOldDownloadsAndInstallers() throws {
    let home = try FakeHome()
    try home.file("Downloads/old.zip", size: 1 * mb, byte: 4, modified: longAgo)
    try home.file("Downloads/recent.zip", size: 1 * mb, byte: 5)
    try home.file("Downloads/Installer.dmg", size: 1 * mb, byte: 6)

    let report = try scan(home)
    let names = Set(report.filtered(categories: [.downloads]).map { ($0.path as NSString).lastPathComponent })
    #expect(names.contains("Installer.dmg"))
    #expect(!names.contains("recent.zip"))
    // "old.zip" dipende dalla data di ultimo uso di Spotlight, che per file appena creati
    // può non essere disponibile: in quel caso conta la data di modifica.
    if FileStats.lastUsedDate(home.root.appendingPathComponent("Downloads/old.zip"))! < Date().addingTimeInterval(-90 * 86_400) {
        #expect(names.contains("old.zip"))
    }
}

@Test func findsNodeModulesOnlyInInactiveProjects() throws {
    let home = try FakeHome()
    try home.file("Devel/old-project/package.json", size: 10)
    try home.file("Devel/old-project/node_modules/lib/index.js", size: 1 * mb, byte: 7)
    try home.setModified("Devel/old-project/package.json", longAgo)
    try home.setModified("Devel/old-project", longAgo)

    try home.file("Devel/active-project/package.json", size: 10)
    try home.file("Devel/active-project/node_modules/lib/index.js", size: 1 * mb, byte: 8)

    let report = try scan(home)
    let dev = report.filtered(categories: [.developer]).map(\.path)
    #expect(dev.contains(home.root.appendingPathComponent("Devel/old-project/node_modules").path))
    #expect(!dev.contains(home.root.appendingPathComponent("Devel/active-project/node_modules").path))
}

@Test func reportRemovesNestedAndDuplicatePaths() {
    let a = Finding(path: "/h/Library/Caches", size: 10, category: .caches, risk: .safe, reason: "")
    let b = Finding(path: "/h/Library/Caches/x", size: 5, category: .caches, risk: .safe, reason: "")
    let c = Finding(path: "/h/f.bin", size: 7, category: .largeFiles, risk: .review, reason: "")
    let d = Finding(path: "/h/f.bin", size: 7, category: .duplicates, risk: .review, reason: "copia")
    let report = ScanReport(root: "/h", scannedAt: Date(), duration: 0, itemsScanned: 0,
                            findings: [a, b, c, d], unreadableCount: 0, unreadableSamples: [])
    #expect(report.findings.count == 2)
    #expect(report.totalSize == 17)
    #expect(report.findings.first { $0.path == "/h/f.bin" }?.category == .duplicates)
}

@Test func cleanerMovesOnlyValidItems() throws {
    let home = try FakeHome()
    let fakeTrash = home.root.appendingPathComponent(".FakeTrash")
    try FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
    let cache = try home.file("Library/Caches/app/blob", size: 1000).deletingLastPathComponent()

    let cleaner = Cleaner(root: home.root) { url in
        let dest = fakeTrash.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: dest)
        return dest
    }
    let ok = Finding(path: cache.path, size: 1000, category: .caches, risk: .safe, reason: "")
    let outside = Finding(path: "/etc/hosts", size: 1, category: .caches, risk: .safe, reason: "")
    let protected = Finding(path: home.root.appendingPathComponent("Library").path, size: 1,
                            category: .caches, risk: .safe, reason: "")
    let reportOnly = Finding(path: cache.path, size: 1, category: .trash, risk: .safe, reason: "",
                             actionable: false)
    let missing = Finding(path: home.root.appendingPathComponent("nope").path, size: 1,
                          category: .caches, risk: .safe, reason: "")

    let result = cleaner.clean([reportOnly, outside, protected, missing, ok])
    #expect(result.trashed.map(\.finding.path) == [cache.path])
    #expect(result.trashed.first?.trashedTo == fakeTrash.appendingPathComponent("app").path)
    #expect(result.failed.count == 4)
    #expect(!FileManager.default.fileExists(atPath: cache.path))
    #expect(FileManager.default.fileExists(atPath: fakeTrash.appendingPathComponent("app").path))
}

@Test func symlinkEscapeIsRejected() throws {
    let home = try FakeHome()
    let outside = try FakeHome()
    try outside.file("secret/data", size: 10)
    try FileManager.default.createSymbolicLink(
        at: home.root.appendingPathComponent("link"), withDestinationURL: outside.root)

    let cleaner = Cleaner(root: home.root) { _ in Issue.record("non doveva spostare nulla"); return nil }
    let escaped = Finding(path: home.root.appendingPathComponent("link/secret").path, size: 10,
                          category: .caches, risk: .safe, reason: "")
    let result = cleaner.clean([escaped])
    #expect(result.trashed.isEmpty)
}

@Test func parsesSizes() {
    #expect(SizeFormatter.parse("500MB") == 500_000_000)
    #expect(SizeFormatter.parse("1.5G") == 1_500_000_000)
    #expect(SizeFormatter.parse("200k") == 200_000)
    #expect(SizeFormatter.parse("1024") == 1024)
    #expect(SizeFormatter.parse("abc") == nil)
    #expect(SizeFormatter.parse("10 XB") == nil)
}

@Test func appDataIsReportedAsAWholeAndNotAsLargeFiles() throws {
    let home = try FakeHome()
    try home.file("Library/Application Support/SomeGame/data.pak", size: 6 * mb, byte: 11)
    try home.file("Library/Application Support/com.apple.wallpaper/w.heic", size: 6 * mb, byte: 12)
    try home.file(".ollama/models/blob", size: 6 * mb, byte: 13)

    let report = try scan(home)
    let appData = Dictionary(uniqueKeysWithValues: report.filtered(categories: [.appData]).map { ($0.path, $0) })

    let game = try #require(appData[home.root.appendingPathComponent("Library/Application Support/SomeGame").path])
    #expect(game.risk == .caution)
    #expect(game.actionable)
    #expect(appData[home.root.appendingPathComponent(".ollama").path] != nil)
    #expect(appData[home.root.appendingPathComponent("Library/Application Support/com.apple.wallpaper").path]?.actionable == false)
    // I singoli file dentro i dati delle app non devono comparire come "file grandi".
    #expect(report.filtered(categories: [.largeFiles]).isEmpty)
    // Gli elementi "attenzione" non contano nello spazio sicuro.
    #expect(report.reclaimableSize == 0)
}

@Test func exportsScanReportInAllFormats() throws {
    let f = Finding(path: "/h/a, \"b\"|c", size: 2_000_000, category: .caches, risk: .safe,
                    reason: "motivo", hint: "brew cleanup")
    let report = ScanReport(root: "/h", scannedAt: Date(), duration: 1, itemsScanned: 10,
                            findings: [f], unreadableCount: 0, unreadableSamples: [])

    let csv = String(decoding: try report.export(.csv), as: UTF8.self)
    #expect(csv.hasPrefix("path,size_bytes,"))
    #expect(csv.contains("\"/h/a, \"\"b\"\"|c\",2000000,"))

    let md = String(decoding: try report.export(.markdown), as: UTF8.self)
    #expect(md.contains("## Cache"))
    #expect(md.contains("a, \"b\"\\|c"))

    let json = try JSONSerialization.jsonObject(with: try report.export(.json)) as? [String: Any]
    #expect((json?["findings"] as? [Any])?.count == 1)

    #expect(ReportFormat(fileURL: URL(fileURLWithPath: "/x/r.CSV")) == .csv)
    #expect(ReportFormat(fileURL: URL(fileURLWithPath: "/x/r.txt")) == .markdown)
}

@Test func historyAppendsAndLoadsCleanResults() throws {
    let home = try FakeHome()
    let history = CleanHistory(fileURL: home.root.appendingPathComponent("hist/history.jsonl"))
    #expect(history.load().isEmpty)

    var first = CleanResult(root: "/h")
    first.trashed = [TrashedItem(finding: Finding(path: "/h/x", size: 5, category: .logs, risk: .safe, reason: "r"),
                                 trashedTo: "/h/.Trash/x")]
    var second = CleanResult(root: "/h")
    second.failed = [CleanFailure(finding: Finding(path: "/h/y", size: 1, category: .caches, risk: .safe, reason: "r"),
                                  message: "non esiste più")]
    try history.append(first)
    try history.append(CleanResult(root: "/h"))   // vuoto: non registrato
    try history.append(second)

    let loaded = history.load()
    #expect(loaded.count == 2)
    #expect(loaded[0].trashed.first?.trashedTo == "/h/.Trash/x")
    #expect(loaded[0].freedBytes == 5)
    #expect(loaded[1].failed.first?.message == "non esiste più")

    let md = String(decoding: try loaded[0].export(.markdown), as: UTF8.self)
    #expect(md.contains("/h/.Trash/x"))
}

@Test func restorerPutsItemsBackWithoutOverwriting() throws {
    let home = try FakeHome()
    let trash = home.root.appendingPathComponent(".Trash")
    try home.file(".Trash/cache-a/blob", size: 10)
    try home.file(".Trash/cache-b/blob", size: 10)
    try home.file("Library/Caches/cache-b/blob", size: 10)   // posizione già occupata

    func item(_ name: String, trashed: String?) -> TrashedItem {
        TrashedItem(finding: Finding(path: home.root.appendingPathComponent("Library/Caches/\(name)").path,
                                     size: 10, category: .caches, risk: .safe, reason: ""),
                    trashedTo: trashed)
    }
    let a = item("cache-a", trashed: trash.appendingPathComponent("cache-a").path)
    let b = item("cache-b", trashed: trash.appendingPathComponent("cache-b").path)
    let gone = item("cache-c", trashed: trash.appendingPathComponent("cache-c").path)
    let notTrash = item("cache-d", trashed: home.root.appendingPathComponent("Documents/x").path)
    let outside = TrashedItem(finding: Finding(path: "/etc/hosts", size: 1, category: .caches, risk: .safe, reason: ""),
                              trashedTo: trash.appendingPathComponent("cache-a").path)

    let restorer = Restorer()
    let root = home.root.path
    #expect(restorer.state(of: a, root: root) == .restorable)
    #expect(restorer.state(of: b, root: root) == .conflict)
    #expect(restorer.state(of: gone, root: root) == .goneFromTrash)
    if case .invalid = restorer.state(of: notTrash, root: root) {} else { Issue.record("atteso invalid") }
    if case .invalid = restorer.state(of: outside, root: root) {} else { Issue.record("atteso invalid") }

    let result = restorer.restore([a, b, gone, notTrash, outside], root: root)
    #expect(result.restored.map(\.finding.path) == [a.finding.path])
    #expect(result.failed.count == 4)
    #expect(FileManager.default.fileExists(atPath: home.root.appendingPathComponent("Library/Caches/cache-a/blob").path))
    // L'elemento in conflitto resta nel Cestino.
    #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent("cache-b").path))
    #expect(restorer.state(of: a, root: root) == .alreadyRestored)
}

@Test func languageDetectionPriority() {
    #expect(L10n.detect(explicit: "it", environment: ["SMSPACE_LANG": "en"], preferred: ["en-US"]) == .it)
    #expect(L10n.detect(explicit: nil, environment: ["SMSPACE_LANG": "it"], preferred: ["en-US"]) == .it)
    #expect(L10n.detect(explicit: nil, environment: [:], preferred: ["it-IT", "en-US"]) == .it)
    #expect(L10n.detect(explicit: nil, environment: [:], preferred: ["fr-FR", "en-GB"]) == .en)
    #expect(L10n.detect(explicit: nil, environment: [:], preferred: ["de-DE"]) == .en)
}

@Test func translationsFollowTheCurrentLanguage() {
    let saved = L10n.language
    defer { L10n.language = saved }
    L10n.language = .en
    #expect(Risk.safe.label == "safe")
    #expect(CleanupCategory.largeFiles.label == "Large files")
    L10n.language = .it
    #expect(Risk.safe.label == "sicuro")
    #expect(CleanupCategory.largeFiles.label == "File grandi")
}

@Test func terminalOutputNeutralizesControlCharacters() {
    #expect(Sanitize.forTerminal("ok\u{1B}[2Kx\u{7}\ny\u{9B}") == "ok\\x1b[2Kx\\x07\\x0ay\\x9b")
    #expect(Sanitize.forTerminal("/Users/a/Café 📦.dmg") == "/Users/a/Café 📦.dmg")
}

@Test func csvCellsCannotBecomeFormulas() {
    #expect(Sanitize.forSpreadsheet("=HYPERLINK(\"x\")") == "'=HYPERLINK(\"x\")")
    #expect(Sanitize.forSpreadsheet("+1") == "'+1")
    #expect(Sanitize.forSpreadsheet("/Users/a/b") == "/Users/a/b")
    #expect(Encoding.csvLine(["@cmd", "ok"]) == "'@cmd,ok")
}
