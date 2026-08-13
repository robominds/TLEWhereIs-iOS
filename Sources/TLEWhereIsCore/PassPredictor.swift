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

    /// Scans `[start, start+duration)` at `coarseStepSeconds` resolution for
    /// the first local minimum of range (the moment of closest physical
    /// approach, not gated on being above the horizon — a pass that never
    /// clears the horizon still has one), then refines around that bracket
    /// at `refinedStepSeconds` resolution. Returns nil if no local minimum
    /// falls within the window (range only rises or only falls throughout —
    /// shouldn't happen given a window longer than one orbital period).
    ///
    /// Pure function of the sampling closure, mirroring `findPasses`, so it
    /// can be unit tested against a synthetic range time series.
    public static func findNextClosestApproach(
        from start: Date,
        duration: TimeInterval,
        coarseStepSeconds: TimeInterval,
        refinedStepSeconds: TimeInterval,
        sample: (Date) throws -> LookAngle
    ) rethrows -> (time: Date, lookAngle: LookAngle)? {
        let end = start.addingTimeInterval(duration)
        var t0 = start
        var r0 = try sample(t0)
        var t1 = t0.addingTimeInterval(coarseStepSeconds)
        guard t1 < end else { return nil }
        var r1 = try sample(t1)

        while t1 < end {
            let t2 = t1.addingTimeInterval(coarseStepSeconds)
            guard t2 < end else { break }
            let r2 = try sample(t2)

            if r1.rangeKm <= r0.rangeKm, r1.rangeKm <= r2.rangeKm {
                var bestTime = t1
                var best = r1
                var t = t0
                while t <= t2 {
                    let candidate = try sample(t)
                    if candidate.rangeKm < best.rangeKm {
                        best = candidate
                        bestTime = t
                    }
                    t = t.addingTimeInterval(refinedStepSeconds)
                }
                return (bestTime, best)
            }

            t0 = t1; r0 = r1
            t1 = t2; r1 = r2
        }
        return nil
    }

    /// Convenience overload wired to a real propagator/observer pair.
    /// Defaults cover a full day at 1-minute coarse resolution — comfortably
    /// more than one orbital period for anything in LEO — refined to 2
    /// seconds around the bracket.
    public static func nextClosestApproach(
        propagator: Propagator,
        observer: Observer,
        from start: Date,
        duration: TimeInterval = 24 * 3600,
        coarseStepSeconds: TimeInterval = 60,
        refinedStepSeconds: TimeInterval = 2
    ) throws -> (time: Date, lookAngle: LookAngle)? {
        try findNextClosestApproach(
            from: start, duration: duration,
            coarseStepSeconds: coarseStepSeconds, refinedStepSeconds: refinedStepSeconds
        ) { date in
            try propagator.lookAngle(from: observer, at: date)
        }
    }
}
