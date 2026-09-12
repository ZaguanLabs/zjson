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
