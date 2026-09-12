# SPDX-License-Identifier: Apache-2.0
# UTF-8 primitives. Byte data is constant; no locale-dependent printf escapes.
typeset -gi _zjson_utf8_error=0
typeset -g _zjson_bytes=$'\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2a\x2b\x2c\x2d\x2e\x2f\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3a\x3b\x3c\x3d\x3e\x3f\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4a\x4b\x4c\x4d\x4e\x4f\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5a\x5b\x5c\x5d\x5e\x5f\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6a\x6b\x6c\x6d\x6e\x6f\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7a\x7b\x7c\x7d\x7e\x7f\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xbb\xbc\xbd\xbe\xbf\xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf\xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf\xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff'

# Input is an internally validated Unicode scalar. Scalar indexing is in bytes.
_zjson_codepoint_utf8() {
  emulate -L zsh
  setopt nomultibyte
  local -i cp=$1
  if (( cp < 0x80 )); then
    REPLY="${_zjson_bytes[cp+1]}"
  elif (( cp < 0x800 )); then
    REPLY="${_zjson_bytes[(0xC0 | (cp >> 6))+1]}${_zjson_bytes[(0x80 | (cp & 63))+1]}"
  elif (( cp < 0x10000 )); then
    REPLY="${_zjson_bytes[(0xE0 | (cp >> 12))+1]}${_zjson_bytes[(0x80 | ((cp >> 6) & 63))+1]}${_zjson_bytes[(0x80 | (cp & 63))+1]}"
  else
    REPLY="${_zjson_bytes[(0xF0 | (cp >> 18))+1]}${_zjson_bytes[(0x80 | ((cp >> 12) & 63))+1]}${_zjson_bytes[(0x80 | ((cp >> 6) & 63))+1]}${_zjson_bytes[(0x80 | (cp & 63))+1]}"
  fi
}

