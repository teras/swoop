type
  ProjectKind* = enum
    pkAnt = "ant"
    pkBazel = "bazel"
    pkBundler = "bundler"
    pkCargo = "cargo"
    pkCMake = "cmake"
    pkComposer = "composer"
    pkDart = "dart"
    pkDotnet = "dotnet"
    pkElixir = "elixir"
    pkGo = "go"
    pkGodot = "godot"
    pkGradle = "gradle"
    pkHaskell = "haskell"
    pkHugo = "hugo"
    pkJekyll = "jekyll"
    pkMakefile = "makefile"
    pkMaven = "maven"
    pkMeson = "meson"
    pkNim = "nim"
    pkNode = "node"
    pkPython = "python"
    pkSbt = "sbt"
    pkSwift = "swift"
    pkUnity = "unity"
    pkZig = "zig"

  CleanLevel* = enum
    clClean
    clDistclean

  CleanEntry* = object
    path*: string
    size*: int64
    isDir*: bool

  AnalyzeResult* = object
    cleanTargets*: seq[string]
    distcleanTargets*: seq[string]
    skipDirs*: seq[string]

  ProjectInfo* = object
    path*: string
    kinds*: set[ProjectKind]
    entries*: seq[CleanEntry]
    totalSize*: int64
    hasLocalConfig*: bool
    isRoot*: bool
    error*: string

  LocalConfig* = object
    ignore*: bool
    root*: bool
    typeOverride*: string
    extraClean*: seq[string]
    keep*: seq[string]
    skipScan*: seq[string]     # extra dirs to skip scanning
    traverseScan*: seq[string] # undo global_skip for this project
    maxDepth*: int             # 0 = inherit

  ScanResult* = object
    projects*: seq[ProjectInfo]
    errors*: seq[string]

const
  DefaultGlobalSkip* = [".git", ".idea", ".vscode", ".svn", ".hg"]
