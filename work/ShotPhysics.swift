import Foundation

/// A shot describes motion only. The rim crossing decides whether it scores.
struct ShotFlight {
    var time: Double = 0
    let duration: Double
    let points: Int

    private let startGround: CGPoint
    private let endGround: CGPoint
    private let startHeight: CGFloat
    private let targetHeight: CGFloat
    private let initialVerticalVelocity: CGFloat
    private let gravity: CGFloat
    private static let brakingFraction = 0.30
    private static let maximumHorizontalSpeed: CGFloat = 1100

    init(startGround: CGPoint, startHeight: CGFloat, endGround: CGPoint,
         distance: CGFloat, points: Int, targetHeight: CGFloat = Hoop.height) {
        self.startGround = startGround
        self.endGround = endGround
        self.startHeight = startHeight
        self.targetHeight = targetHeight
        self.points = points

        let actualDistance = hypot(endGround.x - startGround.x, endGround.y - startGround.y)
        let travelDistance = max(actualDistance, max(0, distance))
        let preferredDuration = min(1.7, max(0.5, 0.55 + Double(travelDistance) / 1150))
        // Braking raises the initial speed. Lengthen exceptional off-court shots
        // instead of allowing their speed to grow without a bound.
        let speedLimitedDuration = Double(actualDistance / Self.maximumHorizontalSpeed)
            / (1 - Self.brakingFraction / 2)
        duration = max(preferredDuration, speedLimitedDuration)

        let apex = max(startHeight + 100, targetHeight + 125)
        let risingHeight = sqrt(apex - startHeight)
        let fallingHeight = sqrt(apex - targetHeight)
        let totalHeight = risingHeight + fallingHeight
        let flightDuration = CGFloat(duration)
        gravity = 2 * totalHeight * totalHeight / (flightDuration * flightDuration)
        initialVerticalVelocity = 2 * risingHeight * totalHeight / flightDuration
    }

    func sample(at time: Double) -> LooseBall {
        let t = CGFloat(max(0, min(duration, time)))
        let flightDuration = CGFloat(duration)
        let brakingTime = flightDuration * CGFloat(Self.brakingFraction)
        let brakingStart = flightDuration - brakingTime
        let normalizedTravelTime = flightDuration - brakingTime / 2
        let brakingElapsed = max(0, t - brakingStart)
        let progress = min(1, (t - brakingElapsed * brakingElapsed / (2 * brakingTime))
            / normalizedTravelTime)
        let speedScale = max(0, 1 - brakingElapsed / brakingTime) / normalizedTravelTime
        let dx = endGround.x - startGround.x
        let dy = endGround.y - startGround.y
        let ground = t == flightDuration ? endGround : CGPoint(
            x: startGround.x + dx * progress,
            y: startGround.y + dy * progress)
        let height = t == flightDuration ? targetHeight
            : startHeight + initialVerticalVelocity * t - gravity * t * t / 2
        return LooseBall(
            ground: ground,
            velocity: CGPoint(x: dx * speedScale, y: dy * speedScale),
            height: height,
            verticalVelocity: initialVerticalVelocity - gravity * t)
    }

    /// Returns the hoop index only for a downward passage through its opening.
    static func crossingHoop(from previous: LooseBall, to next: LooseBall) -> Int? {
        guard previous.height.isFinite, next.height.isFinite, next.verticalVelocity<0,
              previous.height > Hoop.height, next.height <= Hoop.height else { return nil }
        let fraction = (previous.height - Hoop.height) / (previous.height - next.height)
        let crossing = CGPoint(
            x: previous.ground.x + (next.ground.x - previous.ground.x) * fraction,
            y: previous.ground.y + (next.ground.y - previous.ground.y) * fraction)
        guard crossing.x.isFinite, crossing.y.isFinite else { return nil }
        let insideX = Hoop.radiusX - Basketball.radius - 3
        let insideY = Hoop.radiusY - (Basketball.radius + 3) / Hoop.groundDepthScale
        guard insideX > 0, insideY > 0 else { return nil }
        for (index, hoop) in Hoop.all.enumerated() {
            let x = (crossing.x - hoop.center.x) / insideX
            let y = (crossing.y - hoop.center.y) / insideY
            if x * x + y * y < 1 { return index }
        }
        return nil
    }
}

