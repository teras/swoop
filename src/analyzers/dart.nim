import std/os
import ../types

proc analyzeDart*(dir: string): AnalyzeResult =
  if dirExists(dir / ".dart_tool"):
    result.cleanTargets.add ".dart_tool"
  if dirExists(dir / "build"):
    result.cleanTargets.add "build"

  # .packages is deprecated but may still exist
  if fileExists(dir / ".packages"):
    result.cleanTargets.add ".packages"

  result.skipDirs.add "lib"
  result.skipDirs.add "test"
  result.skipDirs.add "android"
  result.skipDirs.add "ios"
  result.skipDirs.add "web"
  result.skipDirs.add "linux"
  result.skipDirs.add "macos"
  result.skipDirs.add "windows"
