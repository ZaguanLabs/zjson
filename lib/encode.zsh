# SPDX-License-Identifier: Apache-2.0
# Additive whole-document APIs built on the shared tokenizer and type tags.

# Return the root value in REPLY and its type tag in ZJSON_TYPE.
zjson_parse() {
  emulate -L zsh
  REPLY=""
  ZJSON_TYPE=""
  (( $# == 1 )) || { _zjson_fail usage "expected one JSON argument" 0 2; return 2; }
  local kind=""
  zjson_begin "$1" || return 1
  kind="$ZJSON_TOKEN_TYPE"
  _zjson_read_value || return 1
  [[ "$ZJSON_TOKEN_TYPE" == eof ]] || {
    _zjson_fail trailing_content "trailing content after JSON value"
    return 1
  }
  ZJSON_TYPE="$kind"
  ZJSON_CHARS=()
}

# Encode one value. The explicit type tag preserves the string/number/null
# distinctions that Zsh scalars cannot represent on their own.
zjson_encode_value() {
  emulate -L zsh
  REPLY=""
  ZJSON_ERROR=""
  ZJSON_ERROR_CODE=""
  ZJSON_ERROR_OFFSET=0 ZJSON_ERROR_LINE=0 ZJSON_ERROR_COLUMN=0
  (( $# == 2 )) || { _zjson_fail usage "expected value and type arguments" 0 2; return 2; }
  local value="$1" type="$2"
  case "$type" in
    string)
      zjson_quote "$value"
      ;;
    number)
      zjson_begin "$value" || return 1
      [[ "$ZJSON_TOKEN_TYPE" == number ]] || {
        _zjson_fail invalid_number "expected JSON number text"
        return 1
      }
      zjson_next || return 1
      [[ "$ZJSON_TOKEN_TYPE" == eof ]] || {
        _zjson_fail trailing_content "trailing content after JSON number"
        return 1
      }
      REPLY="$value"
      ZJSON_CHARS=()
      ;;
    true|false|null)
      [[ "$value" == "$type" ]] || { _zjson_fail usage "value does not match type tag" 0 2; return 2; }
      REPLY="$value"
      ;;
    '{'|'[')
      zjson_validate "$value" || return 1
      REPLY="$value"
      ;;
    *)
      _zjson_fail usage "unknown JSON type tag" 0 2
      return 2
      ;;
  esac
}