/// Foundation-only checks, also callable by the app's internal test runner.
func runShotPhysicsTests() {
    for (index, hoop) in Hoop.all.enumerated() {
        let direction: CGFloat = index == 0 ? -1 : 1
        for distance: CGFloat in [180, 550, 1250] {
            let start = CGPoint(x: hoop.center.x - direction * distance, y: hoop.center.y + 100)
            let flight = ShotFlight(startGround: start, startHeight: 82,
                endGround: hoop.center, distance: distance, points: distance > 500 ? 3 : 2)
            precondition(flight.duration >= 0.5 && flight.duration <= 1.7,
                "Court shots must have a distance-scaled flight duration")
            let first = flight.sample(at: 0)
            let last = flight.sample(at: flight.duration)
            precondition(first.ground.x == start.x && first.ground.y == start.y && first.height == 82)
            precondition(last.ground.x == hoop.center.x && last.ground.y == hoop.center.y
                && last.height == Hoop.height)
            precondition(last.verticalVelocity < 0, "Shots arrive at the rim while falling")
            precondition(hypot(last.velocity.x, last.velocity.y) < 0.0001,
                "Rim arrival brakes continuously into the loose-ball state")

            var previous = first
            var maximumHeight = first.height
            var crossing: Int?
            for step in 1...480 {
                let next = flight.sample(at: flight.duration * Double(step) / 480)
                maximumHeight = max(maximumHeight, next.height)
                let shotDX = hoop.center.x - start.x
                let shotDY = hoop.center.y - start.y
                let travelDX = next.ground.x - start.x
                let travelDY = next.ground.y - start.y
                precondition(abs(shotDX * travelDY - shotDY * travelDX) < 0.001,
                    "Shots retain their chosen straight ground direction")
                precondition(hypot(next.velocity.x, next.velocity.y) <= 1100.001,
                    "Long shots obey the horizontal speed limit")
                var collisionProbe = next
                precondition(!collisionProbe.collideWithHoops(),
                    "A centered shot must clear the rim during its approach")
                if let found = ShotFlight.crossingHoop(from: previous, to: next) { crossing = found }
                previous = next
            }
            precondition(maximumHeight >= Hoop.height + 100)
            precondition(crossing == index, "Centered descending shots cross the target hoop")
            var loose = last
            loose.step(dt: 0.08)
            precondition(loose.height < Hoop.height && loose.rimHits == 0 && loose.boardHits == 0,
                "The last sample must continue through the real rim without a velocity reset")
        }

        let above = LooseBall(ground: hoop.center, velocity: CGPoint(x: 0, y: 0),
            height: Hoop.height + 70, verticalVelocity: -600)
        let below = LooseBall(ground: hoop.center, velocity: CGPoint(x: 0, y: 0),
            height: Hoop.height - 70, verticalVelocity: -600)
        precondition(ShotFlight.crossingHoop(from: above, to: below) == index,
            "A large time step still detects a downward rim crossing")
        precondition(ShotFlight.crossingHoop(from: below, to: above) == nil,
            "An upward pass cannot score")
        var outsideAbove = above
        var outsideBelow = below
        outsideAbove.ground.x += Hoop.radiusX - Basketball.radius - 2
        outsideBelow.ground = outsideAbove.ground
        precondition(ShotFlight.crossingHoop(from: outsideAbove, to: outsideBelow) == nil,
            "The ball must fit inside the rim opening")
        outsideAbove.ground = CGPoint(x: hoop.center.x,
            y: hoop.center.y + Hoop.radiusY - (Basketball.radius + 3) / Hoop.groundDepthScale + 0.5)
        outsideBelow.ground = outsideAbove.ground
        precondition(ShotFlight.crossingHoop(from: outsideAbove, to: outsideBelow) == nil,
            "An outer-edge crossing cannot score")

        var movingAbove = above
        var movingBelow = below
        movingAbove.ground.x -= 80
        movingBelow.ground.x += 80
        precondition(ShotFlight.crossingHoop(from: movingAbove, to: movingBelow) == index,
            "Crossing uses the position at rim height, not a frame endpoint")
    }

    let extreme = ShotFlight(startGround: CGPoint(x: 0, y: 0), startHeight: 82,
        endGround: CGPoint(x: 10000, y: 0), distance: 10000, points: 3)
    precondition(extreme.sample(at: 0).velocity.x <= 1100.001,
        "Exceptional distances cannot produce unbounded shot speed")
}
