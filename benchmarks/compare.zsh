#!/usr/bin/env zsh
# Compare the same low-level operations against any compatible trusted parser.
# Usage: zsh -f benchmarks/compare.zsh /path/to/entry.zsh json|zjson
emulate -LR zsh
if (( $# != 2 )) || [[ "$2" != json && "$2" != zjson ]]; then
  print -u2 -r -- 'usage: compare.zsh parser-entry.zsh json|zjson'
  exit 2
fi
typeset compare_entry=${1:A} compare_prefix=$2
path=()
source "$compare_entry" || exit 1
typeset compare_token=${(U)compare_prefix}_TOKEN_TYPE

compare_validate() {
  "${compare_prefix}_begin" "$1" && "${compare_prefix}_discard_value" &&
    [[ "${(P)compare_token}" == eof ]]
}
compare_quote() { "${compare_prefix}_quote" "$1"; }
compare_measure() {
  local label=$1 operation=$2 input=$3
  local -i iterations=$4 i
  local -F 9 SECONDS=0 elapsed
  "$operation" "$input" || return 1
  SECONDS=0
  for (( i=0; i<iterations; ++i )); do
    "$operation" "$input" || return 1
  done
  elapsed=$SECONDS
  printf '%s\t%.6f\n' "$label" "$(( elapsed * 1000 / iterations ))"
}

typeset text
typeset -a units=()
text=${(l:100000::x:)}
compare_measure ascii-100k compare_validate "\"$text\"" 5 || exit 1
repeat 4000 units+=('"x"')
compare_measure strings-4000 compare_validate "[${(j:,:)units}]" 2 || exit 1
units=()
repeat 12500 units+=('é😀')
text=${(j::)units}
compare_measure unicode-25k compare_validate "\"$text\"" 5 || exit 1
compare_measure quote-unicode-25k compare_quote "$text" 5 || exit 1
units=()
repeat 2000 units+=('\u00e9')
compare_measure unicode-escapes-2000 compare_validate "\"${(j::)units}\"" 2 || exit 1
# More distinct code points than the per-string cache can hold.
units=()
typeset -i cp
for (( cp=256; cp<2256; ++cp )); do
  printf -v text '\\u%04x' "$cp"
  units+=( "$text" )
done
compare_measure unicode-escapes-varied compare_validate "\"${(j::)units}\"" 2 || exit 1
