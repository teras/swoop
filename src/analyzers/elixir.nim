import std/os
import ../types

proc analyzeElixir*(dir: string): AnalyzeResult =
  if dirExists(dir / "_build"):
    result.cleanTargets.add "_build"

  # deps/ contains downloaded dependencies
  if dirExists(dir / "deps"):
    result.distcleanTargets.add "deps"

  result.skipDirs.add "lib"
  result.skipDirs.add "test"
  result.skipDirs.add "config"
  result.skipDirs.add "priv"
