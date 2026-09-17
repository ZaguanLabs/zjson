# SPDX-License-Identifier: Apache-2.0

# Dynamic locals restore the parser automatically when the callback returns or
# unwinds with an error. The byte array is rebuilt only after a nested begin.
# REPLY, ZJSON_TYPE and the object/array decoder results remain callback outputs.
zjson_with_context() {
  emulate -L zsh
  (( $# )) || return 2
  local ZJSON_SOURCE="$ZJSON_SOURCE"
  local _zjson_context_source="$ZJSON_SOURCE"
  local -i ZJSON_POS=$ZJSON_POS ZJSON_LEN=$ZJSON_LEN ZJSON_TOKEN_START=$ZJSON_TOKEN_START
  local ZJSON_TOKEN_TYPE="$ZJSON_TOKEN_TYPE" ZJSON_TOKEN_VALUE="$ZJSON_TOKEN_VALUE"
  local ZJSON_ERROR="$ZJSON_ERROR" ZJSON_ERROR_CODE="$ZJSON_ERROR_CODE"
  local -i ZJSON_ERROR_OFFSET=$ZJSON_ERROR_OFFSET ZJSON_ERROR_LINE=$ZJSON_ERROR_LINE
  local -i ZJSON_ERROR_COLUMN=$ZJSON_ERROR_COLUMN _zjson_utf8_error=$_zjson_utf8_error
  local -i _zjson_depth=0 _zjson_context_generation=$_zjson_begin_generation
  {
    "$@"
  } always {
    if (( _zjson_begin_generation != _zjson_context_generation )); then
      setopt nomultibyte
      if [[ -n "$_zjson_context_source" ]]; then
        ZJSON_CHARS=( "${(@s::)_zjson_context_source}" )
      else
        ZJSON_CHARS=()
      fi
    fi
  }
}
