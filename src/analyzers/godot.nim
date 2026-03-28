import std/os
import ../types

proc analyzeGodot*(dir: string): AnalyzeResult =
  # .godot/ is the main cache (Godot 4+)
  if dirExists(dir / ".godot"):
    result.cleanTargets.add ".godot"

  # .import/ is the asset import cache (Godot 3)
  if dirExists(dir / ".import"):
    result.cleanTargets.add ".import"

  result.skipDirs.add "addons"
  result.skipDirs.add "scenes"
  result.skipDirs.add "scripts"
  result.skipDirs.add "assets"
