# zjson development

- Keep library code, examples, and the test suite 100% pure Zsh. Do not add
  external executables, third-party modules, package managers, or a build step
  as dependencies. Development inspection tools are fine.
- Use the `zsh-expert` skill for Zsh implementation and review.
- Source `zjson.zsh` as the public entry point. Keep application-specific codecs
  outside the generic library.
- Preserve caller options, aliases, locale, and unrelated variables. Treat JSON
  as data; never evaluate it as shell code or arithmetic.
- Keep public names under `zjson_` / `ZJSON_` and private names under `_zjson_`.
- Preserve number spelling and distinguish strings, numbers, booleans, and null.
- Run `zsh -f -n` on changed Zsh files and `zsh -f tests/run.zsh`; run the suite
  with `LC_ALL=C` when changing encoding or parsing. The test suite must continue
  to pass with its command search path empty.
- Document API changes, encoding policies, and compatibility limits in README.md.
