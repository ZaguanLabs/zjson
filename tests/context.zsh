context_snapshot() {
  context_state=( "$ZJSON_SOURCE" "$ZJSON_POS" "$ZJSON_LEN" "$ZJSON_TOKEN_START"
    "$ZJSON_TOKEN_TYPE" "$ZJSON_TOKEN_VALUE" "$ZJSON_ERROR" "$ZJSON_ERROR_CODE"
    "$ZJSON_ERROR_OFFSET" "$ZJSON_ERROR_LINE" "$ZJSON_ERROR_COLUMN"
    "$_zjson_utf8_error" "${ZJSON_CHARS[@]}" )
}

context_assert_restored() {
  local -i i
  context_snapshot
  assert_eq "${#expected_state}" "${#context_state}" 'context restores state size'
  for (( i=1; i<=${#expected_state}; ++i )); do
    assert_eq "${expected_state[i]}" "${context_state[i]}" 'context restores parser state'
  done
}

context_callback() {
  application_output="$1"
  zjson_parse_object '{"answer":42}' || return 1
  zjson_parse_array '[true,"nested"]' || return 1
  zjson_get '{"name":"inner"}' /name || return 1
  return "$2"
}

context_failure() {
  zjson_validate $'{\n"bad":"\xff"}'
}

context_nested() {
  zjson_begin '["middle",3]' || return 1
  zjson_next || return 1
  local before="$ZJSON_SOURCE $ZJSON_POS $ZJSON_TOKEN_VALUE"
  zjson_with_context context_callback twice 23
  assert_eq 23 $? 'nested scope preserves callback status'
  assert_eq "$before" "$ZJSON_SOURCE $ZJSON_POS $ZJSON_TOKEN_VALUE" 'nested scope restores middle parser'
  zjson_next
}

context_runtime_error() {
  zjson_begin '[9]' || return 1
  # The caller catches this shell error; scope locals must unwind with it.
  local value=$(( 1 / 0 ))
}

context_begin_runtime_error() {
  zjson_begin '{"inner":1}' || return 1
  local value=$(( 1 / 0 ))
}

() {
  local -a context_state=() expected_state=()
  local application_output=before REPLY=before
  local -i result
  zjson_begin '["\u0000é",2]'
  zjson_next
  context_snapshot
  expected_state=( "${context_state[@]}" )
  for result in 0 7 23; do
    zjson_with_context context_callback 'same shell' "$result"
    assert_eq "$result" $? 'scope returns callback status'
    context_assert_restored
    assert_eq 'same shell' "$application_output" 'scope keeps application side effects'
    assert_eq inner "$REPLY" 'scope keeps REPLY output'
    assert_eq string "$ZJSON_TYPE" 'scope keeps lookup type'
    assert_eq 42 "${ZJSON_OBJECT[answer]}" 'scope keeps object results'
    assert_eq number "${ZJSON_OBJECT_TYPES[answer]}" 'scope keeps object types'
    assert_eq nested "${ZJSON_ARRAY[2]}" 'scope keeps array results'
    assert_eq string "${ZJSON_ARRAY_TYPES[2]}" 'scope keeps array types'
  done
  zjson_with_context context_failure
  assert_eq 1 $? 'scope returns parsing failure'
  context_assert_restored
  zjson_with_context context_nested
  assert_ok $? 'recursively nested scope succeeds'
  context_assert_restored
  zjson_with_context
  assert_eq 2 $? 'scope requires callback'
  context_assert_restored
  {
    zjson_with_context context_runtime_error 2>/dev/null
  } always {
    if (( TRY_BLOCK_ERROR )); then
      TRY_BLOCK_ERROR=0
      application_output=caught
    fi
  }
  assert_eq caught "$application_output" 'test caught callback runtime error'
  context_assert_restored
  zjson_next
  assert_eq ',' "$ZJSON_TOKEN_TYPE" 'outer parser can continue'
  zjson_next
  assert_eq 2 "$ZJSON_TOKEN_VALUE" 'outer parser retains its next value'

  context_snapshot
  expected_state=( "${context_state[@]}" )

  {
    zjson_with_context context_begin_runtime_error 2>/dev/null
  } always {
    if (( TRY_BLOCK_ERROR )); then
      TRY_BLOCK_ERROR=0
      application_output=caught-begin
    fi
  }
  assert_eq caught-begin "$application_output" 'test caught runtime error after nested begin'
  context_assert_restored
  zjson_next
  assert_eq ']' "$ZJSON_TOKEN_TYPE" 'outer parser can continue after nested begin error'

  zjson_validate $'{\n"bad":01}'
  context_snapshot
  expected_state=( "${context_state[@]}" )
  zjson_with_context context_callback success 0
  context_assert_restored
  # An outer parser depth must not reduce the nested document's budget.
  local -i _zjson_depth=128
  zjson_with_context zjson_validate '[0]'
  assert_ok $? 'nested document starts a fresh depth budget'
  assert_eq 128 "$_zjson_depth" 'scope restores outer recursion depth'
} || return 1

() {
  local REPLY=''
  setopt shwordsplit ksharrays globsubst
  zjson_with_context zjson_get '{"a":"é"}' /a
  assert_ok $? 'context works under foreign options'
  assert_eq é "$REPLY" 'context result under foreign options'
  [[ -o shwordsplit && -o ksharrays && -o globsubst ]]
  assert_ok $? 'context preserves caller options'
} || return 1
