import std/[os, strutils]
import ../types

proc analyzeCMake*(dir: string): AnalyzeResult =
  # Scan one level deep for dirs containing CMakeCache.txt
  for (kind, path) in walkDir(dir):
    if kind != pcDir and kind != pcLinkToDir:
      continue
    let name = path.extractFilename
    if fileExists(path / "CMakeCache.txt"):
      result.cleanTargets.add name

  # CLion convention: cmake-build-*
  for (kind, path) in walkDir(dir):
    if kind != pcDir:
      continue
    let name = path.extractFilename
    if name.startsWith("cmake-build-"):
      if name notin result.cleanTargets:
        result.cleanTargets.add name

  # CMakeFiles/ is always created in-source during configure
  if dirExists(dir / "CMakeFiles"):
    result.cleanTargets.add "CMakeFiles"

  result.skipDirs.add "src"
  result.skipDirs.add "include"
  result.skipDirs.add "cmake"
