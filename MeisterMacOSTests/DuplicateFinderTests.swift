import XCTest
@testable import Meister

// MARK: - Duplicate Finder

final class DuplicateFinderTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meister-dup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let t = tmp { try? FileManager.default.removeItem(at: t) }
    }

    func test_finds_duplicate_pair() async throws {
        let payload = Data(repeating: 0xAB, count: 2_000_000)
        try payload.write(to: tmp.appendingPathComponent("a.bin"))
        try payload.write(to: tmp.appendingPathComponent("b.bin"))
        try Data(repeating: 0xCD, count: 2_000_000).write(to: tmp.appendingPathComponent("c.bin"))

        let finder = DuplicateFinder()
        let groups = await finder.find(in: [tmp], minSize: 1_048_576)
        XCTAssertEqual(groups.count, 1, "exactly one duplicate group expected")
        XCTAssertEqual(groups.first?.files.count, 2)
    }

    func test_skips_files_below_min_size() async throws {
        let small = Data(count: 1024)
        try small.write(to: tmp.appendingPathComponent("a.txt"))
        try small.write(to: tmp.appendingPathComponent("b.txt"))

        let finder = DuplicateFinder()
        let groups = await finder.find(in: [tmp], minSize: 1_048_576)
        XCTAssertTrue(groups.isEmpty)
    }

    func test_sha256_matches_known_value() {
        // SHA256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
        let url = tmp.appendingPathComponent("hello.txt")
        try? "hello".data(using: .utf8)?.write(to: url)
        let hash = DuplicateFinder.sha256(of: url)
        XCTAssertEqual(hash, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }
}
