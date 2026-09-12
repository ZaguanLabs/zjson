# SPDX-License-Identifier: Apache-2.0
# Extracted and adapted from zcoder.zsh/lib/json.zsh; see docs/origin.md.
# Internal implementation. Source ../zjson.zsh for option-safe loading.

typeset -g ZJSON_VERSION=0.1.0
typeset -g ZJSON_SOURCE="" ZJSON_TOKEN_TYPE="" ZJSON_TOKEN_VALUE="" ZJSON_ERROR=""
typeset -ga ZJSON_CHARS=() ZJSON_ARRAY=() ZJSON_ARRAY_TYPES=()
typeset -gA ZJSON_OBJECT=() ZJSON_OBJECT_TYPES=()
typeset -gi ZJSON_POS=1 ZJSON_LEN=0 ZJSON_TOKEN_START=1
typeset -g ZJSON_ERROR_CODE="" ZJSON_TYPE=""
typeset -gi ZJSON_ERROR_OFFSET=0 ZJSON_ERROR_LINE=0 ZJSON_ERROR_COLUMN=0

# Called only on failure. Locations are 1-based bytes; LF starts a new line.
# Offset zero denotes a usage/pointer error without a JSON source location.
_zjson_fail() {
  emulate -L zsh
  setopt nomultibyte
  local -i offset=${3:-$ZJSON_TOKEN_START} length=${#ZJSON_SOURCE}
  local prefix=""
  local -a lines=()
  ZJSON_ERROR_CODE="$1"
  ZJSON_ERROR="$2"
  ZJSON_ERROR_OFFSET=0
  ZJSON_ERROR_LINE=0
  ZJSON_ERROR_COLUMN=0
  if (( offset > 0 )); then
    (( offset > length + 1 )) && offset=$(( length + 1 ))
    ZJSON_ERROR_OFFSET=$offset
    ZJSON_ERROR_LINE=1
    ZJSON_ERROR_COLUMN=1
    if (( offset > 1 )); then
      prefix="${ZJSON_SOURCE[1,offset-1]}"
      lines=( "${(@ps:\n:)prefix}" )
      ZJSON_ERROR_LINE=${#lines}
      ZJSON_ERROR_COLUMN=$(( ${#lines[-1]} + 1 ))
    fi
  fi
  return ${4:-1}
}

_zjson_control_error() {
  emulate -L zsh
  setopt nomultibyte
  local pattern=$'[\0-\37]'
  _zjson_fail unescaped_control "unescaped JSON control character" \
    "${ZJSON_CHARS[(ib:ZJSON_POS:)$pattern]}"
}

# Escape the remaining JSON controls with at most 32 native split/join passes.
# Dynamic delimiters preserve empty fields; no scalar character indexing or
# per-match string replacement is needed even for control-heavy Unicode text.
_zjson_quote_controls() {
  emulate -L zsh
  setopt nomultibyte
  local output="$1" ch="" encoded="" escaped=""
  local -i code
  for (( code=0; code<32; code++ )); do
    printf -v encoded '\\x%02x' "$code"
    printf -v ch '%b' "$encoded"
    [[ "$output" == *"$ch"* ]] || continue
    printf -v escaped '\\u%04x' "$code"
    output="${(pj:$escaped:)${(@ps:$ch:)output}}"
  done
  REPLY="$output"
}

zjson_quote() {
  emulate -L zsh
  setopt nomultibyte
  ZJSON_ERROR=""
  ZJSON_ERROR_CODE=""
  ZJSON_ERROR_OFFSET=0 ZJSON_ERROR_LINE=0 ZJSON_ERROR_COLUMN=0
  REPLY=""
  (( $# == 1 )) || { _zjson_fail usage "expected one string argument" 0 2; return 2; }
  local input="$1" output=""

  # Parameter substitution performs the common JSON string encoding in native
  # Zsh internals. Building the result one character at a time is quadratic
  # for large resumed histories and can pin a core during compaction.
  # ${//} pays a rebuild per match, so the frequent newline and tab escapes use
  # a C-speed split+join instead; quoted (@s) splitting keeps empty fields, so
  # the round trip is exact.
  _zjson_utf8_text "$input"
  output="$REPLY"
  [[ "$output" == *'\'* ]] && output="${(pj:\\\\:)${(@ps:\\:)output}}"
  [[ "$output" == *'"'* ]] && output="${(pj:\\\":)${(@ps:\":)output}}"
  [[ "$output" == *$'\b'* ]] && output="${(pj:\\b:)${(@ps:\b:)output}}"
  [[ "$output" == *$'\f'* ]] && output="${(pj:\\f:)${(@ps:\f:)output}}"
  [[ "$output" == *$'\r'* ]] && output="${(pj:\\r:)${(@ps:\r:)output}}"
  [[ "$output" == *$'\n'* ]] && output="${(pj:\\n:)${(@ps:\n:)output}}"
  [[ "$output" == *$'\t'* ]] && output="${(pj:\\t:)${(@ps:\t:)output}}"

  # JSON forbids only U+0000 through U+001F, not DEL or other characters
  # that a locale may classify as controls.
  if [[ "$output" == *[$'\0'-$'\37']* ]]; then
    _zjson_quote_controls "$output"
    output="$REPLY"
  fi
  REPLY="\"${output}\""
}

zjson_begin() {
  emulate -L zsh
  setopt nomultibyte
  ZJSON_ERROR=""
  ZJSON_ERROR_CODE=""
  ZJSON_ERROR_OFFSET=0 ZJSON_ERROR_LINE=0 ZJSON_ERROR_COLUMN=0
  ZJSON_SOURCE=""
  ZJSON_TOKEN_TYPE=""
  ZJSON_TOKEN_VALUE=""
  ZJSON_CHARS=()
  ZJSON_POS=1
  ZJSON_LEN=0
  ZJSON_TOKEN_START=1
  (( $# == 1 )) || { _zjson_fail usage "expected one JSON argument" 0 2; return 2; }
  local REPLY=""
  ZJSON_SOURCE="$1"
  _zjson_utf8_validate "$1" || { _zjson_fail invalid_utf8 "invalid UTF-8 in JSON input" "$_zjson_utf8_error"; return 1; }
  # Tokenize over a byte array: Zsh scalar subscripting with multibyte enabled
  # walks the string from its start on every access. Array indexing and pattern
  # searches over the array run at C speed.
  if [[ -n "$1" ]]; then
    ZJSON_CHARS=("${(@s::)1}")
  else
    ZJSON_CHARS=()
  fi
  ZJSON_POS=1
  ZJSON_LEN=${#ZJSON_CHARS}
  ZJSON_TOKEN_TYPE=""
  ZJSON_TOKEN_VALUE=""
  ZJSON_ERROR=""
  zjson_next
}

# Decode a string token whose opening quote has been consumed. Strings without
# escapes copy in one slice; strings with only the simple two-character escapes
# decode with C-speed split+join transforms. Anything else — \u escapes,
# invalid escapes, unterminated input — falls back to the exact
# character-by-character scanner so every error and edge case is unchanged.
_zjson_scan_string() {
  emulate -L zsh
  setopt nomultibyte
  local raw="" part="" quote_char='"'
  local -a parts=() decoded_parts=()
  local -i quote before
  # Stop at the first quote OR backslash. Searching the entire remaining
  # document for an absent backslash made arrays of short strings quadratic.
  quote=${ZJSON_CHARS[(ib:ZJSON_POS:)[\"\\\\]]}
  if (( quote > ZJSON_LEN )); then
    _zjson_scan_string_slow
    return
  fi
  if [[ "${ZJSON_CHARS[quote]}" == '"' ]]; then
    (( quote > ZJSON_POS )) && ZJSON_TOKEN_VALUE="${(j::)ZJSON_CHARS[ZJSON_POS,quote-1]}" || ZJSON_TOKEN_VALUE=""
    [[ "$ZJSON_TOKEN_VALUE" != *[$'\0'-$'\37']* ]] || { _zjson_control_error; return 1; }
    ZJSON_TOKEN_TYPE="string"
    ZJSON_POS=$(( quote + 1 ))
    return 0
  fi
  quote=${ZJSON_CHARS[(ib:quote+1:)$quote_char]}
  if (( quote > ZJSON_LEN )); then
    _zjson_scan_string_slow
    return
  fi
  # The closing quote is the next one preceded by an even run of backslashes.
  while true; do
    before=$(( quote - 1 ))
    while (( before >= ZJSON_POS )) && [[ "${ZJSON_CHARS[before]}" == '\' ]]; do (( before-- )); done
    (( (quote - 1 - before) % 2 == 0 )) && break
    quote=${ZJSON_CHARS[(ib:quote+1:)$quote_char]}
    if (( quote > ZJSON_LEN )); then
      _zjson_scan_string_slow
      return
    fi
  done
  raw="${(j::)ZJSON_CHARS[ZJSON_POS,quote-1]}"
  [[ "$raw" != *[$'\0'-$'\37']* ]] || { _zjson_control_error; return 1; }
  if [[ "$raw" == *'\u'* ]]; then
    _zjson_scan_string_slow
    return
  fi
  parts=("${(@ps:\\\\:)raw}")
  for part in "${parts[@]}"; do
    if [[ "$part" == *'\'* ]]; then
      part="${(pj:\n:)${(@ps:\\n:)part}}"
      part="${(pj:\t:)${(@ps:\\t:)part}}"
      part="${(pj:\r:)${(@ps:\\r:)part}}"
      part="${(pj:\b:)${(@ps:\\b:)part}}"
      part="${(pj:\f:)${(@ps:\\f:)part}}"
      part="${(pj:\":)${(@ps:\\\":)part}}"
      part="${(pj:/:)${(@ps:\\/:)part}}"
      if [[ "$part" == *'\'* ]]; then
        _zjson_scan_string_slow
        return
      fi
    fi
    decoded_parts+=("$part")
  done
  ZJSON_TOKEN_VALUE="${(pj:\\:)decoded_parts}"
  ZJSON_TOKEN_TYPE="string"
  ZJSON_POS=$(( quote + 1 ))
  return 0
}

_zjson_scan_string_slow() {
  emulate -L zsh
  setopt nomultibyte
  local REPLY=""
  # Repeated escapes are common in ASCII-serialized Unicode text. Keep a small
  # per-string cache; disable it after 256 distinct code points so high-diversity
  # text does not keep paying for unsuccessful associative lookups.
  local -A codepoints=()
  local -i cache_active=1
  local ch="" esc="" hex="" low_hex="" decoded="" value="" run=""
  local -i cp low_cp boundary
  while (( ZJSON_POS <= ZJSON_LEN )); do
    # Copy the run up to the next quote or escape in one slice instead of
    # appending character by character.
    boundary=${ZJSON_CHARS[(ib:ZJSON_POS:)[\"\\\\]]}
    (( boundary <= ZJSON_LEN )) || break
    if (( boundary > ZJSON_POS )); then
      run="${(j::)ZJSON_CHARS[ZJSON_POS,boundary-1]}"
      [[ "$run" != *[$'\0'-$'\37']* ]] || { _zjson_control_error; return 1; }
      value+="$run"
    fi
    ch="${ZJSON_CHARS[boundary]}"
    ZJSON_POS=$(( boundary + 1 ))
    if [[ "$ch" == '"' ]]; then
      ZJSON_TOKEN_TYPE="string"
      ZJSON_TOKEN_VALUE="$value"
      return 0
    fi
    (( ZJSON_POS <= ZJSON_LEN )) || { _zjson_fail unterminated_escape "unterminated JSON escape" "$(( ZJSON_LEN + 1 ))"; return 1; }
    esc="${ZJSON_CHARS[ZJSON_POS]}"
    (( ZJSON_POS++ ))
    case "$esc" in
      '"'|$'\\'|'/') value+="$esc" ;;
      b) value+=$'\b' ;;
      f) value+=$'\f' ;;
      n) value+=$'\n' ;;
      r) value+=$'\r' ;;
      t) value+=$'\t' ;;
      u)
        hex="${(j::)ZJSON_CHARS[ZJSON_POS,ZJSON_POS+3]}"
        # JSON requires exactly four ASCII hex digits. Streaming callers use
        # emulate -L zsh, so validation must not depend on EXTENDED_GLOB (or a
        # pattern cached by an earlier decode with different options).
        [[ ${#hex} -eq 4 && "$hex" != *[^0-9a-fA-F]* ]] || { _zjson_fail invalid_unicode_escape "invalid JSON unicode escape" "$ZJSON_POS"; return 1; }
        (( ZJSON_POS += 4 ))
        cp=$(( 16#$hex ))
        if (( cp >= 0xD800 && cp <= 0xDBFF )) && \
           [[ "${(j::)ZJSON_CHARS[ZJSON_POS,ZJSON_POS+1]}" == $'\\u' ]]; then
          low_hex="${(j::)ZJSON_CHARS[ZJSON_POS+2,ZJSON_POS+5]}"
          if [[ ${#low_hex} -eq 4 && "$low_hex" != *[^0-9a-fA-F]* ]]; then
            low_cp=$(( 16#$low_hex ))
            if (( low_cp >= 0xDC00 && low_cp <= 0xDFFF )); then
              cp=$(( 0x10000 + ((cp - 0xD800) << 10) + low_cp - 0xDC00 ))
              (( ZJSON_POS += 6 ))
            fi
          fi
        fi
        if (( cp >= 0xD800 && cp <= 0xDFFF )); then
          # An unpaired UTF-16 surrogate has no character encoding. Substitute
          # the Unicode replacement character; handing the raw code point to
          # printf %b is a fatal error that would abort the whole process.
          cp=0xFFFD
        fi
        if (( cache_active )) && (( ${+codepoints[$cp]} )); then
          decoded="${codepoints[$cp]}"
        else
          _zjson_codepoint_utf8 "$cp"
          decoded="$REPLY"
          if (( cache_active )); then
            if (( ${#codepoints} < 256 )); then
              codepoints[$cp]="$decoded"
            else
              cache_active=0
              codepoints=()
            fi
          fi
        fi
        value+="$decoded"
        ;;
      *) _zjson_fail invalid_escape "invalid JSON escape" "$(( ZJSON_POS - 1 ))"; return 1 ;;
    esac
  done
  _zjson_fail unterminated_string "unterminated JSON string" "$(( ZJSON_LEN + 1 ))"
  return 1
}

zjson_next() {
  emulate -L zsh
  setopt nomultibyte
  local ch="" value="" previous="$ZJSON_TOKEN_TYPE" whitespace=$' \t\r\n'
  local -i boundary
  setopt extendedglob

  [[ -z "$ZJSON_ERROR" ]] || return 1

  # First non-whitespace character at or after ZJSON_POS, located in C.
  ZJSON_POS=${ZJSON_CHARS[(ib:ZJSON_POS:)[^${whitespace}]]}
  ZJSON_TOKEN_START=$ZJSON_POS
  if (( ZJSON_POS > ZJSON_LEN )); then
    ZJSON_TOKEN_TYPE="eof"
    ZJSON_TOKEN_VALUE=""
    return 0
  fi

  ch="${ZJSON_CHARS[ZJSON_POS]}"
  if [[ "$previous" == ',' && ( "$ch" == '}' || "$ch" == ']' ) ]]; then
    _zjson_fail trailing_comma "trailing comma in JSON container"
    return 1
  fi
  case "$ch" in
    '{'|'}'|'['|']'|':'|',')
      ZJSON_TOKEN_TYPE="$ch"
      ZJSON_TOKEN_VALUE="$ch"
      (( ZJSON_POS++ ))
      return 0
      ;;
    '"')
      (( ZJSON_POS++ ))
      _zjson_scan_string
      ;;
    -|[0-9])
      boundary=${ZJSON_CHARS[(ib:ZJSON_POS:)[^0-9eE+.-]]}
      value="${(j::)ZJSON_CHARS[ZJSON_POS,boundary-1]}"
      [[ "$value" == (-|)(0|[1-9][0-9]#)(.[0-9]##|)([eE](+|-|)[0-9]##|) ]] || {
        _zjson_fail invalid_number "invalid JSON number"
        return 1
      }
      ZJSON_POS=$boundary
      ZJSON_TOKEN_TYPE="number"
      ZJSON_TOKEN_VALUE="$value"
      ;;
    [tfn])
      boundary=${ZJSON_CHARS[(ib:ZJSON_POS:)[^[:alpha:]]]}
      value="${(j::)ZJSON_CHARS[ZJSON_POS,boundary-1]}"
      ZJSON_POS=$boundary
      case "$value" in
        true|false|null) ZJSON_TOKEN_TYPE="$value"; ZJSON_TOKEN_VALUE="$value" ;;
        *) _zjson_fail invalid_literal "invalid JSON literal"; return 1 ;;
      esac
      ;;
    *) _zjson_fail unexpected_character "unexpected JSON character at byte $ZJSON_POS"; return 1 ;;
  esac
}

# Advance over a complete JSON value without rebuilding it. This is useful for
# large protocol envelopes where the caller only needs one top-level member.
zjson_discard_value() {
  emulate -L zsh
  setopt nomultibyte
  [[ -z "$ZJSON_ERROR" ]] || return 1
  local -i _zjson_depth=${_zjson_depth:-0}
  if [[ "$ZJSON_TOKEN_TYPE" == '[' || "$ZJSON_TOKEN_TYPE" == '{' ]]; then
    (( ++_zjson_depth <= 128 )) || { _zjson_fail nesting_limit "JSON nesting exceeds 128 containers"; return 1; }
  fi
  case "$ZJSON_TOKEN_TYPE" in
    string|number|true|false|null)
      zjson_next || return 1
      ;;
    '[')
      zjson_next || return 1
      while [[ "$ZJSON_TOKEN_TYPE" != ']' ]]; do
        zjson_discard_value || return 1
        if [[ "$ZJSON_TOKEN_TYPE" == ',' ]]; then
          zjson_next || return 1
        elif [[ "$ZJSON_TOKEN_TYPE" != ']' ]]; then
          _zjson_fail expected_array_separator "expected comma or closing bracket"
          return 1
        fi
      done
      zjson_next || return 1
      ;;
    '{')
      zjson_next || return 1
      while [[ "$ZJSON_TOKEN_TYPE" != '}' ]]; do
        [[ "$ZJSON_TOKEN_TYPE" == string ]] || { _zjson_fail expected_key "expected object key"; return 1; }
        zjson_next || return 1
        [[ "$ZJSON_TOKEN_TYPE" == ':' ]] || { _zjson_fail expected_colon "expected colon"; return 1; }
        zjson_next || return 1
        zjson_discard_value || return 1
        if [[ "$ZJSON_TOKEN_TYPE" == ',' ]]; then
          zjson_next || return 1
        elif [[ "$ZJSON_TOKEN_TYPE" != '}' ]]; then
          _zjson_fail expected_object_separator "expected comma or closing brace"
          return 1
        fi
      done
      zjson_next || return 1
      ;;
    *)
      _zjson_fail expected_value "expected JSON value"
      return 1
      ;;
  esac
}

# Preserve the exact source slice for a value while using the tokenizer only
# to locate its boundary. Unlike zjson_capture_value this performs no repeated
# string concatenation or JSON re-encoding.
zjson_capture_raw_value() {
  emulate -L zsh
  setopt nomultibyte
  local -i start=$ZJSON_TOKEN_START end=0
  zjson_discard_value || return 1
  end=$(( ZJSON_TOKEN_START - 1 ))
  while (( end >= start )) && [[ "${ZJSON_CHARS[end]}" == [[:space:]] ]]; do (( end-- )); done
  (( end >= start )) && REPLY="${(j::)ZJSON_CHARS[start,end]}" || REPLY=""
}

# Serialize and consume the value at the current token. This lets us preserve
# arbitrary nested values using only native Zsh operations.
zjson_capture_value() {
  emulate -L zsh
  setopt nomultibyte
  [[ -z "$ZJSON_ERROR" ]] || return 1
  local -i _zjson_depth=${_zjson_depth:-0}
  if [[ "$ZJSON_TOKEN_TYPE" == '[' || "$ZJSON_TOKEN_TYPE" == '{' ]]; then
    (( ++_zjson_depth <= 128 )) || { _zjson_fail nesting_limit "JSON nesting exceeds 128 containers"; return 1; }
  fi
  local output="" item="" key="" comma=""
  case "$ZJSON_TOKEN_TYPE" in
    string)
      zjson_quote "$ZJSON_TOKEN_VALUE"; output="$REPLY"
      zjson_next || return 1
      ;;
    number|true|false|null)
      output="$ZJSON_TOKEN_VALUE"
      zjson_next || return 1
      ;;
    '[')
      output="["
      zjson_next || return 1
      while [[ "$ZJSON_TOKEN_TYPE" != ']' ]]; do
        zjson_capture_value || return 1
        item="$REPLY"
        output+="${comma}${item}"
        comma=","
        if [[ "$ZJSON_TOKEN_TYPE" == ',' ]]; then
          zjson_next || return 1
        elif [[ "$ZJSON_TOKEN_TYPE" != ']' ]]; then
          _zjson_fail expected_array_separator "expected comma or closing bracket"
          return 1
        fi
      done
      zjson_next || return 1
      output+="]"
      ;;
    '{')
      output="{"
      zjson_next || return 1
      while [[ "$ZJSON_TOKEN_TYPE" != '}' ]]; do
        [[ "$ZJSON_TOKEN_TYPE" == string ]] || { _zjson_fail expected_key "expected object key"; return 1; }
        key="$ZJSON_TOKEN_VALUE"
        zjson_next || return 1
        [[ "$ZJSON_TOKEN_TYPE" == ':' ]] || { _zjson_fail expected_colon "expected colon"; return 1; }
        zjson_next || return 1
        zjson_capture_value || return 1
        item="$REPLY"
        zjson_quote "$key"
        output+="${comma}${REPLY}:${item}"
        comma=","
        if [[ "$ZJSON_TOKEN_TYPE" == ',' ]]; then
          zjson_next || return 1
        elif [[ "$ZJSON_TOKEN_TYPE" != '}' ]]; then
          _zjson_fail expected_object_separator "expected comma or closing brace"
          return 1
        fi
      done
      zjson_next || return 1
      output+="}"
      ;;
    *) _zjson_fail expected_value "expected JSON value"; return 1 ;;
  esac
  REPLY="$output"
}

# Callers that skip a member only need the cursor advanced past it; rebuilding
# the serialized value just to throw it away is pure waste for large payloads.
zjson_skip_value() {
  emulate -L zsh
  setopt nomultibyte
  zjson_discard_value
}

# Whole-document operations require EOF; the token API intentionally permits
# callers to consume individual values. All diagnostics stay out of stdout.
zjson_validate() {
  emulate -L zsh
  zjson_begin "$@" || return $?
  zjson_discard_value || return 1
  [[ "$ZJSON_TOKEN_TYPE" == eof ]] || {
    _zjson_fail trailing_content "trailing content after JSON value"
    return 1
  }
}

# Return decoded scalars or the original source of a container in REPLY.
_zjson_read_value() {
  emulate -L zsh
  local value=""
  case "$ZJSON_TOKEN_TYPE" in
    string|number|true|false|null)
      value="$ZJSON_TOKEN_VALUE"
      zjson_next || return 1
      REPLY="$value"
      ;;
    *) zjson_capture_raw_value || return 1 ;;
  esac
}

zjson_parse_object() {
  emulate -L zsh
  local key="" kind="" REPLY=""
  local -A values=() kinds=()
  local -i _zjson_depth=1
  ZJSON_OBJECT=()
  ZJSON_OBJECT_TYPES=()
  zjson_begin "$@" || return $?
  [[ "$ZJSON_TOKEN_TYPE" == '{' ]] || { _zjson_fail expected_object "expected JSON object"; return 1; }
  zjson_next || return 1
  while [[ "$ZJSON_TOKEN_TYPE" != '}' ]]; do
    [[ "$ZJSON_TOKEN_TYPE" == string ]] || { _zjson_fail expected_key "expected object key"; return 1; }
    key="$ZJSON_TOKEN_VALUE"
    zjson_next || return 1
    [[ "$ZJSON_TOKEN_TYPE" == ':' ]] || { _zjson_fail expected_colon "expected colon"; return 1; }
    zjson_next || return 1
    kind="$ZJSON_TOKEN_TYPE"
    _zjson_read_value || return 1
    values[$key]="$REPLY"
    kinds[$key]="$kind"
    if [[ "$ZJSON_TOKEN_TYPE" == ',' ]]; then
      zjson_next || return 1
    elif [[ "$ZJSON_TOKEN_TYPE" != '}' ]]; then
      _zjson_fail expected_object_separator "expected comma or closing brace"
      return 1
    fi
  done
  zjson_next || return 1
  [[ "$ZJSON_TOKEN_TYPE" == eof ]] || { _zjson_fail trailing_content "trailing content after JSON object"; return 1; }
  ZJSON_OBJECT=( "${(@kv)values}" )
  ZJSON_OBJECT_TYPES=( "${(@kv)kinds}" )
}

zjson_parse_array() {
  emulate -L zsh
  local kind="" REPLY=""
  local -a values=() kinds=()
  local -i _zjson_depth=1
  ZJSON_ARRAY=()
  ZJSON_ARRAY_TYPES=()
  zjson_begin "$@" || return $?
  [[ "$ZJSON_TOKEN_TYPE" == '[' ]] || { _zjson_fail expected_array "expected JSON array"; return 1; }
  zjson_next || return 1
  while [[ "$ZJSON_TOKEN_TYPE" != ']' ]]; do
    kind="$ZJSON_TOKEN_TYPE"
    _zjson_read_value || return 1
    values+=( "$REPLY" )
    kinds+=( "$kind" )
    if [[ "$ZJSON_TOKEN_TYPE" == ',' ]]; then
      zjson_next || return 1
    elif [[ "$ZJSON_TOKEN_TYPE" != ']' ]]; then
      _zjson_fail expected_array_separator "expected comma or closing bracket"
      return 1
    fi
  done
  zjson_next || return 1
  [[ "$ZJSON_TOKEN_TYPE" == eof ]] || { _zjson_fail trailing_content "trailing content after JSON array"; return 1; }
  ZJSON_ARRAY=( "${values[@]}" )
  ZJSON_ARRAY_TYPES=( "${kinds[@]}" )
}
