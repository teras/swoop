import std/[os, sets, strutils]
import parsetoml
import types

const
  LocalConfigFile* = ".swoop.toml"

  DefaultLocalConfigContent* = """# Swoop - Per-project configuration
# Place this file as .swoop.toml in any directory

# Skip this project entirely
# ignore = false

# Break aggregation: "self" = this is a root, "children" = each child is a root
# root = "self"

# Override/extend detected types (space-separated)
# Supported: ant, bazel, bundler, cargo, cmake, composer, custom, dart, dotnet, elixir,
#            flatpak, go, godot, gradle, haskell, hugo, jekyll, makefile, maven,
#            meson, nim, node, python, sbt, swift, unity, zig
# type = "gradle maven"

# Additional targets to clean, relative to this directory (local only)
# extra_clean = ["generated/", "custom-output/"]

# Additional targets to clean only with --all (deps/caches)
# extra_all = ["build", "venv"]

# Targets to keep even if matched for cleaning
# keep = ["build/resources/"]

# Directories to skip scanning (don't descend into)
# skip_scan = ["vendor/", "third-party/"]

# Directories to traverse even if skipped (by built-in list or parent config)
# (overrides: .git, .idea, .vscode, .svn, .hg, and parent skip_scan entries)
# traverse_scan = [".idea"]

# Max scan depth from this point (0 = unlimited)
# max_depth = 0
"""

proc createLocalConfig*(path: string): bool =
  if path == "-":
    echo DefaultLocalConfigContent
    return true
  let target = if dirExists(path): path / LocalConfigFile else: path
  if fileExists(target):
    stderr.writeLine "Error: file already exists: " & target
    return false
  let dir = parentDir(target)
  if not dirExists(dir):
    stderr.writeLine "Error: directory does not exist: " & dir
    return false
  writeFile(target, DefaultLocalConfigContent)
  echo "Created " & target
  return true

proc loadLocalConfig*(projectDir: string): LocalConfig =
  let path = projectDir / LocalConfigFile
  if not fileExists(path):
    return
  let toml = parsetoml.parseFile(path)

  if toml.hasKey("ignore"):
    result.ignore = toml["ignore"].getBool()
  if toml.hasKey("root"):
    result.root = toml["root"].getStr()
  if toml.hasKey("type"):
    result.typeOverride = toml["type"].getStr()
  template readStringOrArray(key: string, target: var seq[string]) =
    if toml.hasKey(key):
      let val = toml[key]
      if val.kind == String:
        target.add val.getStr()
      else:
        for item in val.getElems():
          target.add item.getStr()

  readStringOrArray("extra_clean", result.extraClean)
  readStringOrArray("extra_all", result.extraAll)
  readStringOrArray("keep", result.keep)
  readStringOrArray("skip_scan", result.skipScan)
  readStringOrArray("traverse_scan", result.traverseScan)
  if toml.hasKey("max_depth"):
    result.maxDepth = toml["max_depth"].getInt().int

proc resolveSkipSet*(localCfg: LocalConfig, inherited: HashSet[string]): HashSet[string] =
  ## Compute effective skip set from inherited parent set.
  ## traverse_scan removes from inherited, skip_scan adds to it.
  result = inherited
  # traverse_scan removes from skip
  for t in localCfg.traverseScan:
    result.excl t
  # skip_scan adds to skip
  for s in localCfg.skipScan:
    result.incl s

proc buildAncestorSkipSet*(path: string): HashSet[string] =
  ## Walk from root down to path, accumulating skip sets from .swoop.toml files.
  result = DefaultGlobalSkip.toHashSet
  let parts = path.normalizedPath.split('/')
  var current = ""
  for i in 0 ..< parts.len:
    current = if current.len == 0: parts[i] else: current / parts[i]
    if current.len == 0: current = "/"
    result = resolveSkipSet(loadLocalConfig(current), result)
