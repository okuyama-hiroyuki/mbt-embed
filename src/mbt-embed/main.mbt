///|
/// Usage shown when arguments are wrong.
fn print_usage() -> Unit {
  println("usage: mbt-embed <input_dir> [--package <name>]")
  println("  <input_dir>    folder to embed recursively")
  println("  --package <name>  optional, recorded as a header comment in")
  println("                   the generated file (e.g. myapp/assets)")
  println("Generated MoonBit source is written to stdout.")
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
/// `(input_dir, package_hint)`. Flags may appear after the positional
/// argument; the positional must come first.
///
/// Returns a `Result` because errors are not exceptional at the CLI boundary.
fn parse_args(args : Array[String]) -> Result[(String, String), String] {
  if args.length() < 2 {
    Err("not enough arguments")
  } else {
    let input_dir = args[1]
    let mut pkg = ""
    let mut i = 2
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
    Ok((input_dir, pkg))
  }
}

///|
/// Entry point.
///
///   mbt-embed <input_dir> [--package <name>]
///
/// Reads `<input_dir>` recursively and writes the generated `.mbt` source to
/// stdout, exposing the embedded bytes as `pub let entries : Map[String,
/// Bytes]` and `pub fn get(String) -> Bytes?`.
fn main {
  let args = @sys.get_cli_args()
  let (input_dir, package_hint) = match parse_args(args) {
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
  println(body)
}
