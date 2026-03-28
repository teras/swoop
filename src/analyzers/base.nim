import ../types
import maven, gradle, cargo, nim_proj, node, python, cmake, ant, makefile, hugo

proc analyze*(dir: string, kind: ProjectKind): AnalyzeResult =
  case kind
  of pkMaven: analyzeMaven(dir)
  of pkGradle: analyzeGradle(dir)
  of pkCargo: analyzeCargo(dir)
  of pkNim: analyzeNim(dir)
  of pkNode: analyzeNode(dir)
  of pkPython: analyzePython(dir)
  of pkCMake: analyzeCMake(dir)
  of pkAnt: analyzeAnt(dir)
  of pkMakefile: analyzeMakefile(dir)
  of pkHugo: analyzeHugo(dir)

proc mergeResults*(results: seq[AnalyzeResult]): AnalyzeResult =
  for r in results:
    for d in r.cleanTargets:
      if d notin result.cleanTargets:
        result.cleanTargets.add d
    for d in r.distcleanTargets:
      if d notin result.distcleanTargets:
        result.distcleanTargets.add d
    for d in r.skipDirs:
      if d notin result.skipDirs:
        result.skipDirs.add d
