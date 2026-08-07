import XCTest
@testable import MeisterIOS

// Grounded strictly on MeisterIOS/Storage/StorageReader.swift:
//   struct StorageInfo {
//       let total: Int64
//       let free: Int64
//       var used: Int64 { total - free }
//       var usedRatio: Double { total > 0 ? Double(used) / Double(total) : 0 }
//   }
//   enum StorageReader { static func read() -> StorageInfo; static func appCacheBytes() -> Int64; ... }
//
// The task brief names "usedBytes"/"usedFraction"; the REAL symbols are `used` and
// `usedRatio`, so those are what we test (grounding wins over the brief).
// `purgeAppCache()` is destructive (wipes the live caches/tmp sandbox) and `read()`
// depends on the host volume, so those are only touched via non-mutating invariants.
final class StorageReaderTests: XCTestCase {

    // MARK: - StorageInfo.used (happy path)

    func testUsedIsTotalMinusFree() {
        let info = StorageInfo(total: 100, free: 30)
        XCTAssertEqual(info.used, 70)
    }

    func testUsedWhenNothingFree() {
        let info = StorageInfo(total: 100, free: 0)
        XCTAssertEqual(info.used, 100)
    }

    func testUsedWhenEverythingFree() {
        let info = StorageInfo(total: 100, free: 100)
        XCTAssertEqual(info.used, 0)
    }

    func testUsedPreservesStoredProperties() {
        let info = StorageInfo(total: 512, free: 128)
        XCTAssertEqual(info.total, 512)
        XCTAssertEqual(info.free, 128)
        XCTAssertEqual(info.used, 384)
    }

    // MARK: - StorageInfo.used (zero / empty)

    func testUsedAllZero() {
        let info = StorageInfo(total: 0, free: 0)
        XCTAssertEqual(info.used, 0)
    }

    func testUsedZeroTotalNonZeroFree() {
        // No clamping in the source: used = total - free can go negative.
        let info = StorageInfo(total: 0, free: 50)
        XCTAssertEqual(info.used, -50)
    }

    // MARK: - StorageInfo.used (negative / overflow boundaries)

    func testUsedNegativeWhenFreeExceedsTotal() {
        let info = StorageInfo(total: 40, free: 100)
        XCTAssertEqual(info.used, -60)
    }

    func testUsedWithNegativeFree() {
        // Int64 inputs are not validated; used = total - free arithmetic holds.
        let info = StorageInfo(total: 100, free: -25)
        XCTAssertEqual(info.used, 125)
    }

    func testUsedWithNegativeTotal() {
        let info = StorageInfo(total: -10, free: -10)
        XCTAssertEqual(info.used, 0)
    }

    func testUsedWithLargeValues() {
        // 2 TiB total, 1 TiB free — realistic large-disk magnitudes, no overflow.
        let total: Int64 = 2 * 1024 * 1024 * 1024 * 1024
        let free: Int64 = 1 * 1024 * 1024 * 1024 * 1024
        let info = StorageInfo(total: total, free: free)
        XCTAssertEqual(info.used, 1 * 1024 * 1024 * 1024 * 1024)
    }

    func testUsedAtInt64Max() {
        let info = StorageInfo(total: Int64.max, free: 0)
        XCTAssertEqual(info.used, Int64.max)
    }

    func testUsedIsIdempotent() {
        let info = StorageInfo(total: 999, free: 333)
        XCTAssertEqual(info.used, info.used)
        XCTAssertEqual(info.used, 666)
    }

    // MARK: - StorageInfo.usedRatio (happy path)

    func testUsedRatioHalf() {
        let info = StorageInfo(total: 100, free: 50)
        XCTAssertEqual(info.usedRatio, 0.5, accuracy: 1e-9)
    }

    func testUsedRatioFull() {
        let info = StorageInfo(total: 100, free: 0)
        XCTAssertEqual(info.usedRatio, 1.0, accuracy: 1e-9)
    }

    func testUsedRatioEmpty() {
        let info = StorageInfo(total: 100, free: 100)
        XCTAssertEqual(info.usedRatio, 0.0, accuracy: 1e-9)
    }

    func testUsedRatioThreeQuarters() {
        let info = StorageInfo(total: 400, free: 100)
        XCTAssertEqual(info.usedRatio, 0.75, accuracy: 1e-9)
    }

    func testUsedRatioOneThird() {
        let info = StorageInfo(total: 3, free: 2)
        XCTAssertEqual(info.usedRatio, 1.0 / 3.0, accuracy: 1e-12)
    }

    // MARK: - StorageInfo.usedRatio (divide-by-zero guard — the focus)

    func testUsedRatioZeroTotalReturnsZeroNotNaN() {
        let info = StorageInfo(total: 0, free: 0)
        XCTAssertEqual(info.usedRatio, 0.0, accuracy: 1e-12)
        XCTAssertFalse(info.usedRatio.isNaN)
        XCTAssertFalse(info.usedRatio.isInfinite)
    }

