# zjson

JSON parsing and string encoding in **100% pure Zsh**.

Source the library and work with native Zsh scalars, arrays, and associative
arrays. No jq, Python, external commands, third-party modules, or build step is
required. The library uses Zsh builtins and parameter expansion only.

This is the first standalone extraction of the JSON core from
[`zcoder.zsh`](docs/origin.md), with a new `zjson_` API. Version 0.2.0 is a
development release; the API may evolve. **Zsh 5.8 and newer are supported.**
The release test matrix runs actual Zsh 5.8 and 5.9.2 on Linux, in both C and
C.UTF-8 locales, with the correctness suite's command path empty.

## Quick start

Copy this directory into your project, keeping `zjson.zsh` beside `lib/`, then
source the entry point from Zsh:

```zsh
source /path/to/zjson/zjson.zsh

if zjson_parse_object '{"name":"zjson","enabled":true,"ports":[8080,8081]}'; then
  print -r -- "${ZJSON_OBJECT[name]}"          # zjson
  print -r -- "${ZJSON_OBJECT_TYPES[enabled]}" # true

  zjson_parse_array "${ZJSON_OBJECT[ports]}"
  print -rl -- "${ZJSON_ARRAY[@]}"            # one port per line
else
  print -u2 -r -- "$ZJSON_ERROR"
fi

zjson_quote $'hello\nworld'
print -r -- "$REPLY"                         # "hello\nworld"

zjson_validate '{"valid":true}'               # status 0
```

Call functions directly to retain their result variables in the current shell.
They do not print results or diagnostics. Check the return status before reading
output; copy results before another call overwrites them.

Run the self-contained example with `zsh -f examples/basic.zsh`.

## API

| Function | Result |
| --- | --- |
| `zjson_validate "$json"` | Validate exactly one complete JSON value. |
| `zjson_quote "$text"` | Encode a string, including surrounding quotes, into `REPLY`. |
| `zjson_utf8_repair "$text"` | Return repaired, unquoted UTF-8 in `REPLY`, preserving parser state and diagnostics. |
| `zjson_parse "$json"` | Return the root in `REPLY` and `ZJSON_TYPE`. |
| `zjson_parse_object "$json"` | Populate `ZJSON_OBJECT` and `ZJSON_OBJECT_TYPES`. |
| `zjson_parse_array "$json"` | Populate `ZJSON_ARRAY` and `ZJSON_ARRAY_TYPES`. |
| `zjson_get "$json" "$pointer"` | Resolve a JSON Pointer into `REPLY` and `ZJSON_TYPE`. |
| `zjson_get_multi "$json" "$pointer"...` | Resolve multiple Pointers in one pass into `ZJSON_RESULTS` and `ZJSON_TYPES`. |
| `zjson_each_object "$json" callback args...` | Invoke `callback key value type args...` for each object member. |
| `zjson_each_array "$json" callback args...` | Invoke `callback index value type args...` for each array element. |
| `zjson_encode_value "$value" "$type"` | Encode one typed value into `REPLY`. |
| `zjson_encode_array` | Encode `ZJSON_ARRAY` and `ZJSON_ARRAY_TYPES` into `REPLY`. |
| `zjson_encode_object` | Encode `ZJSON_OBJECT`, `ZJSON_OBJECT_TYPES`, and `ZJSON_OBJECT_KEYS` into `REPLY`. |
| `zjson_begin "$json"` | Initialize the tokenizer and read the first token. |
| `zjson_next` | Advance one token. |
| `zjson_discard_value` | Validate and consume the value at the current token. |
| `zjson_skip_value` | Alias function for `zjson_discard_value`. |
| `zjson_capture_raw_value` | Consume a value and put its original JSON text in `REPLY`. |
| `zjson_capture_value` | Consume a value and put compact, re-encoded JSON in `REPLY`. |
| `zjson_with_context callback args...` | Run a callback in the same shell and restore the outer tokenizer and diagnostics. |

Whole-document functions and `zjson_quote` take exactly one argument.
`zjson_get` takes JSON and one Pointer; `zjson_get_multi` takes JSON and one or
more Pointers. Iteration functions take JSON, a callback name, and optional
callback arguments. Encode functions take either a value and type tag or no
arguments and read their published decoder results. Status is `0` for success,
`1` for invalid JSON, or `2` for incorrect arguments. Pointer lookup also uses
`2` for invalid Pointer syntax and `3` when a valid Pointer cannot resolve a
value.
`ZJSON_ERROR` contains a diagnostic on failure. Object/array results and lookup
results are published only after the entire document succeeds; their respective
outputs are cleared on failure.
`zjson_utf8_repair` returns 0 even when it repairs malformed bytes, or 2 for
incorrect argument count; it preserves diagnostics in either case.
`zjson_with_context` returns its callback's status, or 2 if no callback is given.

### Values and types

