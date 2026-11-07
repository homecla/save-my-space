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
                if let report = model.report {
                    Section(tr("Categories", "Categorie")) {
                        ForEach(report.categoryTotals) { t in
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
            Text(tr("You can restore them from the Trash until you empty it (Report › Restore last cleanup).",
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
        .tag(Optional(SidebarItem(category: category)))
    }

    @ViewBuilder
    private var detail: some View {
        if model.isScanning {
            VStack(spacing: 12) {
                ProgressView()
                Text(model.progressText).foregroundStyle(.secondary).monospacedDigit()
                Button(tr("Cancel", "Annulla")) { model.cancelScan() }
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
        .overlay(alignment: .bottomLeading) {
            if let message = model.lastMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 2)
            }
        }
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
                    .disabled(model.isScanning)
            } label: {
                Label("Report", systemImage: "doc.text.magnifyingglass")
            }
            .help(tr("Export the suggestions or open the cleanup history", "Esporta i suggerimenti o apri lo storico delle pulizie"))

            Button {
                model.selectAllSafe(in: currentCategory)
            } label: {
                Label(tr("Select safe", "Seleziona sicuri"), systemImage: "checkmark.circle")
            }
            .disabled(model.report == nil || model.isScanning)
            .help(tr("Select all items with \"safe\" risk", "Seleziona tutti gli elementi a rischio \"sicuro\""))

            Button(role: .destructive) {
                model.confirmingTrash = true
            } label: {
                Label(tr("Move to Trash", "Sposta nel Cestino"), systemImage: "trash")
            }
            .disabled(model.selectedFindings.isEmpty || model.isScanning)

            Button {
                model.scan()
            } label: {
                Label(tr("Analyze", "Analizza"), systemImage: "arrow.clockwise")
            }
            .disabled(model.isScanning)
        }
    }
}
