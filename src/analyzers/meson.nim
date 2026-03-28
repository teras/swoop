import std/[os, strutils]
import ../types

proc analyzeMeson*(dir: string): AnalyzeResult =
  # Scan for build directories containing build.ninja (Meson's output)
  for (kind, path) in walkDir(dir):
    if kind != pcDir: continue
    let name = path.extractFilename
    if fileExists(path / "build.ninja") and fileExists(path / "meson-info" / "intro-buildoptions.json"):
      result.cleanTargets.add name

  result.skipDirs.add "src"
  result.skipDirs.add "include"
  result.skipDirs.add "test"
  result.skipDirs.add "subprojects"
