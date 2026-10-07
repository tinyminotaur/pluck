import XCTest
import PluckCore

final class BlobMassTests: XCTestCase {
    let params = BlobMassParams.default

    func testRestMatchesRestRadius() {
        let r = BlobMass.uniformRadius(forLength: 0, params: params)
        XCTAssertEqual(r, params.restRadius, accuracy: 0.01)
    }

    func testLongerPullIsThinner() {
        let short = BlobMass.uniformRadius(forLength: 40, params: params)
        let long = BlobMass.uniformRadius(forLength: 220, params: params)
        XCTAssertGreaterThan(short, long)
        XCTAssertGreaterThanOrEqual(long, params.minRadius)
    }

    func testProfileConservesAreaApproximately() {
        for L: CGFloat in [0, 40, 120, 160, 280] {
            let radii = BlobMass.radiusProfile(length: L, samples: 12, params: params)
            let area = BlobMass.approximateArea(radii: radii, length: L)
            XCTAssertEqual(
                area,
                params.totalArea,
                accuracy: params.totalArea * 0.06,
                "length \(L)"
            )
        }
    }

    func testEndsThickerThanNeckWhenStretched() {
        let radii = BlobMass.radiusProfile(length: 200, samples: 11, params: params)
        let mid = radii[radii.count / 2]
        XCTAssertGreaterThan(radii[0], mid)
        XCTAssertGreaterThan(radii[radii.count - 1], mid)
    }

    func testPinHoldsMoreMassThanHead() {
        let radii = BlobMass.radiusProfile(length: 180, samples: 15, params: params)
        XCTAssertGreaterThan(radii[0], radii[radii.count - 1])
        XCTAssertGreaterThan(radii[radii.count - 1], params.minRadius)
    }
}
