import std;
import os;
import .doc;

fn read(path: const u8[:]) -> u8[>..] {
    var data: u8[>..] = [];
    if !read_file(path, data) {
        write_stderr(path); write_stderr(": ");
        doc::fail("cannot read file");
    }
    return data;
}

fn main() {
    let args = ::args();
    var title:       const u8[:] = "API reference";
    var output:      const u8[:] = "";
    var source_url:  const u8[:] = "";
    var root:        const u8[:] = ".";
    var symbol_file: const u8[:] = "";
    var check = false;
    var require_docs = false;
    var extract_examples = false;
    var require_examples = false;
    var files: const u8[:][>..] = [];
    var i = 1;
    var positional = false;
    while i < args.len {
        let arg = args[i];
        if positional { files.push(arg); }
        else if arg == "--" { positional = true; }
        else if arg == "--check" { check = true; }
        else if arg == "--require-docs" { require_docs = true; }
        else if arg == "--examples" { extract_examples = true; }
        else if arg == "--require-examples" { require_examples = true; }
        else if arg == "--help" {
            print("Usage: goose-doc [options] FILE.goose...\n",
                  "  --output FILE       Write Markdown (default: stdout)\n",
                  "  --check             Fail if output is missing or stale; never write\n",
                  "  --title TEXT        Document title (default: API reference)\n",
                  "  --root DIR          Read source paths relative to DIR (default: .)\n",
                  "  --symbols FILE      Qualified names, one per line; select all overloads\n",
                  "  --require-docs      Fail if a selected declaration has no comment\n",
                  "  --examples          Emit executable doc fences as JSON lines, not Markdown\n",
                  "  --require-examples  Require a runnable example for each selected declaration\n",
                  "  --source-url URL    Source URL prefix, e.g. https://github.com/owner/repo/blob/SHA\n",
                  "  --                  Treat remaining arguments as file paths");
            return;
        } else if arg == "--output" || arg == "--title" || arg == "--root" ||
                      arg == "--symbols" || arg == "--source-url" {
            i += 1;
            if i == args.len { doc::fail("option needs a value"); }
            if arg == "--output" { output = args[i]; }
            else if arg == "--title" { title = args[i]; }
            else if arg == "--root" { root = args[i]; }
            else if arg == "--symbols" { symbol_file = args[i]; }
            else { source_url = args[i]; }
        } else if starts_with(arg, "-") { doc::fail("unknown option; see --help"); }
        else { files.push(arg); }
        i += 1;
    }
    if files.len == 0 { doc::fail("provide at least one source file; see --help"); }
    if check && output.len == 0 { doc::fail("--check requires --output"); }
    while ends_with(source_url, "/") { source_url = source_url[..source_url.len - 1]; }
    var names: u8[][>..] = [];
    if symbol_file.len > 0 {
        let data = read(symbol_file);
        for line in split(data, '\n') {
            let name = trim(line);
            if name.len == 0 || starts_with(name, "#") { continue; }
            for previous in names { if previous == name { doc::fail("duplicate symbol in selection"); } }
            var owned: u8[>..] = []; owned.append(name); names.push(copy(owned));
        }
        if names.len == 0 { doc::fail("symbol selection is empty"); }
    }
    var found: bool[>..] = [];
    for name in names { found.push(false); }
    var body:     u8[>..] = [];
    var index:    u8[>..] = [];
    var examples: u8[>..] = [];
    var count = 0;
    for file in files {
        if starts_with(file, "/") || find(file, "\\") >= 0 {
            doc::fail("source paths must be relative to --root and use / separators");
        }
        for component in split(file, '/') {
            if component == ".." || component == "." || component.len == 0 {
                doc::fail("source paths must not contain . or .. components");
            }
        }
        var path: u8[>..] = []; path.append(root); path.push('/'); path.append(file);
        let source = read(path);
        let entries = doc::parse(source);
        for entry in entries {
            var selected = names.len == 0;
            for name, n in names {
                if entry.name == name { selected = true; found[n] = true; }
            }
            if !selected { continue; }
            if require_docs && trim(entry.doc).len == 0 {
                write_stderr(entry.name); write_stderr(": ");
                doc::fail("missing documentation comment");
            }
            if extract_examples || require_examples {
                let n = doc::examples(examples, entry, file);
                if require_examples && n == 0 {
                    write_stderr(entry.name); write_stderr(": ");
                    doc::fail("missing executable example");
                }
            }
            count += 1;
            index.append("- [`"); index.append(entry.name); index.append("`](#api-");
            format(index, count); index.append(")\n");
            doc::render(body, entry, file, source_url, count);
        }
    }
    for name, n in names {
        if !found[n] {
            write_stderr(name); write_stderr(": ");
            doc::fail("selected symbol not found");
        }
    }
    if count == 0 { doc::fail("no declarations selected"); }
    var markdown: u8[>..] = [];
    if extract_examples { markdown.append(examples); }
    else {
        markdown.append("<!-- Generated by goose-doc. Edit source comments, not this file. -->\n\n# ");
        markdown.append(title); markdown.append("\n\n"); markdown.append(index);
        markdown.push('\n'); markdown.append(body);
        while ends_with(markdown, "\n\n") { markdown.pop(); }
    }
    if check {
        let previous = read(output);
        if previous != markdown { doc::fail("API reference is stale; regenerate it"); }
    } else if output.len > 0 {
        if !write_file_atomic(output, markdown) { doc::fail("cannot write output"); }
    } else { write_stdout(markdown); }
}
