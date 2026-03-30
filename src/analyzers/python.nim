import std/[os, strutils]
import ../types

proc analyzePython*(dir: string): AnalyzeResult =
  # Clean level: build artifacts
  for d in ["build", "dist"]:
    if dirExists(dir / d):
      result.cleanTargets.add d

  # __pycache__ can be anywhere — we check top-level presence
  if dirExists(dir / "__pycache__"):
    result.cleanTargets.add "__pycache__"

  # *.egg-info directories
  for (kind, path) in walkDir(dir):
    if kind == pcDir and path.extractFilename.endsWith(".egg-info"):
      result.cleanTargets.add path.extractFilename

  # Distclean: virtual environments and tool caches
  for d in [".venv", "venv"]:
    if dirExists(dir / d):
      result.distcleanTargets.add d

  for d in [".mypy_cache", ".pytest_cache", ".ruff_cache", ".tox", "htmlcov"]:
    if dirExists(dir / d):
      result.distcleanTargets.add d

  result.skipDirs.add "src"
  result.skipDirs.add "tests"
  result.skipDirs.add "docs"
