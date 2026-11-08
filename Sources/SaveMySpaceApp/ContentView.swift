// SPDX-FileCopyrightText: 2026 homecla
// SPDX-License-Identifier: AGPL-3.0-or-later

import SaveMySpaceCore
import SwiftUI

/// Voce della sidebar: tutte le categorie (`nil`) o una specifica.
struct SidebarItem: Hashable {
    let category: CleanupCategory?
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    private var currentCategory: CleanupCategory? { model.sidebarCategory?.category }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.sidebarCategory) {
                Section(tr("Overview", "Riepilogo")) {
                    sidebarRow(nil, title: tr("All suggestions", "Tutti i suggerimenti"), symbol: "sparkles")
                }
                if !model.visibleCategories.isEmpty {
                    Section(tr("Categories", "Categorie")) {
                        ForEach(model.visibleCategories) { t in
                            sidebarRow(t.category, title: t.category.label, symbol: t.category.symbolName)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            detail
                .toolbar { toolbar }
        }
        .confirmationDialog(
            tr("Move \(model.selectedFindings.count) items (\(SizeFormatter.string(model.selectedSize))) to the Trash?",
               "Spostare nel Cestino \(model.selectedFindings.count) elementi (\(SizeFormatter.string(model.selectedSize)))?"),
            isPresented: $model.confirmingTrash
        ) {
            Button(tr("Move to Trash", "Sposta nel Cestino"), role: .destructive) { model.moveSelectionToTrash() }
            Button(tr("Cancel", "Annulla"), role: .cancel) {}
        } message: {
            let risky = model.selectedRiskyCount
            Text((risky > 0
                  ? tr("\(risky) of them are not \"safe\": check them before continuing. ",
                       "\(risky) di questi non sono \"sicuri\": controllali prima di continuare. ")
                  : "")
                 + tr("You can restore them from the Trash until you empty it (Report › Restore last cleanup).",
                      "Potrai ripristinarli dal Cestino finché non lo svuoti (Report › Ripristina ultima pulizia)."))
        }
    }

    private func sidebarRow(_ category: CleanupCategory?, title: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            if model.report != nil {
                Text(SizeFormatter.string(model.total(of: category)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .tag(SidebarItem(category: category))
    }

    @ViewBuilder
    private var detail: some View {
        if model.isBusy {
            VStack(spacing: 12) {
                ProgressView()
                Text(model.progressText).foregroundStyle(.secondary).monospacedDigit()
                if model.isScanning {
                    Button(tr("Cancel", "Annulla")) { model.cancelScan() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.report == nil {
            ContentUnavailableView {
                Label(tr("Analyze your home folder", "Analizza la tua home"), systemImage: "internaldrive")
            } description: {
                Text(tr("Save My Space looks for caches, large files, duplicates and other reclaimable space. "
                        + "Nothing is deleted without your confirmation.",
                     "Save My Space cerca cache, file grandi, duplicati e altro spazio recuperabile. "
                        + "Non viene cancellato nulla senza la tua conferma."))
            } actions: {
                Button(tr("Analyze", "Analizza")) { model.scan() }
                    .buttonStyle(.borderedProminent)
                if let message = model.lastMessage {
                    Text(message).foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(spacing: 0) {
                header
                Divider()
                let items = model.findings(in: currentCategory)
                if items.isEmpty {
                    ContentUnavailableView(tr("Nothing to clean here", "Niente da pulire qui"), systemImage: "checkmark.circle")
                } else {
                    List(items) { finding in
                        FindingRow(finding: finding)
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryBar
            if let message = model.lastMessage {
                messageBar(message)
            }
        }
    }

    private func messageBar(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                // Niente .textSelection/.fixedSize: con un testo su più righe sopra la List
                // mandano in tilt il layout e la finestra resta vuota (macOS 27).
                .frame(maxWidth: .infinity, alignment: .leading)
                .contextMenu {
                    Button(tr("Copy message", "Copia messaggio")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message, forType: .string)
                    }
                }
            Button(tr("Analyze again", "Analizza di nuovo")) { model.scan() }
                .controlSize(.small)
                .disabled(model.isBusy)
            Button {
                model.lastMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(tr("Dismiss", "Chiudi"))
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    private var summaryBar: some View {
        @Bindable var model = model
        return HStack(alignment: .firstTextBaseline, spacing: 24) {
            if model.report != nil {
                let items = model.findings(in: currentCategory)
                stat(tr("Flagged", "Segnalato"), SizeFormatter.string(items.reduce(0) { $0 + $1.size }))
                stat(tr("Safe", "Sicuro"), SizeFormatter.string(items.filter { $0.actionable && $0.risk == .safe }.reduce(0) { $0 + $1.size }))
                stat(tr("Selected", "Selezionato"), SizeFormatter.string(model.selectedSize))
            }
            Spacer()
            Picker(tr("Maximum risk", "Rischio massimo"), selection: $model.maxRisk) {
                ForEach(Risk.allCases, id: \.self) { Text($0.label.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
        }
        .padding()
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Button(tr("Export report…", "Esporta report…")) { model.exportReport(category: currentCategory) }
                    .disabled(model.report == nil)
                Button(tr("Show cleanup history", "Mostra storico delle pulizie")) { model.revealHistory() }
                Divider()
                Button(tr("Restore last cleanup…", "Ripristina ultima pulizia…")) { model.restoreLastClean() }
                    .disabled(model.isBusy)
            } label: {
                Label("Report", systemImage: "doc.text.magnifyingglass")
            }
            .help(tr("Export the suggestions or open the cleanup history", "Esporta i suggerimenti o apri lo storico delle pulizie"))

            Menu {
                Button(tr("Select safe", "Seleziona sicuri")) { model.selectAllSafe(in: currentCategory) }
                Button(tr("Select all shown", "Seleziona tutti quelli visibili")) {
                    model.selectAllVisible(in: currentCategory)
                }
                Divider()
                Button(tr("Deselect all", "Deseleziona tutto")) { model.deselectAll() }
                    .disabled(model.selection.isEmpty)
            } label: {
                Label(tr("Select", "Seleziona"),
                      systemImage: model.allVisibleSelected(in: currentCategory) ? "checkmark.circle.fill" : "checkmark.circle")
            } primaryAction: {
                model.toggleAllVisible(in: currentCategory)
            }
            .disabled(model.report == nil || model.isBusy)
            .help(tr("Click: select or deselect all shown items. Arrow: more options",
                     "Clic: seleziona o deseleziona tutti gli elementi visibili. Freccia: altre opzioni"))

            Button(role: .destructive) {
                model.confirmingTrash = true
            } label: {
                Label(tr("Move to Trash", "Sposta nel Cestino"), systemImage: "trash")
            }
            .disabled(model.selectedFindings.isEmpty || model.isBusy)

            Button {
                model.scan()
            } label: {
                Label(tr("Analyze", "Analizza"), systemImage: "arrow.clockwise")
            }
            .disabled(model.isBusy)
        }
    }
}
