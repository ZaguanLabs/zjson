#!/usr/bin/env zsh
# Pure Zsh wall-clock benchmarks. Optional argument: samples per workload.
emulate -LR zsh
setopt extendedglob
if (( $# > 1 )) || [[ ${1:-5} != [1-9][0-9]# || ${#1} -gt 3 ]]; then
  print -u2 -r -- 'usage: zsh -f benchmarks/run.zsh [samples: 1..999]'
  exit 2
fi
typeset -i BENCH_SAMPLES=${1:-5}
path=()
source "${ZJSON_BENCH_ROOT:-${0:A:h:h}}/zjson.zsh" || exit 1

bench_raw() { zjson_begin "$1" && zjson_capture_raw_value; }
bench_compact() { zjson_begin "$1" && zjson_capture_value; }

bench() {
  emulate -L zsh
  setopt nomultibyte
  local label=$1 operation=$2 document=$3
  shift 3
  local -a samples=()
  local -i i microseconds middle=$(( (BENCH_SAMPLES + 1) / 2 ))
  # SECONDS is Zsh's native elapsed-time parameter, localized for this timer.
  local -F 6 SECONDS=0
  "$operation" "$document" "$@" || {
    print -u2 -r -- "benchmark $label/$operation failed: $ZJSON_ERROR"
    return 1
  }
  for (( i=0; i<BENCH_SAMPLES; ++i )); do
    SECONDS=0
    "$operation" "$document" "$@" || return 1
    microseconds=$(( SECONDS * 1000000 ))
    samples+=( "$microseconds" )
  done
  samples=( ${(on)samples} )
  local -F median=$(( samples[middle] / 1000.0 ))
  if (( BENCH_SAMPLES % 2 == 0 )); then
    median=$(( (samples[middle] + samples[middle+1]) / 2000.0 ))
  fi
  printf '%s\t%s\t%d\t%d\t%.3f\t%.3f\t%.3f\n' \
    "$label" "$operation" "${#document}" "$BENCH_SAMPLES" \
    "$(( samples[1] / 1000.0 ))" "$median" "$(( samples[-1] / 1000.0 ))"
}

printf '# zjson=%s zsh=%s platform=%s locale=%s PATH=empty\n' \
  "$ZJSON_VERSION" "$ZSH_VERSION" "$OSTYPE/$MACHTYPE" "${LC_ALL:-${LC_CTYPE:-${LANG:-C}}}"
printf '# label=%s\n' "${ZJSON_BENCH_LABEL:-working-tree}"
print -r -- $'case\toperation\tbytes\tsamples\tmin_ms\tmedian_ms\tmax_ms'
typeset -a elements=()
typeset -i n
typeset document text unit expected
for n in 1000 2000 4000; do
  elements=( ${(s::)${(pl:$n::1:)}} )
  document="[${(j:,:)elements}]"
  bench "numbers-$n" zjson_validate "$document" || exit 1
  elements=( ${elements//1/\"x\"} )
  document="[${(j:,:)elements}]"
  bench "strings-$n" zjson_validate "$document" || exit 1
done
text=${(pl:100000::x:)}
bench ascii-100k zjson_validate "\"$text\"" || exit 1
bench ascii-100k zjson_quote "$text" || exit 1
elements=()
repeat 12500 elements+=( 'é😀' )
text="${(j::)elements}"
bench unicode-25k zjson_validate "\"$text\"" || exit 1
bench unicode-25k zjson_quote "$text" || exit 1
unit='\u00e9'
elements=()
repeat 2000 elements+=( "$unit" )
text="${(j::)elements}"
zjson_begin "\"$text\"" || exit 1
expected=''
repeat 2000 expected+='é'
[[ "$ZJSON_TOKEN_VALUE" == "$expected" ]] || exit 1
bench unicode-escapes zjson_validate "\"$text\"" || exit 1
unit='\n\t\\'
elements=()
repeat 2000 elements+=( "$unit" )
text="${(j::)elements}"
zjson_begin "\"$text\"" || exit 1
[[ "$ZJSON_TOKEN_VALUE" == $'\n\t\\'* && ${#ZJSON_TOKEN_VALUE} == 6000 ]] || exit 1
bench simple-escapes zjson_validate "\"$text\"" || exit 1
document="${(pl:64::[:)}0${(pl:64::]:)}"
bench nested-64 zjson_validate "$document" || exit 1
elements=( ${(s::)${(pl:1000::1:)}} )
document="{\"data\":[${(j:,:)elements}],\"result\":{\"name\":\"zjson\"}}"
bench envelope zjson_parse_object "$document" || exit 1
bench envelope bench_raw "$document" || exit 1
bench envelope bench_compact "$document" || exit 1
if (( $+functions[zjson_get] )); then
  bench envelope zjson_get "$document" /result/name || exit 1
fi
