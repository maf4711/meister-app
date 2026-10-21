# Contact matching performance — 21 October 2026

Contact deduplication now prepares each name once, indexes its normalized tokens,
and computes edit distance only for candidates that can reach the existing 0.85
threshold. Disjoint token sets score at most 0.4. Other candidates are rejected
when their exact token score plus the maximum edit-distance contribution is
below 0.85.

Phone/email indexes retain one representative per value. Union by size and
iterative path compression avoid deep recursive chains, and contacts already in
the same group need no further name comparison. Levenshtein work rows use the
shorter name's character count. Public similarity scores, transitive group
membership, progress updates, and the 5,000-name cutoff are preserved.

## Measurements

Apple M4 Pro, macOS 27.2, Apple Swift 6.4. Both implementations were compiled
together with `-swift-version 5 -O`. The reference fixture preserves the original
matcher and deduplicator from commit
`ea7f865165494ecf55c37b1e634a5b2be43a354d`, with only type names changed.

Each workload first checks identical group membership. Times are the median of
three synchronous matching runs, alternating execution order, and include
normalization of output group IDs for comparison. Input construction is outside
the timed interval.

| Synthetic workload | Baseline | Optimized | Speedup |
| --- | ---: | ---: | ---: |
| 500 distinct names | 1,925.08 ms | 2.18 ms | 881.1× |
| 500 names sharing a surname | 1,860.97 ms | 13.14 ms | 141.6× |
| 500 names in sets of five identical copies | 1,899.08 ms | 2.43 ms | 781.4× |
| 200 permutations of the same Unicode tokens | 929.95 ms | 36.41 ms | 25.5× |

These measure the matching phase on synthetic contacts, not end-to-end scan time
or real address-book performance. No Contacts permission or personal data is
needed. Dense shared-token inputs still produce quadratic candidate work, with
sorting per contact. Cached names retain additional linear input storage;
reduced peak memory has not been measured. Candidate pairs are never retained
for the entire library.

Reproduce from the repository root:

```sh
python3 scripts/tests/test_contact_matching.py --benchmark
python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v
swift test --package-path Packages/MeisterKit
```

The benchmark prints SHA-256 hashes for its sources and fails if they change
during the run. This run used:

| Source | SHA-256 |
| --- | --- |
| `ContactDeduplicator.swift` | `4ab8bf55fd7363e23495dce1995f1f535c99613d980a5fc6eb70c7f62f4ac591` |
| `FuzzyMatcher.swift` | `eab62692efc90f04b7c8d13cf8b91b3036de53afa9de80aa1a20584cb446f237` |
| `contact_matching_checks.swift` | `837c775aaa2a27ee194fc8382a8fc2e797741de7f48aed197648acedede65c05` |
| `contact_matching_reference.swift` | `4ed3254aee4a357b5364a18f905f398812b8cc37e0983baadf8fea55e9529b95` |

## Verification

- All 14 script tests and all 16 MeisterKit tests passed.
- The four contact source files passed type checking for
  `arm64-apple-ios17.0-simulator`, Swift language version 5. No simulator was booted.
- Equivalence checks cover Unicode, punctuation-only names, exact threshold
  boundaries, randomized overlapping names, transitive fuzzy/phone/email groups,
  async results, both sides of the 5,000-name cutoff, and a 10,000-contact phone chain.
- A separate read-only review found no correctness blocker.
- Full application builds and on-device timing were not performed.

Existing photo, filesystem-scanner, and helper-test edits were preserved.
