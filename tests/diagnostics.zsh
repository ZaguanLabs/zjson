# Diagnostic location policy: tokens for grammar/number/literal failures,
# offending byte for controls/escapes/UTF-8, and length+1 for missing input.
assert_diagnostic() {
  emulate -L zsh
  zjson_validate "$1"
  assert_eq 1 $? "$6 fails"
  assert_eq "$2" "$ZJSON_ERROR_CODE" "$6 code"
  assert_eq "$3" "$ZJSON_ERROR_OFFSET" "$6 byte offset"
  assert_eq "$4" "$ZJSON_ERROR_LINE" "$6 line"
  assert_eq "$5" "$ZJSON_ERROR_COLUMN" "$6 byte column"
}

assert_diagnostic '' expected_value 1 1 1 'empty document'
assert_diagnostic $'\n\n' expected_value 3 3 1 'EOF after newlines'
assert_diagnostic $'{\n  "x": 01\n}' invalid_number 10 2 8 'invalid number'
assert_diagnostic '[truth]' invalid_literal 2 1 2 'invalid literal'
assert_diagnostic $'{\n "x" 1}' expected_colon 8 2 6 'missing colon'
assert_diagnostic '{x:1}' unexpected_character 2 1 2 'unexpected character'
assert_diagnostic '{1:1}' expected_key 2 1 2 'expected key'
assert_diagnostic '[1 2]' expected_array_separator 4 1 4 'array separator'
assert_diagnostic '{"x":1 "y":2}' expected_object_separator 8 1 8 'object separator'
assert_diagnostic '[1,]' trailing_comma 4 1 4 'trailing comma'
assert_diagnostic '{} []' trailing_content 4 1 4 'trailing content'
assert_diagnostic '"\q"' invalid_escape 3 1 3 'invalid escape byte'
assert_diagnostic '"\u12x4"' invalid_unicode_escape 4 1 4 'Unicode escape digit group'
assert_diagnostic '"abc' unterminated_string 5 1 5 'unterminated string EOF'
assert_diagnostic '"abc\' unterminated_escape 6 1 6 'unterminated escape EOF'
assert_diagnostic $'"ab\1"' unescaped_control 4 1 4 'control in fast string'
assert_diagnostic $'"\\u0041ab\1"' unescaped_control 10 1 10 'control in slow string'
assert_diagnostic $'"\\nab\1"' unescaped_control 6 1 6 'control after simple escape'
assert_diagnostic $'{\n"é": [1,]\n}' trailing_comma 12 2 10 'multibyte byte column'
assert_diagnostic $'[\r\n1,\r\n]' trailing_comma 8 3 1 'CRLF lines'
assert_diagnostic $'{\n"x":"\xff"}' invalid_utf8 8 2 6 'malformed UTF-8 byte'
assert_diagnostic $'"\xe2\x82A"' invalid_utf8 2 1 2 'malformed UTF-8 prefix'
assert_diagnostic $'"\xe2\x82' invalid_utf8 2 1 2 'truncated UTF-8 prefix'

() {
  local prefix="${(l:1023::x:)}"
  local -i offset=$(( ${#prefix} + 2 ))
  assert_diagnostic "\"${prefix}"$'\xff"' invalid_utf8 "$offset" 1 "$offset" 'UTF-8 error across repair block'
  zjson_parse_object '[1]'
  assert_eq expected_object "$ZJSON_ERROR_CODE" 'object API type diagnostic'
  zjson_parse_array '{"x":1}'
  assert_eq expected_array "$ZJSON_ERROR_CODE" 'array API type diagnostic'
  zjson_validate
  assert_eq usage "$ZJSON_ERROR_CODE" 'usage diagnostic'
  assert_eq '0 0 0' "$ZJSON_ERROR_OFFSET $ZJSON_ERROR_LINE $ZJSON_ERROR_COLUMN" 'usage has no source location'
  zjson_validate '[1,]'
  local saved="$ZJSON_ERROR_CODE $ZJSON_ERROR_OFFSET $ZJSON_ERROR_LINE $ZJSON_ERROR_COLUMN"
  zjson_next
  assert_eq "$saved" "$ZJSON_ERROR_CODE $ZJSON_ERROR_OFFSET $ZJSON_ERROR_LINE $ZJSON_ERROR_COLUMN" 'token failure preserves first diagnostic'
  zjson_validate '1'
  assert_eq '' "$ZJSON_ERROR_CODE" 'valid input resets code'
  assert_eq '0 0 0' "$ZJSON_ERROR_OFFSET $ZJSON_ERROR_LINE $ZJSON_ERROR_COLUMN" 'valid input resets location'
  zjson_validate '[1,]'
  zjson_quote x
  assert_eq '' "$ZJSON_ERROR_CODE" 'quote resets code'
  assert_eq '0 0 0' "$ZJSON_ERROR_OFFSET $ZJSON_ERROR_LINE $ZJSON_ERROR_COLUMN" 'quote resets location'
} || return 1
