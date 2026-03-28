import std/os
import ../types

proc analyzeBundler*(dir: string): AnalyzeResult =
  if dirExists(dir / "vendor" / "bundle"):
    result.distcleanTargets.add "vendor/bundle"

  if dirExists(dir / ".bundle"):
    result.distcleanTargets.add ".bundle"

  result.skipDirs.add "app"
  result.skipDirs.add "lib"
  result.skipDirs.add "spec"
  result.skipDirs.add "test"
  result.skipDirs.add "config"
