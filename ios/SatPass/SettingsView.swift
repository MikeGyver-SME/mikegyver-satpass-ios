import SwiftUI
import UserNotifications

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @EnvironmentObject var store: PassStore
    @Environment(\.dismiss) private var dismiss

    @State private var testResult: String?
    @State private var testing = false
    @State private var pendingAlerts = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Worker") {
                    TextField("https://satpass-tle.<you>.workers.dev", text: $settings.workerURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    HStack {
                        Button(testing ? "Testing…" : "Test connection") {
                            testConnection()
                        }
                        .disabled(testing || !settings.isConfigured)
                        Spacer()
                        if let testResult {
                            Text(testResult)
                                .font(.footnote)
                                .foregroundStyle(testResult.hasPrefix("✓") ? .green : .red)
                        }
                    }
                    Text("The Worker serves cached CelesTrak TLEs. Passes are computed on your iPhone — nothing leaves the device except the TLE fetch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Ground station") {
                    HStack {
                        Text("Latitude")
                        Spacer()
                        TextField("29.9767", value: $settings.latitude, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                    HStack {
                        Text("Longitude")
                        Spacer()
                        TextField("-95.6169", value: $settings.longitude, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                    Text("Defaults to Tomball, TX. Change it if you take the FT-65R on the road.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Alerts") {
                    Toggle("10-minute heads-up", isOn: $settings.alertsEnabled)
                        .onChange(of: settings.alertsEnabled) { _, on in
                            if on {
                                Task { await enableAlerts() }
                            } else {
                                NotificationScheduler.clearAll()
                                pendingAlerts = 0
                            }
                        }
                    HStack {
                        Text("Alert threshold")
                        Spacer()
                        Stepper("\(Int(settings.alertThreshold))°", value: $settings.alertThreshold, in: 20...80, step: 5)
                    }
                    if settings.alertsEnabled {
                        HStack {
                            Text("Scheduled alerts")
                            Spacer()
                            Text("\(pendingAlerts)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Notifies 10 minutes before AOS for passes peaking at or above the threshold. Purely local — no push server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Display") {
                    HStack {
                        Text("Show passes above")
                        Spacer()
                        Stepper("\(Int(settings.minElFilter))°", value: $settings.minElFilter, in: 5...40, step: 5)
                    }
                    Picker("Window", selection: $settings.windowHours) {
                        Text("24 hours").tag(24.0)
                        Text("48 hours").tag(48.0)
                        Text("72 hours").tag(72.0)
                    }
                    .onChange(of: settings.minElFilter) { _, _ in store.refresh() }
                    .onChange(of: settings.windowHours) { _, _ in store.refresh() }
                }

                Section("Data") {
                    Button("Clear TLE cache", role: .destructive) {
                        TleStore.clearCache()
                        store.refresh()
                    }
                    .disabled(!settings.isConfigured)
                }

                Section("About") {
                    Text("MikeGyver SatPass predicts ISS and amateur-satellite passes with on-device SGP4 (satellite.js, MIT), validated against the satpass Go CLI. TLEs: CelesTrak, cached 12 h. Frequencies: AMSAT / work-sat.com via the CLI guide.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                pendingAlerts = await NotificationScheduler.pendingCount()
            }
        }
    }

    private func testConnection() {
        testing = true
        testResult = nil
        Task {
            do {
                let count = try await ApiClient.testConnection(baseURL: settings.baseURL)
                testResult = "✓ Connected — \(count) satellites"
            } catch {
                testResult = "✗ \(error.localizedDescription)"
            }
            testing = false
        }
    }

    private func enableAlerts() async {
        let status = await NotificationScheduler.authorizationStatus()
        if status == .notDetermined {
            let granted = await NotificationScheduler.requestPermission()
            if !granted {
                await MainActor.run { settings.alertsEnabled = false }
                return
            }
        } else if status == .denied {
            await MainActor.run { settings.alertsEnabled = false }
            return
        }
        await NotificationScheduler.refresh(passes: store.passes, threshold: settings.alertThreshold)
        pendingAlerts = await NotificationScheduler.pendingCount()
    }
}
