import std/os
import ../types

proc analyzeGo*(dir: string): AnalyzeResult =
  # Go binaries end up in project root or custom output dir
  # No standard build output directory to clean

  # Distclean: vendor/ contains downloaded dependencies
  if dirExists(dir / "vendor"):
    result.distcleanTargets.add "vendor"

  result.skipDirs.add "cmd"
  result.skipDirs.add "internal"
  result.skipDirs.add "pkg"
  result.skipDirs.add "api"
  result.skipDirs.add "docs"
