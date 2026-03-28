import std/[os, re]
import ../types

proc parseBuildDir(dir: string): string =
  for name in ["build.gradle.kts", "build.gradle"]:
    let path = dir / name
    if not fileExists(path):
      continue
    try:
      let content = readFile(path)
      var m: array[1, string]
      if content.find(re"""layout\s*\.\s*buildDirectory\s*\.\s*set\s*\(\s*file\s*\(\s*["']([^"']+)["']""", m) >= 0:
        return m[0]
      if content.find(re"""buildDir\s*=\s*(?:file\s*\(\s*)?["']([^"']+)["']""", m) >= 0:
        return m[0]
    except:
      discard
  return ""

proc analyzeGradle*(dir: string): AnalyzeResult =
  let customBuildDir = parseBuildDir(dir)
  if customBuildDir.len > 0:
    result.cleanTargets.add customBuildDir
  else:
    result.cleanTargets.add "build"

  result.distcleanTargets.add ".gradle"

  result.skipDirs.add "src"
  result.skipDirs.add "gradle"
