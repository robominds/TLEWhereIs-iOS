import SwiftUI
import TLEWhereIsCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var manualLatText = ""
    @State private var manualLonText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Notifications") {
                    Toggle(
                        "Notify when overhead",
                        isOn: Binding(
                            get: { model.state.settings.notificationsEnabled },
                            set: { newValue in
                                if newValue {
                                    Task {
                                        let granted = await model.requestNotificationAuthorization()
                                        model.updateSettings { $0.notificationsEnabled = granted }
                                    }
                                } else {
                                    model.updateSettings { $0.notificationsEnabled = false }
                                }
                            }
                        )
                    )
                    VStack(alignment: .leading) {
                        Text("Elevation threshold: \(Int(model.state.settings.elevationThresholdDeg))°")
                        Slider(
                            value: Binding(
                                get: { model.state.settings.elevationThresholdDeg },
                                set: { newValue in model.updateSettings { $0.elevationThresholdDeg = newValue } }
                            ),
                            in: 0...90,
                            step: 1
                        )
                    }
                }

                Section("Location") {
                    Picker(
                        "Source",
                        selection: Binding(
                            get: { model.state.settings.locationMode },
                            set: { newValue in
                                model.updateSettings { $0.locationMode = newValue }
                                if newValue == .gps { model.locationManager.requestAuthorization() }
                            }
                        )
                    ) {
                        Text("Device GPS").tag(Settings.LocationMode.gps)
                        Text("Manual").tag(Settings.LocationMode.manual)
                    }
                    .pickerStyle(.segmented)

                    if model.state.settings.locationMode == .manual {
                        TextField("Latitude", text: $manualLatText)
                            .keyboardType(.numbersAndPunctuation)
                        TextField("Longitude", text: $manualLonText)
                            .keyboardType(.numbersAndPunctuation)
                        Button("Save Location") {
                            guard let lat = Double(manualLatText), let lon = Double(manualLonText) else { return }
                            model.updateSettings { $0.manualObserver = Observer(latitude: lat, longitude: lon) }
                        }
                    } else if model.locationManager.authorizationState == .denied {
                        Label(
                            "Location access denied — enable it in iOS Settings or switch to Manual.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                if let manual = model.state.settings.manualObserver {
                    manualLatText = String(manual.latitude)
                    manualLonText = String(manual.longitude)
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppModel())
}
