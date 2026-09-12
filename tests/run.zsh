#!/usr/bin/env zsh
# Run with: zsh -f tests/run.zsh
emulate -LR zsh
setopt extendedglob
typeset TEST_ROOT=${0:A:h:h}
# Prove that loading and exercising the library needs no external commands.
path=()
source "$TEST_ROOT/zjson.zsh" || exit 1
typeset -i checks=0 failures=0

assert_eq() {
  (( ++checks ))
  if [[ "$1" != "$2" ]]; then
    (( ++failures ))
    print -u2 -r -- "FAIL: $3; expected ${(qqqq)1}, got ${(qqqq)2}"
  fi
  return 0
}

assert_ok() { assert_eq 0 "$1" "$2"; }
assert_bad() {
  (( ++checks ))
  if (( $1 == 0 )) || [[ -z "$ZJSON_ERROR" ]]; then
    (( ++failures ))
    print -u2 -r -- "FAIL: $2; status $1, error ${(qqqq)ZJSON_ERROR}"
  fi
  return 0
}

typeset sample expected quoted ch encoded wire
typeset -i code
for sample in 'null' 'true' 'false' '0' '-0' '12' '-12.25e+2' '1E-3' \
  '1234567890123456789012345678901234567890' '1e9999999' '""' '"é😀"' \
  '[]' '{}' '[{},[],"",0,false,null]' '{"":{"a":[1,{"b":2}]}}' \
  $' \t\r\n{"x":1}\n'; do
  zjson_validate "$sample"
  assert_ok $? "accept ${(qqqq)sample}"
done

for sample in '' ' ' '01' '-01' '-' '+1' '.1' '1.' '1e' '1e+' '1..2' \
  'NaN' 'Infinity' 'True' 'nul' 'truefalse' 'true false' '{}[]' 'null 1' \
  '[' '{' ']' '}' ':' ',' '[1,]' '{"a":1,}' '{a:1}' '{"a" 1}' \
  '{"a":}' '[1 2]' '{"a":1 "b":2}' '[,1]' '[1,,2]' '{"a":[]]' \
  '"unterminated' '"\q"' '"\u000g"' '"\u123"' '"\u"' '"\"' \
  $'\vnull' $'\fnull' $'"a\nb"' $'"\xff"' $'"\xc0\xaf"' \
  $'\xef\xbb\xbf{}' $'null\0'; do
  zjson_validate "$sample"
  assert_bad $? "reject ${(qqqq)sample}"
done

for (( code=0; code<32; code++ )); do
  printf -v encoded '\\x%02x' "$code"
  printf -v ch '%b' "$encoded"
  sample="${ch}é${ch}"
  zjson_quote "$sample"; quoted="$REPLY"
  zjson_begin "$quoted"
  assert_ok $? "parse escaped control $code"
  assert_eq "$sample" "$ZJSON_TOKEN_VALUE" "round-trip control $code"
  zjson_validate "\"$sample\""
  assert_bad $? "reject literal control $code"
done

for sample in '' '"' '\' '\\' '\n' 'x\ny' 'a"b\c' \
  $'\n\n\t\r\b\f' $'\177' '你好 👋 é' '$(print hacked)' '`print hacked`'; do
  zjson_quote "$sample"
  zjson_begin "$REPLY"
  assert_ok $? 'parse quoted text'
  assert_eq "$sample" "$ZJSON_TOKEN_VALUE" 'quote/decode preserves text'
done

