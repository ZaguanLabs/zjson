#!/usr/bin/env zsh
emulate -L zsh
source "${0:A:h:h}/zjson.zsh" || exit 1

zjson_parse_object '{"name":"zjson","ports":[8080,8081]}' || {
  print -u2 -r -- "$ZJSON_ERROR"
  exit 1
}
print -r -- "Name: ${ZJSON_OBJECT[name]}"

zjson_parse_array "${ZJSON_OBJECT[ports]}" || exit 1
print -r -- "Ports: ${(j:, :)ZJSON_ARRAY}"

zjson_get '{"servers":[{"host":"localhost"}]}' /servers/0/host || exit 1
print -r -- "First host: $REPLY ($ZJSON_TYPE)"

zjson_quote $'hello\nworld'
print -r -- "JSON string: $REPLY"
