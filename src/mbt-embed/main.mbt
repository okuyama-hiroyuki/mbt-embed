///|
/// Usage shown when arguments are wrong.
fn print_usage() -> Unit {
  println("usage: mbt-embed <input_dir> <output_file> [--package <name>]")
  println("  <input_dir>    folder to embed recursively")
  println("  <output_file>  path the generated MoonBit source is written to")
  println("  --package <name>  optional, recorded as a header comment in")
  println("                   the generated file (e.g. myapp/assets)")
}

///|
/// Exit with `code` after printing `msg` and usage. Never returns; the
/// caller relies on the polymorphic `abort` to satisfy the type system.
fn die(msg : String, code : Int) -> Unit {
  println("error: \{msg}")
  print_usage()
  @sys.exit(code)
}

///|
/// Parse the part of argv after the program name into
/// `(input_dir, output_file, package_hint)`. Flags may appear after the
/// positional arguments; the positionals must come first, in order.
///
/// Returns a `Result` because errors are not exceptional at the CLI boundary.
fn parse_args(args : Array[String]) -> Result[(String, String, String), String] {
  if args.length() < 3 {
    Err("not enough arguments")
  } else {
    let input_dir = args[1]
    let output_file = args[2]
    let mut pkg = ""
    let mut i = 3
    while i < args.length() {
      let a = args[i]
      if a == "--package" {
        if i + 1 >= args.length() {
          return Err("--package requires a value")
        }
        pkg = args[i + 1]
        i = i + 2
      } else {
        return Err("unknown argument: \{a}")
      }
    }
    Ok((input_dir, output_file, pkg))
  }
}

///|
/// Entry point.
///
///   mbt-embed <input_dir> <output_file> [--package <name>]
///
/// Reads `<input_dir>` recursively and writes the generated `.mbt` source to
/// `<output_file>`, exposing the embedded bytes as `pub let entries :
/// Map[String, Bytes]` and `pub fn get(String) -> Bytes?`.
fn main {
  let args = @sys.get_cli_args()
  let (input_dir, output_file, package_hint) = match parse_args(args) {
    Ok(tup) => tup
    Err(msg) => {
      die(msg, 1)
      abort("unreachable after sys.exit")
    }
  }
  if !@fs.path_exists(input_dir) {
    die("input dir does not exist: \{input_dir}", 2)
    abort("unreachable after sys.exit")
  }
  let entries : Array[Entry] = walk(input_dir) catch {
    @fs.IOError(msg) => {
      println("error walking \{input_dir}: \{msg}")
      @sys.exit(3)
      abort("unreachable after sys.exit")
    }
  }
  let body = generate(entries, package_hint)
  @fs.write_string_to_file(output_file, body) catch {
    @fs.IOError(msg) => {
      println("error writing \{output_file}: \{msg}")
      @sys.exit(4)
      abort("unreachable after sys.exit")
    }
  }
}
