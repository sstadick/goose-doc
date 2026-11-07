namespace doc;

import std;
import os;
import json;

// A documented declaration. Lines are one-based; end_line includes the body.
// Signature and documentation own their text and do not borrow the source.
// doc_line identifies the first attached comment line, or line if absent.
//
// ```goose
// let entries = doc::parse("// Add two numbers.\nfn add(a: i64, b: i64) -> i64 { a + b }");
// assert(entries.len == 1);
// for entry in entries {
//     assert(entry.name == "add");
//     assert(entry.doc_line == 1 && entry.line == 2);
// }
// ```
struct Entry {
    name:      u8[],
    signature: u8[],
    doc:       u8[],
    line:      i64,
    end_line:  i64,
    doc_line:  i64,
}

struct Token {
    start:     i64, end: i64, line: i64, end_line: i64,
    doc_start: i64, doc_end: i64,
}

fn fail(message: const u8[:]) {
    write_stderr("goose-doc: ");
    write_stderr(message);
    write_stderr("\n");
    exit(1);
}

fn word(c: u8) -> bool {
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') || c == '_'
}

fn at(s: const u8[:], i: i64, text: const u8[:]) -> bool {
    i + text.len <= s.len && s[i..i + text.len] == text
}

fn lex(s: const u8[:]) -> Token[>..] {
    var tokens: Token[>..] = [];
    var i = 0;
    var line = 1;
    var line_start = 0;
    var doc_start = -1;
    var doc_end = 0;
    var doc_line = -1;
    while i < s.len {
        if is_space(s[i]) {
            if s[i] == '\n' { line += 1; line_start = i + 1; }
            i += 1;
            continue;
        }
        if at(s, i, "//") {
            let own = trim(s[line_start..i]).len == 0;
            let start = i;
            while i < s.len && s[i] != '\n' { i += 1; }
            if own {
                if doc_line + 1 != line { doc_start = start; }
                doc_end = i;
                doc_line = line;
            }
            continue;
        }
        if at(s, i, "/*") {
            doc_start = -1;
            doc_line = -1;
            i += 2;
            var depth = 1;
            while i < s.len && depth > 0 {
                if at(s, i, "/*") { depth += 1; i += 2; }
                else if at(s, i, "*/") { depth -= 1; i += 2; }
                else {
                    if s[i] == '\n' { line += 1; line_start = i + 1; }
                    i += 1;
                }
            }
            if depth != 0 { fail("unterminated block comment"); }
            continue;
        }
        let start = i;
        let first_line = line;
        if at(s, i, "\"\"\"") {
            i += 3;
            while i < s.len && !at(s, i, "\"\"\"") {
                if s[i] == '\n' { line += 1; line_start = i + 1; }
                i += 1;
            }
            if i == s.len { fail("unterminated triple-quoted string"); }
            i += 3;
        } else if s[i] == '"' || s[i] == '\'' {
            let quote = s[i];
            i += 1;
            while i < s.len && s[i] != quote {
                if s[i] == '\n' { fail("newline in quoted literal"); }
                if s[i] == '\\' { i += 1; }
                if i < s.len { i += 1; }
            }
            if i == s.len { fail("unterminated quoted literal"); }
            i += 1;
        } else if word(s[i]) {
            while i < s.len && word(s[i]) { i += 1; }
        } else if at(s, i, "::") || at(s, i, "->") {
            i += 2;
        } else {
            i += 1;
        }
        tokens.push(Token {
            start:     start, end: i, line: first_line, end_line: line,
            doc_start: if doc_line + 1 == first_line { doc_start } else { -1 },
            doc_end:   doc_end,
        });
        doc_start = -1;
        doc_line = -1;
    }
    return tokens;
}

fn text(s: const u8[:], tokens: const Token[:], i: i64) -> const u8[:] {
    if i >= tokens.len { return ""; }
    return s[tokens[i].start..tokens[i].end];
}

fn paired(s: const u8[:], tokens: const Token[:], start: i64) -> i64 {
    var stack: u8[>..] = [];
    for i in start..tokens.len {
        let t = text(s, tokens, i);
        if t == "(" { stack.push(')'); }
        else if t == "[" { stack.push(']'); }
        else if t == "{" { stack.push('}'); }
        else if t == ")" || t == "]" || t == "}" {
            if stack.len == 0 || stack[stack.len - 1] != t[0] {
                fail("mismatched delimiter");
            }
            stack.pop();
            if stack.len == 0 { return i + 1; }
        }
    }
    fail("unclosed delimiter");
    return tokens.len;
}

