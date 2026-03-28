import std/[os, strutils, re]
import ../types

type NimbleInfo = object
  bins: seq[string]
  srcDir: string

proc parseNimbleFile(dir: string): NimbleInfo =
  for (kind, path) in walkDir(dir):
    if kind != pcFile: continue
    if not path.extractFilename.endsWith(".nimble"): continue
    try:
      let content = readFile(path)
      var m: array[1, string]
      if content.find(re"""bin\s*=\s*@\[([^\]]+)\]""", m) >= 0:
        for entry in m[0].split(','):
          let name = entry.strip().strip(chars = {'"', '\''})
          if name.len > 0:
            result.bins.add name
      if content.find(re"""srcDir\s*=\s*["']([^"']+)["']""", m) >= 0:
        result.srcDir = m[0]
    except:
      discard
    break

proc analyzeNim*(dir: string): AnalyzeResult =
  for d in ["nimcache", "nimblecache", "htmldocs"]:
    if dirExists(dir / d):
      result.cleanTargets.add d
  if dirExists(dir / "nimbledeps"):
    result.distcleanTargets.add "nimbledeps"

  let info = parseNimbleFile(dir)
  for bin in info.bins:
    if fileExists(dir / bin):
      result.cleanTargets.add bin

  if info.srcDir.len > 0:
    result.skipDirs.add info.srcDir
  else:
    result.skipDirs.add "src"
  result.skipDirs.add "tests"
