import std/[os, sets]
import parsetoml
import types

const
  LocalConfigFile* = ".swoop.toml"

  DefaultLocalConfigContent* = """# Swoop - Per-project configuration
# Place this file as .swoop.toml in any directory

# Skip this project entirely
# ignore = false

# Break from parent — this is a new root project
# root = false

# Override/extend detected types (space-separated)
# Supported: gradle, maven, cargo, nim, node, python, cmake, ant, makefile, hugo
# type = "gradle maven"

# Additional targets to clean, relative to this directory (local only)
# extra_clean = ["generated/", "custom-output/"]

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
    result.root = toml["root"].getBool()
  if toml.hasKey("type"):
    result.typeOverride = toml["type"].getStr()
  if toml.hasKey("extra_clean"):
    for item in toml["extra_clean"].getElems():
      result.extraClean.add item.getStr()
  if toml.hasKey("keep"):
    for item in toml["keep"].getElems():
      result.keep.add item.getStr()
  if toml.hasKey("skip_scan"):
    for item in toml["skip_scan"].getElems():
      result.skipScan.add item.getStr()
  if toml.hasKey("traverse_scan"):
    for item in toml["traverse_scan"].getElems():
      result.traverseScan.add item.getStr()
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
