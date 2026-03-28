import std/os
import parsetoml
import ../types

proc analyzeCargo*(dir: string): AnalyzeResult =
  let cargoPath = dir / "Cargo.toml"
  if not fileExists(cargoPath):
    return

  var targetDir = "target"

  try:
    let toml = parsetoml.parseFile(cargoPath)
    if toml.hasKey("build") and toml["build"].hasKey("target-dir"):
      targetDir = toml["build"]["target-dir"].getStr()
  except:
    discard

  try:
    let configPath = dir / ".cargo" / "config.toml"
    if fileExists(configPath):
      let cfg = parsetoml.parseFile(configPath)
      if cfg.hasKey("build") and cfg["build"].hasKey("target-dir"):
        targetDir = cfg["build"]["target-dir"].getStr()
  except:
    discard

  result.cleanTargets.add targetDir

  result.skipDirs.add "src"
  result.skipDirs.add ".cargo"
  result.skipDirs.add "benches"
  result.skipDirs.add "examples"
