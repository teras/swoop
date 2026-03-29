import std/[os, algorithm, strutils, sets]
import types

proc deleteEntry*(entry: CleanEntry, dryRun: bool): bool =
  ## Delete a single clean entry. Returns true on success.
  if dryRun:
    return true
  try:
    if entry.isDir:
      removeDir(entry.path)
    else:
      removeFile(entry.path)
    return true
  except OSError as e:
    stderr.writeLine "Error deleting " & entry.path & ": " & e.msg
    return false

proc cleanProject*(project: ProjectInfo, dryRun: bool, verbose: bool): tuple[cleaned: int, freed: int64] =
  ## Clean all entries for a project. Returns count and bytes freed.
  for entry in project.entries:
    if deleteEntry(entry, dryRun):
      inc result.cleaned
      result.freed += entry.size
    elif verbose:
      stderr.writeLine "  Failed: " & entry.path

proc cleanAll*(projects: seq[ProjectInfo], dryRun: bool, verbose: bool): tuple[cleaned: int, freed: int64] =
  for p in projects:
    if p.entries.len == 0:
      continue
    let (c, f) = cleanProject(p, dryRun, verbose)
    result.cleaned += c
    result.freed += f

proc findEmptyDirs*(rootPaths: seq[string], exclude: seq[string] = @[],
                    skipNames: openArray[string] = []): seq[string] =
  ## Find empty directories bottom-up, skipping excluded subtrees and named dirs.
  for rootPath in rootPaths:
    var dirs: seq[string]
    var stack = @[rootPath]
    while stack.len > 0:
      let current = stack.pop()
      try:
        for (kind, path) in walkDir(current):
          if kind != pcDir: continue
          let name = path.extractFilename
          # Skip well-known dirs (.git, .idea, etc.)
          if name in skipNames: continue
          # Skip clean target subtrees
          var skip = false
          for ex in exclude:
            if path == ex or path.startsWith(ex & "/"):
              skip = true
              break
          if not skip:
            dirs.add path
            stack.add path
      except OSError:
        discard
    # Sort by length descending (deepest first)
    dirs.sort(proc(a, b: string): int = cmp(b.len, a.len))
    var emptySet: HashSet[string]
    for dir in dirs:
      try:
        var hasContent = false
        for (kind, path) in walkDir(dir):
          if kind == pcDir and path in emptySet:
            continue  # this child will be removed
          hasContent = true
          break
        if not hasContent:
          emptySet.incl dir
      except OSError:
        discard
    # Only report top-level empty dirs (not children of other empty dirs)
    for dir in dirs:
      if dir in emptySet:
        let parent = dir.parentDir
        if parent notin emptySet:
          result.add dir

proc pruneEmptyDirs*(dirs: seq[string], verbose: bool) =
  ## Actually delete the empty directories.
  for dir in dirs:
    try:
      removeDir(dir)
      if verbose:
        stderr.writeLine "Pruned: " & dir
    except OSError:
      discard
