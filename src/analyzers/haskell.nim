import std/[os, strutils]
import ../types

proc analyzeHaskell*(dir: string): AnalyzeResult =
  var workDir = ".stack-work"

  # Read custom work-dir from stack.yaml
  if fileExists(dir / "stack.yaml"):
    try:
      for line in lines(dir / "stack.yaml"):
        let stripped = line.strip()
        if stripped.startsWith("work-dir:"):
          let val = stripped["work-dir:".len .. ^1].strip().strip(chars = {'"', '\''})
          if val.len > 0:
            workDir = val
          break
    except:
      discard

  if dirExists(dir / workDir):
    result.cleanTargets.add workDir

  # Cabal new-style build directory
  if dirExists(dir / "dist-newstyle"):
    result.cleanTargets.add "dist-newstyle"

  # Old-style cabal build directory
  if dirExists(dir / "dist"):
    result.cleanTargets.add "dist"

  result.skipDirs.add "src"
  result.skipDirs.add "app"
  result.skipDirs.add "lib"
  result.skipDirs.add "test"
