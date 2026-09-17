# Additive APIs, source order, encoding, and tokenizer grammar neutrality.
api_collect() {
  api_values+=( "$2" )
  api_types+=( "$3" )
  return 0
}

api_collect_nested() {
  zjson_get '{"inner":7}' /inner || return 1
  api_values+=( "$REPLY" )
  api_types+=( "$ZJSON_TYPE" )
}

api_fail() { return 19; }

() {
  local sample expected
  zjson_parse 'true'
  assert_ok $? 'generic parse accepts scalar root'
  assert_eq true "$REPLY" 'generic parse scalar value'
  assert_eq true "$ZJSON_TYPE" 'generic parse scalar type'
  zjson_parse ' { "a" : [1] } '
  assert_ok $? 'generic parse accepts container root'
  assert_eq '{ "a" : [1] }' "$REPLY" 'generic parse keeps container source'
  assert_eq '{' "$ZJSON_TYPE" 'generic parse container type'
  zjson_parse '[1] true'
  assert_bad $? 'generic parse requires EOF'
  zjson_parse
  assert_eq 2 $? 'generic parse requires one argument'

  zjson_begin '[1,]'
  zjson_next; zjson_next
  assert_eq ',' "$ZJSON_TOKEN_TYPE" 'token API exposes comma'
  zjson_next
  assert_ok $? 'token API exposes closing bracket after comma'
  assert_eq ']' "$ZJSON_TOKEN_TYPE" 'token API does not enforce container grammar'

  zjson_parse_object '{"z":1,"a":2,"z":3,"m":4}'
  assert_ok $? 'object with duplicate keys parses'
  assert_eq 'z a m' "${(j: :)ZJSON_OBJECT_KEYS}" 'object keys preserve first source order'
  assert_eq z "${ZJSON_OBJECT_DUPLICATE_KEYS[1]}" 'duplicate keys are reported'
  assert_eq 3 "${ZJSON_OBJECT[z]}" 'last duplicate value still wins'
  zjson_encode_object
  assert_ok $? 'object encodes'
  assert_eq '{"z":3,"a":2,"m":4}' "$REPLY" 'object encoding preserves source order'

  zjson_parse_array '[0,-1.25e+3,"a\nb",true,false,null,{"k":[1]},[]]'
  assert_ok $? 'array for encoding parses'
  zjson_encode_array
  assert_ok $? 'array encodes'
  assert_eq '[0,-1.25e+3,"a\nb",true,false,null,{"k":[1]},[]]' "$REPLY" 'array encoding preserves types and spelling'

  sample='text "quoted"\'
  zjson_encode_value "$sample" string
  assert_ok $? 'string value encodes'
  zjson_begin "$REPLY"
  assert_ok $? 'encoded string parses'
  assert_eq "$sample" "$ZJSON_TOKEN_VALUE" 'string encoding round-trips'
  zjson_encode_value 1e9999999 number
  assert_ok $? 'large number encodes without arithmetic'
  assert_eq 1e9999999 "$REPLY" 'large number spelling is preserved'
  zjson_encode_value null true
  assert_eq 2 $? 'value must match boolean type tag'
  zjson_encode_value 01 number
  assert_bad $? 'invalid number text is rejected'
  zjson_encode_value '{"a":1' '{'
  assert_bad $? 'nested container text is validated'
  zjson_encode_value x unknown
  assert_eq 2 $? 'unknown type tag is a usage error'

  zjson_parse_object '{"name":"zjson","enabled":true,"ports":[8080,8081]}'
  zjson_encode_object
  expected="$REPLY"
  zjson_parse "$expected"
  assert_ok $? 'encoded object round-trips'
  assert_eq zjson "${ZJSON_OBJECT[name]}" 'round-trip object value'
  assert_eq true "${ZJSON_OBJECT_TYPES[enabled]}" 'round-trip object type'

  ZJSON_OBJECT=(a 1 b 2)
  ZJSON_OBJECT_TYPES=(a number b number)
  ZJSON_OBJECT_KEYS=()
  zjson_encode_object
  assert_ok $? 'manual object encodes without source-order array'
  assert_eq '{"a":1,"b":2}' "$REPLY" 'manual object uses sorted key fallback'
  ZJSON_OBJECT_KEYS=(a a)
  zjson_encode_object
  assert_eq 2 $? 'object encoder rejects duplicate source-order keys'

  local -a api_values=() api_types=()
  zjson_each_object '{"a":1,"b":"x"}' api_collect prefix
  assert_ok $? 'object callback iteration succeeds'
  assert_eq '1 x' "${(j: :)api_values}" 'object callback values'
  assert_eq 'number string' "${(j: :)api_types}" 'object callback types'
  api_values=(); api_types=()
  zjson_each_array '[10,true,"x"]' api_collect
  assert_ok $? 'array callback iteration succeeds'
  assert_eq '10 true x' "${(j: :)api_values}" 'array callback values'
  assert_eq 'number true string' "${(j: :)api_types}" 'array callback types'
  api_values=(); api_types=()
  zjson_each_object '{"a":{"inner":7}}' api_collect_nested
  assert_ok $? 'callback can parse unrelated JSON'
  assert_eq 7 "${api_values[1]}" 'nested callback result is visible'
  zjson_each_array '[1]' api_fail
  assert_eq 19 $? 'callback status propagates'
  zjson_each_object '[]' api_collect
  assert_bad $? 'object callback root must be an object'
  zjson_each_array '[1,]' api_collect
  assert_bad $? 'array callback validates complete document'

  zjson_get_multi '{"a":{"x":1},"b":[2,3],"c":"str"}' /a /a/x /b/1 /b /c
  assert_ok $? 'multi-get resolves all pointers'
  assert_eq '{"x":1}|1|3|[2,3]|str' "${(j:|:)ZJSON_RESULTS}" 'multi-get result order'
  assert_eq '{|number|number|[|string' "${(j:|:)ZJSON_TYPES}" 'multi-get type order'
  zjson_get_multi '{"a":{"x":1},"b":[2,3]}' /missing /a/x
  assert_eq 3 $? 'one missing pointer fails multi-get'
  assert_eq pointer_not_found "$ZJSON_ERROR_CODE" 'multi-get reports missing pointer'
  assert_eq 0 "${#ZJSON_RESULTS}" 'failed multi-get clears results'
  zjson_get_multi '{"x":1,"x":2}' /x
  assert_eq 3 $? 'multi-get rejects duplicate referenced key'
  assert_eq pointer_ambiguous "$ZJSON_ERROR_CODE" 'multi-get duplicate code'
  zjson_get_multi '[1]' /0/y
  assert_eq 3 $? 'multi-get rejects scalar descent'
  assert_eq pointer_type "$ZJSON_ERROR_CODE" 'multi-get scalar descent code'
  zjson_get_multi '[1,]' /0
  assert_bad $? 'multi-get validates unselected malformed suffix'
  zjson_get_multi '{}'
  assert_eq 2 $? 'multi-get requires at least one pointer'
  zjson_get_multi '{"a":1,"b":{"x":2},"empty":""}' /a /a/y /empty
  assert_eq 3 $? 'multi-get clears results when another pointer fails'
  assert_eq 0 "${#ZJSON_RESULTS}" 'partial multi-get results are not published'

  zjson_validate '{"ok":true}'
  assert_ok $? 'successful validation'
  assert_eq 0 "${#ZJSON_CHARS}" 'validation releases byte array'
  zjson_get '{"ok":true}' /ok
  assert_ok $? 'successful lookup'
  assert_eq 0 "${#ZJSON_CHARS}" 'lookup releases byte array'
  zjson_parse_array '[1]'
  assert_ok $? 'successful array parse'
  assert_eq 0 "${#ZJSON_CHARS}" 'array parse releases byte array'

  zjson_get_multi '{"empty":"","one":1}' /empty /one
  assert_ok $? 'multi-get preserves empty first result'
  assert_eq '|1' "${(j:|:)ZJSON_RESULTS}" 'multi-get empty result boundary'
} || return 1

