import std/[os, strutils]
import regex
import ../types

proc sanitizeUtf8(s: string): string =
  result = newStringOfCap(s.len)
  var i = 0
  while i < s.len:
    let c = s[i].uint8
    if c < 0x80:
      result.add s[i]; inc i
    elif c < 0xC0:
      result.add '?'; inc i
    elif c < 0xE0:
      if i + 1 < s.len and (s[i+1].uint8 and 0xC0) == 0x80:
        result.add s[i]; result.add s[i+1]; i += 2
      else: result.add '?'; inc i
    elif c < 0xF0:
      if i + 2 < s.len and (s[i+1].uint8 and 0xC0) == 0x80 and (s[i+2].uint8 and 0xC0) == 0x80:
        result.add s[i]; result.add s[i+1]; result.add s[i+2]; i += 3
      else: result.add '?'; inc i
    elif c < 0xF8:
      if i + 3 < s.len and (s[i+1].uint8 and 0xC0) == 0x80 and (s[i+2].uint8 and 0xC0) == 0x80 and (s[i+3].uint8 and 0xC0) == 0x80:
        result.add s[i]; result.add s[i+1]; result.add s[i+2]; result.add s[i+3]; i += 4
      else: result.add '?'; inc i
    else:
      result.add '?'; inc i

proc parseIncludeVars(dir: string, makefile: string): seq[tuple[key, value: string]] =
  ## Parse variables from included files (e.g. config.mk).
  try:
    let content = sanitizeUtf8(readFile(dir / makefile))
    for line in content.splitLines():
      var m: RegexMatch2
      if line.find(re2"^-?include\s+(\S+)", m):
        let incPath = dir / line[m.group(0)]
        if fileExists(incPath):
          for incLine in lines(incPath):
            let stripped = incLine.strip()
            if stripped.len == 0 or stripped.startsWith("#"): continue
            var vm: RegexMatch2
            if stripped.find(re2"^([A-Za-z_][A-Za-z0-9_]*)\s*[:?]?=\s*(.*)", vm):
              result.add (stripped[vm.group(0)].strip(), stripped[vm.group(1)].strip())
  except:
    discard

proc parseMakefileTarget(dir: string, target: string,
                         vars: seq[tuple[key, value: string]]): seq[string] =
  let path = dir / "Makefile"
  if not fileExists(path):
    return
  try:
    let content = sanitizeUtf8(readFile(path))
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
          var m: RegexMatch2
          if rmLine.find(re2"^[@\-]?rm\s+(-[rfRF]+\s+)*", m):
            rmLine = rmLine[m.boundaries.b + 1 .. ^1]
          for part in rmLine.splitWhitespace():
            var resolved = part
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
