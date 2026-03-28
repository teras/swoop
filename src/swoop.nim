import std/[os, strutils, sequtils]
import types, config, scanner, output, cleaner

proc main() =
  var
    execute = false
    purge = false
    verbose = false
    quiet = false
    noColor = false
    force = false
    makeConfigPath = ""
    numThreads = 0
    maxDepth = 0
    filterType: set[ProjectKind] = {}
    paths: seq[string]

  var i = 1
  while i <= paramCount():
    let arg = paramStr(i)
    case arg
    of "-x", "--execute":
      execute = true
    of "--purge":
      purge = true
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
        for kind in ProjectKind:
          if $kind == paramStr(i):
            filterType.incl kind
    of "-h", "--help":
      echo """swoop - Smart Build Artifact Cleaner

Usage: swoop [options] [path...]

Arguments:
  path              Directories to scan (default: current directory)

Options:
  -x, --execute     Actually delete (without this = dry-run)
  -f, --force       Don't ask for confirmation (with -x)
  --purge           Distclean level: also remove deps/caches/envs
                    (node_modules, .venv, .gradle, etc.)
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

  let level = if purge: clDistclean else: clClean
  let dryRun = not execute

  var scanResult = scanProjects(
    rootPaths = paths,
    level = level,
    maxDepth = maxDepth,
    threads = numThreads,
    onProgress = if not quiet: printCountProgress else: nil,
  )

  if filterType != {}:
    scanResult.projects = scanResult.projects.filterIt((it.kinds * filterType) != {})

  if not quiet:
    clearProgress()

  printResults(scanResult.projects, paths[0], execute, noColor)

  if scanResult.errors.len > 0 and verbose:
    echo "Errors:"
    for e in scanResult.errors:
      echo "  " & e

  if not dryRun and scanResult.projects.len > 0:
    var totalBytes: int64 = 0
    for p in scanResult.projects: totalBytes += p.totalSize
    if not force and not quiet:
      stderr.write "Delete " & fmtSize(totalBytes) & "? [y/N] "
      stderr.flushFile()
      let answer = stdin.readLine().strip().toLowerAscii()
      if answer != "y" and answer != "yes":
        echo "Aborted."
        quit(0)
    let (cleaned, freed) = cleanAll(scanResult.projects, dryRun = false, verbose = verbose)
    if not quiet:
      echo "Cleaned " & $cleaned & " targets, freed " & fmtSize(freed)

when isMainModule:
  main()
