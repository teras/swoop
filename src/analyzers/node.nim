import std/[os, json]
import ../types

proc analyzeNode*(dir: string): AnalyzeResult =
  let pkgPath = dir / "package.json"
  if not fileExists(pkgPath):
    return

  try:
    let js = parseFile(pkgPath)

    # Framework detection from dependencies
    var deps: seq[string]
    for section in ["dependencies", "devDependencies"]:
      if js.hasKey(section) and js[section].kind == JObject:
        for key in js[section].keys:
          deps.add key

    # Framework-specific build output
    if "next" in deps:
      result.cleanTargets.add ".next"
    if "nuxt" in deps or "@nuxt/core" in deps:
      result.cleanTargets.add ".nuxt"
    if "vite" in deps or "vue" in deps or "react-scripts" in deps:
      if dirExists(dir / "dist"):
        result.cleanTargets.add "dist"
    if "gatsby" in deps:
      result.cleanTargets.add ".cache"
      result.cleanTargets.add "public"  # Gatsby generates this

    # distclean: node_modules
    result.distcleanTargets.add "node_modules"

  except:
    result.distcleanTargets.add "node_modules"

  # Positive dirs
  result.skipDirs.add "src"
  result.skipDirs.add "public"
  result.skipDirs.add "assets"
