import Foundation

// This arcade court follows the white arc in the background image, rather than
// claiming regulation dimensions. Drawing and scoring share the same polyline.
enum CourtGeometry {
    static let courtWidth: CGFloat = 1672
    static let courtTop: CGFloat = 253
    static let courtBottom: CGFloat = 781
    // Includes half the painted line and the visible thickness of a player's foot.
    static let footLineMargin: CGFloat = 4

    private static let leftBoundary: [CGPoint] = {
        var points = [CGPoint(x: 140, y: courtTop), CGPoint(x: 140, y: 294)]
        func appendCurve(_ start: CGPoint, _ first: CGPoint, _ second: CGPoint, _ end: CGPoint) {
            for index in 1...160 {
                let t = CGFloat(index) / 160
                let u = 1 - t
                points.append(CGPoint(
                    x: u*u*u*start.x + 3*u*u*t*first.x + 3*u*t*t*second.x + t*t*t*end.x,
                    y: u*u*u*start.y + 3*u*u*t*first.y + 3*u*t*t*second.y + t*t*t*end.y
                ))
            }
        }
        appendCurve(CGPoint(x: 140, y: 294), CGPoint(x: 385, y: 294),
                    CGPoint(x: 568, y: 338), CGPoint(x: 572, y: 478))
        // A horizontal end tangent keeps the lower edge monotonic in y, so each
        // court row has exactly one boundary and the corner cannot fold backward.
        appendCurve(CGPoint(x: 572, y: 478), CGPoint(x: 583, y: 611),
                    CGPoint(x: 332, y: 730), CGPoint(x: 0, y: 730))
        points.append(CGPoint(x: 0, y: courtBottom))
        return points
    }()

    static func threePointPolyline(left: Bool) -> [CGPoint] {
        left ? leftBoundary : leftBoundary.map { CGPoint(x: courtWidth - $0.x, y: $0.y) }
    }

    static func threePointX(at y: CGFloat, left: Bool) -> CGFloat {
        guard y.isFinite else { return .nan }
        let x: CGFloat
        if y <= courtTop {
            x = leftBoundary[0].x
        } else if y >= courtBottom {
            x = leftBoundary[leftBoundary.count - 1].x
        } else {
            var lower = 0
            var upper = leftBoundary.count - 1
            while upper - lower > 1 {
                let middle = (lower + upper) / 2
                if leftBoundary[middle].y <= y { lower = middle } else { upper = middle }
            }
            let a = leftBoundary[lower]
            let b = leftBoundary[upper]
            let fraction = (y - a.y) / (b.y - a.y)
            x = a.x + (b.x - a.x) * fraction
        }
        return left ? x : courtWidth - x
    }

    static func shotPoints(feet: [CGPoint], hoopIndex: Int) -> Int {
        guard feet.count >= 2, hoopIndex == 0 || hoopIndex == 1 else { return 2 }
        let left = hoopIndex == 0
        for foot in feet {
            guard foot.x.isFinite, foot.y.isFinite else { return 2 }
            // Mirror the right basket into the same coordinate system, keeping
            // the side check and the line-contact tolerance exactly symmetric.
            let point = CGPoint(x: left ? foot.x : courtWidth - foot.x, y: foot.y)
            guard point.x > threePointX(at: point.y, left: true),
                  distanceToLeftBoundary(point) > footLineMargin else { return 2 }
        }
        return 3
    }

    private static func distanceToLeftBoundary(_ point: CGPoint) -> CGFloat {
        var nearestSquared = CGFloat.greatestFiniteMagnitude
        for index in 1..<leftBoundary.count {
            let a = leftBoundary[index - 1]
            let b = leftBoundary[index]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lengthSquared = dx*dx + dy*dy
            let t = max(0, min(1, ((point.x - a.x)*dx + (point.y - a.y)*dy) / lengthSquared))
            let offsetX = point.x - (a.x + t*dx)
            let offsetY = point.y - (a.y + t*dy)
            nearestSquared = min(nearestSquared, offsetX*offsetX + offsetY*offsetY)
        }
        return sqrt(nearestSquared)
    }
}

func runCourtGeometryTests() {
    let width = CourtGeometry.courtWidth
    func mirror(_ feet: [CGPoint]) -> [CGPoint] {
        feet.map { CGPoint(x: width - $0.x, y: $0.y) }
    }
    func check(_ feet: [CGPoint], _ expected: Int, _ label: String) {
        precondition(CourtGeometry.shotPoints(feet: feet, hoopIndex: 0) == expected, label)
        precondition(CourtGeometry.shotPoints(feet: mirror(feet), hoopIndex: 1) == expected,
                     "Mirrored court: " + label)
    }
    let leftLine = CourtGeometry.threePointPolyline(left: true)
    let rightLine = CourtGeometry.threePointPolyline(left: false)
    precondition(leftLine.count == rightLine.count)
    for index in leftLine.indices {
        precondition(abs(leftLine[index].x + rightLine[index].x - width) < 0.000001)
        precondition(leftLine[index].y == rightLine[index].y)
        precondition(abs(CourtGeometry.threePointX(at: leftLine[index].y, left: true) - leftLine[index].x) < 0.000001,
                     "Scoring and painted polyline must agree")
        if index > 0 { precondition(leftLine[index].y > leftLine[index - 1].y) }
    }
    for y: CGFloat in [253, 270, 294, 350, 478, 500, 640, 710, 730, 760, 781] {
        let x = CourtGeometry.threePointX(at: y, left: true)
        precondition(abs(x + CourtGeometry.threePointX(at: y, left: false) - width) < 0.000001)
        check([CGPoint(x: x - 20, y: y), CGPoint(x: x - 10, y: y)], 2, "Both feet inside")
        check([CGPoint(x: x, y: y), CGPoint(x: x + 80, y: y)], 2, "One foot on the line")
        check([CGPoint(x: x - 5, y: y), CGPoint(x: x + 80, y: y)], 2, "Feet straddle the line")
        check([CGPoint(x: x + 2, y: y), CGPoint(x: x + 80, y: y)], 2, "Foot overlaps the painted line")
        check([CGPoint(x: x + 120, y: y), CGPoint(x: x + 140, y: y)], 3, "Both feet clearly outside")
    }
    check([CGPoint(x: 820, y: 500), CGPoint(x: 850, y: 500)], 3, "Midcourt three")
    check([CGPoint(x: 250, y: 270), CGPoint(x: 280, y: 270)], 3, "Upper straight corner")
    check([CGPoint(x: 30, y: 760), CGPoint(x: 55, y: 760)], 3, "Lower straight corner")
    // Near a shallow arc, horizontal clearance alone would miss a foot on paint.
    check([CGPoint(x: 300, y: 303), CGPoint(x: 320, y: 303)], 2, "Shallow arc line contact")
    precondition(CourtGeometry.shotPoints(feet: [], hoopIndex: 0) == 2)
    precondition(CourtGeometry.shotPoints(feet: [CGPoint(x: 820, y: 500)], hoopIndex: 0) == 2)
    precondition(CourtGeometry.shotPoints(feet: [CGPoint(x: CGFloat.nan, y: 500), CGPoint(x: 850, y: 500)], hoopIndex: 0) == 2)
    precondition(CourtGeometry.shotPoints(feet: [CGPoint(x: 820, y: 500), CGPoint(x: 850, y: 500)], hoopIndex: 2) == 2)
}
