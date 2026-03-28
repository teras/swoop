import std/[os]
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
