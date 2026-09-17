# SPDX-License-Identifier: Apache-2.0
# RFC 6901 JSON Pointer string form. Loaded by ../zjson.zsh.

typeset -ga ZJSON_RESULTS=() ZJSON_TYPES=()

_zjson_parse_pointer() {
  emulate -L zsh
  local pointer="$1" tail="" part="" REPLY="" slash='/' tilde='~'
  if ! _zjson_utf8_validate "$pointer"; then
    _zjson_fail pointer_syntax "JSON Pointer must be UTF-8" 0 2
    return 2
  fi
  [[ -n "$pointer" ]] || return 0
  [[ "$pointer" == /* ]] || {
    _zjson_fail pointer_syntax "JSON Pointer must be empty or start with /" 0 2
    return 2
  }
  tail="${pointer#/}"
  while true; do
    part="${tail%%/*}"
    if [[ "$part" == *'~'[^01]* || "$part" == *'~' ]]; then
      _zjson_fail pointer_syntax "JSON Pointer escapes must be ~0 or ~1" 0 2
      return 2
    fi
    # Decode in this order: ~01 represents the literal key ~1, not /.
    part="${part//\~1/$slash}"
    part="${part//\~0/$tilde}"
    _zjson_pointer_parts+=( "$part" )
    [[ "$tail" == */* ]] || break
    tail="${tail#*/}"
  done
}

