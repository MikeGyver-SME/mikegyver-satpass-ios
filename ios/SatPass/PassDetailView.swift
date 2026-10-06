import SwiftUI

/// Per-pass detail: times, geometry, and the FT-65R cheat sheet.
struct PassDetailView: View {
    let pass: SatPass

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(pass.guide.fullName)
                            .font(.title2.bold())
                        Spacer()
                        if pass.isPrime {
                            Text("PRIME 40°+")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Brand.gold)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    Text(pass.guide.mode)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Pass") {
                statRow("AOS (rise)", "\(pass.aos.passTimeString) · \(Int(pass.azAos.rounded()))°")
                statRow("TCA (max \(Int(pass.maxEl.rounded()))°)", pass.tca.passTimeString)
                statRow("LOS (set)", "\(pass.los.passTimeString) · \(Int(pass.azLos.rounded()))°")
                statRow("Duration", "\(Int(pass.durMin.rounded())) min")
                if pass.inProgress {
                    statRow("Status", "In progress now")
                } else {
                    statRow("Countdown", pass.aos.relativeString)
                }
            }

            if pass.guide.needsSSB {
                Section {
                    Label {
                        Text("Linear SSB bird — the FM-only FT-65R can't work this one. Catch the downlink on VibeSDR.")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("FT-65R cheat sheet") {
                ForEach(pass.guide.ft65r, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "radio.fill")
                            .font(.caption)
                            .foregroundStyle(Brand.navy)
                            .padding(.top, 3)
                        Text(tip)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Frequency guide") {
                guideRow("Uplink", pass.guide.uplink)
                guideRow("Downlink", pass.guide.downlink)
                if !pass.guide.notes.isEmpty {
                    guideRow("Notes", pass.guide.notes)
                }
            }

            Section {
                Text("Frequencies from the satpass CLI guide (verified against AMSAT, Sep 2026). Verify a bird is active at amsat.org/status before a sked — birds go quiet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(pass.guide.shortName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func guideRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}

/// The static frequency guide for all five birds (no pass needed).
struct GuideListView: View {
    var body: some View {
        NavigationStack {
            List(SatGuide.all) { guide in
                NavigationLink(destination: GuideDetailView(guide: guide)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(guide.fullName)
                            .font(.headline)
                        Text(guide.mode)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(guide.alertLine)
                            .font(.caption)
                            .foregroundStyle(Brand.navy)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Frequency Guide")
        }
    }
}

struct GuideDetailView: View {
    let guide: SatGuide

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(guide.fullName)
                        .font(.title2.bold())
                    Text(guide.mode)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            if guide.needsSSB {
                Section {
                    Label {
                        Text("Linear SSB bird — the FM-only FT-65R can't work this one. Catch the downlink on VibeSDR.")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            Section("FT-65R cheat sheet") {
                ForEach(guide.ft65r, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "radio.fill")
                            .font(.caption)
                            .foregroundStyle(Brand.navy)
                            .padding(.top, 3)
                        Text(tip)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 2)
                }
            }
            Section("Frequencies") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Uplink").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(guide.uplink).font(.subheadline)
                }.padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Downlink").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(guide.downlink).font(.subheadline)
                }.padding(.vertical, 2)
                if !guide.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes").font(.caption.bold()).foregroundStyle(.secondary)
                        Text(guide.notes).font(.subheadline)
                    }.padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(guide.shortName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
