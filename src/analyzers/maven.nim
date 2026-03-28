import std/[os, xmlparser, xmltree, strutils]
import ../types

proc analyzeMaven*(dir: string): AnalyzeResult =
  let pomPath = dir / "pom.xml"
  if not fileExists(pomPath):
    return

  try:
    let xml = loadXml(pomPath)

    # Find build directory (default: target)
    var buildDir = "target"
    let buildNode = xml.child("build")
    if buildNode != nil:
      let dirNode = buildNode.child("directory")
      if dirNode != nil and dirNode.innerText.len > 0:
        buildDir = dirNode.innerText.strip()

    result.cleanTargets.add buildDir

    # Source directory (positive — don't enter)
    var srcDir = "src"
    let srcNode = if buildNode != nil: buildNode.child("sourceDirectory") else: nil
    if srcNode != nil and srcNode.innerText.len > 0:
      srcDir = srcNode.innerText.strip()
    result.skipDirs.add srcDir

    # .mvn directory
    result.skipDirs.add ".mvn"

  except:
    # If XML parsing fails, fall back to defaults
    result.cleanTargets.add "target"
