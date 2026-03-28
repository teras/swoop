import std/[os, strutils]
import ../types

proc analyzeJekyll*(dir: string): AnalyzeResult =
  var destination = "_site"

  # Read custom destination from _config.yml
  for cfgName in ["_config.yml", "_config.yaml"]:
    if fileExists(dir / cfgName):
      try:
        for line in lines(dir / cfgName):
          let stripped = line.strip()
          if stripped.startsWith("destination:"):
            let val = stripped["destination:".len .. ^1].strip().strip(chars = {'"', '\''})
            if val.len > 0:
              destination = val
            break
      except:
        discard
      break

  if dirExists(dir / destination):
    result.cleanTargets.add destination

  if dirExists(dir / ".jekyll-cache"):
    result.cleanTargets.add ".jekyll-cache"

  if dirExists(dir / ".sass-cache"):
    result.cleanTargets.add ".sass-cache"

  result.skipDirs.add "_posts"
  result.skipDirs.add "_layouts"
  result.skipDirs.add "_includes"
  result.skipDirs.add "_data"
  result.skipDirs.add "_drafts"
  result.skipDirs.add "assets"
