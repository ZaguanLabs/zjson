# SPDX-License-Identifier: Apache-2.0
# Source this entry point. The separate source operation prevents caller aliases
# from rewriting implementation code before its option isolation takes effect.
() {
  builtin emulate -L zsh
  builtin setopt no_aliases
  builtin source "${${(%):-%x}:A:h}/lib/utf8.zsh" || return
  builtin source "${${(%):-%x}:A:h}/lib/zjson.zsh" || return
  builtin source "${${(%):-%x}:A:h}/lib/pointer.zsh" || return
  builtin source "${${(%):-%x}:A:h}/lib/context.zsh"
}