fn comment(s: const u8[:], token: Token) -> u8[>..] {
    var out: u8[>..] = [];
    if token.doc_start < 0 { return out; }
    for line in split(s[token.doc_start..token.doc_end], '\n') {
        let stripped = trim_start(line);
        var body = stripped[2..];
        if body.len > 0 && body[0] == ' ' { body = body[1..]; }
        if body.len > 0 && body[body.len - 1] == '\r' { body = body[..body.len - 1]; }
        out.append(body);
        out.push('\n');
    }
    return out;
}

fn modifier(t: const u8[:]) -> bool {
    t == "inline" || t == "simd" || t == "extern" || t == "export" ||
        t == "checkfree" || t == "recursive"
}

// Extract top-level functions, structs, enums and aliases in source order.
// Keeps overloads separate and attaches consecutive standalone // comments
// immediately above a declaration, following Goose's documentation convention.
// Imports are not followed. Malformed delimiters or literals exit with status 1;
// this is a source scanner, not a substitute for `goose check`.
//
// ```goose
// let entries = doc::parse("namespace math;\n// Double.\nfn twice(n: i64) -> i64 { n * 2 }");
// assert(entries.len == 1);
// for entry in entries {
//     assert(entry.name == "math::twice");
//     assert(entry.signature == "fn twice(n: i64) -> i64");
// }
// ```
fn parse(source: const u8[:]) -> Entry[>..] {
    let tokens = lex(source);
    var entries: Entry[>..] = [];
    var ns:      u8[>..]    = [];
    var i = 0;
    var in_extern = false;
    var extern_library = source[..0];
    while i < tokens.len {
        let start = i;
        var t = text(source, tokens, i);
        if t == "namespace" {
            i += 1;
            ns.append(text(source, tokens, i));
            i += 1;
            if text(source, tokens, i) != ";" { fail("expected namespace name and semicolon"); }
            i += 1;
            continue;
        }
        if t == "}" {
            if !in_extern { fail("unexpected closing brace"); }
            in_extern = false;
            i += 1;
            continue;
        }
        while modifier(t) {
            let was_extern = t == "extern";
            i += 1;
            t = text(source, tokens, i);
            if t.len > 0 && t[0] == '"' {
                let library = t;
                i += 1;
                t = text(source, tokens, i);
                if was_extern && t == "{" {
                    in_extern = true;
                    extern_library = library;
                    break;
                }
            }
        }
        if in_extern && t == "{" { i += 1; continue; }
        let is_fn = t == "fn" || t == "thread_fn";
        let is_type = t == "struct" || t == "enum";
        if is_fn || is_type || t == "type" {
            i += 1;
            var name: u8[>..] = [];
            if text(source, tokens, i) == "::" {
                i += 1;
                name.append(text(source, tokens, i));
                i += 1;
            } else {
                if text(source, tokens, i + 1) == "::" {
                    name.append(text(source, tokens, i));
                    name.append("::");
                    i += 2;
                } else if ns.len > 0 {
                    name.append(ns);
                    name.append("::");
                }
                name.append(text(source, tokens, i));
                i += 1;
            }
            // Parenthesized defaults, array-length expressions and function
            // types may contain braces; only an outer brace begins the body.
            while i < tokens.len {
                t = text(source, tokens, i);
                if t == "(" || t == "[" { i = paired(source, tokens, i); }
                else if t == "{" || t == ";" { break; }
                else { i += 1; }
            }
            if i == tokens.len { fail("declaration has no body or semicolon"); }
            var sig_end = tokens[i].start;
            if t == "{" {
                i = paired(source, tokens, i);
                if is_type { sig_end = tokens[i - 1].end; }
            } else {
                sig_end = tokens[i].end;
                i += 1;
            }
            var signature: u8[>..] = [];
            if in_extern {
                signature.append("extern "); signature.append(extern_library);
                signature.append(" {\n    ");
            }
            signature.append(trim(source[tokens[start].start..sig_end]));
            if in_extern { signature.append("\n}"); }
            let doc = comment(source, tokens[start]);
            var doc_line = tokens[start].line;
            for c in doc { if c == '\n' { doc_line -= 1; } }
            entries.push(Entry {
                name:     copy(name), signature: copy(signature), doc: copy(doc),
                line:     tokens[start].line, end_line: tokens[i - 1].end_line,
                doc_line: doc_line,
            });
        } else {
            // Skip imports and global initializers, including nested functions.
            while i < tokens.len && text(source, tokens, i) != ";" {
                t = text(source, tokens, i);
                if t == "(" || t == "[" || t == "{" { i = paired(source, tokens, i); }
                else if t == "}" { fail("unexpected closing brace"); }
                else { i += 1; }
            }
            i += 1;
        }
    }
    if in_extern { fail("unclosed extern block"); }
    return entries;
}

