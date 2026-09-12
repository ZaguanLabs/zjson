# Deterministic strings built from independent JSON spellings. This exercises
# the optimized scanner with mixed escape runs, without another interpreter.
() {
  local -a decoded=( 'a' ' ' '"' '\' '/' $'\n' $'\t' $'\0' 'é' '😀' '~' )
  local -a encoded=( 'a' ' ' '\"' '\\' '\/' '\n' '\t' '\u0000' '\u00e9' '\ud83d\ude00' '~' )
  local -a expected=() documents=()
  local -i seed=1977 i j pick count
  local value wire doc
  for (( i=1; i<=100; ++i )); do
    value=''
    wire='"'
    count=$(( i % 41 ))
    for (( j=0; j<count; ++j )); do
      seed=$(( (25173 * seed + 13849) % 65536 ))
      pick=$(( seed % ${#decoded} + 1 ))
      value+="${decoded[pick]}"
      wire+="${encoded[pick]}"
    done
    wire+='"'
    zjson_begin "$wire"
    assert_ok $? 'generated mixed-escape string parses'
    assert_eq "$value" "$ZJSON_TOKEN_VALUE" 'generated string decodes exactly'
    expected+=( "$value" )
    documents+=( "$wire" )
  done
  doc="[${(j:,:)documents}]"
  zjson_parse_array "$doc"
  assert_ok $? 'generated string array parses'
  assert_eq 100 "${#ZJSON_ARRAY}" 'generated array preserves all boundaries'
  for (( i=1; i<=100; ++i )); do
    assert_eq "${expected[i]}" "${ZJSON_ARRAY[i]}" 'generated array element'
  done
  zjson_get "$doc" /99
  assert_ok $? 'lookup traverses generated mixed-escape array'
  assert_eq "${expected[100]}" "$REPLY" 'lookup result after mixed-escape siblings'
} || return 1
