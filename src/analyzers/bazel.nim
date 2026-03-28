import std/[os, strutils]
import ../types

proc analyzeBazel*(dir: string): AnalyzeResult =
  # bazel-* symlinks/directories in project root
  for (kind, path) in walkDir(dir):
    if kind != pcDir and kind != pcLinkToDir: continue
    let name = path.extractFilename
    if name.startsWith("bazel-"):
      result.cleanTargets.add name

  result.skipDirs.add "src"
  result.skipDirs.add "java"
  result.skipDirs.add "javatests"
  result.skipDirs.add "proto"
