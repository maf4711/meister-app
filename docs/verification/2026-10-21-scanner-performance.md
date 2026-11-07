# Follow-up log review and macOS scanner performance

## Log coverage

Re-read all 26 local log files found in the checkout, decoding compressed Xcode
activity logs, and all 16 available CI logs, including the successful v1.1.3
[run 39606288469](https://github.com/maf4711/meister-app/actions/runs/39606288469).
There are 17 historical CI runs; the May 31 failed run still has expired raw
logs. Its retained annotation was covered in the [earlier audit](2026-10-21-log-audit.md).
Seven local activity logs are empty. No matching Meister crash reports were
found, and a fresh one-day unified-log query returned zero app records.

The available logs contain the previously documented signing, upload, and
toolchain failures; the latest CI log adds no failure. They do not contain a
runtime profile establishing a current scanner bottleneck. The improvements
below were found by source inspection and measured on synthetic files.

The reviewed-log inventory is `/private/tmp/meister-log-followup-20261021.json`
(SHA-256 `f36170844872e389e30b709758192879bcef91e1e9321930c106653f8d538726`).
It records file sizes, hashes, and diagnostic counts without copying secret
values into this report.

## Changes

`DuplicateFinder` previously read every byte of every file sharing a size.
For files larger than 64 KiB it now hashes only that prefix first, discards
singleton prefix groups, and fully hashes the remaining candidates. Every
reported duplicate still has a full SHA-256 digest. Files of at most 64 KiB
keep their single-pass path. Both stages retain the four-worker limit and
discard results when the parent scan is cancelled.

`LargeFilesScanner` no longer requests unused attribute/value-count aggregation
from Spotlight. It reserves output capacity and reads results by index without
materializing `q.results`. Apple's installed SDK explicitly recommends indexed
access for performance: `Foundation.framework/Headers/NSMetadata.h`, lines
106–125. The unused aggregation is documented at lines 130–133 and 229–231.
Query ordering and the existing age-filter/lifecycle fixes are preserved.

## Measurements

The frozen reference includes the streaming enumeration and allocation fixes
already present in the working tree before this task. Thus the comparison
isolates the new prefix filter, rather than attributing earlier work to it.
Both implementations compile with `swiftc -swift-version 5 -O`; timings use
unchanged production source, with no read instrumentation. Each case creates
16 temporary 8 MiB files, verifies matching results, warms both paths, then
alternates their order over five runs and reports the median.

| Workload | Baseline | Candidate | Relative runtime |
| --- | ---: | ---: | ---: |
| Distinct prefixes | 13.880 ms | 0.847 ms | 16.39× faster |
| Four identical files mixed with twelve distinct files | 14.118 ms | 4.285 ms | 3.29× faster |
| Same prefix, different tails | 14.169 ms | 14.609 ms | 3.1% slower |
| All files identical | 14.177 ms | 14.749 ms | 4.0% slower |

These are cached synthetic scans on this Mac, including traversal and hashing;
they are not whole-app timings or cold physical-disk measurements. When the
prefix cannot eliminate files, it adds 64 KiB per file and another open/read
pass. No reduction in whole-process peak memory is claimed. Spotlight changes
were compiled and reviewed but not benchmarked against the user's index.

Separate instrumented tests count bytes actually returned by the stream. Eight
distinct 2 MiB files drop from 16 MiB read to 512 KiB, a 96.875% reduction.
Adding a ninth file that duplicates one existing file requires only the nine
prefixes plus two full-file reads. Files with matching prefixes and different
tails are not reported as duplicates.

## Validation and source identity

The isolated candidate passed all 32 Python/native-helper tests and 16 Swift
package tests. The scanner checks compile both actual macOS scanner sources.
New coverage includes 0/1/65,535/65,536/65,537-byte boundaries, full digest
identity, duplicate membership, repeated roots, differing tails, missing-file
reads, and cancellation before scanning and during both hashing stages.

Independent review found a scheduling race in the test-only read counter. The
counter now serializes the cancellation callback with recorded reads; the
focused regression passed again after that correction. The final benchmark
was rerun against the corrected fixture. Production files were copied back
only after confirming the original working-tree edits had not changed, and
`git diff --check` passes. No application was launched, user files scanned,
or release published during this follow-up.

| Input | SHA-256 |
| --- | --- |
| `MeisterMacOS/Duplicates/DuplicateFinder.swift` | `590d340d9152492c6d6883d9af65875de601e663391c4d1a25e482c3c7e07476` |
| `MeisterMacOS/LargeFiles/LargeFilesScanner.swift` | `4bf34d8dbdfddfc67358e919a6e9c2905ed0c6813b79c28056c0cf1dabad7dcf` |
| `scripts/tests/fixtures/duplicate_finder_reference.swift` | `3ad8863e4ff6bcbc8ee3f16b0549262ac5284bfe3b236676081521fd26803b56` |
| `scripts/tests/fixtures/duplicate_performance_checks.swift` | `87acdf200172624137f833ea1634b8cf0d77c977205969c44bcd34b003e0ed31` |
| `scripts/tests/test_duplicate_performance.py` | `f2fe8d3a92ce58149557a647a4c0e11c5365b31db614d4723e19e9eccbf1a859` |

Reproduce:

```sh
python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v
swift test --package-path Packages/MeisterKit
python3 scripts/tests/test_duplicate_performance.py --benchmark
```

Local evidence: `/private/tmp/meister-scan-tests-20261021.log`,
`/private/tmp/meister-scan-swift-20261021.log`, and
`/private/tmp/meister-scan-benchmarks-20261021.log`.
