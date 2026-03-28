import std/os
import ../types

proc analyzeComposer*(dir: string): AnalyzeResult =
  if dirExists(dir / "vendor"):
    result.distcleanTargets.add "vendor"

  result.skipDirs.add "src"
  result.skipDirs.add "app"
  result.skipDirs.add "public"
  result.skipDirs.add "resources"
  result.skipDirs.add "tests"
  result.skipDirs.add "config"
