# Diagnostic contract

All public parser errors populate `ZJSON_ERROR`, `ZJSON_ERROR_CODE`,
`ZJSON_ERROR_OFFSET`, `ZJSON_ERROR_LINE`, and `ZJSON_ERROR_COLUMN`. Human-readable
wording may improve over time; use the codes and return status in scripts.

Offsets and columns count bytes, not Unicode characters. This keeps diagnostics
identical under UTF-8 and C locales. LF advances the line counter; CR counts as a
byte, so CRLF input starts its next line immediately after LF. Tabs count as one
byte. EOF is the position immediately after the input. Zero means no JSON source
location applies.

| Code | Status | Meaning / location |
| --- | --- | --- |
| `usage` | 2 | Wrong argument count; no JSON location. |
| `invalid_utf8` | 1 | Start of the first malformed UTF-8 prefix. |
| `unexpected_character` | 1 | Unexpected byte outside a string. |
| `unescaped_control` | 1 | Literal U+0000–U+001F byte in a string. |
| `invalid_escape` | 1 | Unsupported escape letter after a backslash. |
| `invalid_unicode_escape` | 1 | Start of the four-digit group required after `\u`. |
| `unterminated_string` | 1 | Missing closing quote; EOF. |
| `unterminated_escape` | 1 | Backslash with no following escape letter; EOF. |
| `invalid_number` | 1 | Start of a malformed numeric token. |
| `invalid_literal` | 1 | Start of a malformed `true`, `false`, or `null` token. |
| `expected_value` | 1 | Unexpected token or EOF where a value was required. |
| `expected_key` | 1 | Unexpected token or EOF where a quoted object key was required. |
| `expected_colon` | 1 | Unexpected token or EOF after an object key. |
| `expected_array_separator` | 1 | Unexpected token or EOF where `,` or `]` was required. |
| `expected_object_separator` | 1 | Unexpected token or EOF where `,` or `}` was required. |
| `expected_object` | 1 | Root token was not an object for `zjson_parse_object`. |
| `expected_array` | 1 | Root token was not an array for `zjson_parse_array`. |
| `trailing_comma` | 1 | Closing bracket/brace immediately after a comma. |
| `trailing_content` | 1 | First extra token after a complete root value. |
| `nesting_limit` | 1 | Opening bracket/brace of the 129th nested container. |
| `pointer_syntax` | 2 | Invalid UTF-8, prefix, or `~` escape in a Pointer; no JSON location. |
| `pointer_not_found` | 3 | Missing member/index, including array `-`; containing object/array. |
| `pointer_index` | 3 | Pointer segment is not a permitted array index; containing array. |
| `pointer_type` | 3 | Attempt to descend into a scalar; scalar token. |
| `pointer_ambiguous` | 3 | Referenced member occurs more than once; containing object. |

`usage` also covers encoder type/result mismatches, such as an unknown type tag,
`true` value text paired with a `false` type, or inconsistent array and type
lengths. Invalid nested JSON supplied to an encoder uses the normal JSON status
of `1` and the corresponding JSON diagnostic code.

Tokenization errors take precedence over grammar checks that require that token.
For example, `{x:1}` reports `unexpected_character`, while `{1:1}` reports
`expected_key`. An unterminated string may report EOF before inspecting controls
in its final run. Diagnostic positions describe the detected error, not a
guarantee to identify the earliest possible error in a multiply malformed input.
Tokenization itself does not reject `}` or `]` after a comma; value-consuming
functions report `trailing_comma` at that closing token.

Lookup checks Pointer syntax first. Once JSON parsing starts, the complete
document must be valid before a result or resolution error is returned. A match,
miss, or ambiguous member cannot hide malformed JSON later in the document.

New operations reset diagnostics. Low-level tokenizer calls following a failure
return nonzero and preserve the diagnostic until another operation starts.
Existing object decoding continues to use the last duplicate key; Pointer
lookup rejects a duplicate only when that member is part of the requested path.
`zjson_get_multi` reports the first unresolved Pointer in argument order after
the complete document is valid. Its result arrays are cleared on any status `3`.

Iteration APIs return a nonzero callback status unchanged and do not replace an
already successful parser diagnostic with a callback error. Parser failures use
their normal diagnostic contract.

Successful whole-document operations release `ZJSON_CHARS` after EOF. This does
not change diagnostics or `ZJSON_SOURCE`, but the shared tokenizer must be
reinitialized before another token operation.
