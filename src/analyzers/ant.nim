import std/[os, xmlparser, xmltree]
import ../types

proc analyzeAnt*(dir: string): AnalyzeResult =
  let buildXmlPath = dir / "build.xml"
  if not fileExists(buildXmlPath):
    return

  var buildDir = "build"
  var distDir = "dist"

  try:
    let xml = loadXml(buildXmlPath)

    # Look for property definitions that set build/dist directories
    for node in xml:
      if node.kind != xnElement or node.tag != "property":
        continue
      let name = node.attr("name")
      let value = node.attr("value")
      if value.len == 0:
        continue
      case name
      of "build.dir", "build", "builddir", "build-dir":
        buildDir = value
      of "dist.dir", "dist", "distdir", "dist-dir":
        distDir = value
  except:
    discard

  if dirExists(dir / buildDir):
    result.cleanTargets.add buildDir
  if dirExists(dir / distDir):
    result.cleanTargets.add distDir

  result.skipDirs.add "src"
  result.skipDirs.add "lib"
  result.skipDirs.add "web"