    func testUsedRatioZeroTotalNonZeroFreeStillGuarded() {
        // Guard is `total > 0`; with total == 0 it must short-circuit to 0
        // regardless of `free`, never computing -50/0.
        let info = StorageInfo(total: 0, free: 50)
        XCTAssertEqual(info.usedRatio, 0.0, accuracy: 1e-12)
        XCTAssertFalse(info.usedRatio.isNaN)
    }

    func testUsedRatioNegativeTotalHitsGuard() {
        // Guard is strictly `total > 0`, so a negative total also returns 0.
        let info = StorageInfo(total: -100, free: 0)
        XCTAssertEqual(info.usedRatio, 0.0, accuracy: 1e-12)
    }

    func testUsedRatioBarelyPositiveTotalNotGuarded() {
        // total == 1 (> 0) so the guard does NOT trigger; ratio is computed.
        let info = StorageInfo(total: 1, free: 0)
        XCTAssertEqual(info.usedRatio, 1.0, accuracy: 1e-9)
    }

    // MARK: - StorageInfo.usedRatio (negative / boundary numerics)

    func testUsedRatioNegativeWhenFreeExceedsTotal() {
        // total > 0 so guard passes; used is negative -> ratio is negative.
        let info = StorageInfo(total: 100, free: 150)
        XCTAssertEqual(info.usedRatio, -0.5, accuracy: 1e-9)
        XCTAssertFalse(info.usedRatio.isNaN)
    }

    func testUsedRatioAboveOneWhenFreeNegative() {
        let info = StorageInfo(total: 100, free: -100)
        XCTAssertEqual(info.usedRatio, 2.0, accuracy: 1e-9)
    }

    func testUsedRatioWithLargeValues() {
        let total: Int64 = 1_000_000_000_000
        let free: Int64 = 250_000_000_000
        let info = StorageInfo(total: total, free: free)
        XCTAssertEqual(info.usedRatio, 0.75, accuracy: 1e-9)
    }

    func testUsedRatioIsFiniteForRepresentativeInputs() {
        for (total, free) in [(0, 0), (0, 5), (100, 0), (100, 100), (100, 50), (7, 3)] as [(Int64, Int64)] {
            let r = StorageInfo(total: total, free: free).usedRatio
            XCTAssertFalse(r.isNaN, "ratio NaN for total=\(total) free=\(free)")
            XCTAssertFalse(r.isInfinite, "ratio infinite for total=\(total) free=\(free)")
        }
    }

    func testUsedRatioIsIdempotent() {
        let info = StorageInfo(total: 256, free: 64)
        let first = info.usedRatio
        let second = info.usedRatio
        XCTAssertEqual(first, second, accuracy: 0.0)
        XCTAssertEqual(first, 0.75, accuracy: 1e-9)
    }

    // MARK: - used / usedRatio consistency

    func testUsedRatioMatchesUsedOverTotal() {
        let info = StorageInfo(total: 800, free: 200)
        let expected = Double(info.used) / Double(info.total)
        XCTAssertEqual(info.usedRatio, expected, accuracy: 1e-12)
    }

    // MARK: - StorageReader.read() invariants (host-dependent, non-mutating)

    func testReadReturnsConsistentStruct() {
        let info = StorageReader.read()
        // `used` is always exactly total - free regardless of the host volume.
        XCTAssertEqual(info.used, info.total - info.free)
    }

    func testReadUsedRatioIsFinite() {
        let info = StorageReader.read()
        XCTAssertFalse(info.usedRatio.isNaN)
        XCTAssertFalse(info.usedRatio.isInfinite)
    }

    func testReadUsedRatioRespectsGuard() {
        let info = StorageReader.read()
        // The guard guarantees: total <= 0 -> ratio exactly 0.
        if info.total <= 0 {
            XCTAssertEqual(info.usedRatio, 0.0, accuracy: 1e-12)
        } else {
            XCTAssertEqual(info.usedRatio, Double(info.used) / Double(info.total), accuracy: 1e-12)
        }
    }

    // MARK: - StorageReader.appCacheBytes() invariant (non-mutating)

    func testAppCacheBytesIsNonNegative() {
        // directorySize sums file sizes; the total is never negative.
        XCTAssertGreaterThanOrEqual(StorageReader.appCacheBytes(), 0)
    }

    func testAppCacheBytesIsStableAcrossReadOnlyCalls() {
        // Two consecutive reads without mutation should not diverge wildly;
        // assert both are non-negative (sandbox may change, so no equality).
        let a = StorageReader.appCacheBytes()
        let b = StorageReader.appCacheBytes()
        XCTAssertGreaterThanOrEqual(a, 0)
        XCTAssertGreaterThanOrEqual(b, 0)
    }
}