_zjson_utf8_valid() {
  emulate -L zsh
  setopt nomultibyte
  local input=$1
  [[ $input != *[$'\x80'-$'\xff']* ]] && return 0
  # Zsh's native multibyte classes validate without rebuilding the string.
  # Use them only for an active UTF-8 locale with working multibyte support.
  # Some libc implementations accept values above U+10FFFF, so additionally
  # exclude those byte encodings. Other locales use the byte grammar below.
  local encoding="${LC_ALL:-${LC_CTYPE:-${LANG:-C}}}" probe=$'\xc3\xa9\xf0\x9f\x98\x80'
  if [[ "${(L)encoding}" == *utf-8* || "${(L)encoding}" == *utf8* ]]; then
    setopt multibyte
    if (( ${#probe} == 2 )); then
      [[ $input != *[[:INVALID:][:INCOMPLETE:]]* ]] || return 1
      setopt nomultibyte
      [[ $input != *[$'\xf5'-$'\xff']* && $input != *$'\xf4'[$'\x90'-$'\xbf']* ]]
      return
    fi
    setopt nomultibyte
  fi
  local LC_ALL=C
  # Illegal leaders, stray continuation after ASCII/start, truncated suffix.
  [[ $input != *[$'\xc0\xc1\xf5'-$'\xff']* &&
     $input != [$'\x80'-$'\xbf']* &&
     $input != *[$'\x00'-$'\x7f'][$'\x80'-$'\xbf']* &&
     $input != *[$'\xc2'-$'\xf4'] &&
     $input != *[$'\xe0'-$'\xf4'][$'\x80'-$'\xbf'] &&
     $input != *[$'\xf0'-$'\xf4'][$'\x80'-$'\xbf'][$'\x80'-$'\xbf'] ]] || return 1
  # Missing continuation inside the input.
  [[ $input != *[$'\xc2'-$'\xf4'][^$'\x80'-$'\xbf']* &&
     $input != *[$'\xe0'-$'\xf4'][$'\x80'-$'\xbf'][^$'\x80'-$'\xbf']* &&
     $input != *[$'\xf0'-$'\xf4'][$'\x80'-$'\xbf'][$'\x80'-$'\xbf'][^$'\x80'-$'\xbf']* ]] || return 1
  # Too many continuation bytes for the leader.
  [[ $input != *[$'\xc2'-$'\xdf'][$'\x80'-$'\xbf'][$'\x80'-$'\xbf']* &&
     $input != *[$'\xe0'-$'\xef'][$'\x80'-$'\xbf'][$'\x80'-$'\xbf'][$'\x80'-$'\xbf']* &&
     $input != *[$'\xf0'-$'\xf4'][$'\x80'-$'\xbf'][$'\x80'-$'\xbf'][$'\x80'-$'\xbf'][$'\x80'-$'\xbf']* ]] || return 1
  # Exclude overlong encodings, surrogates and values above U+10FFFF.
  [[ $input != *$'\xe0'[$'\x80'-$'\x9f']* &&
     $input != *$'\xed'[$'\xa0'-$'\xbf']* &&
     $input != *$'\xf0'[$'\x80'-$'\x8f']* &&
     $input != *$'\xf4'[$'\x90'-$'\xbf']* ]]
}

# Repair malformed UTF-8 at the JSON boundary, including bytes in old saved
# transcripts. Work in bytes regardless of the process locale. Valid text is
# copied in bounded blocks: an unbounded repeated glob can exhaust Zsh's stack.
_zjson_utf8_text() {
  emulate -L zsh
  setopt extendedglob nomultibyte
  local input="$1" chunk='' byte='' second='' replacement=$'\xef\xbf\xbd'
  local unit=$'([\x00-\x7f]|[\xc2-\xdf][\x80-\xbf]|\xe0[\xa0-\xbf][\x80-\xbf]|[\xe1-\xec\xee-\xef][\x80-\xbf][\x80-\xbf]|\xed[\x80-\x9f][\x80-\xbf]|\xf0[\x90-\xbf][\x80-\xbf][\x80-\xbf]|[\xf1-\xf3][\x80-\xbf][\x80-\xbf][\x80-\xbf]|\xf4[\x80-\x8f][\x80-\xbf][\x80-\xbf])'
  local -a pieces=() bytes=()
  local -i offset=1 end length=${#input} i j width count extra
  _zjson_utf8_error=0
  if _zjson_utf8_valid "$input"; then
    REPLY="$input"
    return 0
  fi
  local LC_ALL=C
  while (( offset <= length )); do
    end=$(( offset + 1023 ))
    (( end > length )) && end=$length
    # Include continuation bytes when a valid character crosses a block edge.
    for extra in 1 2 3; do
      (( end < length )) || break
      [[ ${input[end+1]} == [$'\x80'-$'\xbf'] ]] || break
      (( end++ ))
    done
    chunk="${input[offset,end]}"
    if [[ "$chunk" == (${~unit})# ]]; then
      pieces+=("$chunk")
    else
      bytes=("${(@s::)chunk}")
      count=${#bytes}
      for (( i=1; i<=count; )); do
        byte=${bytes[i]}
        width=1
        second=$'[\x80-\xbf]'
        case "$byte" in
          [$'\x00'-$'\x7f']) pieces+=("$byte"); (( i++ )); continue ;;
          [$'\xc2'-$'\xdf']) width=2 ;;
          $'\xe0') width=3; second=$'[\xa0-\xbf]' ;;
          [$'\xe1'-$'\xec']|[$'\xee'-$'\xef']) width=3 ;;
          $'\xed') width=3; second=$'[\x80-\x9f]' ;;
          $'\xf0') width=4; second=$'[\x90-\xbf]' ;;
          [$'\xf1'-$'\xf3']) width=4 ;;
          $'\xf4') width=4; second=$'[\x80-\x8f]' ;;
        esac
        j=$(( i + 1 ))
        if (( width > 1 && j <= count )) && [[ ${bytes[j]} == ${~second} ]]; then
          (( j++ ))
          while (( j < i + width && j <= count )) && [[ ${bytes[j]} == [$'\x80'-$'\xbf'] ]]; do
            (( j++ ))
          done
        fi
        if (( width > 1 && j == i + width )); then
          pieces+=("${(j::)bytes[i,j-1]}")
        else
          # Consume only the malformed prefix; retain the following character.
          (( _zjson_utf8_error )) || _zjson_utf8_error=$(( offset + i - 1 ))
          pieces+=("$replacement")
        fi
        i=$j
      done
    fi
    offset=$(( end + 1 ))
  done
  REPLY="${(j::)pieces}"
}

# On invalid input, the established repair scanner finds the first malformed
# prefix. Successful validation neither repairs nor allocates output pieces.
_zjson_utf8_validate() {
  emulate -L zsh
  _zjson_utf8_error=0
  _zjson_utf8_valid "$1" && return 0
  local REPLY=""
  _zjson_utf8_text "$1"
  return 1
}

# Repair arbitrary text without changing tokenizer state or diagnostics.
# REPLY is the sole output; usage errors clear it and return 2.
zjson_utf8_repair() {
  emulate -L zsh
  local -i _zjson_utf8_error=0
  REPLY=""
  (( $# == 1 )) || return 2
  _zjson_utf8_text "$1"
}