// Append a JSON record per executable Goose fence in entry.doc and return
// the number of examples. Each record contains path, name, line and code.
// Accepts backtick or tilde fences with at least three characters; `goose
// ignore` fences are displayed but not extracted. Unknown Goose fence options
// and unclosed fences are errors. Extraction never executes the examples.
//
// ```goose
// let entries = doc::parse("// ```goose\n// assert(2 + 3 == 5);\n// ```\nfn demo() {}");
// var records: u8[>..] = [];
// for entry in entries {
//     assert(doc::examples(records, entry, "demo.goose") == 1);
// }
// assert(find(records, "assert(2 + 3 == 5);") >= 0);
// ```
fn examples(out: u8[>..]&, entry: const Entry&, path: const u8[:]) -> i64 {
    var marker: u8 = 0;
    var width = 0;
    var executable = false;
    var code: u8[>..] = [];
    var first_line = 0;
    var count = 0;
    for raw, offset in split(entry.doc, '\n') {
        let left = trim_start(raw);
        let indentation = raw.len - left.len;
        let line = trim_end(left);
        var run = 0;
        if indentation <= 3 && line.len > 0 && (line[0] == '`' || line[0] == '~') {
            while run < line.len && line[run] == line[0] { run += 1; }
        }
        if marker != 0 {
            if run >= width && line[0] == marker && trim(line[run..]).len == 0 {
                if executable {
                    if trim(code).len == 0 { fail("empty Goose example"); }
                    out.append("{\"path\":"); json::format_string(out, path);
                    out.append(",\"name\":"); json::format_string(out, entry.name);
                    out.append(",\"line\":"); format(out, first_line);
                    out.append(",\"code\":"); json::format_string(out, code);
                    out.append("}\n");
                    count += 1;
                }
                marker = 0;
            } else if executable { code.append(raw); code.push('\n'); }
        } else if run >= 3 {
            marker = line[0];
            width = run;
            let info = trim(line[run..]);
            executable = info == "goose";
            if starts_with(info, "goose") && info != "goose" && info != "goose ignore" {
                fail("unknown Goose fence option; use goose or goose ignore");
            }
            code.clear();
            first_line = entry.doc_line + offset + 1;
        }
    }
    if marker != 0 { fail("unclosed documentation fence"); }
    return count;
}

fn url_path(out: u8[>..]&, path: const u8[:]) {
    let hex = "0123456789ABCDEF";
    for c in path {
        if word(c) || c == '/' || c == '.' || c == '-' || c == '~' { out.push(c); }
        else { out.push('%'); out.push(hex[c >> 4]); out.push(hex[c & 15]); }
    }
}

// Append one Markdown entry with a source line-range link. source_url is a
// repository blob URL ending in a revision, or empty for relative file links.
// id must be unique in the document; it also identifies this entry in the index.
//
// ```goose
// let entries = doc::parse("// Say hello.\nfn hello() {}");
// var markdown: u8[>..] = [];
// for entry in entries { doc::render(markdown, entry, "hello.goose", "", 1); }
// assert(find(markdown, "[source](hello.goose#L2-L2)") >= 0);
// assert(find(markdown, "Say hello.") >= 0);
// ```
fn render(out: u8[>..]&, entry: const Entry&, path: const u8[:], source_url: const u8[:], id: i64) {
    out.append("<a id=\"api-"); format(out, id); out.append("\"></a>\n\n## `");
    out.append(entry.name); out.append("`\n\n[source](");
    if source_url.len > 0 { out.append(source_url); out.push('/'); }
    url_path(out, path);
    out.append("#L"); format(out, entry.line);
    out.append("-L"); format(out, entry.end_line); out.append(")\n\n");
    // Longer fences keep triple-quoted strings containing ``` valid Markdown.
    var fence: u8[>..] = ['`'; 3];
    while find(entry.signature, fence) >= 0 { fence.push('`'); }
    out.append(fence); out.append("goose\n"); out.append(entry.signature);
    out.push('\n'); out.append(fence); out.append("\n\n");
    if trim(entry.doc).len > 0 { out.append(entry.doc); out.push('\n'); }
    else { out.append("*Undocumented.*\n\n"); }
}
