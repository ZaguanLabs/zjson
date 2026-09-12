# Compatibility and release checks

Zsh 5.8 and newer are supported. The automated matrix covers Zsh 5.8 and 5.9.2 on
Linux, with both C and C.UTF-8 locales. Every suite run clears `PATH` before
loading the library. Tests exercise loading under foreign options and aliases,
Unicode validation/repair, escaped Unicode, diagnostic byte positions, Pointer
lookup, and nested context restoration.

Run the same syntax/locale matrix locally with one or more Zsh executables:

```sh
zsh -f tests/matrix.zsh /path/to/zsh-5.8 /path/to/zsh-5.9.2
```

With no arguments, the runner selects `zsh` from the command path. Every supplied
binary parses all project Zsh files and executes the full suite in both locales.
The runner needs only Zsh; the tested library and assertions run with an empty
command search path.

An uninstalled, separately built interpreter may need its own native module
directory for the tests' alias-table inspection:

```sh
ZJSON_TEST_MODULE_PATH=/path/to/matching/module-root \
  zsh -f tests/matrix.zsh /path/to/built/zsh
```

That directory must contain the `zsh/` module directory for the selected version.
Use this override for one version at a time. Normal installed interpreters find
their matching modules automatically. zjson's runtime does not load modules.

The [GitHub Actions workflow](../.github/workflows/test.yml) builds pinned Zsh
interpreter releases on the runner, installs their matching native modules, and
runs the same matrix on pushes, pull requests, published releases, and manual
dispatch. Archives are checked against the upstream
[5.8 checksum](https://www.zsh.org/pub/old/SHA256SUM) and
[5.9.2 checksum](https://www.zsh.org/pub/SHA256SUM).
This provisions the testing environment; zjson remains source-only with no
consumer build step or external runtime dependencies.

Local verification for this change used actual Zsh 5.8 and 5.9.2 on Linux.
Other operating systems are not yet represented in this matrix.