zjson_encode_array() {
  emulate -L zsh
  REPLY=""
  ZJSON_ERROR=""
  ZJSON_ERROR_CODE=""
  ZJSON_ERROR_OFFSET=0 ZJSON_ERROR_LINE=0 ZJSON_ERROR_COLUMN=0
  (( $# == 0 )) || { _zjson_fail usage "expected no arguments" 0 2; return 2; }
  local -i i
  local -a parts=() keys=()
  if (( ${#ZJSON_ARRAY} != ${#ZJSON_ARRAY_TYPES} )); then
    _zjson_fail usage "ZJSON_ARRAY and ZJSON_ARRAY_TYPES lengths differ" 0 2
    return 2
  fi
  parts=("[")
  for (( i=1; i<=${#ZJSON_ARRAY}; ++i )); do
    zjson_encode_value "${ZJSON_ARRAY[i]}" "${ZJSON_ARRAY_TYPES[i]}" || return $?
    (( i > 1 )) && parts+=(",")
    parts+=("$REPLY")
  done
  parts+=("]")
  REPLY="${(j::)parts}"
}

zjson_encode_object() {
  emulate -L zsh
  REPLY=""
  ZJSON_ERROR=""
  ZJSON_ERROR_CODE=""
  ZJSON_ERROR_OFFSET=0 ZJSON_ERROR_LINE=0 ZJSON_ERROR_COLUMN=0
  (( $# == 0 )) || { _zjson_fail usage "expected no arguments" 0 2; return 2; }
  local -i i first=1
  local key=""
  local -a parts=() keys=()
  local -A seen=()
  if (( ${#ZJSON_OBJECT_TYPES} != ${#ZJSON_OBJECT} )); then
    _zjson_fail usage "ZJSON_OBJECT and ZJSON_OBJECT_TYPES lengths differ" 0 2
    return 2
  fi
  if (( ${#ZJSON_OBJECT_KEYS} == ${#ZJSON_OBJECT} )); then
    keys=( "${ZJSON_OBJECT_KEYS[@]}" )
  else
    # Manually built associative arrays have no source order. Zsh's ordered
    # key expansion provides a deterministic fallback for that case.
    keys=( "${(@k)ZJSON_OBJECT}" )
  fi
  parts=("{")
  for (( i=1; i<=${#keys}; ++i )); do
    key="${keys[i]}"
    if (( ! ${+ZJSON_OBJECT[$key]} || ! ${+ZJSON_OBJECT_TYPES[$key]} )); then
      _zjson_fail usage "ZJSON_OBJECT_KEYS references a missing member" 0 2
      return 2
    fi
    if (( ${+seen[$key]} )); then
      _zjson_fail usage "ZJSON_OBJECT_KEYS contains a duplicate key" 0 2
      return 2
    fi
    seen[$key]=1
    zjson_quote "$key"
    (( first )) || parts+=(",")
    first=0
    parts+=("$REPLY:")
    zjson_encode_value "${ZJSON_OBJECT[$key]}" "${ZJSON_OBJECT_TYPES[$key]}" || return $?
    parts+=("$REPLY")
  done
  parts+=("}")
  REPLY="${(j::)parts}"
}

# Invoke callback key value type extra-args... for each object member.
zjson_each_object() {
  emulate -L zsh
  (( $# >= 2 )) || { _zjson_fail usage "expected JSON and callback arguments" 0 2; return 2; }
  local json="$1" callback="$2" key="" kind="" REPLY=""
  local -i _zjson_depth=1
  shift 2
  zjson_begin "$json" || return 1
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
    zjson_with_context "$callback" "$key" "$REPLY" "$kind" "$@" || return $?
    if [[ "$ZJSON_TOKEN_TYPE" == ',' ]]; then
      zjson_next || return 1
      [[ "$ZJSON_TOKEN_TYPE" != '}' ]] || { _zjson_fail trailing_comma "trailing comma in JSON container"; return 1; }
    elif [[ "$ZJSON_TOKEN_TYPE" != '}' ]]; then
      _zjson_fail expected_object_separator "expected comma or closing brace"
      return 1
    fi
  done
  zjson_next || return 1
  [[ "$ZJSON_TOKEN_TYPE" == eof ]] || { _zjson_fail trailing_content "trailing content after JSON object"; return 1; }
  ZJSON_CHARS=()
}

# Invoke callback index value type extra-args... for each array element.
# Indexes are native Zsh array indexes and therefore start at one.
zjson_each_array() {
  emulate -L zsh
  (( $# >= 2 )) || { _zjson_fail usage "expected JSON and callback arguments" 0 2; return 2; }
  local json="$1" callback="$2" kind="" REPLY=""
  local -i _zjson_depth=1 index=1
  shift 2
  zjson_begin "$json" || return 1
  [[ "$ZJSON_TOKEN_TYPE" == '[' ]] || { _zjson_fail expected_array "expected JSON array"; return 1; }
  zjson_next || return 1
  while [[ "$ZJSON_TOKEN_TYPE" != ']' ]]; do
    kind="$ZJSON_TOKEN_TYPE"
    _zjson_read_value || return 1
    zjson_with_context "$callback" "$index" "$REPLY" "$kind" "$@" || return $?
    (( ++index ))
    if [[ "$ZJSON_TOKEN_TYPE" == ',' ]]; then
      zjson_next || return 1
      [[ "$ZJSON_TOKEN_TYPE" != ']' ]] || { _zjson_fail trailing_comma "trailing comma in JSON container"; return 1; }
    elif [[ "$ZJSON_TOKEN_TYPE" != ']' ]]; then
      _zjson_fail expected_array_separator "expected comma or closing bracket"
      return 1
    fi
  done
  zjson_next || return 1
  [[ "$ZJSON_TOKEN_TYPE" == eof ]] || { _zjson_fail trailing_content "trailing content after JSON array"; return 1; }
  ZJSON_CHARS=()
}