Strings are decoded; numbers retain their exact text without shell arithmetic or
floating-point conversion. Booleans and null are the strings `true`, `false`, and
`null`. Nested containers retain their original JSON text so you can decode them
in a subsequent call.

Types are `string`, `number`, `true`, `false`, `null`, `{` (object), and `[` (array).
This distinguishes `"null"` from `null`, and `"123"` from `123`.

Arrays use native Zsh indexing (starting at 1). Objects support empty keys and
literal shell metacharacters; duplicate keys use the last value.
`ZJSON_OBJECT_KEYS` preserves the first source order of unique keys, while
`ZJSON_OBJECT_DUPLICATE_KEYS` lists repeated source keys in order. Check key
existence with `${+ZJSON_OBJECT[key]}` to distinguish a missing key from an empty
string.

### Encoding

`zjson_encode_value` requires the existing type tags: `string`, `number`,
`true`, `false`, `null`, `{`, and `[`. Numbers keep their spelling and are never
converted to arithmetic. String encoding follows the `zjson_quote` policy and
repairs malformed UTF-8. Container values must already be valid JSON text and
are retained as source text rather than normalized.

`zjson_encode_array` and `zjson_encode_object` encode the published decoder
results. Object encoding uses `ZJSON_OBJECT_KEYS` when it matches the decoded
object, so a round trip retains first-seen source order and last duplicate
values. Manually constructed objects without that array use Zsh's deterministic
sorted key expansion.

```zsh
zjson_parse_object '{"name":"zjson","enabled":true,"ports":[8080,8081]}'
zjson_encode_object
print -r -- "$REPLY" # {"name":"zjson","enabled":true,"ports":[8080,8081]}
```

### Nested lookup

```zsh
json='{"servers":[{"host":"localhost","port":8080}],"token":null}'
if zjson_get "$json" /servers/0/host; then
  print -r -- "$REPLY ($ZJSON_TYPE)"           # localhost (string)
fi

zjson_get "$json" /token                     # status 0, REPLY=null, type=null
zjson_get "$json" /missing                   # status 3, empty result and type
```

