import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: PassStore
    @ObservedObject private var settings = SettingsStore.shared
    @State private var showSettings = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            passesTab
                .tabItem { Label("Passes", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(0)
            GuideListView()
                .tabItem { Label("Guide", systemImage: "book.fill") }
                .tag(1)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear {
            if settings.isConfigured, store.passes.isEmpty {
                store.refresh()
            }
        }
    }

    // MARK: - Passes tab

    private var passesTab: some View {
        NavigationStack {
            Group {
                switch store.phase {
                case .idle:
                    idleView
                case .loading:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Crunching orbits…")
                            .foregroundStyle(.secondary)
                    }
                case .failed:
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundStyle(Brand.gold)
                        Text(store.errorMessage ?? "Something went wrong.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Try again") { store.refresh() }
                            .buttonStyle(.borderedProminent)
                            .tint(Brand.navy)
                        if !settings.isConfigured {
                            Button("Open Settings") { showSettings = true }
                        }
                    }
                    .padding()
                case .loaded:
                    if store.passes.isEmpty {
                        VStack(spacing: 16) {
                            Text("No passes above \(Int(settings.minElFilter))° in the next \(Int(settings.windowHours)) hours.")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                            Button("Refresh") { store.refresh() }
                                .buttonStyle(.bordered)
                        }
                        .padding()
                    } else {
                        passList
                    }
                }
            }
            .navigationTitle("SatPass")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { store.refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh passes")
                    .disabled(!settings.isConfigured)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .refreshable { store.refresh() }
        }
    }

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 84))
                .foregroundStyle(Brand.navy, Brand.gold)
            Text("Passes over Tomball, coming right up.")
                .font(.title2)
                .multilineTextAlignment(.center)
            Text("Add your Worker URL in Settings, then refresh to compute the next \(Int(settings.windowHours)) hours of ISS and amateur-satellite passes.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Settings") { showSettings = true }
                .buttonStyle(.borderedProminent)
                .tint(Brand.navy)
            Spacer()
        }
        .padding()
    }

    private var passList: some View {
        List {
            if let next = store.nextPass {
                Section { nextPassCard(next) }
            }
            ForEach(dayGroups, id: \.day) { group in
                Section(header: Text(group.day.passDayString)) {
                    ForEach(group.passes) { pass in
                        NavigationLink(destination: PassDetailView(pass: pass)) {
                            passRow(pass)
                        }
                    }
                }
            }
            Section {
                tleFooter
            }
        }
        .listStyle(.insetGrouped)
    }

    private var dayGroups: [(day: Date, passes: [SatPass])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: store.passes) { cal.startOfDay(for: $0.aos) }
        return grouped.keys.sorted().map { day in
            (day, grouped[day]!.sorted { $0.aos < $1.aos })
        }
    }

    private func nextPassCard(_ pass: SatPass) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NEXT PASS")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if pass.isPrime {
                    primeBadge
                }
            }
            Text("\(pass.guide.shortName) · max \(Int(pass.maxEl.rounded()))°")
                .font(.title3.bold())
            Text("AOS \(pass.aos.passTimeString) (\(pass.aos.relativeString))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(pass.guide.alertLine)
                .font(.footnote)
                .foregroundStyle(Brand.navy)
        }
        .padding(.vertical, 4)
    }

    private func passRow(_ pass: SatPass) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(pass.guide.shortName)
                        .font(.headline)
                    if pass.isPrime {
                        primeBadge
                    }
                    if pass.inProgress {
                        Text("NOW")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
                Text("\(pass.aos.passTimeString) → \(pass.los.passTimeString)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(pass.aos.relativeString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(pass.maxEl.rounded()))°")
                    .font(.title3.bold())
                    .foregroundStyle(pass.isPrime ? Brand.gold : .primary)
                Text("\(Int(pass.durMin.rounded())) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var primeBadge: some View {
        Text("40°+")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Brand.gold.opacity(0.25))
            .foregroundStyle(Color(red: 0.55, green: 0.4, blue: 0.05))
            .clipShape(Capsule())
    }

    private var tleFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let age = store.tleAgeHours {
                HStack {
                    Image(systemName: store.tleStale ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(store.tleStale ? .orange : .green)
                    Text(tleAgeText(age))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let updated = store.lastUpdated {
                Text("Passes computed \(updated.relativeString)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("SGP4 via satellite.js on-device · validated against the satpass CLI")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func tleAgeText(_ ageHours: Double) -> String {
        if store.tleStale {
            return String(format: "TLEs are %.1f h old (stale) — Worker unreachable, showing cached data", ageHours)
        }
        return String(format: "TLEs %.1f h old (refreshed every 12 h)", ageHours)
    }
}
