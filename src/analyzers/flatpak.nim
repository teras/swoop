import std/[os, strutils]
import ../types

proc analyzeFlatpak*(dir: string): AnalyzeResult =
  result.distcleanTargets.add ".flatpak-builder"

  # Find build output dirs by checking for flatpak metadata format
  for (kind, path) in walkDir(dir):
    if kind != pcDir: continue
    let name = path.extractFilename
    if name == ".flatpak-builder": continue
    let metaPath = path / "metadata"
    if dirExists(path / "files") and fileExists(metaPath):
      try:
        let content = readFile(metaPath)
        if "\n[Application]\n" in content or content.startsWith("[Application]\n") or
           "\n[Runtime]\n" in content or content.startsWith("[Runtime]\n"):
          result.cleanTargets.add name
      except:
        discard
