#!/usr/bin/env zsh
# Syntax and PATH-empty tests in both locales, using each supplied Zsh binary.
emulate -LR zsh
typeset matrix_root=${0:A:h:h}
typeset -a matrix_shells=( "$@" )
(( ${#matrix_shells} )) || matrix_shells=( "${commands[zsh]}" )
typeset matrix_shell matrix_file matrix_locale
for matrix_shell in "${matrix_shells[@]}"; do
  matrix_shell=${matrix_shell:A}
  [[ -x "$matrix_shell" ]] || { print -u2 -r -- "not an executable: $matrix_shell"; exit 2; }
  "$matrix_shell" --version || exit 1
  for matrix_file in "$matrix_root/zjson.zsh" "$matrix_root"/{lib,tests,benchmarks,examples}/*.zsh; do
    "$matrix_shell" -df -n "$matrix_file" || exit 1
  done
  for matrix_locale in C C.UTF-8; do
    print -r -- "Locale: $matrix_locale"
    LC_ALL=$matrix_locale "$matrix_shell" -df -c '
      # Only for separately built interpreters with uninstalled native modules.
      if [[ -n ${ZJSON_TEST_MODULE_PATH:-} ]]; then
        module_path=( "$ZJSON_TEST_MODULE_PATH" "${module_path[@]}" )
      fi
      source "$1/tests/run.zsh"
    ' zjson-matrix "$matrix_root" || exit 1
  done
done
