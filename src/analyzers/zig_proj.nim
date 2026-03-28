import std/os
import ../types

proc analyzeZig*(dir: string): AnalyzeResult =
  if dirExists(dir / "zig-cache"):
    result.cleanTargets.add "zig-cache"

  if dirExists(dir / ".zig-cache"):
    result.cleanTargets.add ".zig-cache"

  if dirExists(dir / "zig-out"):
    result.cleanTargets.add "zig-out"

  result.skipDirs.add "src"
