# Origin and extraction

The initial parser and encoder were extracted from the local `zcoder.zsh`
project's `lib/json.zsh` on 2026-09-12. The most recent source commit touching
that file was:

```text
0bd2c764bc432932e47ea86d83fa8e202a397ab4
Release v0.13.1: repair invalid UTF-8 in transcript JSON
```

The original project and this repository use the Apache License, Version 2.0.
The UTF-8 regression cases in `tests/utf8.zsh` are adapted from the original
`tests/json_utf8.zsh`. Control-character and malformed-input cases also draw on
`tests/hardening_json_tools.zsh`.

The extraction retains the original array-based tokenizer, optimized string
scanners, split/join string encoder, bounded UTF-8 repair, and recursive value
walkers. Public `json_*` functions became `zjson_*`, internal `_json_*` helpers
became `_zjson_*`, and parser state moved from `JSON_*` to `ZJSON_*`.

Changes for standalone use:

- Removed Ollama response, model, and tool-call codecs and their global state.
- Added whole-document validation and general object/array decoding. The old
  application-specific flat argument decoder is not part of this API.
- Added option-safe loading and function-local Zsh emulation.
- Made scanning byte-based and Unicode escape encoding locale-independent.
- Added UTF-8 validation at the input boundary; the original tokenizer accepted
  malformed raw UTF-8 even though its encoder repaired it.
- Replaced regular-expression number matching with native Zsh patterns.
- Limited container recursion to 128 and made token errors persist until a new
  operation starts.
- Added atomic object/array results and a pure Zsh test runner.

The original `zcoder.zsh` checkout is unchanged. Migrating its consumers to this
library is a separate integration step; this repository has no runtime link to
that checkout.
