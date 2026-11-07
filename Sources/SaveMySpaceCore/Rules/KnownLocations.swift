import Foundation

/// Una posizione nota della home che contiene dati tipicamente eliminabili.
struct KnownLocation: Sendable {
    let relativePath: String
    /// Se `true` produce un suggerimento per ogni elemento contenuto (es. una cache per app).
    let perChild: Bool
    let category: CleanupCategory
    let risk: Risk
    let reason: String
    var actionable: Bool = true
    var hint: String? = nil
    /// Motivazioni/suggerimenti specifici per alcuni figli (solo con `perChild`).
    var childOverrides: [String: (reason: String, hint: String?)] = [:]

    static var all: [KnownLocation] { [
        KnownLocation(
            relativePath: "Library/Caches", perChild: true, category: .caches, risk: .safe,
            reason: tr("App cache: recreated automatically when needed", "Cache dell'app: viene ricreata automaticamente quando serve"),
            childOverrides: [
                "Homebrew": (tr("Packages downloaded by Homebrew", "Pacchetti scaricati da Homebrew"), "brew cleanup --prune=all"),
                "pip": (tr("pip Python package cache", "Cache dei pacchetti Python di pip"), "pip cache purge"),
                "Yarn": (tr("Yarn package cache", "Cache dei pacchetti di Yarn"), "yarn cache clean"),
                "CocoaPods": (tr("CocoaPods cache", "Cache di CocoaPods"), "pod cache clean --all"),
            ]
        ),
        KnownLocation(
            relativePath: "Library/Logs", perChild: false, category: .logs, risk: .safe,
            reason: tr("Application logs and crash reports", "File di log delle applicazioni e report dei crash")
        ),
        KnownLocation(
            relativePath: ".Trash", perChild: false, category: .trash, risk: .safe,
            reason: tr("Files already in the Trash that still take up space", "File già nel Cestino che occupano ancora spazio"),
            actionable: false, hint: tr("Empty the Trash from the Finder (⌘⇧⌫)", "Svuota il Cestino dal Finder (⌘⇧⌫)")
        ),
        KnownLocation(
            relativePath: "Library/Developer/Xcode/DerivedData", perChild: false, category: .developer,
            risk: .safe, reason: tr("Xcode intermediate builds, regenerated on the next build", "Build intermedie di Xcode, rigenerate alla prossima compilazione")
        ),
        KnownLocation(
            relativePath: "Library/Developer/Xcode/Archives", perChild: true, category: .developer,
            risk: .review,
            reason: tr("Xcode archive: only needed to symbolicate crashes of shipped versions", "Archivio di Xcode: serve solo per simbolicare i crash delle versioni distribuite")
        ),
        KnownLocation(
            relativePath: "Library/Developer/Xcode/iOS DeviceSupport", perChild: true, category: .developer,
            risk: .safe, reason: tr("Debug symbols for an iOS version; downloaded again when the device is connected", "Simboli di debug di una versione iOS; si riscaricano collegando il dispositivo")
        ),
        KnownLocation(
            relativePath: "Library/Developer/Xcode/watchOS DeviceSupport", perChild: true,
            category: .developer, risk: .safe,
            reason: tr("Debug symbols for a watchOS version; downloaded again when the device is connected", "Simboli di debug di una versione watchOS; si riscaricano collegando il dispositivo")
        ),
        KnownLocation(
            relativePath: "Library/Developer/CoreSimulator/Caches", perChild: false, category: .developer,
            risk: .safe, reason: tr("Xcode simulator caches", "Cache dei simulatori di Xcode")
        ),
        KnownLocation(
            relativePath: "Library/Developer/CoreSimulator/Devices", perChild: false, category: .developer,
            risk: .caution, reason: tr("Xcode simulators and their data", "Simulatori di Xcode e i loro dati"),
            actionable: false, hint: "xcrun simctl delete unavailable"
        ),
        KnownLocation(
            relativePath: ".npm/_cacache", perChild: false, category: .developer, risk: .safe,
            reason: tr("npm package cache", "Cache dei pacchetti npm"), hint: "npm cache clean --force"
        ),
        KnownLocation(
            relativePath: ".cache", perChild: true, category: .developer, risk: .review,
            reason: tr("Cache of a command-line tool (models, packages, ...)", "Cache di uno strumento da riga di comando (modelli, pacchetti, ...)")
        ),
        KnownLocation(
            relativePath: ".gradle/caches", perChild: false, category: .developer, risk: .safe,
            reason: tr("Gradle cache: dependencies and builds are downloaded again when needed", "Cache di Gradle: dipendenze e build riscaricate quando servono")
        ),
        KnownLocation(
            relativePath: ".cargo/registry", perChild: false, category: .developer, risk: .review,
            reason: tr("Downloaded Rust crates; Cargo fetches them again when needed", "Crate Rust scaricati; Cargo li riscarica quando servono")
        ),
        KnownLocation(
            relativePath: "go/pkg/mod", perChild: false, category: .developer, risk: .review,
            reason: tr("Go module cache", "Cache dei moduli Go"), actionable: false, hint: "go clean -modcache"
        ),
        KnownLocation(
            relativePath: "Library/Containers/com.docker.docker", perChild: false, category: .developer,
            risk: .caution, reason: tr("Docker images, containers and volumes", "Immagini, container e volumi di Docker"),
            actionable: false, hint: "docker system prune -a"
        ),
        KnownLocation(
            relativePath: "Library/Application Support/MobileSync/Backup", perChild: true,
            category: .iosBackups, risk: .caution,
            reason: tr("Local iPhone/iPad backup: delete it only if you have a newer one or an iCloud backup", "Backup locale di un iPhone/iPad: eliminalo solo se hai un backup più recente o su iCloud")
        ),
        KnownLocation(
            relativePath: "Library/Containers/com.apple.mail/Data/Library/Mail Downloads", perChild: false,
            category: .messages, risk: .review, reason: tr("Mail attachments opened in the past (temporary copies)", "Allegati di Mail aperti in passato (copie temporanee)")
        ),
        KnownLocation(
            relativePath: "Library/Mail", perChild: false, category: .messages, risk: .caution,
            reason: tr("Mail message store", "Archivio della posta di Mail"),
            actionable: false, hint: tr("Delete old messages or attachments from within Mail", "Elimina vecchi messaggi o allegati direttamente da Mail")
        ),
        KnownLocation(
            relativePath: "Library/Messages/Attachments", perChild: false, category: .messages,
            risk: .caution, reason: tr("Messages attachments", "Allegati di Messaggi"),
            actionable: false, hint: tr("System Settings › General › Storage › Messages", "Impostazioni di Sistema › Generali › Spazio › Messaggi")
        ),
    ] }

