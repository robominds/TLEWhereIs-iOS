import SwiftUI
import TLEWhereIsCore

struct TrackingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if let satellite = model.state.current {
                    List {
                        Section(satellite.name) {
                            LabeledContent("NORAD ID", value: "\(satellite.noradID)")
                            if let position = model.currentPosition {
                                LabeledContent("Latitude", value: degrees(position.latitudeDeg))
                                LabeledContent("Longitude", value: degrees(position.longitudeDeg))
                                LabeledContent("Altitude", value: kilometers(position.altitudeKm))
                                LabeledContent("Speed", value: String(format: "%.3f km/s", position.speedKmS))
                            } else {
                                Text("Computing position…").foregroundStyle(.secondary)
                            }
                        }

                        Section("Relative to you") {
                            if let look = model.currentLookAngle {
                                LabeledContent("Elevation", value: degrees(look.elevationDeg))
                                LabeledContent("Azimuth", value: degrees(look.azimuthDeg))
                                LabeledContent("Range", value: kilometers(look.rangeKm))
                                if look.elevationDeg >= model.state.settings.elevationThresholdDeg {
                                    Label("Above your threshold now", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            } else {
                                Text(
                                    model.observer == nil
                                        ? "Set your location in Settings to see elevation and azimuth."
                                        : "Computing…"
                                )
                                .foregroundStyle(.secondary)
                            }
                        }

                        Section("Next Closest Approach") {
                            if let approach = model.nextClosestApproach {
                                LabeledContent("Time", value: approach.time.formatted(date: .omitted, time: .standard))
                                LabeledContent("When", value: approach.time.formatted(.relative(presentation: .named)))
                                LabeledContent("Elevation", value: degrees(approach.lookAngle.elevationDeg))
                                LabeledContent("Azimuth", value: degrees(approach.lookAngle.azimuthDeg))
                                LabeledContent("Range", value: kilometers(approach.lookAngle.rangeKm))
                                if approach.lookAngle.elevationDeg < 0 {
                                    Text("Below the horizon — won't be visible from here.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text(
                                    model.observer == nil
                                        ? "Set your location in Settings to predict the next closest approach."
                                        : "Computing…"
                                )
                                .foregroundStyle(.secondary)
                            }
                        }

                        if let message = model.errorMessage {
                            Section {
                                Label(message, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Satellite Tracked",
                        systemImage: "airplane.circle",
                        description: Text("Search for a satellite to start tracking it.")
                    )
                }
            }
            .navigationTitle("TLEWhereIs")
            .onAppear { model.onAppear() }
            .onDisappear { model.onDisappear() }
        }
    }

    private func degrees(_ value: Double) -> String {
        String(format: "%.4f°", value)
    }

    private func kilometers(_ value: Double) -> String {
        String(format: "%.2f km", value)
    }
}

#Preview {
    TrackingView()
        .environment(AppModel())
}
