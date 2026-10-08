import CoreGraphics
import PluckCore
import XCTest

final class BlobLumpsTests: XCTestCase {
    func testSameSeedSameShapeDifferentSeedDifferentShape() {
        XCTAssertEqual(BlobLumps.specs(seed: 7, count: 4), BlobLumps.specs(seed: 7, count: 4))
        XCTAssertNotEqual(BlobLumps.specs(seed: 7, count: 4), BlobLumps.specs(seed: 8, count: 4))
    }

    func testLumpsStayInsideTheMassAndKeepPositiveSize() {
        for seed in UInt64(0)..<40 {
            for s in BlobLumps.specs(seed: seed, count: 4) {
                for t in stride(from: CGFloat(0), through: 30, by: 1.7) {
                    let l = BlobLumps.place(s, center: .zero, baseRadius: 40, time: t)
                    XCTAssertGreaterThan(l.radius, 8)
                    XCTAssertLessThan(hypot(l.center.x, l.center.y), 40 * 0.9)
                }
            }
        }
    }

    func testClusterIsNeverSymmetric() {
        // The cluster's centre of mass is off-centre and moves over time: no perfect disc, never frozen.
        func centroid(_ t: CGFloat) -> CGPoint {
            let ls = BlobLumps.specs(seed: 99, count: 4).map { BlobLumps.place($0, center: .zero, baseRadius: 40, time: t) }
            let w = ls.reduce(0) { $0 + $1.radius * $1.radius }
            return CGPoint(
                x: ls.reduce(0) { $0 + $1.center.x * $1.radius * $1.radius } / w,
                y: ls.reduce(0) { $0 + $1.center.y * $1.radius * $1.radius } / w
            )
        }
        XCTAssertGreaterThan(hypot(centroid(0).x, centroid(0).y), 0.5)
        XCTAssertGreaterThan(hypot(centroid(0).x - centroid(2.5).x, centroid(0).y - centroid(2.5).y), 0.5)
    }

    func testJiggleOffsetsTheLump() {
        let s = BlobLumps.specs(seed: 3, count: 1)[0]
        let a = BlobLumps.place(s, center: .zero, baseRadius: 30, time: 1)
        let b = BlobLumps.place(s, center: .zero, baseRadius: 30, time: 1, jiggle: CGPoint(x: 5, y: -3))
        XCTAssertEqual(b.center.x - a.center.x, 5, accuracy: 1e-6)
        XCTAssertEqual(b.center.y - a.center.y, -3, accuracy: 1e-6)
    }
}
