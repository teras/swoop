import std/os
import ../types

proc analyzeSbt*(dir: string): AnalyzeResult =
  if dirExists(dir / "target"):
    result.cleanTargets.add "target"

  # project/target/ contains sbt's own build cache
  if dirExists(dir / "project" / "target"):
    result.cleanTargets.add "project/target"

  # .bsp/ is Build Server Protocol metadata
  if dirExists(dir / ".bsp"):
    result.distcleanTargets.add ".bsp"

  result.skipDirs.add "src"
  result.skipDirs.add "project"
