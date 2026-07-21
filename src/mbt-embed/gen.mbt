///|
const CHUNK_SIZE : Int = 4096

///|
/// Lowercase hex digits, kept as a `FixedArray[String]` so we can index it
/// cheaply when escaping control characters in path literals.
let hex_digits : FixedArray[String] = [
  "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
]

///|
/// Hex of the low byte of `n`, two lowercase digits, for use inside `\u{...}`.
fn hex2(n : Int) -> String {
  let lo = n & 0xFF
  hex_digits[(lo >> 4) & 0x0F] + hex_digits[lo & 0x0F]
}

///|
/// Append, to `out`, one or more lines that together form a MoonBit
/// expression of type `Bytes` whose value equals `bytes`.
///
/// Each 4096-byte chunk is emitted as a single `Bytes::from_array([...])`
/// line concatenated with `+` (Bytes supports `Add`). Bounding the array
/// literals keeps the generated file readable without a single mega-literal.
/// The `+` must trail the line it continues from, not lead the next one:
/// MoonBit's parser inserts an implicit statement break at a line start
/// that isn't a continuation of an open bracket, so a leading `+` reads as
/// an unrelated unbound `~+` reference rather than binding to the
/// preceding `Bytes::from_array([...])`.
fn emit_bytes_lit(bytes : Bytes, out : Array[String]) -> Unit {
  let len = bytes.length()
  if len == 0 {
    out.push("  Bytes::new(0)")
    return
  }
  let mut i = 0
  while i < len {
    let end = if i + CHUNK_SIZE < len { i + CHUNK_SIZE } else { len }
    let parts : Array[String] = []
    parts.push("  Bytes::from_array([")
    let mut j = i
    while j < end {
      if j != i {
        parts.push(", ")
      }
      parts.push("0x")
      parts.push(bytes[j].to_hex())
      j = j + 1
    }
    parts.push("])")
    if end < len {
      parts.push(" +")
    }
    out.push(parts.join(""))
    i = end
  }
}

///|
/// Append the escaped form of one character to `parts`, as it should appear
/// inside a MoonBit `"..."` literal. We escape backslash, double quote, and
/// the common whitespace characters; any other code point below 0x20
/// becomes `\u{NN}` to keep the output printable and ASCII-safe. Code points
/// at or above 0x20 (including UTF-8 above 0x7E) are passed through.
fn push_escaped_char(c : Char, parts : Array[String]) -> Unit {
  match c {
    '\\' => parts.push("\\\\")
    '"' => parts.push("\\\"")
    '\n' => parts.push("\\n")
    '\r' => parts.push("\\r")
    '\t' => parts.push("\\t")
    _ => {
      let n = c.to_int()
      if n < 0x20 {
        parts.push("\\u{" + hex2(n) + "}")
      } else {
        parts.push(c.to_string())
      }
    }
  }
}

///|
/// Append, to `out`, one or more lines that together form a MoonBit
/// expression of type `Bytes`, by round-tripping `s` through `_utf8_encode`
/// (emitted once into the main file, see `utf8_encode_helper`). Used instead
/// of `emit_bytes_lit` whenever `decode_utf8` has confirmed the entry's
/// bytes are well-formed UTF-8: printable text then costs about one source
/// character per original byte, instead of the ~6 characters of a `0xNN, `
/// hex literal. Chunked every `CHUNK_SIZE` characters for the same
/// readability reason as `emit_bytes_lit`, with the same trailing-`+`
/// convention.
fn emit_string_lit(s : String, out : Array[String]) -> Unit {
  let mut parts : Array[String] = ["  _utf8_encode(\""]
  let mut count = 0
  for _, c in s.iter2() {
    if count == CHUNK_SIZE {
      parts.push("\") +")
      out.push(parts.join(""))
      parts = ["  _utf8_encode(\""]
      count = 0
    }
    push_escaped_char(c, parts)
    count = count + 1
  }
  parts.push("\")")
  out.push(parts.join(""))
}

///|
/// Source of the private helper appended to the main file whenever at least
/// one entry is emitted via `emit_string_lit`. Re-encodes a MoonBit
/// `String` (UTF-16 internally) back to UTF-8 `Bytes`, hand-written so the
/// generated output needs no import beyond the implicit builtin prelude.
let utf8_encode_helper : String =
  #|///|
  #|fn _utf8_encode(s : String) -> Bytes {
  #|  let out : Array[Byte] = []
  #|  for _, c in s.iter2() {
  #|    let cp = c.to_int()
  #|    if cp < 0x80 {
  #|      out.push(cp.to_byte())
  #|    } else if cp < 0x800 {
  #|      out.push((0xC0 | (cp >> 6)).to_byte())
  #|      out.push((0x80 | (cp & 0x3F)).to_byte())
  #|    } else if cp < 0x10000 {
  #|      out.push((0xE0 | (cp >> 12)).to_byte())
  #|      out.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
  #|      out.push((0x80 | (cp & 0x3F)).to_byte())
  #|    } else {
  #|      out.push((0xF0 | (cp >> 18)).to_byte())
  #|      out.push((0x80 | ((cp >> 12) & 0x3F)).to_byte())
  #|      out.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
  #|      out.push((0x80 | (cp & 0x3F)).to_byte())
  #|    }
  #|  }
  #|  Bytes::from_array(out[:])
  #|}

///|
/// Escape `s` as a MoonBit `"..."` literal.
fn escape_string_lit(s : String) -> String {
  let parts : Array[String] = []
  parts.push("\"")
  for _, c in s.iter2() {
    push_escaped_char(c, parts)
  }
  parts.push("\"")
  parts.join("")
}

