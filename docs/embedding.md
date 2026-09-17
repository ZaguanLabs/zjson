# Embedding zjson

## Repair arbitrary UTF-8 text

```zsh
zjson_utf8_repair "$pasted_text"
clean_text="$REPLY"
```

`zjson_utf8_repair` takes exactly one string. It copies valid UTF-8 bytes
unchanged, including NUL and control characters. It replaces each malformed
prefix with the UTF-8 encoding of U+FFFD, retaining subsequent valid characters.
Its output is unquoted; use `zjson_quote` when a JSON string is required.

Return status is 0 for both valid and repaired input. Wrong argument count
returns 2 and clears `REPLY`. Both outcomes preserve the active tokenizer,
diagnostics, UTF-8 error scratch position, and decoder result variables.
The function follows the caller-local `REPLY` convention.

Repair behaves identically under C and UTF-8 locales. Encoding is always UTF-8;
the function does not transcode arbitrary legacy character sets.

## Temporarily use another parser context

```zsh
read_metadata() {
  if zjson_get "$1" /name; then
    metadata_name="$REPLY"
  else
    metadata_error="$ZJSON_ERROR"
    return 1
  fi
}

zjson_begin '[1,2]'
zjson_next
zjson_with_context read_metadata '{"name":"example"}'
# The outer current token is still 1. metadata_name is now example.
```

`zjson_with_context callback args...` invokes the callback directly in the
current shell under native Zsh option semantics. Arguments retain their exact
boundaries. It returns the callback's status unchanged; no callback returns 2.
The callback may itself invoke another context scope.

The scope localizes these variables using Zsh dynamic scope:

- `ZJSON_SOURCE`, `ZJSON_POS`, `ZJSON_LEN`, `ZJSON_TOKEN_START`;
- `ZJSON_TOKEN_TYPE`, `ZJSON_TOKEN_VALUE`;
- `ZJSON_ERROR`, `ZJSON_ERROR_CODE`, `ZJSON_ERROR_OFFSET`,
  `ZJSON_ERROR_LINE`, `ZJSON_ERROR_COLUMN`;
- internal UTF-8 error position and recursion depth. The nested document starts
  with its own full nesting budget.

`ZJSON_CHARS` is not copied on scope entry. The scope records the tokenizer
generation and the original source text; if a callback calls `zjson_begin`,
the outer byte array is rebuilt from that source when the callback returns or
unwinds. Callbacks that do not start another parser therefore avoid an
O(document-size) array copy.

Locals automatically restore the outer values on normal return, nonzero status,
and shell-error unwinding. This does not catch errors or prevent a callback from
terminating the process with `exit`. Scope entry inherits the current token;
start unrelated parsing with a whole-document API or `zjson_begin` as usual.

The following remain callback outputs after the scope exits:

- `REPLY` and `ZJSON_TYPE`;
- `ZJSON_OBJECT`, `ZJSON_OBJECT_TYPES`, `ZJSON_OBJECT_KEYS`, and
  `ZJSON_OBJECT_DUPLICATE_KEYS`;
- `ZJSON_ARRAY` and `ZJSON_ARRAY_TYPES`;
- `ZJSON_RESULTS` and `ZJSON_TYPES` from multi-Pointer lookup;
- application variables and other intentional callback side effects.

If an application needs to retain inner diagnostics, copy them to application
variables inside the callback, as in the example above. If decoder outputs also
need isolation, the caller can declare those public result variables local in
its own enclosing function.

Rebuilding after a nested begin costs time proportional to the outer source
size. That cost occurs only at explicit context boundaries, with no snapshot
work added to normal token advancement. A nested whole-document operation may
clear the global byte array after EOF; scope exit still restores the outer
tokenizer's byte array. This API is intended for nested synchronous parsing.
