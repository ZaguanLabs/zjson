# All lead bytes, continuation counts and second-byte boundary classes.
# Expected validity is derived from the UTF-8 encoding widths/ranges, without
# using the validator, repair implementation, or another interpreter as oracle.
() {
  local -a tails=( 0 127 128 143 144 159 160 191 194 255 )
  local -i lead tail count expected
  local head suffix input escaped
  for (( lead=0; lead<256; ++lead )); do
    printf -v escaped '\\x%02x' "$lead"
    printf -v head '%b' "$escaped"
    for tail in "${tails[@]}"; do
      printf -v escaped '\\x%02x' "$tail"
      printf -v suffix '%b' "$escaped"
      input="$head"
      for (( count=0; count<=4; ++count )); do
        expected=1
        if (( lead < 128 )); then
          (( count == 0 || tail < 128 )) && expected=0
        elif (( tail >= 128 && tail <= 191 )); then
          if (( lead >= 194 && lead <= 223 && count == 1 )); then
            expected=0
          elif (( lead >= 224 && lead <= 239 && count == 2 )); then
            if (( (lead != 224 || tail >= 160) && (lead != 237 || tail < 160) )); then
              expected=0
            fi
          elif (( lead >= 240 && lead <= 244 && count == 3 )); then
            if (( (lead != 240 || tail >= 144) && (lead != 244 || tail < 144) )); then
              expected=0
            fi
          fi
        fi
        _zjson_utf8_valid "$input"
        assert_eq "$expected" $? "UTF-8 lead=$lead tail=$tail count=$count"
        input+="$suffix"
      done
    done
  done
} || return 1

() {
  local saved REPLY input expected
  local -i padding cp
  zjson_begin '["outer",2]'
  zjson_next
  saved="$ZJSON_POS $ZJSON_LEN $ZJSON_TOKEN_START $ZJSON_TOKEN_TYPE $ZJSON_TOKEN_VALUE"
  _zjson_utf8_error=17
  zjson_utf8_repair $'\0é\xff\xe2\x82A😀'
  assert_ok $? 'public repair succeeds on malformed text'
  assert_eq $'\0é\xef\xbf\xbd\xef\xbf\xbdA😀' "$REPLY" 'repair is unquoted and keeps NUL and later characters'
  assert_eq "$saved" "$ZJSON_POS $ZJSON_LEN $ZJSON_TOKEN_START $ZJSON_TOKEN_TYPE $ZJSON_TOKEN_VALUE" 'repair preserves tokenizer cursor'
  assert_eq 17 "$_zjson_utf8_error" 'repair preserves internal error position'
  zjson_validate $'{\n"x":01}'
  saved="$ZJSON_ERROR $ZJSON_ERROR_CODE $ZJSON_ERROR_OFFSET $ZJSON_ERROR_LINE $ZJSON_ERROR_COLUMN"
  zjson_utf8_repair 'already valid é😀'
  assert_eq 'already valid é😀' "$REPLY" 'repair preserves valid UTF-8'
  assert_eq "$saved" "$ZJSON_ERROR $ZJSON_ERROR_CODE $ZJSON_ERROR_OFFSET $ZJSON_ERROR_LINE $ZJSON_ERROR_COLUMN" 'repair preserves active diagnostics'
  zjson_utf8_repair
  assert_eq 2 $? 'repair missing argument status'
  assert_eq '' "$REPLY" 'repair usage clears only output'
  assert_eq "$saved" "$ZJSON_ERROR $ZJSON_ERROR_CODE $ZJSON_ERROR_OFFSET $ZJSON_ERROR_LINE $ZJSON_ERROR_COLUMN" 'repair usage preserves diagnostics'
  zjson_utf8_repair a b
  assert_eq 2 $? 'repair extra argument status'
  zjson_utf8_repair ''
  assert_ok $? 'repair empty text'
  assert_eq '' "$REPLY" 'repair empty result'
  for padding in 1021 1022 1023 1024; do
    input="${(l:$padding::x:)}"$'\xe2\x82A\0'
    expected="${(l:$padding::x:)}"$'\xef\xbf\xbdA\0'
    zjson_utf8_repair "$input"
    assert_eq "$expected" "$REPLY" 'repair malformed prefix across block boundary'
  done

  # Saturate the escape cache, revisit an earlier value, and decode uncached
  # values. Construct expected UTF-8 bytes independently for U+0100..U+023F.
  input='"'
  expected=''
  local hex first second byte
  for (( cp=256; cp<576; ++cp )); do
    printf -v hex '\\u%04x' "$cp"
    input+="$hex"
    first=$(( 192 + cp / 64 ))
    second=$(( 128 + cp % 64 ))
    printf -v hex '\\x%02x\\x%02x' "$first" "$second"
    printf -v byte '%b' "$hex"
    expected+="$byte"
  done
  input+='\u0100\u023f"'
  expected+=$'\xc4\x80\xc8\xbf'
  zjson_begin "$input"
  assert_ok $? 'Unicode decoding with a saturated cache'
  assert_eq "$expected" "$ZJSON_TOKEN_VALUE" 'cached and uncached Unicode decode identically'
} || return 1
