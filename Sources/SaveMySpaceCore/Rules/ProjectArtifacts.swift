import Foundation

/// Riconosce le cartelle rigenerabili dentro i progetti software (dipendenze, output di build).
enum ProjectArtifacts {
    struct Match {
        let reason: String
        let hint: String?
    }

    /// Nomi delle cartelle candidate, per un controllo veloce durante la scansione.
    static let candidateNames: Set<String> = [
        "node_modules", ".venv", "venv", "target", "build", ".build", "Pods", ".gradle", ".next",
    ]

    /// Restituisce una corrispondenza se `dir` è un artefatto riconosciuto del progetto che la contiene.
    static func match(_ dir: URL) -> Match? {
        let name = dir.lastPathComponent
        guard candidateNames.contains(name) else { return nil }
        let project = dir.deletingLastPathComponent()
        func has(_ file: String) -> Bool { FileStats.exists(project.appendingPathComponent(file)) }

        switch name {
        case "node_modules" where has("package.json"):
            return Match(reason: tr("Project npm dependencies", "Dipendenze npm del progetto"), hint: tr("npm install to recreate them", "npm install per ricrearle"))
        case ".next" where has("package.json"):
            return Match(reason: tr("Next.js build output", "Output di build di Next.js"), hint: nil)
        case ".venv", "venv":
            if FileStats.exists(dir.appendingPathComponent("pyvenv.cfg")) {
                return Match(reason: tr("Python virtual environment", "Ambiente virtuale Python"), hint: tr("recreate it with python -m venv", "ricrealo con python -m venv"))
            }
        case "target" where has("Cargo.toml"):
            return Match(reason: tr("Rust build output", "Output di build Rust"), hint: "cargo clean")
        case "target" where has("pom.xml"):
            return Match(reason: tr("Maven build output", "Output di build Maven"), hint: "mvn clean")
        case "build" where has("build.gradle") || has("build.gradle.kts") || has("settings.gradle"):
            return Match(reason: tr("Gradle build output", "Output di build Gradle"), hint: "gradle clean")
        case "build" where has("CMakeLists.txt"):
            return Match(reason: tr("CMake build output", "Output di build CMake"), hint: nil)
        case ".build" where has("Package.swift"):
            return Match(reason: tr("Swift Package Manager build output", "Output di build di Swift Package Manager"), hint: "swift package clean")
        case "Pods" where has("Podfile"):
            return Match(reason: tr("CocoaPods dependencies", "Dipendenze CocoaPods"), hint: tr("pod install to recreate them", "pod install per ricrearle"))
        case ".gradle" where has("build.gradle") || has("build.gradle.kts") || has("settings.gradle"):
            return Match(reason: tr("Project Gradle cache", "Cache Gradle del progetto"), hint: nil)
        default:
            break
        }
        return nil
    }

    /// Ultima attività del progetto: la modifica più recente fra la cartella del progetto
    /// e i suoi elementi diretti, esclusi gli artefatti stessi.
    static func lastActivity(ofProject project: URL) -> Date? {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        var dates: [Date] = []
        if let d = try? project.resourceValues(forKeys: Set(keys)).contentModificationDate {
            dates.append(d)
        }
        let children = (try? FileManager.default.contentsOfDirectory(
            at: project, includingPropertiesForKeys: keys, options: []
        )) ?? []
        for child in children where !candidateNames.contains(child.lastPathComponent) {
            if let d = try? child.resourceValues(forKeys: Set(keys)).contentModificationDate {
                dates.append(d)
            }
        }
        return dates.max()
    }
}
