# goose-doc

Turn [Goose](https://github.com/aardappel/goose) source comments into a
Markdown API reference with names, signatures, examples, and source links.
Run the examples as tests so readers can trust the code they copy.

**[API reference](API.md)** · [Pre-migration release: v0.2.0](https://github.com/sstadick/goose-doc/releases/tag/v0.2.0)

Generating documentation requires Goose. Running examples also requires
Python 3; native builds need GCC or Clang.

## Generate your first reference

From your library directory, check out goose-doc alongside it:

```sh
git clone --branch main --depth 1 https://github.com/sstadick/goose-doc.git ../goose-doc
```

Save this as `sample.goose`:

````goose
namespace sample;

// Double a number.
//
// ```goose
// assert(sample::twice(3) == 6);
// ```
fn twice(n: i64) -> i64 { n * 2 }
````

Generate `API.md`, then link it from your README:

```sh
goose run ../goose-doc/main.goose -- --title "Sample API" \
  --output API.md sample.goose
```

The reference includes the function's signature, description, example, and
a link to its source. Pass multiple source files in the order you want them
documented. Imports are not followed. Without `--output`, Markdown goes to stdout.

To build a reusable command instead, run this from the goose-doc checkout:

```sh
goose build main.goose -O2 -o goose-doc
./goose-doc --help
```

## Write comments for readers

Put ordinary `//` comments immediately above a function, struct, enum, or
type alias. Markdown in the comments is preserved, including lists and code
blocks. A blank line outside the comments breaks their attachment to the
declaration. Each overload gets its own comment and reference entry.

Keep a short description first, then show a useful example. Document details
callers need: return values, ownership, errors, and input restrictions.
Struct and enum declarations include their fields and variants; globals and
nested functions are not included.

## Choose what to publish

By default, goose-doc includes every top-level declaration it supports, including
helpers. To select your public API, create `api.txt` with qualified names:

```text
sample::twice
```

Then generate only those entries:

```sh
goose run ../goose-doc/main.goose -- --symbols api.txt --require-docs \
  --title "Sample API" --output API.md sample.goose
```

A name selects all its overloads. Missing or duplicate names are errors.
`--require-docs` rejects selected declarations without comments. Without it,
undocumented entries appear as *Undocumented.*

## Executable examples

Write each fenced `goose` example as the body of `fn main()`. Use `assert`
to check results. The runner executes each example separately, so snippets
do not share variables.

Put imports, structs, and other top-level helpers in a preamble. For the
sample above, create `tests/doc_preamble.goose` containing:

```goose
import std;
import sample from "..";
```

Run the examples from your library directory:

```sh
python3 ../goose-doc/doctest.py --symbols api.txt \
  --preamble tests/doc_preamble.goose --require-examples sample.goose
```

`from ".."` imports your local checkout because temporary example programs
live directly below the library root. Without a preamble, examples get only
`import std;`. Include any explicit transitive imports your package needs.

- All `goose` fences run. Use `goose ignore` for illustrations that should
  appear in the reference but not execute.
- `--require-examples` requires a runnable example for every selected
  declaration, including each overload. Ignored examples do not count.
- Backtick and tilde fences are supported. Empty executable fences, unclosed
  fences, and unknown Goose fence options are errors.
- Compilation errors, failed assertions, nonzero exits, and timeouts fail
  the command. Failures identify the source file, line, and symbol.
- Use `--cc gcc` or `--cc clang` for native execution instead of TinyCC.
  Assertions stay enabled in all three modes.
- Set `GOOSE` or pass `--goose` to choose the compiler. `--timeout` sets the
  limit per compiler/run command in seconds (default 60).

**Run only trusted documentation.** Examples have your normal user permissions;
the runner is not a sandbox. Generating Markdown never executes examples.

## Keep documentation current in CI

Commit `API.md` and regenerate it when the source or comments change. Add
`--require-examples` to the generation command if every entry needs an example.
In CI, check the committed reference and run the examples:

```sh
goose run ../goose-doc/main.goose -- --symbols api.txt --require-docs \
  --require-examples --title "Sample API" --output API.md --check sample.goose
python3 ../goose-doc/doctest.py --symbols api.txt \
  --preamble tests/doc_preamble.goose --require-examples sample.goose
```

`--check` fails if the reference is missing or stale and never rewrites it.
Pin Goose and goose-doc revisions in CI, and make these checks prerequisites
for your release. Add native example runs for the compilers you support.

For a release artifact with permanent GitHub source links:

```sh
goose run ../goose-doc/main.goose -- --symbols api.txt --require-docs \
  --source-url "https://github.com/$GITHUB_REPOSITORY/blob/$GITHUB_SHA" \
  --output API-release.md sample.goose
```

Generate it from the checkout matching that SHA and attach it to your release.
Keep relative links in the committed `API.md` so a new commit alone does not
make the reference stale.

## Paths and other tools

Source paths are relative to `--root`, which defaults to the current directory.
Symbol files, preambles, and output paths are relative to the working directory.
Relative source links assume `API.md` lives at the library root.

For another example runner, extract snippets as JSON lines:

```sh
goose run ../goose-doc/main.goose -- --examples --symbols api.txt sample.goose
```

Each record has `path`, qualified `name`, the one-based first code `line`, and
`code`. Extraction does not execute snippets.

goose-doc preserves written signatures; it does not infer types or typecheck
your library. Run `goose check` separately. See `--help` for all CLI options.

## Contributing

From this checkout, with Goose on `PATH`:

```sh
python3 tests/run.py --cc gcc
python3 tests/run.py --cc clang
goose run main.goose -- --title "goose-doc API" --symbols api.txt \
  --require-docs --require-examples --output API.md doc.goose
python3 doctest.py --symbols api.txt --preamble tests/doc_preamble.goose \
  --require-examples doc.goose
```

## Migration from goosdoc

The repository is now [sstadick/goose-doc](https://github.com/sstadick/goose-doc).
Replace `import goosdoc from "github.com/sstadick/goosdoc@<ref>";` with
`import doc from "github.com/sstadick/goose-doc@<migration-or-later-ref>";`
and change `goosdoc::` to `doc::`. The entry file is `doc.goose`.
Function and type names are unchanged; owned-struct UFCS remains supported.
Old release tags retain the old entry file and namespace, so do not use the
new import identifier with a pre-migration revision. No compatibility wrapper
is provided.

The CLI is now `goose-doc` (build `main.goose -o goose-doc`), not `goosdoc`.

## License

MIT; see [LICENSE](LICENSE).
