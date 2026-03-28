import std/[os, strutils, xmlparser, xmltree]
import ../types

proc analyzeDotnet*(dir: string): AnalyzeResult =
  var outputPath = "bin"
  var intermediatePath = "obj"

  # Try to read custom paths from first .csproj found
  for (kind, path) in walkDir(dir):
    if kind != pcFile: continue
    if not path.endsWith(".csproj"): continue
    try:
      let xml = loadXml(path)
      for pg in xml.findAll("PropertyGroup"):
        let outNode = pg.child("OutputPath")
        if outNode != nil and outNode.innerText.len > 0:
          outputPath = outNode.innerText.strip().split({'/', '\\'})[0]
        let intNode = pg.child("BaseIntermediateOutputPath")
        if intNode != nil and intNode.innerText.len > 0:
          intermediatePath = intNode.innerText.strip().split({'/', '\\'})[0]
    except:
      discard
    break

  if dirExists(dir / outputPath):
    result.cleanTargets.add outputPath
  if dirExists(dir / intermediatePath):
    result.cleanTargets.add intermediatePath

  # packages/ for older NuGet restore
  if dirExists(dir / "packages"):
    result.distcleanTargets.add "packages"

  result.skipDirs.add "Properties"
  result.skipDirs.add "wwwroot"
