import std/[os, strutils, sequtils]
import types, config, scanner, output, cleaner

proc main() =
  var
    execute = false
    all = false
    prune = false
    noSkip = false
    verbose = false
    quiet = false
    noColor = false
    force = false
    makeConfigPath = ""
    numThreads = 0
    maxDepth = 0
    filterType: set[ProjectKind] = {}
    filterEmpty = false
    paths: seq[string]

  var i = 1
  while i <= paramCount():
    let arg = paramStr(i)
    case arg
    of "-x", "--execute":
      execute = true
    of "--all":
      all = true
    of "--prune":
      prune = true
    of "--no-skip":
      noSkip = true
    of "-v", "--verbose":
      verbose = true
    of "-q", "--quiet":
      quiet = true
    of "--no-color":
      noColor = true
    of "-f", "--force":
      force = true
    of "--make-config":
      inc i
      if i <= paramCount():
        makeConfigPath = paramStr(i)
    of "-t", "--threads":
      inc i
      if i <= paramCount():
        try: numThreads = parseInt(paramStr(i))
        except: stderr.writeLine "Invalid value for --threads: " & paramStr(i); quit(1)
    of "--depth":
      inc i
      if i <= paramCount():
        try: maxDepth = parseInt(paramStr(i))
        except: stderr.writeLine "Invalid value for --depth: " & paramStr(i); quit(1)
    of "--type":
      inc i
      if i <= paramCount():
        if paramStr(i) == "empty":
          filterEmpty = true
          prune = true
        else:
          var found = false
          for kind in ProjectKind:
            if $kind == paramStr(i):
              filterType.incl kind
              found = true
          if not found:
            stderr.writeLine "Unknown project type: " & paramStr(i)
            quit(1)
    of "-h", "--help":
      echo """swoop - Smart Build Artifact Cleaner

Usage: swoop [options] [path...]

Arguments:
  path              Directories to scan (default: current directory)

Options:
  -x, --execute     Actually delete (without this = dry-run)
  -f, --force       Don't ask for confirmation (with -x)
  --all             Also remove deps/caches/envs (node_modules, .venv, etc.)
  --prune           Remove empty directories bottom-up after cleaning
  --no-skip         Descend into source directories (override positive matches)
  -v, --verbose     Verbose output
  -q, --quiet       Only errors
  -t, --threads N   Worker threads (default: auto)
  --type TYPE       Only show/clean this project type
  --depth N         Max scan depth (default: unlimited)
  --no-color        Disable colored output
  --make-config P   Create a default .swoop.toml at path P
  -h, --help        Show this help"""
      quit(0)
    else:
      if arg.startsWith("-"):
        stderr.writeLine "Unknown option: " & arg
        quit(1)
      paths.add arg
    inc i

  if paths.len == 0:
    paths.add getCurrentDir()

  for j in 0 ..< paths.len:
    paths[j] = paths[j].expandTilde().absolutePath()

  if makeConfigPath.len > 0:
    if createLocalConfig(makeConfigPath):
      quit(0)
    else:
      quit(1)

  let level = if all: clDistclean else: clClean
  let dryRun = not execute

  var scanResult = scanProjects(
    rootPaths = paths,
    level = level,
    maxDepth = maxDepth,
    threads = numThreads,
    noSkip = noSkip,
    onProgress = if not quiet: printCountProgress else: nil,
  )

  if filterType != {}:
    scanResult.projects = scanResult.projects.filterIt((it.kinds * filterType) != {})

  if not quiet:
    clearProgress()

  var emptyDirs: seq[string]
  var orphanEmpty: seq[string]
  if prune:
    var excludePaths: seq[string]
    for p in scanResult.projects:
      for d in p.artifactDirs:
        excludePaths.add d

    emptyDirs = findEmptyDirs(paths, excludePaths, DefaultGlobalSkip)
    for emptyDir in emptyDirs:
      # Assign to nearest project
      var assigned = false
      for pi in 0 ..< scanResult.projects.len:
        if emptyDir.startsWith(scanResult.projects[pi].path & "/"):
          scanResult.projects[pi].entries.add CleanEntry(
            path: emptyDir, size: 0, isDir: true)
          assigned = true
          break
      if not assigned:
        orphanEmpty.add emptyDir

  if filterEmpty:
    printResults(@[], paths[0], execute, noColor, orphanEmpty)
  else:
    printResults(scanResult.projects, paths[0], execute, noColor,
                 if prune: orphanEmpty else: @[])

  if scanResult.errors.len > 0 and verbose:
    echo "Errors:"
    for e in scanResult.errors:
      echo "  " & e

  if filterEmpty:
    # Only clean empty dirs
    if not dryRun and (orphanEmpty.len > 0 or emptyDirs.len > 0):
      if not force and not quiet:
        stderr.write "Delete " & $emptyDirs.len & " empty directories? [y/N] "
        stderr.flushFile()
        let answer = stdin.readLine().strip().toLowerAscii()
        if answer != "y" and answer != "yes":
          echo "Aborted."
          quit(0)
      pruneEmptyDirs(emptyDirs, verbose = verbose)
      if not quiet:
        echo "Pruned " & $emptyDirs.len & " empty directories"
  elif not dryRun and scanResult.projects.len > 0:
    var totalBytes: int64 = 0
    for p in scanResult.projects: totalBytes += p.totalSize
    if not force and not quiet:
      stderr.write "Delete " & fmtSize(totalBytes, pad = false) & "? [y/N] "
      stderr.flushFile()
      let answer = stdin.readLine().strip().toLowerAscii()
      if answer != "y" and answer != "yes":
        echo "Aborted."
        quit(0)
    let (cleaned, freed) = cleanAll(scanResult.projects, dryRun = false, verbose = verbose)
    if prune and orphanEmpty.len > 0:
      pruneEmptyDirs(orphanEmpty, verbose = verbose)
    if not quiet:
      echo "Cleaned " & $cleaned & " targets, freed " & fmtSize(freed, pad = false)

when isMainModule:
  main()
