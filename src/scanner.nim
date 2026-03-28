import std/[os, sets, strutils, sequtils, atomics, cpuinfo]
import std/typedthreads
import types, config
import analyzers/base

proc detectProjectKinds*(dir: string): set[ProjectKind] =
  var hasMakefile = false
  var hasNimSrc = false

  for (kind, path) in walkDir(dir):
    if kind != pcFile and kind != pcLinkToFile:
      continue
    let name = path.extractFilename
    case name
    of "Cargo.toml":    result.incl pkCargo
    of "build.gradle.kts", "build.gradle": result.incl pkGradle
    of "pom.xml":       result.incl pkMaven
    of "package.json":  discard  # detected below with lockfile check
    of "pyproject.toml", "setup.py": result.incl pkPython
    of "CMakeLists.txt": result.incl pkCMake
    of "build.xml":     result.incl pkAnt
    of "Makefile":      hasMakefile = true
    of "go.mod":        result.incl pkGo
    of "pubspec.yaml":  result.incl pkDart
    of "build.sbt":     result.incl pkSbt
    of "Package.swift": result.incl pkSwift
    of "build.zig":     result.incl pkZig
    of "mix.exs":       result.incl pkElixir
    of "meson.build":   result.incl pkMeson
    of "project.godot": result.incl pkGodot
    of "MODULE.bazel", "WORKSPACE", "WORKSPACE.bazel": result.incl pkBazel
    else:
      if name.endsWith(".nimble"): result.incl pkNim
      elif name.endsWith(".nim"): hasNimSrc = true
      elif name.endsWith(".csproj") or name.endsWith(".sln"): result.incl pkDotnet
      elif name.endsWith(".cabal"): result.incl pkHaskell
      elif name.endsWith(".uproject"): discard  # Unreal, not supported

  if pkNim notin result and hasMakefile and hasNimSrc:
    result.incl pkNim

  # Makefile: only if no other type was detected (many projects have Makefiles as wrappers)
  if hasMakefile and result == {}:
    try:
      let content = readFile(dir / "Makefile")
      if "\nclean:" in content or content.startsWith("clean:"):
        result.incl pkMakefile
    except: discard

  # Hugo: require hugo-specific config file names to avoid false positives
  # on generic config.yaml + content/ combinations
  if fileExists(dir / "hugo.yaml") or fileExists(dir / "hugo.toml"):
    result.incl pkHugo
  elif dirExists(dir / "content") and dirExists(dir / "layouts") and
       (fileExists(dir / "config.yaml") or fileExists(dir / "config.toml")):
    result.incl pkHugo

  # Unity: ProjectSettings/ directory is the reliable indicator
  if dirExists(dir / "ProjectSettings") and dirExists(dir / "Assets"):
    result.incl pkUnity

  # Jekyll: _config.yml + _posts/
  if dirExists(dir / "_posts") and
     (fileExists(dir / "_config.yml") or fileExists(dir / "_config.yaml")):
    result.incl pkJekyll

  # Haskell: stack.yaml (cabal files detected in the case block above)
  if fileExists(dir / "stack.yaml"):
    result.incl pkHaskell

  # Bundler: Gemfile + Gemfile.lock
  if fileExists(dir / "Gemfile") and fileExists(dir / "Gemfile.lock"):
    result.incl pkBundler

  # Composer: composer.json + composer.lock
  if fileExists(dir / "composer.json") and fileExists(dir / "composer.lock"):
    result.incl pkComposer

  # Node: package.json + evidence of real npm/yarn/pnpm usage
  if fileExists(dir / "package.json") and
     (fileExists(dir / "package-lock.json") or
      fileExists(dir / "yarn.lock") or
      fileExists(dir / "pnpm-lock.yaml") or
      dirExists(dir / "node_modules")):
    result.incl pkNode

proc getDirSize*(path: string): int64 =
  try:
    for entry in walkDirRec(path):
      try: result += getFileSize(entry)
      except OSError: discard
  except OSError: discard

