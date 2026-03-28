import std/os
import ../types

proc analyzeUnity*(dir: string): AnalyzeResult =
  # Library/ is the main cache — can be huge (GBs)
  if dirExists(dir / "Library"):
    result.cleanTargets.add "Library"

  if dirExists(dir / "Temp"):
    result.cleanTargets.add "Temp"

  if dirExists(dir / "Obj"):
    result.cleanTargets.add "Obj"

  if dirExists(dir / "Logs"):
    result.cleanTargets.add "Logs"

  result.skipDirs.add "Assets"
  result.skipDirs.add "Packages"
  result.skipDirs.add "ProjectSettings"
  result.skipDirs.add "UserSettings"