zjson_begin '"\u0000\u007f\u0080\u07ff\u0800\uffff\ud800\udc00\udbff\udfff"'
assert_ok $? 'decode Unicode boundaries'
assert_eq $'\0\x7f\xc2\x80\xdf\xbf\xe0\xa0\x80\xef\xbf\xbf\xf0\x90\x80\x80\xf4\x8f\xbf\xbf' "$ZJSON_TOKEN_VALUE" 'UTF-8 byte encoding'
zjson_begin '"\ud800\u0041\udc00"'
assert_ok $? 'accept unpaired surrogate escapes'
assert_eq $'\xef\xbf\xbdA\xef\xbf\xbd' "$ZJSON_TOKEN_VALUE" 'replace unpaired surrogates'
zjson_begin '"\u0041\n\t\b\f\r\/\\\""'
assert_eq $'A\n\t\b\f\r/\\"' "$ZJSON_TOKEN_VALUE" 'mixed Unicode and simple escapes'

zjson_parse_object '{"":"empty key","name":"zjson","enabled":true,"nil":null,"n":-0.20E+50,"nested": { "a" : [1] },"list":[false, ""],"name":"last"}'
assert_ok $? 'decode object'
key=""
assert_eq 'empty key' "${ZJSON_OBJECT[$key]}" 'empty object key'
assert_eq last "${ZJSON_OBJECT[name]}" 'last duplicate key wins'
assert_eq true "${ZJSON_OBJECT_TYPES[enabled]}" 'boolean type'
assert_eq null "${ZJSON_OBJECT_TYPES[nil]}" 'null type'
assert_eq '-0.20E+50' "${ZJSON_OBJECT[n]}" 'number spelling is exact'
assert_eq '{ "a" : [1] }' "${ZJSON_OBJECT[nested]}" 'nested object retains source'
assert_eq '[' "${ZJSON_OBJECT_TYPES[list]}" 'array type'
zjson_parse_object '{"good":1,"bad":}'
assert_bad $? 'malformed object fails'
assert_eq 0 "${#ZJSON_OBJECT}" 'failure clears object output'
assert_eq 0 "${#ZJSON_OBJECT_TYPES}" 'failure clears object types'
zjson_parse_object '[]'
assert_bad $? 'object API requires object'

zjson_parse_array '["", "a\nb", 12345678901234567890, false, null, { "k":1 }, []]'
assert_ok $? 'decode array'
assert_eq 7 "${#ZJSON_ARRAY}" 'array preserves empty string element'
assert_eq '' "${ZJSON_ARRAY[1]}" 'first array element'
assert_eq $'a\nb' "${ZJSON_ARRAY[2]}" 'decoded newline'
assert_eq '12345678901234567890' "${ZJSON_ARRAY[3]}" 'large number text'
assert_eq '{ "k":1 }' "${ZJSON_ARRAY[6]}" 'raw nested object'
assert_eq 'string string number false null { [' "${(j: :)ZJSON_ARRAY_TYPES}" 'array types'
zjson_parse_array '[1,]'
assert_bad $? 'malformed array fails'
assert_eq 0 "${#ZJSON_ARRAY}" 'failure clears array output'
assert_eq 0 "${#ZJSON_ARRAY_TYPES}" 'failure clears array types'
zjson_parse_array '{}'
assert_bad $? 'array API requires array'
zjson_parse_array '[] false'
assert_bad $? 'array API requires EOF'
zjson_parse_object '{} false'
assert_bad $? 'object API requires EOF'

wire=$' { "a" : [1, "\\u00e9",true], "b":null } \n'
zjson_begin "$wire" && zjson_capture_raw_value
assert_ok $? 'capture raw value'
assert_eq '{ "a" : [1, "\u00e9",true], "b":null }' "$REPLY" 'raw capture keeps inner whitespace and escapes'
assert_eq eof "$ZJSON_TOKEN_TYPE" 'capture consumes value'
zjson_begin "$wire" && zjson_capture_value
assert_ok $? 'capture compact value'
assert_eq '{"a":[1,"é",true],"b":null}' "$REPLY" 'compact capture serializes values'
zjson_begin '[1,]'
zjson_capture_value
assert_bad $? 'compact capture rejects malformed input'
zjson_next
assert_bad $? 'token errors remain set until begin'
zjson_begin '"\q"'
zjson_capture_value
assert_bad $? 'capture cannot recover a failed string token'
zjson_validate 'true'
assert_ok $? 'begin resets errors'

