import MapKit
import SwiftUI
import TLEWhereIsCore

struct SatelliteMapView: View {
    @Environment(AppModel.self) private var model
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasCenteredCamera = false

    var body: some View {
        NavigationStack {
            Group {
                if model.state.current != nil {
                    // Without explicit bounds, Map's default maximum zoom-out
                    // distance stops well short of framing the whole globe.
                    // 30,000 km comfortably fits the entire Earth in view;
                    // 500m is a reasonable close-in limit.
                    Map(
                        position: $cameraPosition,
                        bounds: MapCameraBounds(minimumDistance: 500, maximumDistance: 30_000_000),
                        interactionModes: .all
                    ) {
                        if let subsolar = model.subsolarPoint {
                            MapPolygon(coordinates: Self.nightPolygonCoordinates(subsolar: subsolar))
                                .foregroundStyle(.black.opacity(0.28))

                            Annotation("Sun", coordinate: subsolar.coordinate) {
                                Image(systemName: "sun.max.fill")
                                    .foregroundStyle(.yellow)
                                    .shadow(radius: 1)
                            }
                        }

                        ForEach(Array(Self.splitAtAntimeridian(model.groundTrack.map(\.position.coordinate)).enumerated()), id: \.offset) { _, segment in
                            MapPolyline(coordinates: segment)
                                .stroke(.yellow, lineWidth: 2.5)
                        }

                        if let observer = model.observer {
                            Annotation("You", coordinate: observer.coordinate) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(.red)
                                    .background(Circle().fill(.white))
                            }
                        }

                        if let position = model.currentPosition {
                            Annotation(model.state.current?.name ?? "Satellite", coordinate: position.coordinate) {
                                Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                    .background(Circle().fill(.white))
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .onChange(of: model.currentPosition) { _, newValue in
                        guard !hasCenteredCamera, let newValue else { return }
                        hasCenteredCamera = true
                        cameraPosition = .region(
                            MKCoordinateRegion(
                                center: newValue.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 90, longitudeDelta: 120)
                            )
                        )
                    }
                } else {
                    ContentUnavailableView(
                        "No Satellite Tracked",
                        systemImage: "map",
                        description: Text("Search for a satellite to see it on the map.")
                    )
                }
            }
            .navigationTitle("Map")
        }
    }

    /// Splits a coordinate sequence wherever it crosses the antimeridian, so
    /// MapKit draws separate line segments instead of one line cutting
    /// straight across the map at the wraparound.
    static func splitAtAntimeridian(_ points: [CLLocationCoordinate2D]) -> [[CLLocationCoordinate2D]] {
        guard !points.isEmpty else { return [] }
        var segments: [[CLLocationCoordinate2D]] = [[points[0]]]
        for point in points.dropFirst() {
            if let last = segments[segments.count - 1].last, abs(point.longitude - last.longitude) > 180 {
                segments.append([])
            }
            segments[segments.count - 1].append(point)
        }
        return segments.filter { $0.count > 1 }
    }

    /// The night-side region as a single polygon: the terminator curve
    /// (the great circle 90° from the subsolar point) across the full
    /// longitude range, closed via the pole that's in darkness.
    static func nightPolygonCoordinates(subsolar: SubsolarPoint) -> [CLLocationCoordinate2D] {
        let darkPoleLat: Double = subsolar.latitudeDeg >= 0 ? -90 : 90
        var coordinates: [CLLocationCoordinate2D] = [
            CLLocationCoordinate2D(latitude: darkPoleLat, longitude: -180),
        ]
        for longitude in stride(from: -180.0, through: 180.0, by: 4.0) {
            let latitude = SolarPosition.terminatorLatitudeDeg(atLongitudeDeg: longitude, subsolar: subsolar)
            coordinates.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
        coordinates.append(CLLocationCoordinate2D(latitude: darkPoleLat, longitude: 180))
        return coordinates
    }
}

private extension SatellitePosition {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitudeDeg, longitude: longitudeDeg)
    }
}

private extension SubsolarPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitudeDeg, longitude: longitudeDeg)
    }
}

private extension Observer {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

#Preview {
    SatelliteMapView()
        .environment(AppModel())
}
