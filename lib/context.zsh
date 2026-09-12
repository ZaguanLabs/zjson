# SPDX-License-Identifier: Apache-2.0

# Dynamic locals restore the parser automatically when the callback returns or
# unwinds with an error. Copying is confined to this explicit scope boundary.
# REPLY, ZJSON_TYPE and the object/array decoder results remain callback outputs.
zjson_with_context() {
  emulate -L zsh
  (( $# )) || return 2
  local ZJSON_SOURCE="$ZJSON_SOURCE"
  local -a ZJSON_CHARS=( "${ZJSON_CHARS[@]}" )
  local -i ZJSON_POS=$ZJSON_POS ZJSON_LEN=$ZJSON_LEN ZJSON_TOKEN_START=$ZJSON_TOKEN_START
  local ZJSON_TOKEN_TYPE="$ZJSON_TOKEN_TYPE" ZJSON_TOKEN_VALUE="$ZJSON_TOKEN_VALUE"
  local ZJSON_ERROR="$ZJSON_ERROR" ZJSON_ERROR_CODE="$ZJSON_ERROR_CODE"
  local -i ZJSON_ERROR_OFFSET=$ZJSON_ERROR_OFFSET ZJSON_ERROR_LINE=$ZJSON_ERROR_LINE
  local -i ZJSON_ERROR_COLUMN=$ZJSON_ERROR_COLUMN _zjson_utf8_error=$_zjson_utf8_error
  local -i _zjson_depth=0
  "$@"
}