() {
  local LC_ALL=C.UTF-8
  zjson_validate $'"\xe0\x80\xaf"'
  assert_bad $? 'UTF-8 locale rejects overlong encoding'
  zjson_validate $'"\xed\xa0\x80"'
  assert_bad $? 'UTF-8 locale rejects encoded surrogate'
  zjson_validate $'"\xf4\x90\x80\x80"'
  assert_bad $? 'UTF-8 locale rejects value above U+10FFFF'
} || return 1

() {
  local LC_ALL=C before="$-"
  setopt shwordsplit ksharrays globsubst rcexpandparam
  unsetopt multibyte
  zjson_parse_object '{"é":"\ud83d\ude00","x":1}'
  assert_ok $? 'new APIs parse under hostile caller options'
  zjson_encode_object
  assert_ok $? 'object encoding under hostile caller options'
  zjson_get_multi '{"é":"x","x":1}' /é /x
  assert_ok $? 'multi-get under hostile caller options'
  local -a hostile_results=( "${ZJSON_RESULTS[@]}" )
  zjson_each_object '{"x":1}' api_collect
  assert_ok $? 'callback iteration under hostile caller options'
  [[ -o shwordsplit && -o ksharrays && -o globsubst && -o rcexpandparam && ! -o multibyte ]]
  assert_ok $? 'new APIs preserve caller options'
  assert_eq C "$LC_ALL" 'new APIs preserve caller locale'
  emulate -L zsh
  assert_eq 'x|1' "${(j:|:)hostile_results}" 'multi-get results under hostile caller options'
} || return 1
