import std/[os, strutils]
import ../types

proc analyzeCMake*(dir: string): AnalyzeResult =
  for (kind, path) in walkDir(dir):
    if kind != pcDir and kind != pcLinkToDir: continue
    let name = path.extractFilename
    if name == "CMakeFiles" or
       fileExists(path / "CMakeCache.txt") or
       name.startsWith("cmake-build-"):
      if name notin result.cleanTargets:
        result.cleanTargets.add name

  result.skipDirs.add "src"
  result.skipDirs.add "include"
  result.skipDirs.add "cmake"
