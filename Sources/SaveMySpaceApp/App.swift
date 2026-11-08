// SPDX-FileCopyrightText: 2026 homecla
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SaveMySpaceCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Necessario quando l'app è avviata come semplice eseguibile (swift run / smspace gui).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct SaveMySpaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel()

    var body: some Scene {
        WindowGroup("Save My Space") {
            ContentView()
                .environment(model)
                // Ricostruisce l'interfaccia quando cambia la lingua.
                .id(model.language)
                .frame(minWidth: 860, minHeight: 520)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button(tr("Analyze", "Analizza")) { model.scan() }
                    .keyboardShortcut("r")
                    .disabled(model.isBusy)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .id(model.language)
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Picker(tr("Language", "Lingua"), selection: $model.languagePreference) {
                Text(tr("Automatic", "Automatica")).tag(Language?.none)
                ForEach(Language.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
            }
            LabeledContent(tr("Large files over", "File grandi oltre")) {
                Stepper(value: $model.largeSizeGB, in: 0.1...50, step: 0.1) {
                    Text(String(format: "%.1f GB", model.largeSizeGB))
                }
            }
            LabeledContent(tr("Unused for", "Inutilizzati da")) {
                Stepper(value: $model.olderThanDays, in: 7...3650, step: 30) {
                    Text(tr("\(model.olderThanDays) days", "\(model.olderThanDays) giorni"))
                }
            }
            Toggle(tr("Look for duplicate files", "Cerca file duplicati"), isOn: $model.findDuplicates)
        }
        .padding()
        .frame(width: 400)
    }
}
