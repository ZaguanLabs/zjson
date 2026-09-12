# RFC 6901 examples and lookup/validation boundary regressions.
assert_get() {
  emulate -L zsh
  zjson_get "$3" "$4"
  assert_ok $? "$5 succeeds"
  assert_eq "$1" "$REPLY" "$5 value"
  assert_eq "$2" "$ZJSON_TYPE" "$5 type"
  assert_eq '' "$ZJSON_ERROR_CODE" "$5 clears diagnostics"
}

assert_get_error() {
  emulate -L zsh
  REPLY=stale
  ZJSON_TYPE=stale
  zjson_get "$3" "$4"
  assert_eq "$1" "$?" "$5 status"
  assert_eq "$2" "$ZJSON_ERROR_CODE" "$5 error code"
  assert_eq '' "$REPLY" "$5 clears value"
  assert_eq '' "$ZJSON_TYPE" "$5 clears type"
}

() {
  local doc='{"foo":["bar","baz"],"":0,"a/b":1,"c%d":2,"e^f":3,"g|h":4,"i\\j":5,"k\"l":6," ":7,"m~n":8}'
  local pointer expected sample key
  local -i i sentinel=7
  local -a cases=(
    /foo/0 bar string
    /foo/1 baz string
    /foo '["bar","baz"]' '['
    / 0 number
    /a~1b 1 number
    /c%d 2 number
    '/e^f' 3 number
    /g\|h 4 number
    '/i\j' 5 number
    '/k"l' 6 number
    '/ ' 7 number
    /m~0n 8 number
  )
  for (( i=1; i<=${#cases}; i+=3 )); do
    assert_get "${cases[i+1]}" "${cases[i+2]}" "$doc" "${cases[i]}" "RFC example ${cases[i]}"
  done
  assert_get "$doc" '{' "$doc" '' 'empty pointer selects root'
  assert_get ' { "x" : 1 } ' string '" { \"x\" : 1 } "' '' 'root string decodes'
  assert_get '{ "x" : 1 }' '{' $' \n{ "x" : 1 }\t' '' 'root container keeps only internal whitespace'
  assert_get null null '{"x":null}' /x 'null is present'
  assert_get '' string '{"x":""}' /x 'empty string is present'
  assert_get false false '[false]' /0 'false is present'
  assert_get true true '[true]' /0 'true is present'
  assert_get '-0.123E+9999' number '[-0.123E+9999]' /0 'number spelling preserved'
  assert_get 1 number '{"":{"":1}}' // 'consecutive empty keys'
  assert_get 2 number '{"x":{"":2}}' /x/ 'trailing empty key'
  assert_get 3 number '{"~1":3,"/":4}' /~01 'escape decoding order'
  assert_get 4 number '{"~1":3,"/":4}' /~1 'escaped slash'
  assert_get 5 number '{"~":5}' /~0 'escaped tilde'
  assert_get 6 number '{"a//b":6}' /a~1~1b 'multiple escaped slashes'
  assert_get 7 number '{"\u00e9":{"\ud83d\ude00":7}}' /é/😀 'Unicode keys'
  assert_get 8 number '{"a\nb":8}' $'/a\nb' 'newline in key'
  assert_get 9 number '{"\u0000":9}' $'/\0' 'NUL in key'
  assert_get 10 number '{"01":10}' /01 'numeric object key is literal'
  assert_get 11 number '{"-":11}' /- 'dash object key is literal'
  assert_get 12 number '{"%2F":12}' /%2F 'percent sequences are literal'
  assert_get '[ 1, {"a":2} ]' '[' '{"x":[ 1, {"a":2} ]}' /x 'container source preserved'

  assert_get_error 3 pointer_not_found "$doc" /missing 'missing object member'
  assert_get_error 3 pointer_not_found '[]' /0 'empty array'
  assert_get_error 3 pointer_not_found '[1]' /1 'array upper bound'
  assert_get_error 3 pointer_not_found '[1]' /- 'dash has no existing array element'
  assert_get_error 3 pointer_not_found '[1]' /99999999999999999999999999999999 'huge index never overflows'
  assert_get_error 3 pointer_type '{"x":1}' /x/y 'cannot descend into scalar'
  assert_get_error 3 pointer_not_found '{"é":1}' $'/e\xcc\x81' 'no Unicode normalization'
  for pointer in /01 /00 /+1 /-1 /1.0 /1e0 /x / /'sentinel=99' /'$(sentinel=99)'; do
    assert_get_error 3 pointer_index '[0,1]' "$pointer" 'invalid array index'
  done
  assert_eq 7 "$sentinel" 'index text never reaches arithmetic'
  for pointer in foo '#/foo' /~ /~2 /~a /a~1b~ /~~0 $'/\xff'; do
    assert_get_error 2 pointer_syntax '{}' "$pointer" 'invalid pointer syntax'
    assert_eq 0 "$ZJSON_ERROR_OFFSET" 'pointer syntax has no JSON offset'
  done

  assert_get_error 3 pointer_ambiguous '{"x":1,"x":2}' /x 'duplicate referenced member'
  assert_get_error 3 pointer_ambiguous '{"x":1,"\u0078":2}' /x 'duplicate decoded member'
  assert_get_error 3 pointer_ambiguous '{"x":{},"x":{"a":1}}' /x/a 'duplicate ancestor overrides missing descendant'
  assert_get 3 number '{"x":1,"x":2,"y":3}' /y 'unreferenced duplicate remains allowed'
  assert_get '{"x":1,"x":2}' '{' '{"x":1,"x":2}' '' 'root lookup preserves duplicates'

  for pointer in /x /missing /x/y; do
    assert_get_error 1 trailing_comma '{"x":1,"later":[2,]}' "$pointer" 'malformed suffix overrides lookup result'
    assert_get_error 1 trailing_content '{"x":1} false' "$pointer" 'trailing value overrides lookup result'
  done
  assert_get_error 1 expected_value '{"x":1,"x":}' /x 'invalid JSON overrides ambiguity'
  assert_get_error 1 invalid_utf8 $'{"x":1,"y":"\xff"}' /x 'invalid unselected UTF-8'
  assert_get_error 1 expected_key '{' '' 'root lookup validates grammar'

  sample="${(pl:128::[:)}0${(pl:128::]:)}"
  pointer=${(l:256::/0:)}
  assert_get 0 number "$sample" "$pointer" 'lookup at maximum depth'
  assert_get_error 1 nesting_limit "[$sample]" /0 'selected branch enforces total depth'
  assert_get_error 1 nesting_limit "[$sample]" /1 'unselected branch enforces total depth'

  for key in '*?[]' 'a[1]' '$(sentinel=99)' '`sentinel=99`'; do
    zjson_quote "$key"
    doc="{$REPLY:1}"
    assert_get 1 number "$doc" "/$key" 'shell metacharacters are literal'
  done
  assert_eq 7 "$sentinel" 'key text never executes'
  local REPLY=caller
  zjson_get '{"x":42}' /x
  assert_eq 42 "$REPLY" 'get honors caller-local REPLY'
  zjson_get '{}'
  assert_eq 2 $? 'get requires two arguments'
  assert_eq usage "$ZJSON_ERROR_CODE" 'get usage code'
  assert_eq '' "$REPLY" 'usage clears result'
  zjson_get '{}' '' extra
  assert_eq 2 $? 'get rejects extra arguments'
  zjson_get
  assert_eq 2 $? 'get rejects missing arguments'
} || return 1

() {
  local LC_ALL=C before="$-" REPLY=''
  setopt shwordsplit ksharrays globsubst rcexpandparam
  unsetopt multibyte
  zjson_get '{"é":["\ud83d\ude00"]}' /é/0
  assert_ok $? 'get under foreign caller options'
  assert_eq $'\xf0\x9f\x98\x80' "$REPLY" 'get in C locale'
  [[ -o shwordsplit && -o ksharrays && -o globsubst && -o rcexpandparam && ! -o multibyte ]]
  assert_ok $? 'get preserves options'
  zjson_get $'{\n"é": [1,]\n}' /é/0
  assert_eq trailing_comma "$ZJSON_ERROR_CODE" 'diagnostics under foreign caller options'
  assert_eq 2 "$ZJSON_ERROR_LINE" 'diagnostics keep LF line counting'
} || return 1