# Walk only the requested branch; consume and validate every other value.
# The _zjson_lookup_* locals belong to zjson_get and are shared intentionally
# through Zsh dynamic scope. Resolution errors are deferred until JSON is valid.
_zjson_lookup_value() {
  emulate -L zsh
  setopt extendedglob
  local -i step=$1 start=$ZJSON_TOKEN_START index=0 matches=0 eligible=1
  local part="${_zjson_pointer_parts[step]}" key="" kind="$ZJSON_TOKEN_TYPE" REPLY=""
  if (( step > ${#_zjson_pointer_parts} )); then
    _zjson_read_value || return 1
    _zjson_lookup_result="$REPLY"
    _zjson_lookup_type="$kind"
    return 0
  fi
  local -i _zjson_depth=${_zjson_depth:-0}
  if [[ "$kind" == '[' || "$kind" == '{' ]]; then
    (( ++_zjson_depth <= 128 )) || {
      _zjson_fail nesting_limit "JSON nesting exceeds 128 containers"
      return 1
    }
  fi
  case "$kind" in
    '{')
      zjson_next || return 1
      while [[ "$ZJSON_TOKEN_TYPE" != '}' ]]; do
        [[ "$ZJSON_TOKEN_TYPE" == string ]] || { _zjson_fail expected_key "expected object key"; return 1; }
        key="$ZJSON_TOKEN_VALUE"
        zjson_next || return 1
        [[ "$ZJSON_TOKEN_TYPE" == ':' ]] || { _zjson_fail expected_colon "expected colon"; return 1; }
        zjson_next || return 1
        if [[ "$key" == "$part" ]]; then
          (( ++matches ))
          if (( matches == 1 )); then
            _zjson_lookup_value "$(( step + 1 ))" || return 1
          else
            # RFC 6901 cannot resolve a non-unique referenced member.
            _zjson_lookup_code=pointer_ambiguous
            _zjson_lookup_message="JSON Pointer references a duplicate object key"
            _zjson_lookup_offset=$start
            zjson_discard_value || return 1
          fi
        else
          zjson_discard_value || return 1
        fi
        if [[ "$ZJSON_TOKEN_TYPE" == ',' ]]; then
          zjson_next || return 1
          [[ "$ZJSON_TOKEN_TYPE" != '}' ]] || { _zjson_fail trailing_comma "trailing comma in JSON container"; return 1; }
        elif [[ "$ZJSON_TOKEN_TYPE" != '}' ]]; then
          _zjson_fail expected_object_separator "expected comma or closing brace"
          return 1
        fi
      done
      zjson_next || return 1
      ;;
    '[')
      # Never convert pointer text into shell arithmetic, including enormous
      # indexes. Compare the validated decimal spelling to our own counter.
      if [[ "$part" != (0|[1-9][0-9]#) ]]; then
        eligible=0
        if [[ "$part" != '-' ]]; then
          _zjson_lookup_code=pointer_index
          _zjson_lookup_message="JSON Pointer array index must be 0 or digits without leading zeros"
          _zjson_lookup_offset=$start
        fi
      fi
      zjson_next || return 1
      while [[ "$ZJSON_TOKEN_TYPE" != ']' ]]; do
        if (( eligible )) && [[ "$part" == "$index" ]]; then
          matches=1
          _zjson_lookup_value "$(( step + 1 ))" || return 1
        else
          zjson_discard_value || return 1
        fi
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
      ;;
    *)
      zjson_discard_value || return 1
      _zjson_lookup_code=pointer_type
      _zjson_lookup_message="JSON Pointer cannot descend into a scalar"
      _zjson_lookup_offset=$start
      return 0
      ;;
  esac
  if (( matches == 0 )) && [[ -z "$_zjson_lookup_code" ]]; then
    _zjson_lookup_code=pointer_not_found
    _zjson_lookup_message="JSON Pointer does not resolve to a value"
    _zjson_lookup_offset=$start
  fi
  return 0
}

# Decoded scalar or raw container -> REPLY; matching token type -> ZJSON_TYPE.
# Status: 0 success, 1 invalid JSON, 2 usage/pointer syntax, 3 unresolved pointer.
zjson_get() {
  emulate -L zsh
  REPLY=""
  ZJSON_TYPE=""
  local -a _zjson_pointer_parts=()
  local _zjson_lookup_result="" _zjson_lookup_type=""
  local _zjson_lookup_code="" _zjson_lookup_message=""
  local -i _zjson_lookup_offset=0 _zjson_depth=0
  (( $# == 2 )) || { _zjson_fail usage "expected JSON and JSON Pointer arguments" 0 2; return 2; }
  _zjson_parse_pointer "$2" || return 2
  zjson_begin "$1" || return 1
  _zjson_lookup_value 1 || return 1
  [[ "$ZJSON_TOKEN_TYPE" == eof ]] || { _zjson_fail trailing_content "trailing content after JSON value"; return 1; }
  if [[ -n "$_zjson_lookup_code" ]]; then
    _zjson_fail "$_zjson_lookup_code" "$_zjson_lookup_message" "$_zjson_lookup_offset" 3
    return 3
  fi
  REPLY="$_zjson_lookup_result"
  ZJSON_TYPE="$_zjson_lookup_type"
  ZJSON_CHARS=()
}

# Collect several RFC 6901 paths during one tokenizer pass. The flat parts,
# lengths, and starts arrays belong to zjson_get_multi and are shared through
# dynamic scope; starts is one-based like all Zsh indexed arrays.
_zjson_collect_value() {
  emulate -L zsh
  setopt extendedglob
  local -i depth=$1 _zjson_depth=${_zjson_depth:-0}
  shift
  local -a candidates=( "$@" )
  local -i candidate start token_start=0 index=0 seen_index=0
  local kind="$ZJSON_TOKEN_TYPE" key="" part="" value="" raw_end=0

  local -a exact=() longer=() active=() selected=()
  for candidate in "${candidates[@]}"; do
    if (( ${_zjson_multi_lengths[candidate]} == depth )); then
      exact+=( "$candidate" )
    elif (( ${_zjson_multi_lengths[candidate]} > depth )); then
      longer+=( "$candidate" )
    fi
  done

  if (( ! ${#longer} )); then
    _zjson_read_value || return 1
    for candidate in "${exact[@]}"; do
      _zjson_multi_results[candidate]="$REPLY"
      _zjson_multi_types[candidate]="$kind"
      _zjson_multi_found[candidate]=1
    done
    return 0
  fi

  case "$kind" in
    string|number|true|false|null)
      value="$ZJSON_TOKEN_VALUE"
      zjson_discard_value || return 1
      for candidate in "${longer[@]}"; do
        _zjson_multi_codes[candidate]=pointer_type
        _zjson_multi_messages[candidate]="JSON Pointer cannot descend into a scalar"
        _zjson_multi_offsets[candidate]=$ZJSON_TOKEN_START
      done
      for candidate in "${exact[@]}"; do
        _zjson_multi_results[candidate]="$value"
        _zjson_multi_types[candidate]="$kind"
        _zjson_multi_found[candidate]=1
      done
      return 0
      ;;
    '['|'{')
      (( ++_zjson_depth <= 128 )) || {
        _zjson_fail nesting_limit "JSON nesting exceeds 128 containers"
        return 1
      }
      ;;
    *)
      _zjson_fail expected_value "expected JSON value"
      return 1
      ;;
  esac

  token_start=$ZJSON_TOKEN_START
  case "$kind" in
    '{')
      zjson_next || return 1
      while [[ "$ZJSON_TOKEN_TYPE" != '}' ]]; do
        [[ "$ZJSON_TOKEN_TYPE" == string ]] || { _zjson_fail expected_key "expected object key"; return 1; }
        key="$ZJSON_TOKEN_VALUE"
        zjson_next || return 1
        [[ "$ZJSON_TOKEN_TYPE" == ':' ]] || { _zjson_fail expected_colon "expected colon"; return 1; }
        zjson_next || return 1
        selected=()
        for candidate in "${longer[@]}"; do
          (( ${_zjson_multi_lengths[candidate]} > depth )) || continue
          start=${_zjson_multi_starts[candidate]}
          part="${_zjson_multi_parts[start + depth]}"
          [[ "$part" == "$key" ]] || continue
          seen_index=$(( (candidate - 1) * _zjson_multi_width + depth + 1 ))
          if [[ "${_zjson_multi_seen[$seen_index]}" == "$key" ]]; then
            _zjson_multi_codes[candidate]=pointer_ambiguous
            _zjson_multi_messages[candidate]="JSON Pointer references a duplicate object key"
            _zjson_multi_offsets[candidate]=$token_start
          else
            _zjson_multi_seen[$seen_index]="$key"
            selected+=( "$candidate" )
          fi
        done
        if (( ${#selected} )); then
          _zjson_collect_value $(( depth + 1 )) "${selected[@]}" || return 1
        else
          zjson_discard_value || return 1
        fi
        if [[ "$ZJSON_TOKEN_TYPE" == ',' ]]; then
          zjson_next || return 1
          [[ "$ZJSON_TOKEN_TYPE" != '}' ]] || { _zjson_fail trailing_comma "trailing comma in JSON container"; return 1; }
        elif [[ "$ZJSON_TOKEN_TYPE" != '}' ]]; then
          _zjson_fail expected_object_separator "expected comma or closing brace"
          return 1
        fi
      done
      zjson_next || return 1
      for candidate in "${longer[@]}"; do
        if [[ "${_zjson_multi_found[candidate]}" != 1 ]] && [[ -z "${_zjson_multi_codes[candidate]}" ]]; then
          _zjson_multi_codes[candidate]=pointer_not_found
          _zjson_multi_messages[candidate]="JSON Pointer does not resolve to a value"
          _zjson_multi_offsets[candidate]=$token_start
        fi
      done
      ;;
    '[')
      active=()
      for candidate in "${longer[@]}"; do
        (( ${_zjson_multi_lengths[candidate]} > depth )) || continue
        start=${_zjson_multi_starts[candidate]}
        part="${_zjson_multi_parts[start + depth]}"
        if [[ "$part" != (0|[1-9][0-9]#) && "$part" != '-' ]]; then
          _zjson_multi_codes[candidate]=pointer_index
          _zjson_multi_messages[candidate]="JSON Pointer array index must be 0 or digits without leading zeros"
          _zjson_multi_offsets[candidate]=$token_start
        else
          active+=( "$candidate" )
        fi
      done
      zjson_next || return 1
      while [[ "$ZJSON_TOKEN_TYPE" != ']' ]]; do
        selected=()
        for candidate in "${active[@]}"; do
          start=${_zjson_multi_starts[candidate]}
          part="${_zjson_multi_parts[start + depth]}"
          [[ "$part" == "$index" ]] && selected+=( "$candidate" )
        done
        if (( ${#selected} )); then
          _zjson_collect_value $(( depth + 1 )) "${selected[@]}" || return 1
        else
          zjson_discard_value || return 1
        fi
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
      for candidate in "${active[@]}"; do
        if [[ "${_zjson_multi_found[candidate]}" != 1 ]] && [[ -z "${_zjson_multi_codes[candidate]}" ]]; then
          _zjson_multi_codes[candidate]=pointer_not_found
          _zjson_multi_messages[candidate]="JSON Pointer does not resolve to a value"
          _zjson_multi_offsets[candidate]=$token_start
        fi
      done
      ;;
  esac

  # Exact pointers at a container need its raw source while longer pointers
  # may also descend into that same container.
  if (( ${#exact} )); then
    raw_end=$(( ZJSON_TOKEN_START - 1 ))
    while (( raw_end >= token_start )) && [[ "${ZJSON_CHARS[raw_end]}" == [$' \t\r\n'] ]]; do
      (( raw_end-- ))
    done
    (( raw_end >= token_start )) && REPLY="${(j::)ZJSON_CHARS[token_start,raw_end]}" || REPLY=""
    for candidate in "${exact[@]}"; do
      _zjson_multi_results[candidate]="$REPLY"
      _zjson_multi_types[candidate]="$kind"
      _zjson_multi_found[candidate]=1
    done
  fi
}

# Resolve multiple Pointers with one tokenizer pass. Results are published in
# the argument order as ZJSON_RESULTS and ZJSON_TYPES only when all resolve.
zjson_get_multi() {
  emulate -L zsh
  ZJSON_RESULTS=()
  ZJSON_TYPES=()
  (( $# >= 2 )) || { _zjson_fail usage "expected JSON and JSON Pointer arguments" 0 2; return 2; }
  local json="$1" pointer="" REPLY=""
  local -a candidates=()
  local -i i=1 cursor=0 length=0
  local -a _zjson_pointer_parts=() _zjson_multi_parts=() _zjson_multi_lengths=() _zjson_multi_starts=()
  local -a _zjson_multi_results=() _zjson_multi_types=() _zjson_multi_codes=() _zjson_multi_messages=()
  local -a _zjson_multi_found=()
  local -a _zjson_multi_offsets=() _zjson_multi_seen=()
  local -i _zjson_multi_width=0 _zjson_depth=0
  shift
  for pointer in "$@"; do
    _zjson_pointer_parts=()
    _zjson_parse_pointer "$pointer" || return 2
    length=${#_zjson_pointer_parts}
    (( length > _zjson_multi_width )) && _zjson_multi_width=$length
    _zjson_multi_lengths+=( "$length" )
    _zjson_multi_starts+=( $(( cursor + 1 )) )
    _zjson_multi_parts+=( "${_zjson_pointer_parts[@]}" )
    (( cursor += length ))
    candidates+=( "$(( i++ ))" )
  done
  zjson_begin "$json" || return 1
  _zjson_collect_value 0 "${candidates[@]}" || return 1
  [[ "$ZJSON_TOKEN_TYPE" == eof ]] || { _zjson_fail trailing_content "trailing content after JSON value"; return 1; }
  for (( i=1; i<=${#_zjson_multi_lengths}; ++i )); do
    if [[ -n "${_zjson_multi_codes[i]}" ]]; then
      _zjson_fail "${_zjson_multi_codes[i]}" "${_zjson_multi_messages[i]}" "${_zjson_multi_offsets[i]}" 3
      ZJSON_RESULTS=()
      ZJSON_TYPES=()
      return 3
    fi
  done
  ZJSON_RESULTS=( "${_zjson_multi_results[@]}" )
  ZJSON_TYPES=( "${_zjson_multi_types[@]}" )
  ZJSON_CHARS=()
}
