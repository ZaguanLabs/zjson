# Adapted from zcoder.zsh/tests/json_utf8.zsh (Apache-2.0).
# JSON output must remain UTF-8 even for binary commands and old transcripts.
() {
  local sample='' expected='' quoted='' prefix=''
  local replacement=$'\xef\xbf\xbd'
  local -a cases=(
    $'\x80\xff' "${replacement}${replacement}"
    $'\xc0\xaf' "${replacement}${replacement}"
    $'\xe0\x80\x80' "${replacement}${replacement}${replacement}"
    $'\xed\xa0\x80' "${replacement}${replacement}${replacement}"
    $'\xf4\x90\x80\x80' "${replacement}${replacement}${replacement}${replacement}"
    $'\xf5\x80\x80\x80' "${replacement}${replacement}${replacement}${replacement}"
    $'\xc2' "$replacement"
    $'\xe2\x82' "$replacement"
    $'\xf0\x90\x80' "$replacement"
    $'\xe2\x82A\xc3\xa9' "${replacement}Aé"
    $'\xe2"\\\n' "${replacement}"$'"\\\n'
  )
  local -i i padding
  for (( i=1; i<=${#cases}; i+=2 )); do
    zjson_quote "${cases[i]}"; quoted="$REPLY"
    zjson_begin "$quoted"
    assert_ok $? 'malformed UTF-8 still produces a JSON string'
    assert_eq "${cases[i+1]}" "$ZJSON_TOKEN_VALUE" 'JSON replaces malformed prefixes and retains following text'
  done
  # Boundary values exclude overlong forms, surrogates, and values > U+10FFFF.
  sample=$'\xc2\x80\xdf\xbf\xe0\xa0\x80\xed\x9f\xbf\xee\x80\x80\xef\xbf\xbf\xf0\x90\x80\x80\xf4\x8f\xbf\xbf'
  zjson_quote "$sample"
  assert_eq "\"$sample\"" "$REPLY" 'JSON preserves all valid UTF-8 boundary encodings'
  for padding in 1021 1022 1023 1024; do
    prefix=${(pl:$padding::a:)}
    for sample in é € 😀 $'\xe2\x82A'; do
      _zjson_utf8_text "$sample"; expected="${prefix}${REPLY}tail"
      zjson_quote "${prefix}${sample}tail"
      assert_eq "\"$expected\"" "$REPLY" 'UTF-8 repair preserves characters across block boundaries'
    done
  done
  sample=${(pl:100000::é😀:)}
  zjson_quote "$sample"
  assert_eq "\"$sample\"" "$REPLY" 'large Unicode strings encode without unbounded glob recursion'
  # Encoding must not depend on the caller's locale or MULTIBYTE setting.
  (
    local LC_ALL=C
    unsetopt multibyte
    zjson_quote $'\xc3\xa9\xff\xf0\x9f\x98\x80'
    [[ "$REPLY" == $'"\xc3\xa9\xef\xbf\xbd\xf0\x9f\x98\x80"' ]]
  )
  assert_ok $? 'JSON repairs UTF-8 in the C locale with MULTIBYTE disabled'
} || return 1
