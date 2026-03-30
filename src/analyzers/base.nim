import ../types
import ant, bazel, bundler, cargo, cmake, composer, dart, dotnet
import elixir, flatpak, go_proj, godot, gradle, haskell, hugo, jekyll, makefile
import maven, meson, nim_proj, node, python, sbt, swift, unity, zig_proj

proc analyze*(dir: string, kind: ProjectKind): AnalyzeResult =
  case kind
  of pkAnt: analyzeAnt(dir)
  of pkBazel: analyzeBazel(dir)
  of pkBundler: analyzeBundler(dir)
  of pkCargo: analyzeCargo(dir)
  of pkCustom: AnalyzeResult()
  of pkCMake: analyzeCMake(dir)
  of pkComposer: analyzeComposer(dir)
  of pkDart: analyzeDart(dir)
  of pkDotnet: analyzeDotnet(dir)
  of pkElixir: analyzeElixir(dir)
  of pkFlatpak: analyzeFlatpak(dir)
  of pkGo: analyzeGo(dir)
  of pkGodot: analyzeGodot(dir)
  of pkGradle: analyzeGradle(dir)
  of pkHaskell: analyzeHaskell(dir)
  of pkHugo: analyzeHugo(dir)
  of pkJekyll: analyzeJekyll(dir)
  of pkMakefile: analyzeMakefile(dir)
  of pkMaven: analyzeMaven(dir)
  of pkMeson: analyzeMeson(dir)
  of pkNim: analyzeNim(dir)
  of pkNode: analyzeNode(dir)
  of pkPython: analyzePython(dir)
  of pkSbt: analyzeSbt(dir)
  of pkSwift: analyzeSwift(dir)
  of pkUnity: analyzeUnity(dir)
  of pkZig: analyzeZig(dir)

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
