import Contacts
import Foundation

@main struct ContactMatchingChecks {
    static func item(_ id: Int, _ name: String, phones: [String] = [], emails: [String] = []) -> ContactItem {
        ContactItem(id: String(id), fullName: name, givenName: name, familyName: "",
                    phones: phones, emails: emails, hasImage: false, organization: "", cn: CNMutableContact())
    }

    static func memberships(_ groups: [ContactGroup]) -> [[String]] {
        groups.map { $0.items.map(\.id).sorted() }.sorted { $0.lexicographicallyPrecedes($1) }
    }

    static func equivalent(_ items: [ContactItem]) {
        precondition(memberships(ContactDeduplicator.dedupe(items)) ==
                     memberships(ReferenceContactDeduplicator.dedupe(items)), "Grouping changed")
    }

    // Letters only, so tokenization retains each synthetic name's distinct identity.
    static func suffix(_ number: Int) -> String {
        var value = number
        var result = ""
        repeat {
            result.append(Character(UnicodeScalar(97 + value % 26)!))
            value /= 26
        } while value > 0
        return result
    }

    static func checks() async {
        let names = ["", " ", "123", "!!!", "👩🏽‍💻", "Müller", "Mueller", "MÜLLER", "Straße", "Strasse",
                     "José García", "Jose Garcia", "Jose\u{301} Garcia", "Jan Kowalski", "Kowalski, Jan",
                     "Jan Jan Kowalski", "Alice Smith", "Alice Smithson", "Alice-Smith", "Bob Jones",
                     "李 小龙", "小龙 李", "Ольга Иванова", "محمد علي", "A B C", "A B C D",
                     "AB----CD", "AB-CD", "AB-----CD"]
        for a in names {
            for b in names {
                let expected = ReferenceFuzzyMatcher.nameSimilarity(a, b)
                let preparedA = FuzzyMatcher.PreparedName(a), preparedB = FuzzyMatcher.PreparedName(b)
                precondition(abs(FuzzyMatcher.nameSimilarity(a, b) - expected) < 1e-12)
                precondition(abs(FuzzyMatcher.nameSimilarity(preparedA, preparedB) - expected) < 1e-12)
                for threshold in [0.0, 0.4, 0.7, 0.85, 1.0, expected, expected.nextUp] {
                    precondition(FuzzyMatcher.namesMatch(preparedA, preparedB, threshold: threshold) ==
                                 (expected >= threshold), "Threshold changed for \(a), \(b)")
                }
                precondition(FuzzyMatcher.levenshtein(a, b) == ReferenceFuzzyMatcher.levenshtein(a, b))
            }
        }
        equivalent([])
        equivalent([item(0, "Alice")])
        equivalent(names.enumerated().map { item($0.offset, $0.element) })
        let base = "Alexander Maximilian Christopher Jonathan"
        let nameChain = [item(0, base + " a"), item(1, base), item(2, base + " b")]
        equivalent(nameChain)
        precondition(memberships(ContactDeduplicator.dedupe(nameChain)) == [["0", "1", "2"]])
        precondition(memberships(ContactDeduplicator.dedupe([item(0, "AB----CD"), item(1, "AB-CD")])) ==
                     [["0", "1"]], "Inclusive 0.85 boundary changed")
        let transitive = [item(0, "Alice", phones: ["+49123", "+49123"]),
                          item(1, "Bob", phones: ["+49123"], emails: ["shared@example.test"]),
                          item(2, "Carol", emails: ["shared@example.test"]), item(3, "Carol"),
                          item(4, "", phones: ["+49999"]), item(5, "", phones: ["+49999"]),
                          item(6, "!!!"), item(7, "!!!")]
        equivalent(transitive)
        precondition(memberships(ContactDeduplicator.dedupe(transitive)) == [["0", "1", "2", "3"], ["4", "5"]])

        // Deterministic mixtures of overlapping token sets, duplicates, and Unicode.
        var seed: UInt64 = 123456789
        func next(_ limit: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 32) % UInt64(limit))
        }
        let tokens = ["Alice", "Bob", "Müller", "Mueller", "Smith", "José", "李", "D", "E"]
        for _ in 0..<12 {
            let items = (0..<35).map { i in
                item(i, (0..<(1 + next(4))).map { _ in tokens[next(tokens.count)] }.joined(separator: " "),
                     phones: i % 9 == 0 ? ["phone\(i % 3)"] : [],
                     emails: i % 11 == 0 ? ["email\(i % 2)"] : [])
            }
            equivalent(items)
        }

        // Above the existing cap, fuzzy matching is still skipped, but exact indexes work.
        var capped = (0..<5001).map { item($0, "Identical Name") }
        capped[0] = item(0, "Identical Name", phones: ["shared"])
        capped[1] = item(1, "Identical Name", phones: ["shared"])
        equivalent(capped)
        precondition(memberships(ContactDeduplicator.dedupe(capped)) == [["0", "1"]])
        var atLimit = (0..<5000).map { item($0, "First\(suffix($0)) Last\(suffix($0))") }
        atLimit[4999] = item(4999, atLimit[0].fullName)
        precondition(memberships(ContactDeduplicator.dedupe(atLimit)) == [["0", "4999"]])
        let phoneChain = (0..<10_000).map { item($0, "", phones: ["phone\($0)", "phone\($0 + 1)"]) }
        let phoneGroups = ContactDeduplicator.dedupe(phoneChain)
        precondition(phoneGroups.count == 1 && phoneGroups[0].items.count == phoneChain.count)
        let asyncGroups = await ContactDeduplicator.dedupe(transitive, progress: { value, _ in
            precondition((0...1).contains(value))
        })
        precondition(memberships(asyncGroups) == memberships(ContactDeduplicator.dedupe(transitive)))
        print("Contact matching checks passed: scores, thresholds, Unicode, grouping, cap, async")
    }

    static func benchmark() {
        let unicodeTokens = ["Müller", "José", "François", "Иванова", "小龙", "Jonathan"]
        let sameTokens = (0..<200).map { i -> ContactItem in
            var pool = unicodeTokens
            var order: [String] = []
            var permutation = i
            while !pool.isEmpty {
                let position = permutation % pool.count
                permutation /= pool.count
                order.append(pool.remove(at: position))
            }
            return item(i, order.joined(separator: " "))
        }
        let workloads: [(String, [ContactItem])] = [
            ("distinct-500", (0..<500).map { item($0, "First\(suffix($0)) Last\(suffix($0))") }),
            ("shared-surname-500", (0..<500).map { item($0, "First\(suffix($0)) Smith") }),
            ("duplicates-500", (0..<500).map { item($0, "First\(suffix($0 / 5)) Last\(suffix($0 / 5))") }),
            ("same-unicode-tokens-200", sameTokens),
        ]
        for (name, items) in workloads {
            equivalent(items)
            var baseline: [Double] = [], optimized: [Double] = []
            func measure(_ operation: () -> [ContactGroup]) -> Double {
                let started = DispatchTime.now().uptimeNanoseconds
                let result = memberships(operation())
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
                precondition(result.count <= items.count / 2)
                return elapsed
            }
            // Alternate execution order; report medians, with both paths compiled using -O.
            for iteration in 0..<3 {
                if iteration % 2 == 0 {
                    baseline.append(measure { ReferenceContactDeduplicator.dedupe(items) })
                    optimized.append(measure { ContactDeduplicator.dedupe(items) })
                } else {
                    optimized.append(measure { ContactDeduplicator.dedupe(items) })
                    baseline.append(measure { ReferenceContactDeduplicator.dedupe(items) })
                }
            }
            let before = baseline.sorted()[1], after = optimized.sorted()[1]
            print("\(name): baseline_ms=\(before) optimized_ms=\(after) speedup=\(before / after)")
            fflush(stdout)
        }
    }

    static func main() async {
        if CommandLine.arguments.contains("--benchmark") { benchmark() }
        else { await checks() }
    }
}
