import XCTest
import UIKit
import ImageIO
@testable import MeisterIOS

/// Tests for the pure hardening helpers added to the Vision similarity path:
/// failure reporting (#5) and aspect-preserving / orientation-correct extraction (#7).
final class SimilarityHardeningTests: XCTestCase {

    // MARK: #5 — failure signal (photos whose fingerprint couldn't be computed)

    func testFailedIDsEmptyWhenAllFingerprinted() {
        let all = ["a", "b", "c"]
        XCTAssertEqual(SimilarityClustering.failedIDs(allIDs: all, fingerprintedIDs: ["a", "b", "c"]), [])
    }

    func testFailedIDsReportsMissing() {
        let all = ["a", "b", "c"]
        XCTAssertEqual(SimilarityClustering.failedIDs(allIDs: all, fingerprintedIDs: ["a", "c"]), ["b"])
    }

    func testFailedIDsAllWhenNoneFingerprinted() {
        let all = ["a", "b"]
        XCTAssertEqual(SimilarityClustering.failedIDs(allIDs: all, fingerprintedIDs: []), ["a", "b"])
    }

    func testFailedIDsPreservesInputOrder() {
        let all = ["z", "y", "x", "w"]
        XCTAssertEqual(SimilarityClustering.failedIDs(allIDs: all, fingerprintedIDs: ["y", "w"]), ["z", "x"])
    }

    func testFailedIDsEmptyInput() {
        XCTAssertEqual(SimilarityClustering.failedIDs(allIDs: [], fingerprintedIDs: ["a"]), [])
    }

    // MARK: #7a — aspect-preserving thumbnail size (no 299×299 squash)

    func testFittedSizePreservesLandscapeRatio() {
        // 4000×2000 into a 299 box → 299×150 (ratio 2:1 kept), not 299×299
        let s = SimilarityClustering.fittedSize(pixelWidth: 4000, pixelHeight: 2000, maxDimension: 299)
        XCTAssertEqual(s.width, 299, accuracy: 0.5)
        XCTAssertEqual(s.height, 150, accuracy: 0.5)
    }

    func testFittedSizePreservesPortraitRatio() {
        let s = SimilarityClustering.fittedSize(pixelWidth: 2000, pixelHeight: 4000, maxDimension: 299)
        XCTAssertEqual(s.height, 299, accuracy: 0.5)
        XCTAssertEqual(s.width, 150, accuracy: 0.5)
    }

    func testFittedSizeSquareStaysSquare() {
        let s = SimilarityClustering.fittedSize(pixelWidth: 3000, pixelHeight: 3000, maxDimension: 299)
        XCTAssertEqual(s.width, 299, accuracy: 0.5)
        XCTAssertEqual(s.height, 299, accuracy: 0.5)
    }

    func testFittedSizeNeverUpscalesSmallImage() {
        // smaller than the box → request native size, don't blow it up
        let s = SimilarityClustering.fittedSize(pixelWidth: 100, pixelHeight: 80, maxDimension: 299)
        XCTAssertEqual(s.width, 100, accuracy: 0.5)
        XCTAssertEqual(s.height, 80, accuracy: 0.5)
    }

    func testFittedSizeZeroDimensionsFallBackToSquare() {
        let s = SimilarityClustering.fittedSize(pixelWidth: 0, pixelHeight: 0, maxDimension: 299)
        XCTAssertEqual(s.width, 299, accuracy: 0.5)
        XCTAssertEqual(s.height, 299, accuracy: 0.5)
    }

    func testFittedSizeNeverExceedsMaxDimension() {
        let s = SimilarityClustering.fittedSize(pixelWidth: 8000, pixelHeight: 6000, maxDimension: 299)
        XCTAssertLessThanOrEqual(max(s.width, s.height), 299)
    }

    // MARK: #7b — orientation mapping (image.cgImage drops UIImage orientation)

    func testOrientationMappingCoversAllCases() {
        let pairs: [(UIImage.Orientation, CGImagePropertyOrientation)] = [
            (.up, .up), (.down, .down), (.left, .left), (.right, .right),
            (.upMirrored, .upMirrored), (.downMirrored, .downMirrored),
            (.leftMirrored, .leftMirrored), (.rightMirrored, .rightMirrored),
        ]
        for (ui, expected) in pairs {
            XCTAssertEqual(CGImagePropertyOrientation(ui), expected)
        }
    }
}