///|
/// Decode `bytes` as well-formed UTF-8, or return `None` if any byte
/// sequence is truncated, overlong, encodes a surrogate half, or exceeds
/// U+10FFFF. Written by hand (rather than pulled from a library) so that
/// neither this tool nor the code it generates needs any import beyond the
/// implicit builtin prelude.
fn decode_utf8(bytes : Bytes) -> String? {
  let len = bytes.length()
  let chars : Array[Char] = []
  let mut i = 0
  while i < len {
    let b0 = bytes[i].to_int()
    if b0 < 0x80 {
      chars.push(b0.unsafe_to_char())
      i = i + 1
    } else if (b0 & 0xE0) == 0xC0 {
      if i + 1 >= len {
        return None
      }
      let b1 = bytes[i + 1].to_int()
      if (b1 & 0xC0) != 0x80 {
        return None
      }
      let cp = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
      if cp < 0x80 {
        return None
      }
      chars.push(cp.unsafe_to_char())
      i = i + 2
    } else if (b0 & 0xF0) == 0xE0 {
      if i + 2 >= len {
        return None
      }
      let b1 = bytes[i + 1].to_int()
      let b2 = bytes[i + 2].to_int()
      if (b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80 {
        return None
      }
      let cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
      if cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF) {
        return None
      }
      chars.push(cp.unsafe_to_char())
      i = i + 3
    } else if (b0 & 0xF8) == 0xF0 {
      if i + 3 >= len {
        return None
      }
      let b1 = bytes[i + 1].to_int()
      let b2 = bytes[i + 2].to_int()
      let b3 = bytes[i + 3].to_int()
      if (b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 {
        return None
      }
      let cp = ((b0 & 0x07) << 18) |
        ((b1 & 0x3F) << 12) |
        ((b2 & 0x3F) << 6) |
        (b3 & 0x3F)
      if cp < 0x10000 || cp > 0x10FFFF {
        return None
      }
      chars.push(cp.unsafe_to_char())
      i = i + 4
    } else {
      return None
    }
  }
  Some(String::from_array(chars[:]))
}

///|
/// Name of the main generated file (the one holding `entries` and `get`),
/// written into `<output_dir>`.
const OUTPUT_FILE_NAME : String = "embed.mbt"

///|
/// Name of the package manifest written into `<output_dir>` so the
/// generated files form a standalone MoonBit package on their own.
const PKG_FILE_NAME : String = "moon.pkg"

///|
/// Name of the per-entry file holding `_embed_\{i}`, written into
/// `<output_dir>` alongside `OUTPUT_FILE_NAME`.
fn embed_file_name(i : Int) -> String {
  "embed_\{i}.mbt"
}

///|
/// Produce the generated source as `(file_name, content)` pairs, one file
/// per embedded entry (`_embed_\{i}`) plus a main file holding `entries` and
/// `get`, plus a `moon.pkg` manifest. Splitting one file per entry keeps any
/// single generated file from growing with the number (or size) of embedded
/// assets, and lets the compiler parallelize across them; `_embed_\{i}` has
/// no `pub`, so it's only visible within this package, which is exactly how
/// the main file reaches it despite living in a different file.
/// `package_hint` is written only as a header comment (MoonBit does not
/// require a per-file `package` directive; this just documents where the
/// files are meant to live). The generated code never references anything
/// outside the builtin prelude, so `moon.pkg` carries an empty `import {}`.
fn generate_files(
  entries : Array[Entry],
  package_hint : String,
) -> Array[(String, String)] {
  let decoded : Array[String?] = []
  let mut any_utf8 = false
  for _, e in entries.iter2() {
    let d = decode_utf8(e.bytes)
    match d {
      Some(_) => any_utf8 = true
      None => ()
    }
    decoded.push(d)
  }
  let files : Array[(String, String)] = []
  let main_lines : Array[String] = []
  main_lines.push("// Generated by mbt-embed. DO NOT EDIT.")
  main_lines.push("// Keys are file paths relative to the input directory,")
  main_lines.push("// joined with `/` and produced by `mbt-embed` at build time.")
  if package_hint != "" {
    main_lines.push("// Belongs to package: \{package_hint}")
  }
  main_lines.push("")
  main_lines.push("///|")
  main_lines.push("pub let entries : Map[String, Bytes] = Map::from_array([")
  let n = entries.length()
  for i, e in entries.iter2() {
    let trailing = if i + 1 < n { "," } else { "" }
    main_lines.push("  (\{escape_string_lit(e.rel)}, _embed_\{i}())\{trailing}")
  }
  main_lines.push("])")
  main_lines.push("")
  main_lines.push("///|")
  main_lines.push("/// Look up an embedded file by its relative path.")
  main_lines.push("pub fn get(path : String) -> Bytes? { entries.get(path) }")
  main_lines.push("")
  if any_utf8 {
    main_lines.push(utf8_encode_helper)
  }
  files.push((OUTPUT_FILE_NAME, main_lines.join("\n")))
  files.push((PKG_FILE_NAME, "import {\n}\n"))
  for i, e in entries.iter2() {
    let lines : Array[String] = []
    lines.push("// Generated by mbt-embed. DO NOT EDIT.")
    lines.push("")
    lines.push("///|")
    lines.push("fn _embed_\{i}() -> Bytes {")
    match decoded[i] {
      Some(s) => emit_string_lit(s, lines)
      None => emit_bytes_lit(e.bytes, lines)
    }
    lines.push("}")
    lines.push("")
    files.push((embed_file_name(i), lines.join("\n")))
  }
  files
}
