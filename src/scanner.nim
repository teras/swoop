import std/[os, sets, strutils, atomics, cpuinfo, tables]
import std/typedthreads
import types, config
import analyzers/base

proc detectProjectKinds*(dir: string): set[ProjectKind] =
  var hasMakefile = false

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
      elif name.endsWith(".csproj") or name.endsWith(".sln"): result.incl pkDotnet
      elif name.endsWith(".cabal"): result.incl pkHaskell
      elif name.endsWith(".uproject"): discard  # Unreal, not supported

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

  # Flatpak: .flatpak-builder/ directory
  if dirExists(dir / ".flatpak-builder"):
    result.incl pkFlatpak

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

  # --- Artifact-based fallback detection ---
  # Detect project types by unique build artifacts even without project definition files

  if pkPython notin result:
    for d in ["__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".tox"]:
      if dirExists(dir / d):
        result.incl pkPython
        break
  if pkPython notin result:
    for d in ["venv", ".venv"]:
      if fileExists(dir / d / "bin" / "python") or
         fileExists(dir / d / "Scripts" / "python.exe"):
        result.incl pkPython
        break

  if pkNode notin result:
    for d in [".next", ".nuxt", ".parcel-cache", ".turbo", ".angular"]:
      if dirExists(dir / d):
        result.incl pkNode
        break

  if pkNim notin result and dirExists(dir / "nimcache"):
    result.incl pkNim

  if pkZig notin result:
    for d in ["zig-cache", ".zig-cache", "zig-out"]:
      if dirExists(dir / d):
        result.incl pkZig
        break

  if pkGodot notin result and dirExists(dir / ".godot"):
    result.incl pkGodot

  if pkJekyll notin result and dirExists(dir / ".jekyll-cache"):
    result.incl pkJekyll

  if pkDart notin result and dirExists(dir / ".dart_tool"):
    result.incl pkDart

  if pkHaskell notin result and dirExists(dir / ".stack-work"):
    result.incl pkHaskell

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

# --- Scan types ---

type
  DirEntry = tuple[path: string, depth: int, rootProject: string, skipSet: HashSet[string], forceRoot: bool]

  SubtreeResult = object
    projects: seq[ProjectInfo]
    emptyDirs: seq[string]
    dirInfo: Table[string, tuple[hasFiles: bool, childDirs: int]]
    errors: seq[string]
    scanned: int

# --- Core scan logic (used by both single and multi-threaded) ---

proc scanSubtree(initialEntries: seq[DirEntry], level: CleanLevel,
                 effectiveDepth: int, noSkip: bool, prune: bool,
                 homeDir: string,
                 onProgress: proc(count: int) = nil): SubtreeResult =
  var stack = initialEntries

  while stack.len > 0:
    let (dir, depth, currentRoot, inheritedSkip, forceRoot) = stack.pop()
    inc result.scanned

    if onProgress != nil and (result.scanned mod 50) == 0:
      onProgress(result.scanned)

    let localCfg = loadLocalConfig(dir)
    if localCfg.ignore:
      continue

    var kinds = if dir == homeDir:
                  {}
                else:
                  detectProjectKinds(dir)
    if localCfg.typeOverride.len > 0:
      kinds = {}
      for part in localCfg.typeOverride.splitWhitespace():
        for kind in ProjectKind:
          if $kind == part: kinds.incl kind

    let hasExtraTargets = localCfg.extraClean.len > 0 or localCfg.extraAll.len > 0
    if hasExtraTargets and kinds == {}:
      kinds.incl pkCustom

    if kinds != {}:
      var analyzeResults: seq[AnalyzeResult]
      for kind in kinds:
        analyzeResults.add analyze(dir, kind)
      let merged = mergeResults(analyzeResults)

      var allCleanDirs = merged.cleanTargets
      var allDistcleanTargets = merged.distcleanTargets
      for d in localCfg.extraClean:
        if d notin allCleanDirs: allCleanDirs.add d
      for d in localCfg.extraAll:
        if d notin allDistcleanTargets: allDistcleanTargets.add d
      let keepSet = localCfg.keep.toHashSet

      var targetDirs = allCleanDirs
      let cleanSet = allCleanDirs.toHashSet
      let distcleanSet = allDistcleanTargets.toHashSet - cleanSet
      if level == clDistclean:
        for d in allDistcleanTargets:
          if d notin targetDirs: targetDirs.add d

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
        let isDist = d in distcleanSet
        if dirExists(fullPath):
          entries.add CleanEntry(path: fullPath, size: -1, isDir: true, distclean: isDist)
        elif fileExists(fullPath):
          try:
            let size = getFileSize(fullPath)
            entries.add CleanEntry(path: fullPath, size: size, isDir: false, distclean: isDist)
          except OSError:
            discard

      var artifactDirs: seq[string]
      for d in allCleanDirs & allDistcleanTargets & merged.skipDirs:
        let fullPath = dir / d
        if dirExists(fullPath):
          artifactDirs.add fullPath

      let isNewRoot = currentRoot.len == 0 or localCfg.root == "self" or forceRoot
      let negativeDirs = (allCleanDirs & allDistcleanTargets).toHashSet
      var positiveDirs = if noSkip: initHashSet[string]()
                         else: merged.skipDirs.toHashSet
      for t in localCfg.traverseScan: positiveDirs.excl t
      let skipHere = resolveSkipSet(localCfg, inheritedSkip)

      var nextRoot: string
      if isNewRoot:
        result.projects.add ProjectInfo(
          path: dir,
          kinds: kinds,
          entries: entries,
          artifactDirs: artifactDirs,
        )
        nextRoot = dir
      else:
        for i in countdown(result.projects.len - 1, 0):
          if result.projects[i].path == currentRoot:
            for e in entries:
              result.projects[i].entries.add e
            for d in artifactDirs:
              result.projects[i].artifactDirs.add d
            break
        nextRoot = currentRoot

      try:
        var hasFiles = false
        var childDirs = 0
        var hasEntries = false
        for (kind, path) in walkDir(dir):
          hasEntries = true
          if kind != pcDir:
            hasFiles = true
            continue
          childDirs += 1
          let name = path.extractFilename
          if name in skipHere: continue
          if name in negativeDirs: continue
          if name in positiveDirs: continue
          stack.add (path, 1, nextRoot, skipHere, localCfg.root == "children")
        if prune:
          if not hasEntries:
            result.emptyDirs.add dir
          else:
            result.dirInfo[dir] = (hasFiles, childDirs)
      except OSError:
        result.errors.add "Cannot read: " & dir

    else:
      if effectiveDepth > 0 and depth + 1 > effectiveDepth:
        continue
      let skipHere = resolveSkipSet(localCfg, inheritedSkip)
      let childForceRoot = localCfg.root == "children"
      try:
        var hasFiles = false
        var childDirs = 0
        var hasEntries = false
        for (kind, path) in walkDir(dir):
          hasEntries = true
          if kind != pcDir:
            hasFiles = true
            continue
          childDirs += 1
          if path.extractFilename in skipHere: continue
          stack.add (path, depth + 1, currentRoot, skipHere, childForceRoot)
        if prune:
          if not hasEntries:
            result.emptyDirs.add dir
          else:
            result.dirInfo[dir] = (hasFiles, childDirs)
      except OSError:
        result.errors.add "Cannot read: " & dir

# --- Parallel scan worker ---

import threading/channels

type
  ScanWorkerArg = object
    work: ptr seq[DirEntry]
    nextTask: ptr Atomic[int]
    level: CleanLevel
    effectiveDepth: int
    noSkip: bool
    prune: bool
    homeDir: string
    ch: ptr Chan[SubtreeResult]

proc scanWorker(arg: ScanWorkerArg) {.thread.} =
  {.cast(gcsafe).}:
    var combined: SubtreeResult
    while true:
      let idx = arg.nextTask[].fetchAdd(1)
      if idx >= arg.work[].len: break
      let entry = arg.work[][idx]
      let sub = scanSubtree(@[entry], arg.level, arg.effectiveDepth,
                            arg.noSkip, arg.prune, arg.homeDir)
      for proj in sub.projects: combined.projects.add proj
      for d in sub.emptyDirs: combined.emptyDirs.add d
      for e in sub.errors: combined.errors.add e
      for k, v in sub.dirInfo: combined.dirInfo[k] = v
      combined.scanned += sub.scanned
    arg.ch[].send(move combined)

# --- Main scanner ---

proc scanProjects*(rootPaths: seq[string],
                   level: CleanLevel = clClean,
                   maxDepth: int = 0,
                   threads: int = 0,
                   noSkip: bool = false,
                   prune: bool = false,
                   onProgress: proc(count: int) = nil): ScanResult =
  let effectiveDepth = maxDepth
  let numThreads = if threads > 0: threads else: countProcessors()

  var homeDir = getHomeDir().normalizedPath
  if homeDir.endsWith("/"): homeDir = homeDir[0..^2]

  # Step 1: Process root paths to collect top-level work items
  var topLevelWork: seq[DirEntry]

  for p in rootPaths:
    let initialSkip = buildAncestorSkipSet(p)
    let localCfg = loadLocalConfig(p)
    if localCfg.ignore: continue

    var kinds = if p == homeDir: {} else: detectProjectKinds(p)
    if localCfg.typeOverride.len > 0:
      kinds = {}
      for part in localCfg.typeOverride.splitWhitespace():
        for kind in ProjectKind:
          if $kind == part: kinds.incl kind
    let hasExtraTargets = localCfg.extraClean.len > 0 or localCfg.extraAll.len > 0
    if hasExtraTargets and kinds == {}:
      kinds.incl pkCustom

    if kinds != {}:
      # Root path is a project — scan full subtree directly
      let rootResult = scanSubtree(@[(p, 0, "", initialSkip, false)],
                                   level, effectiveDepth, noSkip, prune, homeDir,
                                   onProgress)
      for proj in rootResult.projects: result.projects.add proj
      for d in rootResult.emptyDirs: result.emptyDirs.add d
      for e in rootResult.errors: result.errors.add e
      for k, v in rootResult.dirInfo: result.dirInfo[k] = v
      if onProgress != nil: onProgress(rootResult.scanned)
    else:
      # Root path is not a project — collect children as work items
      let skipHere = resolveSkipSet(localCfg, initialSkip)
      let childForceRoot = localCfg.root == "children"
      try:
        for (kind, path) in walkDir(p):
          if kind != pcDir: continue
          if path.extractFilename in skipHere: continue
          topLevelWork.add (path, 1, "", skipHere, childForceRoot)
      except OSError:
        result.errors.add "Cannot read: " & p
      if prune:
        var hasEntries = false
        try:
          for entry in walkDir(p):
            hasEntries = true
            break
        except OSError: discard
        if not hasEntries:
          result.emptyDirs.add p

  # Expand work items for better parallel distribution
  # If we have few top-level items, go one level deeper for non-project dirs
  if numThreads > 1:
    var expandRound = 0
    while topLevelWork.len < numThreads * 4 and expandRound < 3:
      inc expandRound
      var expanded: seq[DirEntry]
      var didExpand = false
      for entry in topLevelWork:
        let cfg = loadLocalConfig(entry.path)
        if cfg.ignore:
          continue
        let kinds = if entry.path == homeDir: {} else: detectProjectKinds(entry.path)
        if kinds != {} or (cfg.extraClean.len > 0 or cfg.extraAll.len > 0):
          expanded.add entry  # keep projects as-is
        else:
          # Not a project — add its children instead
          let skip = resolveSkipSet(cfg, entry.skipSet)
          let force = cfg.root == "children"
          var hasFiles = false
          var childDirs = 0
          var hasEntries = false
          try:
            for (kind, path) in walkDir(entry.path):
              hasEntries = true
              if kind != pcDir:
                hasFiles = true
                continue
              childDirs += 1
              if path.extractFilename in skip: continue
              expanded.add (path, entry.depth + 1, entry.rootProject, skip, force or entry.forceRoot)
              didExpand = true
          except OSError: discard
          if prune:
            if not hasEntries:
              result.emptyDirs.add entry.path
            else:
              result.dirInfo[entry.path] = (hasFiles, childDirs)
      if not didExpand: break
      topLevelWork = expanded

  # Step 2: Process top-level work items
  if topLevelWork.len > 0:
    if numThreads <= 1 or topLevelWork.len <= 1:
      # Single-threaded
      let sub = scanSubtree(topLevelWork, level, effectiveDepth, noSkip, prune, homeDir,
                            onProgress)
      for proj in sub.projects: result.projects.add proj
      for d in sub.emptyDirs: result.emptyDirs.add d
      for e in sub.errors: result.errors.add e
      for k, v in sub.dirInfo: result.dirInfo[k] = v
      if onProgress != nil: onProgress(sub.scanned)
    else:
      # Multi-threaded: work-stealing — each worker picks dirs one at a time
      if onProgress != nil:
        onProgress(0)
      let workerCount = min(numThreads, topLevelWork.len)
      var ch = newChan[SubtreeResult](workerCount)
      var nextTask: Atomic[int]
      nextTask.store(0)

      var scanThreads = newSeq[Thread[ScanWorkerArg]](workerCount)
      for i in 0 ..< workerCount:
        createThread(scanThreads[i], scanWorker, ScanWorkerArg(
          work: addr topLevelWork,
          nextTask: addr nextTask,
          level: level,
          effectiveDepth: effectiveDepth,
          noSkip: noSkip,
          prune: prune,
          homeDir: homeDir,
          ch: addr ch,
        ))

      # Collect results
      var totalScanned = 0
      for i in 0 ..< workerCount:
        var sub = ch.recv()
        for proj in sub.projects: result.projects.add proj
        for d in sub.emptyDirs: result.emptyDirs.add d
        for e in sub.errors: result.errors.add e
        for k, v in sub.dirInfo: result.dirInfo[k] = v
        totalScanned += sub.scanned
        if onProgress != nil:
          onProgress(totalScanned)

      for i in 0 ..< workerCount:
        joinThread(scanThreads[i])

      if onProgress != nil: onProgress(totalScanned)

  # Phase 2: Compute sizes in parallel
  computeSizesParallel(result.projects, numThreads)

  # Phase 3: Bottom-up empty dir rollup (in-memory, no filesystem calls)
  if prune and result.emptyDirs.len > 0:
    let allDirInfo = result.dirInfo

    var emptySet = result.emptyDirs.toHashSet
    var changed = true
    while changed:
      changed = false
      var emptyChildCount: Table[string, int]
      for d in emptySet:
        let parent = d.parentDir
        emptyChildCount[parent] = emptyChildCount.getOrDefault(parent) + 1
      for parent, count in emptyChildCount:
        if parent in emptySet: continue
        if parent in allDirInfo:
          let info = allDirInfo[parent]
          if not info.hasFiles and count >= info.childDirs:
            emptySet.incl parent
            changed = true
    result.emptyDirs = @[]
    for d in emptySet:
      result.emptyDirs.add d
