# Photo grouping performance — 21 October 2026

Complete-link photo grouping now updates cached cluster distances using
`D(A∪B,C) = max(D(A,C), D(B,C))`. A packed triangular matrix replaces the full
symmetric matrix. Each active cluster caches its best later neighbor; merging
clusters only invalidates candidates whose linkage increases. Members are
sorted once at output.

The original merge order and oriented representative tie break are preserved.
Every finished group remains strictly below the distance threshold, and Vision
distances are still requested exactly once per pair in the original order.
The existing capture-window correction and keeper/deletion rules are preserved.

One safety correction is intentional: nonfinite distances now prevent a merge.
Previously, NaN and negative infinity behaved like zero distance and could
incorrectly imply that photos were duplicates.

## Measurements

Apple M4 Pro, macOS 27.2, Apple Swift 6.4. The actual production method is
extracted into a standalone enum so the benchmark needs neither PhotoKit access
nor a simulator. Both versions compile together with `-swift-version 5 -O`.
The frozen reference matches the grouping method from commit
`ea7f865165494ecf55c37b1e634a5b2be43a354d`.

Each workload first checks exact output equivalence. Results below are medians
of three timed runs with alternating execution order.

| Synthetic distances for 500 photos | Baseline | Optimized | Speedup |
| --- | ---: | ---: | ---: |
| All mutually similar | 52.78 ms | 1.21 ms | 43.7× |
| Separate groups of five | 38.99 ms | 1.08 ms | 36.3× |
| Adjacent similar pairs forming a chain | 28.46 ms | 0.89 ms | 31.9× |
| All distinct | 0.37 ms | 0.30 ms | 1.2× |

At 500 photos, the distance array's Float payload decreases from 1,000,000 to
499,000 bytes, a 50.1% reduction. This is calculated storage for that array,
not measured peak process memory. The candidate metadata adds linear storage.
Worst-case grouping time remains cubic because invalidated candidate rows can
require rescanning. These timings isolate grouping and use inexpensive synthetic
distances; they do not measure Vision, image decoding, or total photo-scan time.

Reproduce from the repository root:

```sh
python3 scripts/tests/test_photo_grouping.py --benchmark
python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v
```

The benchmark verifies unchanged input hashes across each run. This run used:

| Source | SHA-256 |
| --- | --- |
| `SimilarityClustering.swift` | `d9d09ef73ac9afc126278e24545ea79ef953870faf8c4865a6541fd0115d0f8c` |
| `photo_grouping_checks.swift` | `4da8fe639014d1d5750b9ee782ab06a933eb913a053e988a3eab8b4599027fc8` |
| `photo_grouping_reference.swift` | `3554080837f96afb20b82b86ebb8734f2ecfd1c1aff4f2e5c4bf65b65cd3bb88` |

## Verification

- All 15 script tests passed, including the contact-matching regressions.
- All 729 four-item matrices over three distance levels and 528 deterministic
  randomized matrices match the original groups exactly. Additional cases cover
  tie orientation, stale candidates, threshold boundaries, finite negative
  distances, singleton handling, and distance-call count/order.
- NaN/infinity rejection and blocking larger merges containing invalid pairs
  have dedicated regression checks. The new safety check failed against the
  original implementation before the fix.
- The production photo-clustering source and its four supporting photo files
  pass type checking for `arm64-apple-ios17.0-simulator`, Swift language version 5.
  No simulator was booted. Full application builds and on-device timings were
  not performed.
- A separate read-only review found no correctness blocker. Integrated sources
  match the tested isolated worktree.
