///|
/// One embedded file: its key (path relative to the root, joined with `/`)
/// and its raw bytes.
priv struct Entry {
  rel : String
  bytes : Bytes
}

///|
/// Kind of a directory entry: directory, regular file, or something else
/// (symlink, pipe, vanished path...) that we skip.
priv enum Kind {
  Dir
  File
  Other
}

///|
/// Classify a path, never raising: paths that disappear mid-walk or that
/// `@fs` refuses to stat are reported as `Other`.
fn classify(path : String) -> Kind {
  try {
    if @fs.is_dir(path) {
      Dir
    } else if @fs.is_file(path) {
      File
    } else {
      Other
    }
  } catch {
    _ => Other
  }
}

///|
/// Join `rel` and `name` with a `/`, or return `name` when `rel` is empty
/// (i.e. `name` is directly under the root). Keeping this branch out of the
/// hot string-concat path makes the output a tiny bit faster.
fn join_rel(rel : String, name : String) -> String {
  if rel == "" {
    name
  } else {
    "\{rel}/\{name}"
  }
}

///|
/// Recursively walk `root`, returning every regular file under it as an
/// `Entry` whose `rel` is the path relative to `root` (using `/` separators).
/// Entries are returned in a stable, sorted order so the generated output is
/// reproducible across runs and filesystems.
///
/// Hidden files and directories (those whose name starts with `.`) are kept,
/// since users may want to embed e.g. `.gitkeep` placeholders.
fn walk(root : String) -> Array[Entry] raise @fs.IOError {
  let out : Array[Entry] = []
  walk_dir(root, "", out)
  out.sort_by_key(fn(e) { e.rel })
  out
}

///|
fn walk_dir(
  root : String,
  rel : String,
  out : Array[Entry],
) -> Unit raise @fs.IOError {
  let dir_path = if rel == "" { root } else { "\{root}/\{rel}" }
  let names = @fs.read_dir(dir_path)
  names.sort()
  for name in names {
    let child_rel = join_rel(rel, name)
    let child_path = "\{root}/\{child_rel}"
    match classify(child_path) {
      Dir => walk_dir(root, child_rel, out)
      File =>
        out.push({ rel: child_rel, bytes: @fs.read_file_to_bytes(child_path) })
      Other => ()
    }
  }
}