# JSON keys and values must never become shell code or arithmetic expressions.
typeset sentinel=unchanged
sample='{"$(sentinel=hacked)":"$(sentinel=hacked)","a[1]":"*?[]","`sentinel=hacked`":"literal"}'
zjson_parse_object "$sample"
assert_ok $? 'metacharacter keys'
typeset key='$(sentinel=hacked)'
assert_eq '$(sentinel=hacked)' "${ZJSON_OBJECT[$key]}" 'literal key lookup'
assert_eq unchanged "$sentinel" 'input is never evaluated'

sample="${(pl:128::[:)}0${(pl:128::]:)}"
zjson_validate "$sample"
assert_ok $? '128 levels accepted'
zjson_validate "[$sample]"
assert_bad $? '129 levels rejected'
zjson_begin "[$sample]" && zjson_capture_value
assert_bad $? 'compact capture bounds recursion'
zjson_parse_array "[$sample]"
assert_bad $? 'array decoding includes root in depth limit'
zjson_parse_object "{\"a\":$sample}"
assert_bad $? 'object decoding includes root in depth limit'

zjson_validate
assert_eq 2 $? 'missing input is a usage error'
zjson_validate '{}' '{}'
assert_eq 2 $? 'extra input is a usage error'
zjson_quote
assert_eq 2 $? 'quote requires one argument'
assert_eq '' "$REPLY" 'quote usage error clears scalar result'
zjson_quote a b
assert_eq 2 $? 'quote rejects extra arguments'
zjson_parse_object '{}'
assert_ok $? 'empty object succeeds'
assert_eq 0 "${#ZJSON_OBJECT}" 'empty object has no invented members'
zjson_parse_array '[]'
assert_ok $? 'empty array succeeds'
assert_eq 0 "${#ZJSON_ARRAY}" 'empty array has no invented elements'

# Loading and calls preserve options, aliases, locale, and caller scratch state.
() {
  setopt shwordsplit ksharrays globsubst rcexpandparam
  unsetopt multibyte
  local LC_ALL=C before="$-" value=caller input=caller key=caller
  alias local='print BROKEN'
  source "$TEST_ROOT/zjson.zsh"
  zjson_parse_object '{"x":"\u00e9\ud83d\ude00"}'
  assert_ok $? 'load and parse under hostile options and aliases'
  assert_eq $'\xc3\xa9\xf0\x9f\x98\x80' "${ZJSON_OBJECT[x]}" 'Unicode under C locale'
  assert_eq "$before" "$-" 'caller options preserved'
  assert_eq 'print BROKEN' "${aliases[local]}" 'caller alias preserved'
  assert_eq caller "$value" 'caller value preserved'
  assert_eq caller "$input" 'caller input preserved'
  assert_eq caller "$key" 'caller key preserved'
  [[ -o shwordsplit && -o ksharrays && -o globsubst && -o rcexpandparam && ! -o multibyte ]]
  assert_ok $? 'named caller options preserved'
  assert_eq C "$LC_ALL" 'caller locale preserved'
  unalias local
}

sample=$(source "$TEST_ROOT/zjson.zsh"; zjson_quote 'hello'; zjson_parse_array '[1]'; zjson_validate 'false')
assert_eq '' "$sample" 'loading and library calls do not print'
source "$TEST_ROOT/tests/utf8.zsh" || exit 1
source "$TEST_ROOT/tests/diagnostics.zsh" || exit 1
source "$TEST_ROOT/tests/pointer.zsh" || exit 1
source "$TEST_ROOT/tests/scanner.zsh" || exit 1
source "$TEST_ROOT/tests/utf8_api.zsh" || exit 1
source "$TEST_ROOT/tests/context.zsh" || exit 1
print -r -- "$checks checks, $failures failures (external command path empty)"
(( failures == 0 ))
