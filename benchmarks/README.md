# Benchmarks

Run from the project root:

```sh
zsh -f benchmarks/run.zsh 5
LC_ALL=C zsh -f benchmarks/run.zsh 5
```

The optional argument is the number of samples per workload (1–999, default 5).
Output is TSV with minimum, median, and maximum wall-clock milliseconds per
operation. Comment lines identify Zsh, platform, locale, and an optional run label.
Redirect stdout to retain a result file.

The runner uses only Zsh builtins, parameter expansion, and the native `SECONDS`
timer. It empties `PATH` before sourcing the library. Fixture generation and one
warm-up call occur outside measurement. Samples are sorted as integer
microseconds before calculating the median. The Unicode fixtures use fixed
repetitions so both C and UTF-8 locales receive identical bytes.

Workloads cover increasing numbers of short strings and numbers, long ASCII and
UTF-8 strings, Unicode escapes, simple escapes, nested containers, object
decoding, raw capture, compact capture, and Pointer lookup. Escape-heavy fixtures
also check their decoded values before timing.
The 2026-09-17 run also measures object iteration, two-Pointer multi-get, and
encoding an already decoded object.

These are warm, in-process measurements. They measure neither startup time nor
peak memory use. CPU load, Zsh version, and hardware affect the results; compare
runs on the same machine. There are no timing thresholds in the correctness
suite.

To compare another trusted checkout with the same runner:

```sh
ZJSON_BENCH_ROOT=/path/to/other/zjson ZJSON_BENCH_LABEL=other-checkout \
  zsh -f benchmarks/run.zsh 5
```

`ZJSON_BENCH_ROOT` is sourced as library code. `ZJSON_BENCH_LABEL` labels the
output. Lookup is omitted when the selected library does not provide `zjson_get`.

## String-scanner comparison, 2026-09-12

Five samples after one warm-up, Zsh 5.9.2, Linux x86-64, C.UTF-8, on the same
local machine. The baseline was a temporary copy of the current library with
the original separate quote and backslash searches restored. Diagnostics and
Pointer code were identical, isolating the scanner change. Both runs used the
same benchmark runner and fixtures.

| Validation workload | Bytes | Original median | Updated median | Speedup |
| --- | ---: | ---: | ---: | ---: |
| 1,000 short strings | 4,001 | 97.263 ms | 69.198 ms | 1.41× |
| 2,000 short strings | 8,001 | 268.930 ms | 151.511 ms | 1.78× |
| 4,000 short strings | 16,001 | 812.762 ms | 356.766 ms | 2.28× |
| 4,000 numbers | 8,001 | 239.803 ms | 238.109 ms | 1.01× |
| One 100 KB ASCII string | 100,002 | 17.306 ms | 16.957 ms | 1.02× |

The scanner now locates the first quote or backslash together. For unescaped
strings, this stops at the closing quote. Previously, each string triggered a
search for a backslash through the remaining document, producing repeated scans
of the same suffix. Token-dense documents still have substantial traversal cost;
this optimization addresses that specific repeated search.

Complete distributions and the remaining workloads are in
[before.tsv](results/2026-09-12-before.tsv) and
[after.tsv](results/2026-09-12-after.tsv).

## Unicode and embedding review, 2026-09-12

The integration review identified strict UTF-8 validation and Unicode escape
decoding as expensive paths. Successful validation now avoids constructing a
repaired copy. An active UTF-8 locale uses Zsh's native multibyte validity
classes plus a Unicode upper-bound check; C and other locales use byte-pattern
validation. Malformed input still reaches the established scanner for exact
error offsets and repair semantics. Strict validation remains mandatory.

Escaped Unicode uses a constant byte lookup table for locale-independent
encoding and a per-string code-point cache. After 256 distinct entries, the
cache is disabled to avoid repeated failed lookups on varied text. The
comparison includes a varied-escape workload to exercise this case.

Seven rounds of separate processes, alternating implementation order, pinned
to CPU 2, Zsh 5.9.2, Linux x86-64, C.UTF-8. Each workload has one warm-up and then
two or five timed iterations per process. Values below are medians of the seven
process averages, in milliseconds. The original parser is zcoder `ec78880`;
the zjson release is `3067829` (0.1.0). Reference source was copied into temporary
directories without compiled wordcode, and each process used the same runner.

| Workload | Original zcoder | zjson 0.1.0 | Updated zjson | Speedup vs 0.1.0 |
| --- | ---: | ---: | ---: | ---: |
| ASCII string, 100 KB | 16.228 | 16.488 | 16.605 | 0.99× |
| 4,000 short strings | 770.115 | 354.414 | 358.838 | 0.99× |
| 25,000 Unicode code points, 75 KB | 7.755 | 44.748 | 15.364 | 2.91× |
| Quote the same Unicode text | 41.950 | 38.476 | 9.652 | 3.99× |
| 2,000 repeated `\u00e9` escapes | 60.986 | 85.790 | 45.910 | 1.87× |
| 2,000 distinct Unicode escapes | 60.893 | 87.397 | 76.056 | 1.15× |

ASCII and dense-string medians changed by about 1% in this run. Raw Unicode
parsing remains slower than the original parser, which does not perform strict
input UTF-8 validation and uses a character array instead of zjson's byte array.
The results establish improvements against zjson's previous correctness
contract; they do not equate the validation work of the two parsers.

All 126 measurements are in [unicode.tsv](results/2026-09-12-unicode.tsv).
The standalone comparison runner uses only Zsh:

```sh
zsh -f benchmarks/compare.zsh /path/to/zjson/zjson.zsh zjson
zsh -f benchmarks/compare.zsh /path/to/original/lib/json.zsh json
```

The trusted entry file must provide `PREFIX_begin`, `PREFIX_discard_value`,
`PREFIX_quote`, and `PREFIX_TOKEN_TYPE` (uppercase variable prefix). The accepted
function prefixes are `json` and `zjson`. No application checkout is needed for
normal tests or benchmarks; an original parser is supplied only for an explicit
comparison. CPU pinning in the recorded experiment was provided by the external
measurement driver, outside the pure Zsh runner.

## Correctness and API additions, 2026-09-17

Nine samples, Zsh 5.9.2, Linux x86_64, C.UTF-8, on the same local machine. The
full distribution is in
[correctness-and-apis.tsv](results/2026-09-17-correctness-and-apis.tsv).

| Workload | Median |
| --- | ---: |
| 4,000 numbers, validation | 230.706 ms |
| 4,000 short strings, validation | 348.417 ms |
| Envelope, object decode | 52.586 ms |
| Envelope, object callback iteration | 52.375 ms |
| Envelope, two-Pointer multi-get | 59.231 ms |
| Envelope, encode decoded object | 52.987 ms |

The recorded 2026-09-12 five-sample medians for 4,000 numbers and strings were
238.109 ms and 356.766 ms. These runs are not a controlled alternating A/B
experiment, but the direction is consistent with removing redundant private
`emulate` scopes on scanner helpers. Compact capture remains close to its
previous cost on the small envelope while now joining an array of parts, which
avoids repeated full-output concatenation on large containers.

The full byte-array representation was retained, so no peak-memory column was
added. Successful whole-document operations now clear `ZJSON_CHARS` at EOF, but
Zsh has no portable per-operation peak-RSS primitive. Token APIs intentionally
retain the array until the next `zjson_begin`.
