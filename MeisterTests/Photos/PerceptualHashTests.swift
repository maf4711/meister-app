import XCTest
@testable import MeisterIOS

final class PerceptualHashTests: XCTestCase {

    // MARK: - distance: identical = 0

    func testDistanceIdenticalIsZero() {
        XCTAssertEqual(PerceptualHash.distance(0, 0), 0)
    }

    func testDistanceIdenticalNonZeroIsZero() {
        XCTAssertEqual(PerceptualHash.distance(0xDEADBEEFCAFEBABE, 0xDEADBEEFCAFEBABE), 0)
    }

    func testDistanceAllOnesIdenticalIsZero() {
        XCTAssertEqual(PerceptualHash.distance(UInt64.max, UInt64.max), 0)
    }

    // MARK: - distance: known bit-diff vectors

    func testDistanceSingleBitDiffIsOne() {
        XCTAssertEqual(PerceptualHash.distance(0, 1), 1)
    }

    func testDistanceHighBitDiffIsOne() {
        XCTAssertEqual(PerceptualHash.distance(0, 1 << 63), 1)
    }

    func testDistanceTwoBitsDiff() {
        // bits 0 and 1 differ
        XCTAssertEqual(PerceptualHash.distance(0, 0b11), 2)
    }

    func testDistanceAllBitsDiffIs64() {
        XCTAssertEqual(PerceptualHash.distance(0, UInt64.max), 64)
    }

    func testDistanceAllBitsDiffFromMaxIs64() {
        XCTAssertEqual(PerceptualHash.distance(UInt64.max, 0), 64)
    }

    func testDistanceFourBitNibbleDiff() {
        // 0x0 vs 0xF differ in 4 bits
        XCTAssertEqual(PerceptualHash.distance(0x0, 0xF), 4)
    }

    func testDistanceAlternatingPattern() {
        // 0xAAAA... vs 0x5555... — every bit differs → 64
        XCTAssertEqual(
            PerceptualHash.distance(0xAAAAAAAAAAAAAAAA, 0x5555555555555555),
            64
        )
    }

    func testDistanceAlternatingVsZero() {
        // 0xAAAA... has 32 set bits
        XCTAssertEqual(PerceptualHash.distance(0xAAAAAAAAAAAAAAAA, 0), 32)
    }

    func testDistanceEightBitByteDiff() {
        // one full byte differs → 8 bits
        XCTAssertEqual(PerceptualHash.distance(0x00, 0xFF), 8)
    }

    func testDistanceXorIsPopcount() {
        // distance == nonzeroBitCount of the XOR, by definition
        let a: UInt64 = 0x1234_5678_9ABC_DEF0
        let b: UInt64 = 0x0FED_CBA9_8765_4321
        XCTAssertEqual(
            PerceptualHash.distance(a, b),
            (a ^ b).nonzeroBitCount
        )
    }

    // MARK: - distance: symmetry

    func testDistanceIsSymmetric() {
        let a: UInt64 = 0xDEAD_BEEF_0000_1111
        let b: UInt64 = 0x1111_0000_BEEF_DEAD
        XCTAssertEqual(
            PerceptualHash.distance(a, b),
            PerceptualHash.distance(b, a)
        )
    }

    func testDistanceSymmetricForManyPairs() {
        let samples: [UInt64] = [
            0, 1, UInt64.max, 0xAAAAAAAAAAAAAAAA, 0x5555555555555555,
            0x0123456789ABCDEF, 0xFEDCBA9876543210, 1 << 63, 1 << 31
        ]
        for a in samples {
            for b in samples {
                XCTAssertEqual(
                    PerceptualHash.distance(a, b),
                    PerceptualHash.distance(b, a),
                    "Distance should be symmetric for \(a), \(b)"
                )
            }
        }
    }

    // MARK: - distance: range / bounds

    func testDistanceNeverExceeds64() {
        let samples: [UInt64] = [
            0, 1, UInt64.max, 0xAAAAAAAAAAAAAAAA, 0x5555555555555555,
            0x0123456789ABCDEF, 0xFEDCBA9876543210
        ]
        for a in samples {
            for b in samples {
                let d = PerceptualHash.distance(a, b)
                XCTAssertGreaterThanOrEqual(d, 0)
                XCTAssertLessThanOrEqual(d, 64)
            }
        }
    }

    func testDistanceTriangleInequality() {
        // Hamming distance is a metric: d(a,c) <= d(a,b) + d(b,c)
        let a: UInt64 = 0x0000_0000_0000_0000
        let b: UInt64 = 0x0000_0000_FFFF_FFFF
        let c: UInt64 = 0xFFFF_FFFF_FFFF_FFFF
        let ac = PerceptualHash.distance(a, c)
        let ab = PerceptualHash.distance(a, b)
        let bc = PerceptualHash.distance(b, c)
        XCTAssertLessThanOrEqual(ac, ab + bc)
    }
}
