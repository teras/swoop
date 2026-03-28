import std/[os, strutils, re]
import ../types

proc parseIncludeVars(dir: string, makefile: string): seq[tuple[key, value: string]] =
  ## Parse variables from included files (e.g. config.mk).
  try:
    let content = readFile(dir / makefile)
    for line in content.splitLines():
      # Look for: include config.mk
      var m: array[1, string]
      if line.match(re"^-?include\s+(\S+)", m):
        let incPath = dir / m[0]
        if fileExists(incPath):
          for incLine in lines(incPath):
            let stripped = incLine.strip()
            if stripped.len == 0 or stripped.startsWith("#"): continue
            var vm: array[2, string]
            if stripped.match(re"^([A-Za-z_][A-Za-z0-9_]*)\s*[:?]?=\s*(.*)", vm):
              result.add (vm[0].strip(), vm[1].strip())
  except:
    discard

proc parseMakefileTarget(dir: string, target: string,
                         vars: seq[tuple[key, value: string]]): seq[string] =
  let path = dir / "Makefile"
  if not fileExists(path):
    return
  try:
    let content = readFile(path)
    var inTarget = false
    for line in content.splitLines():
      if line.startsWith(target & ":"):
        inTarget = true
        continue
      if inTarget:
        let stripped = line.strip()
        if stripped.len == 0 or (not line.startsWith("\t") and not line.startsWith("  ")):
          break
        var rmLine = stripped
        if rmLine.startsWith("rm ") or rmLine.startsWith("-rm ") or rmLine.startsWith("@rm "):
          let isRecursive = "-r" in rmLine or "-rf" in rmLine or "-fR" in rmLine or "-fr" in rmLine
          rmLine = rmLine.replace(re"^[@-]?rm\s+(-[rfRF]+\s+)*", "")
          for part in rmLine.splitWhitespace():
            var resolved = part
            # Resolve variables from includes
            for (key, value) in vars:
              resolved = resolved.replace("${" & key & "}", value)
              resolved = resolved.replace("$(" & key & ")", value)
            if '$' in resolved: continue
            if '*' in resolved: continue
            if ".." in resolved: continue
            if resolved.len == 0: continue
            let fullPath = dir / resolved
            if isRecursive and dirExists(fullPath):
              result.add resolved
  except:
    discard

proc analyzeMakefile*(dir: string): AnalyzeResult =
  let vars = parseIncludeVars(dir, "Makefile")

  let cleanTargets = parseMakefileTarget(dir, "clean", vars)
  for t in cleanTargets:
    result.cleanTargets.add t

  let distcleanTargets = parseMakefileTarget(dir, "distclean", vars)
  for t in distcleanTargets:
    if t notin result.cleanTargets:
      result.distcleanTargets.add t
