import std/[os, strutils]
import regex
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
      var m: RegexMatch2
      if content.find(re2"""bin\s*=\s*@\[([^\]]+)\]""", m):
        for entry in content[m.group(0)].split(','):
          let name = entry.strip().strip(chars = {'"', '\''})
          if name.len > 0:
            result.bins.add name
      if content.find(re2"""srcDir\s*=\s*["']([^"']+)["']""", m):
        result.srcDir = content[m.group(0)]
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
