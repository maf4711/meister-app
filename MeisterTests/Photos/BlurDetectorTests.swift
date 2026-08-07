import XCTest
import CoreGraphics
import UIKit
@testable import MeisterIOS

/// Tests for `BlurDetector.laplacianVariance`.
///
/// Grounding notes:
/// - `BlurDetector.scan` is intentionally NOT tested: it depends on
///   `PhotoThumbnailLoader.thumbnail(for: item.asset, ...)` where `item.asset`
///   is a `PHAsset` — an opaque system type that cannot be constructed
///   deterministically in a unit test without Photos-library authorization.
/// - `laplacianVariance(_:)` is the only reachable (internal/static) helper that
///   accepts a value we can build deterministically in-process (a `UIImage`),
///   so all assertions below target it.
/// - The `image.cgImage == nil` guard is fully device-independent and is asserted
///   exactly (returns `nil`). The Core Image rendering path depends on a working
///   `CIContext` on the test host; for those cases we assert only structural
///   properties that hold whenever a value is produced (non-negative, finite,
///   bounded, idempotent) — never an exact rendered value.
final class BlurDetectorTests: XCTestCase {

    // MARK: - Image fixtures (deterministic, in-process)

    /// Builds a CGImage-backed `UIImage` from an 8-bit grayscale pixel grid.
    /// Returns nil if the bitmap context or image cannot be created on this host.
    private func makeGrayImage(width: Int, height: Int, fill: (Int, Int) -> UInt8) -> UIImage? {
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = fill(x, y)
            }
        }
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let cg = ctx.makeImage() else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    private func solidImage(width: Int, height: Int, value: UInt8) -> UIImage? {
        makeGrayImage(width: width, height: height) { _, _ in value }
    }

    private func checkerImage(width: Int, height: Int) -> UIImage? {
        makeGrayImage(width: width, height: height) { x, y in
            ((x ^ y) & 1) == 0 ? 0 : 255
        }
    }

    // MARK: - nil-guard path (fully deterministic, device-independent)

    func testEmptyImageReturnsNil() {
        // UIImage() has no cgImage backing -> first guard returns nil.
        XCTAssertNil(BlurDetector.laplacianVariance(UIImage()))
    }

    func testEmptyImageReturnsNilIsIdempotent() {
        let img = UIImage()
        XCTAssertNil(BlurDetector.laplacianVariance(img))
        XCTAssertNil(BlurDetector.laplacianVariance(img))
    }

    func testCIImageBackedImageWithoutCGImageReturnsNil() {
        // A UIImage created from a CIImage has cgImage == nil, exercising the guard
        // without depending on any Core Image rendering.
        let ci = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let img = UIImage(ciImage: ci)
        XCTAssertNil(img.cgImage, "Precondition: CIImage-backed UIImage has no cgImage")
        XCTAssertNil(BlurDetector.laplacianVariance(img))
    }

    // MARK: - rendered path: structural properties (assert only when a value exists)

    func testSolidImageVarianceIsNonNegativeWhenRendered() throws {
        guard let img = solidImage(width: 32, height: 32, value: 128) else {
            throw XCTSkip("Could not construct CGImage on this host")
        }
        guard let v = BlurDetector.laplacianVariance(img) else {
            throw XCTSkip("CIContext rendering unavailable on this host")
        }
        XCTAssertGreaterThanOrEqual(v, 0.0)
    }

    func testSolidImageVarianceIsFiniteWhenRendered() throws {
        guard let img = solidImage(width: 32, height: 32, value: 200) else {
            throw XCTSkip("Could not construct CGImage on this host")
        }
        guard let v = BlurDetector.laplacianVariance(img) else {
            throw XCTSkip("CIContext rendering unavailable on this host")
        }
        XCTAssertTrue(v.isFinite)
        XCTAssertFalse(v.isNaN)
    }

    func testVarianceIsBoundedByDefinitionWhenRendered() throws {
        // variance of values in [0,1] about their own mean cannot exceed 0.25.
        guard let img = checkerImage(width: 32, height: 32) else {
            throw XCTSkip("Could not construct CGImage on this host")
        }
        guard let v = BlurDetector.laplacianVariance(img) else {
            throw XCTSkip("CIContext rendering unavailable on this host")
        }
        XCTAssertGreaterThanOrEqual(v, 0.0)
        XCTAssertLessThanOrEqual(v, 0.25 + 1e-9)
    }

    func testVarianceIsIdempotentWhenRendered() throws {
        guard let img = checkerImage(width: 32, height: 32) else {
            throw XCTSkip("Could not construct CGImage on this host")
        }
        guard let first = BlurDetector.laplacianVariance(img) else {
            throw XCTSkip("CIContext rendering unavailable on this host")
        }
        guard let second = BlurDetector.laplacianVariance(img) else {
            return XCTFail("Second call returned nil after first succeeded")
        }
        XCTAssertEqual(first, second, accuracy: 1e-12)
    }

    func testSharpImageHasHigherVarianceThanFlatImage() throws {
        // Behavioral contract: a high-contrast edge pattern (sharp) yields a larger
        // Laplacian variance than a flat solid image (no edges). This is the property
        // `isBlurry`/`scan` relies on (flat -> low variance -> flagged blurry).
        guard let flat = solidImage(width: 48, height: 48, value: 128),
              let sharp = checkerImage(width: 48, height: 48) else {
            throw XCTSkip("Could not construct CGImage on this host")
        }
        guard let flatVar = BlurDetector.laplacianVariance(flat),
              let sharpVar = BlurDetector.laplacianVariance(sharp) else {
            throw XCTSkip("CIContext rendering unavailable on this host")
        }
        XCTAssertGreaterThanOrEqual(sharpVar, flatVar)
    }

    func testSmallestRenderableImageDoesNotCrashWhenRendered() throws {
        guard let img = solidImage(width: 1, height: 1, value: 255) else {
            throw XCTSkip("Could not construct 1x1 CGImage on this host")
        }
        // Either nil (renderer/extent issue) or a non-negative finite value — never a crash.
        if let v = BlurDetector.laplacianVariance(img) {
            XCTAssertGreaterThanOrEqual(v, 0.0)
            XCTAssertTrue(v.isFinite)
        }
    }

    func testLargeImageProducesBoundedResultWhenRendered() throws {
        guard let img = checkerImage(width: 256, height: 256) else {
            throw XCTSkip("Could not construct large CGImage on this host")
        }
        guard let v = BlurDetector.laplacianVariance(img) else {
            throw XCTSkip("CIContext rendering unavailable on this host")
        }
        XCTAssertGreaterThanOrEqual(v, 0.0)
        XCTAssertLessThanOrEqual(v, 0.25 + 1e-9)
        XCTAssertTrue(v.isFinite)
    }

    func testNonSquareImageIsHandledWhenRendered() throws {
        guard let img = checkerImage(width: 64, height: 16) else {
            throw XCTSkip("Could not construct non-square CGImage on this host")
        }
        guard let v = BlurDetector.laplacianVariance(img) else {
            throw XCTSkip("CIContext rendering unavailable on this host")
        }
        XCTAssertGreaterThanOrEqual(v, 0.0)
        XCTAssertTrue(v.isFinite)
    }

    func testDistinctSolidValuesYieldNonNegativeVarianceWhenRendered() throws {
        for value in [UInt8(0), 64, 128, 192, 255] {
            guard let img = solidImage(width: 24, height: 24, value: value) else {
                throw XCTSkip("Could not construct CGImage on this host")
            }
            guard let v = BlurDetector.laplacianVariance(img) else {
                throw XCTSkip("CIContext rendering unavailable on this host")
            }
            XCTAssertGreaterThanOrEqual(v, 0.0, "value=\(value)")
            XCTAssertTrue(v.isFinite, "value=\(value)")
        }
    }
}