# --- Parallel size computation ---

type
  SizeEntry = object
    path: string
    size: Atomic[int64]

  SharedState = object
    entries: seq[SizeEntry]
    nextTask: Atomic[int]

  WorkerArg = object
    state: ptr SharedState

proc sizeWorker(arg: WorkerArg) {.thread.} =
  let state = arg.state
  let total = state[].entries.len
  while true:
    let idx = state[].nextTask.fetchAdd(1)
    if idx >= total: break
    let size = getDirSize(state[].entries[idx].path)
    state[].entries[idx].size.store(size)

proc computeSizesParallel(projects: var seq[ProjectInfo], numThreads: int) =
  # Build flat entry list
  var entryMap: seq[tuple[projIdx, entIdx: int]]
  var state = cast[ptr SharedState](allocShared0(sizeof(SharedState)))
  state[].entries = @[]
  state[].nextTask.store(0)

  for pi in 0 ..< projects.len:
    for ei in 0 ..< projects[pi].entries.len:
      if not projects[pi].entries[ei].isDir:
        continue  # files already have size
      entryMap.add (pi, ei)
      var se = SizeEntry(path: projects[pi].entries[ei].path)
      se.size.store(0)
      state[].entries.add se

  # Files already have sizes — add them to totalSize now
  for pi in 0 ..< projects.len:
    for e in projects[pi].entries:
      if not e.isDir:
        projects[pi].totalSize += e.size

  if entryMap.len == 0:
    deallocShared(state)
    return

  let workerCount = min(numThreads, entryMap.len)
  var threads = newSeq[Thread[WorkerArg]](workerCount)

  for i in 0 ..< workerCount:
    createThread(threads[i], sizeWorker, WorkerArg(state: state))

  for i in 0 ..< workerCount:
    joinThread(threads[i])

  # Apply dir sizes and add to totalSize
  for i in 0 ..< entryMap.len:
    let (pi, ei) = entryMap[i]
    let size = state[].entries[i].size.load()
    projects[pi].entries[ei].size = size
    projects[pi].totalSize += size

  deallocShared(state)

# --- Main scanner ---

