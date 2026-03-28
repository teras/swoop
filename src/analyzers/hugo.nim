import std/os
import ../types

proc analyzeHugo*(dir: string): AnalyzeResult =
  # Clean: generated output
  if dirExists(dir / "public"):
    result.cleanTargets.add "public"

  # resources/_gen is Hugo's processed assets cache
  if dirExists(dir / "resources" / "_gen"):
    result.cleanTargets.add "resources/_gen"

  # Positive dirs (don't enter)
  for d in ["content", "static", "layouts", "themes", "archetypes", "data", "i18n", "assets"]:
    result.skipDirs.add d
