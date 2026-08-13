import Foundation

/// A predicted window during which a satellite's elevation stays at or above
/// a threshold, as seen from a fixed observer.
public struct SatellitePass: Sendable, Equatable {
    public let riseTime: Date
    public let setTime: Date
    public let maxElevationDeg: Double

    public init(riseTime: Date, setTime: Date, maxElevationDeg: Double) {
        self.riseTime = riseTime
        self.setTime = setTime
        self.maxElevationDeg = maxElevationDeg
    }
}

public enum PassPredictor {
    /// Scans `[start, start+duration)` at `stepSeconds` resolution, sampling
    /// `elevationDeg` at each step, and returns the intervals during which
    /// elevation stays continuously at or above `thresholdDeg`. Rise/set
    /// times are reported at sample resolution — good enough for scheduling
    /// a notification a little ahead of a pass, not survey-grade.
    ///
    /// Pure function of the sampling closure, so pass prediction logic can
    /// be unit tested against a synthetic elevation time series without a
    /// real TLE or propagator.
    public static func findPasses(
        from start: Date,
        duration: TimeInterval,
        stepSeconds: TimeInterval,
        thresholdDeg: Double,
        maxPasses: Int = 20,
        elevationDeg: (Date) throws -> Double
    ) rethrows -> [SatellitePass] {
        var passes: [SatellitePass] = []
        var riseTime: Date?
        var maxElev = -Double.infinity
        let end = start.addingTimeInterval(duration)
        var t = start

        while t < end, passes.count < maxPasses {
            let elev = try elevationDeg(t)
            if elev >= thresholdDeg {
                if riseTime == nil {
                    riseTime = t
                    maxElev = elev
                } else {
                    maxElev = max(maxElev, elev)
                }
            } else if let rise = riseTime {
                passes.append(SatellitePass(riseTime: rise, setTime: t, maxElevationDeg: maxElev))
                riseTime = nil
                maxElev = -Double.infinity
            }
            t = t.addingTimeInterval(stepSeconds)
        }
        if let rise = riseTime, passes.count < maxPasses {
            passes.append(SatellitePass(riseTime: rise, setTime: end, maxElevationDeg: maxElev))
        }
        return passes
    }

    /// Convenience overload wired to a real propagator/observer pair.
    public static func predictPasses(
        propagator: Propagator,
        observer: Observer,
        thresholdDeg: Double,
        from start: Date,
        duration: TimeInterval,
        stepSeconds: TimeInterval = 30,
        maxPasses: Int = 20
    ) throws -> [SatellitePass] {
        try findPasses(
            from: start, duration: duration, stepSeconds: stepSeconds,
            thresholdDeg: thresholdDeg, maxPasses: maxPasses
        ) { date in
            try propagator.lookAngle(from: observer, at: date).elevationDeg
        }
    }
}