    /// Percorsi che la scansione generale non deve attraversare: sono già coperti dalle regole
    /// sopra, sono gestiti da iCloud/servizi cloud, o contengono dati di app da non toccare.
    static let walkExclusions: [String] = all.map(\.relativePath) + [
        "Library/Caches",
        "Library/Logs",
        "Library/Developer",
        "Library/Mobile Documents",
        "Library/CloudStorage",
        "Library/Containers",
        "Library/Group Containers",
        "Library/Mail",
        "Library/Messages",
        "Library/Metadata",
        "Library/Biome",
        "Library/Application Support/MobileSync",
        ".Trash",
        ".npm",
        ".gradle",
        ".cargo",
        "go/pkg",
    ]

    func findings(root: URL, options: ScanOptions, errors: ErrorCollector) -> [Finding] {
        let base = root.appendingPathComponent(relativePath)
        guard FileStats.exists(base) else { return [] }

        if !perChild {
            let size = FileStats.allocatedSize(of: base, errors: errors)
            guard size >= options.minFindingSize else { return [] }
            return [Finding(path: base.path, size: size, category: category, risk: risk,
                            reason: reason, actionable: actionable, hint: hint)]
        }

        guard let children = try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: nil, options: []
        ) else {
            errors.record(base)
            return []
        }
        return children.compactMap { child in
            let size = FileStats.allocatedSize(of: child, errors: errors)
            guard size >= options.minFindingSize else { return nil }
            let override = childOverrides[child.lastPathComponent]
            return Finding(
                path: child.path, size: size, category: category, risk: risk,
                reason: override?.reason ?? reason, actionable: actionable,
                hint: override?.hint ?? hint, lastUsed: FileStats.lastUsedDate(child)
            )
        }
    }
}
