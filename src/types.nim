type
  ProjectKind* = enum
    pkGradle = "gradle"
    pkMaven = "maven"
    pkCargo = "cargo"
    pkNim = "nim"
    pkNode = "node"
    pkPython = "python"
    pkCMake = "cmake"
    pkAnt = "ant"
    pkMakefile = "makefile"
    pkHugo = "hugo"

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
