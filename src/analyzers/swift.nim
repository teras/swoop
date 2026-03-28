import std/os
import ../types

proc analyzeSwift*(dir: string): AnalyzeResult =
  # Swift Package Manager build directory
  if dirExists(dir / ".build"):
    result.cleanTargets.add ".build"

  result.skipDirs.add "Sources"
  result.skipDirs.add "Tests"