`zjson_get` accepts the [RFC 6901 JSON Pointer string form](https://www.rfc-editor.org/rfc/rfc6901):

- `''` selects the root; `/` selects an object member with an empty key.
- `/servers/0/host` selects the first server's host. Pointer array indexes start
  at **0**, while native `ZJSON_ARRAY` indexes start at 1.
- Inside a key, `~1` represents `/` and `~0` represents `~`. For example,
  `/a~1b` selects `a/b`, and `/~01` selects the literal key `~1`.
- Keys are literal UTF-8 strings, with no globbing, shell evaluation, or Unicode
  normalization. Numeric object keys are literal too.
- A referenced duplicate member is ambiguous and fails. Duplicates elsewhere
  remain permitted; selecting a container retains its original members.
- Array indexes must be `0` or decimal digits without leading zeros. `-` refers
  to the nonexistent position after the last element and returns status 3.
- URI fragments such as `#/servers/0` are not accepted. Percent sequences in
  keys are literal; callers pass the already decoded Pointer string.

Strings are decoded, numbers retain their spelling, and containers retain their
source text. The result type uses the same vocabulary as the object/array APIs.
Lookup validates skipped values and requires EOF before publishing results.
Malformed JSON takes precedence over a missing or ambiguous value. Pointer
syntax is checked before parsing the document.

`zjson_get_multi` follows the same Pointer syntax and resolution rules. It
tokenizes and validates the document once, discarding branches that cannot
match any requested Pointer. Results and types are published in argument order
only when every Pointer resolves; any resolution failure clears both arrays and
returns `3`. The diagnostic describes the first unresolved Pointer in argument
order.

### Iteration

The callback APIs do not build the full object or array result. Object
callbacks receive `key`, decoded scalar or raw container `value`, and `type`.
Array callbacks receive the native Zsh `index` (starting at 1), `value`, and
`type`; optional trailing arguments are passed through. Success requires a
complete valid document. A nonzero callback status is returned immediately and
may leave the tokenizer positioned after that member.

```zsh
show_member() { print -r -- "$1 = $2 ($3)"; }
zjson_each_object '{"name":"zjson","port":8080}' show_member
```

Callbacks run through `zjson_with_context`, so they may parse unrelated JSON
without destroying the outer iteration state. Callback arguments are data and
are never evaluated.

### Structured diagnostics

Existing readable errors remain in `ZJSON_ERROR`. Callers can also inspect:

| Variable | Meaning |
| --- | --- |
| `ZJSON_ERROR_CODE` | Stable machine-readable error code. Empty on success. |
| `ZJSON_ERROR_OFFSET` | 1-based byte offset in JSON, including `length + 1` for EOF. |
| `ZJSON_ERROR_LINE` | 1-based line number; LF starts a new line. |
| `ZJSON_ERROR_COLUMN` | 1-based **byte** column, consistent across locales. |

Argument and Pointer-syntax errors have no JSON location; all three location
fields are zero. Resolution failures point to the container or scalar where
lookup failed. Line and column are computed only on failure. New document or
quote operations reset diagnostics; advancing a failed tokenizer preserves them.
See [diagnostic codes](docs/diagnostics.md) for the complete contract.

### Embedding and text repair

`zjson_utf8_repair "$text"` is useful for pasted text and cached response bodies.
It preserves valid bytes, including NUL, and replaces malformed UTF-8 prefixes
with U+FFFD while retaining later valid characters. Its output is unquoted.
Only `REPLY` changes; tokenizer state and active diagnostics are preserved.

Use `zjson_with_context` when an operation needs to parse unrelated JSON while
an outer tokenizer is active:

```zsh
zjson_begin '[1,2]'
zjson_next                                  # outer token: 1
zjson_with_context zjson_get '{"name":"inner"}' /name
print -r -- "$REPLY"                        # inner
zjson_next                                  # outer token: comma
```

The callback runs in the same shell. Source, byte array, cursor, current token,
diagnostics, and parser scratch state are restored on return or error unwinding.
`REPLY`, `ZJSON_TYPE`, and object/array decoder results remain callback outputs.
Application variable updates also remain visible. Nested scopes are supported;
state copying occurs only at these explicit boundaries. See the full
[embedding contract](docs/embedding.md).

### Token access

`ZJSON_TOKEN_TYPE` contains a value type, punctuation (`{ } [ ] : ,`), or `eof`.
`ZJSON_TOKEN_VALUE` contains decoded string text or the literal token text.
`ZJSON_TOKEN_START` is the token's 1-based **byte** offset; `ZJSON_POS` is the
scanner cursor. Tokenization alone does not validate container grammar or require
EOF. Use `zjson_validate` for complete validation.

The consume/capture functions leave the next token current. Raw capture excludes
surrounding whitespace and preserves internal whitespace, number spelling, and
escape spelling. Compact capture removes structural whitespace and re-encodes
strings; it is not a canonicalization algorithm.

## Encoding and limits

- Input must be UTF-8. Parsing rejects malformed UTF-8, a leading BOM, unescaped
  controls, invalid escapes and numbers, trailing commas, and trailing content.
- Unicode escapes decode to UTF-8 in both UTF-8 and C locales. Paired UTF-16
  surrogates decode together; unpaired surrogates become U+FFFD, preserving the
  original parser's recovery policy.
- Strict input validation uses native multibyte character classes when an active
  UTF-8 locale is available, plus explicit rejection of overlong encodings,
  surrogates, and values above U+10FFFF. Other locales use a byte grammar. Both
  paths enforce the same encoding rules.
- String encoding replaces malformed UTF-8 prefixes with U+FFFD and escapes all
  JSON control characters. It is a text encoder, not a lossless binary codec.
- Zsh scalars can retain NUL; the library preserves it through `\u0000`. External
  process arguments cannot carry NUL.
- Container nesting is limited to 128. Parsing holds the complete source and a
  byte array in memory. It is intended for shell-sized documents, not streaming
  large datasets; input size has no separate hard cap. Successful
  whole-document operations release the byte array after reaching EOF; the
  tokenizer is already unusable until the next `zjson_begin`.
- There is one shared tokenizer state. Calls preserve shell options and locale,
  but replace the documented `ZJSON_*` results. Reserve `ZJSON_*`, `zjson_*`, and
  `_zjson_*` names for the library. `REPLY` follows Zsh's caller-local output
  convention. Use `zjson_with_context` for nested operations. The tokenizer is
  not incremental, and simultaneous independent parser objects are not provided.

## Development

```sh
zsh -f tests/run.zsh
LC_ALL=C zsh -f tests/run.zsh
zsh -f -n zjson.zsh
zsh -f -n lib/zjson.zsh
zsh -f -n lib/pointer.zsh
zsh -f -n lib/encode.zsh
zsh -f tests/matrix.zsh /path/to/zsh-5.8 /path/to/zsh-5.9.2
zsh -f benchmarks/run.zsh 5
```

The test runner empties `PATH` before loading the library and running every
assertion. Tests cover valid and malformed syntax, scalar types, nested values,
control characters, Unicode and malformed UTF-8, exact source capture, nesting
limits, shell metacharacters, and caller option/alias isolation.
Pointer examples, generic parsing, multi-Pointer lookup, source-order encoding,
callbacks, diagnostic locations, and deterministic mixed-escape strings extend
the same dependency-free suite. See [benchmark methodology and results](benchmarks/README.md).
The [CI workflow](.github/workflows/test.yml) provisions versioned Zsh
interpreters and runs the matrix on pushes, pull requests, and releases.
Provisioning the test interpreters uses the runner's build tools; installing or
using zjson itself requires no compilation. See [compatibility testing](docs/compatibility.md).

Licensed under [Apache-2.0](LICENSE). See [origin and extraction notes](docs/origin.md).