proc scanProjects*(rootPaths: seq[string],
                   level: CleanLevel = clClean,
                   maxDepth: int = 0,
                   threads: int = 0,
                   onProgress: proc(count: int) = nil): ScanResult =
  let defaultSkip = DefaultGlobalSkip.toHashSet
  let effectiveDepth = maxDepth

  type DirEntry = tuple[path: string, depth: int, rootProject: string, skipSet: HashSet[string]]
  var stack: seq[DirEntry]
  for p in rootPaths:
    stack.add (p, 0, "", defaultSkip)

  var scanned = 0
  var projectMap: seq[ProjectInfo]

  # Phase 1: Scan directories, detect projects, find clean targets (no size computation)
  while stack.len > 0:
    let (dir, depth, currentRoot, inheritedSkip) = stack.pop()
    inc scanned

    if onProgress != nil:
      onProgress(scanned)

    let localCfg = loadLocalConfig(dir)
    if localCfg.ignore:
      continue

    var kinds = detectProjectKinds(dir)
    if localCfg.typeOverride.len > 0:
      kinds = {}
      for part in localCfg.typeOverride.splitWhitespace():
        for kind in ProjectKind:
          if $kind == part: kinds.incl kind

    if kinds != {}:
      # Always analyze (needed for traversal decisions)
      var analyzeResults: seq[AnalyzeResult]
      for kind in kinds:
        analyzeResults.add analyze(dir, kind)
      let merged = mergeResults(analyzeResults)

      var allCleanDirs = merged.cleanTargets
      var allDistcleanTargets = merged.distcleanTargets
      for d in localCfg.extraClean:
        if d notin allCleanDirs: allCleanDirs.add d
      let keepSet = localCfg.keep.toHashSet

      var targetDirs = allCleanDirs
      if level == clDistclean:
        for d in allDistcleanTargets:
          if d notin targetDirs: targetDirs.add d

      # Filter out dirs that are subdirectories of other clean dirs
      var filteredDirs: seq[string]
      for d in targetDirs:
        if d in keepSet: continue
        var isSubdir = false
        for other in targetDirs:
          if other != d and d.startsWith(other & "/"):
            isSubdir = true
            break
        if not isSubdir:
          filteredDirs.add d

      var entries: seq[CleanEntry]
      for d in filteredDirs:
        let fullPath = dir / d
        if dirExists(fullPath):
          entries.add CleanEntry(path: fullPath, size: -1, isDir: true)
        elif fileExists(fullPath):
          try:
            let size = getFileSize(fullPath)
            entries.add CleanEntry(path: fullPath, size: size, isDir: false)
          except OSError:
            discard

        let isNewRoot = currentRoot.len == 0 or localCfg.root

        if isNewRoot:
          projectMap.add ProjectInfo(
            path: dir,
            kinds: kinds,
            entries: entries,
            totalSize: 0,
            hasLocalConfig: localCfg.typeOverride.len > 0 or
                            localCfg.extraClean.len > 0 or
                            localCfg.keep.len > 0,
            isRoot: true,
          )
          let newRoot = dir

          let negativeDirs = (allCleanDirs & allDistcleanTargets).toHashSet
          var positiveDirs = merged.skipDirs.toHashSet
          # traverse_scan overrides analyzer skipDirs too
          for t in localCfg.traverseScan: positiveDirs.excl t
          let skipHere = resolveSkipSet(localCfg, inheritedSkip)
          let localDepth = if localCfg.maxDepth > 0: localCfg.maxDepth else: effectiveDepth

          try:
            for (kind, path) in walkDir(dir):
              if kind != pcDir: continue
              let name = path.extractFilename
              if name in skipHere: continue
              if name in negativeDirs: continue
              if name in positiveDirs: continue
              if localDepth > 0 and 1 > localDepth: continue
              stack.add (path, 1, newRoot, skipHere)
          except OSError:
            result.errors.add "Cannot read: " & dir

        else:
          for i in countdown(projectMap.len - 1, 0):
            if projectMap[i].path == currentRoot:
              for e in entries:
                projectMap[i].entries.add e
              break

          let negativeDirs = (allCleanDirs & allDistcleanTargets).toHashSet
          var positiveDirs = merged.skipDirs.toHashSet
          # traverse_scan overrides analyzer skipDirs too
          for t in localCfg.traverseScan: positiveDirs.excl t
          let skipHere = resolveSkipSet(localCfg, inheritedSkip)
          let localDepth = if localCfg.maxDepth > 0: localCfg.maxDepth else: effectiveDepth

          try:
            for (kind, path) in walkDir(dir):
              if kind != pcDir: continue
              let name = path.extractFilename
              if name in skipHere: continue
              if name in negativeDirs: continue
              if name in positiveDirs: continue
              if localDepth > 0 and 1 > localDepth: continue
              stack.add (path, 1, currentRoot, skipHere)
          except OSError:
            result.errors.add "Cannot read: " & dir

    else:
      if effectiveDepth > 0 and depth + 1 > effectiveDepth:
        continue
      let skipHere = resolveSkipSet(localCfg, inheritedSkip)
      try:
        for (kind, path) in walkDir(dir):
          if kind != pcDir: continue
          if path.extractFilename in skipHere: continue
          stack.add (path, depth + 1, currentRoot, skipHere)
      except OSError:
        result.errors.add "Cannot read: " & dir

  discard scanned

  # Filter empty projects
  projectMap = projectMap.filterIt(it.entries.len > 0)

  # Phase 2: Compute sizes in parallel
  let numThreads = if threads > 0: threads else: countProcessors()
  computeSizesParallel(projectMap, numThreads)

  result.projects = projectMap
