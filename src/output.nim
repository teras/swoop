import std/[os, strutils, terminal, algorithm, tables]
import types

const
  Reset = "\e[0m"
  Bold = "\e[1m"
  Dim = "\e[2m"
  Red = "\e[31m"
  Green = "\e[32m"
  Yellow = "\e[33m"
  Blue = "\e[34m"
  LineCh = when defined(windows): "-" else: "\u2500"

proc fmtSize*(bytes: int64, pad: bool = true): string =
  if bytes < 0: return "—"
  let sp = if pad: "  " else: " "
  if bytes < 1024:
    return $bytes & sp & "B"
  elif bytes < 1024 * 1024:
    return formatFloat(bytes.float / 1024.0, ffDecimal, 1) & " KB"
  elif bytes < 1024 * 1024 * 1024:
    return formatFloat(bytes.float / (1024.0 * 1024.0), ffDecimal, 1) & " MB"
  else:
    return formatFloat(bytes.float / (1024.0 * 1024.0 * 1024.0), ffDecimal, 2) & " GB"

proc colorSize(s: string, bytes: int64): string =
  if bytes >= 1024 * 1024 * 1024: return Red & s & Reset
  elif bytes >= 100 * 1024 * 1024: return Yellow & s & Reset
  else: return s

proc kindColor*(kind: ProjectKind): string =
  Blue

proc kindScore(kind: ProjectKind): int =
  case kind
  of pkMakefile: 1
  of pkAnt: 10
  of pkMaven: 20
  of pkCMake: 25
  of pkMeson: 26
  of pkSbt: 30
  of pkGradle: 35
  of pkNode: 40
  of pkDotnet: 45
  else: 50

proc primaryKind*(kinds: set[ProjectKind]): ProjectKind =
  result = pkMakefile
  var best = -1
  for k in kinds:
    let s = kindScore(k)
    if s > best:
      best = s
      result = k


proc shortenPath*(path: string, maxLen: int): string =
  if path.len <= maxLen:
    return path
  let parts = path.split('/')
  if parts.len <= 1:
    return path
  var shortened = parts
  for i in 0 ..< shortened.len - 1:
    shortened[i] = $shortened[i][0]
    let candidate = shortened.join("/")
    if candidate.len <= maxLen:
      return candidate
  return shortened.join("/")

proc shortenFolder*(folder: string, maxLen: int): string =
  ## Shorten a folder path from the LEFT, keeping the rightmost parts.
  if folder.len <= maxLen:
    return folder
  let parts = folder.split('/')
  # Try removing parts from the left
  for start in 1 ..< parts.len:
    const ellipsis = when defined(windows): "..." else: "\u2026"
    let candidate = ellipsis & "/" & parts[start .. ^1].join("/")
    if candidate.len <= maxLen:
      return candidate
  # Can't shorten enough — just the last part
  if parts[^1].len <= maxLen:
    return parts[^1]
  return folder[^maxLen .. ^1]

proc relativeTo*(path, base: string): string =
  if path.startsWith(base):
    var rel = path[base.len .. ^1]
    if rel.len > 0 and rel[0] in {'/', '\\'}:
      rel = rel[1 .. ^1]
    return rel
  return path

type
  EntryLine = object
    folder: string
    size: string
    sizeBytes: int64

  ProjectDisplay = object
    path: string
    kind: ProjectKind
    entries: seq[EntryLine]
    totalSize: int64

proc printResults*(projects: seq[ProjectInfo], rootPath: string, execute: bool, noColor: bool = false, emptyDirs: seq[string] = @[]) =
  let termWidth = try: terminalWidth() except: 80
  let useColor = when defined(windows): false
                 else: not noColor and isatty(stdout)

  # Build display data
  var displays: seq[ProjectDisplay]
  for p in projects:
    if p.entries.len == 0: continue
    var d = ProjectDisplay(
      path: p.path.relativeTo(rootPath),
      kind: primaryKind(p.kinds),
      totalSize: p.totalSize,
    )
    for entry in p.entries:
      let rel = entry.path.relativePath(p.path) & (if entry.isDir: "/" else: "")
      d.entries.add EntryLine(folder: rel, size: fmtSize(entry.size), sizeBytes: entry.size)
    displays.add d

  # Group by primary kind
  var groups: Table[ProjectKind, seq[ProjectDisplay]]
  for d in displays:
    if d.kind notin groups:
      groups[d.kind] = @[]
    groups[d.kind].add d

  for kind in ProjectKind:
    if kind in groups:
      var sorted = groups[kind]
      sorted.sort(proc(a, b: ProjectDisplay): int = cmp(b.totalSize, a.totalSize))
      groups[kind] = sorted

  if displays.len == 0 and emptyDirs.len == 0:
    echo "No cleanable projects found in " & rootPath
    return

  # Header
  let mode = if execute: (if useColor: Red & Bold & "[EXECUTE]" & Reset else: "[EXECUTE]")
             else: (if useColor: Green & "[DRY RUN]" & Reset else: "[DRY RUN]")
  echo mode & " " & rootPath
  echo ""

  let indent = 2
  let gap = 2
  let minGap = 4
  var maxSizeLen = 0
  for d in displays:
    for e in d.entries:
      maxSizeLen = max(maxSizeLen, e.size.len)
  let sizeCol = max(maxSizeLen, 8)

  # Sort groups by total size descending
  var sortedKinds: seq[tuple[kind: ProjectKind, size: int64]]
  for kind in ProjectKind:
    if kind notin groups: continue
    var total: int64 = 0
    for d in groups[kind]: total += d.totalSize
    sortedKinds.add (kind, total)
  sortedKinds.sort(proc(a, b: tuple[kind: ProjectKind, size: int64]): int = cmp(b.size, a.size))

  # Print each group
  for (kind, _) in sortedKinds:
    let projs = groups[kind]

    var groupSize: int64 = 0
    for d in projs: groupSize += d.totalSize
    let kindStr = $kind
    let sizeStr = " " & fmtSize(groupSize) & " "
    let lineLen = termWidth - kindStr.len - 1 - sizeStr.len - 1  # -1 for final ─
    let kColor = kindColor(kind)
    let line = LineCh.repeat(max(lineLen, 1))
    let header = if useColor:
      Bold & kColor & kindStr & Reset & " " & Dim & line & " " & Reset & kColor & fmtSize(groupSize) & Reset & Dim & " " & LineCh & Reset
    else:
      kindStr & " " & line & sizeStr & LineCh
    echo header

    for d in projs:
      if d.entries.len == 0:
        echo " ".repeat(indent) & d.path
        continue

      for ei, entry in d.entries:
        let alignedSize = entry.size.align(sizeCol)
        let rightFixedLen = gap + sizeCol  # " ".repeat(gap) + aligned size

        if ei == 0:
          # First entry: project name + folder + size must fit in termWidth
          # First try: shorten path to fit with full folder
          let availPath1 = termWidth - indent - entry.folder.len - rightFixedLen - minGap
          let shortPath1 = shortenPath(d.path, max(availPath1, 1))
          # Check if it fits
          let totalLen1 = indent + shortPath1.len + minGap + entry.folder.len + rightFixedLen
          var folder: string
          var shortPath: string
          if totalLen1 <= termWidth:
            folder = entry.folder
            shortPath = shortPath1
          else:
            # Path is already minimally shortened — must cut folder too
            let minPathLen = shortenPath(d.path, 1).len
            let maxFolder = termWidth - indent - minPathLen - minGap - rightFixedLen
            folder = shortenFolder(entry.folder, max(maxFolder, 5))
            let availPath2 = termWidth - indent - folder.len - rightFixedLen - minGap
            shortPath = shortenPath(d.path, max(availPath2, 1))
          let leftSide = " ".repeat(indent) & shortPath
          let plainRight = folder & " ".repeat(gap) & alignedSize
          let padding = termWidth - leftSide.len - plainRight.len
          let rightColored = if useColor:
            Dim & folder & Reset & " ".repeat(gap) & colorSize(alignedSize, entry.sizeBytes)
          else: plainRight
          if padding >= minGap:
            echo leftSide & " ".repeat(padding) & rightColored
          else:
            echo leftSide & " ".repeat(minGap) & rightColored
        else:
          # Subsequent: right-aligned, no project name
          let maxFolder = termWidth - rightFixedLen - indent
          let folder = shortenFolder(entry.folder, maxFolder)
          let plainRight = folder & " ".repeat(gap) & alignedSize
          let rightColored = if useColor:
            Dim & folder & Reset & " ".repeat(gap) & colorSize(alignedSize, entry.sizeBytes)
          else: plainRight
          let pad = termWidth - plainRight.len
          if pad > 0:
            echo " ".repeat(pad) & rightColored
          else:
            echo rightColored

  # Empty dirs group
  if emptyDirs.len > 0:
    let kindStr = "empty"
    let sizeStr = " " & $emptyDirs.len & " dirs "
    let lineLen = termWidth - kindStr.len - 1 - sizeStr.len - 1
    let line = LineCh.repeat(max(lineLen, 1))
    if useColor:
      echo Bold & Blue & kindStr & Reset & " " & Dim & line & " " & Reset & Blue & $emptyDirs.len & " dirs" & Reset & Dim & " " & LineCh & Reset
    else:
      echo kindStr & " " & line & sizeStr & LineCh
    var sortedEmpty = emptyDirs
    sortedEmpty.sort()
    for dir in sortedEmpty:
      echo "  " & dir.relativeTo(rootPath) & "/"

  # Summary
  var totalBytes: int64 = 0
  for d in displays: totalBytes += d.totalSize
  var summaryParts: seq[string]
  if displays.len > 0:
    summaryParts.add $displays.len & " projects, " & fmtSize(totalBytes, pad = false) & " reclaimable"
  if emptyDirs.len > 0:
    summaryParts.add $emptyDirs.len & " empty directories"
  let summary = "Total: " & summaryParts.join(", ")
  echo ""
  if useColor:
    echo Bold & summary & Reset
  else:
    echo summary

proc printCountProgress*(count: int) =
  when defined(windows):
    let spinChars = ["|", "/", "-", "\\"]
  else:
    let spinChars = ["\u280B", "\u2819", "\u2839", "\u2838", "\u283C", "\u2834", "\u2826", "\u2827", "\u2807", "\u280F"]
  let ch = spinChars[(count div 50) mod spinChars.len]
  let line = "Scanning " & ch & " " & $count & " dirs"
  let termWidth = try: terminalWidth() except: 80
  let padded = if line.len < termWidth: line & " ".repeat(termWidth - line.len)
               else: line[0 ..< termWidth]
  stderr.write "\r" & padded
  stderr.flushFile()

proc clearProgress*() =
  let termWidth = try: terminalWidth() except: 80
  stderr.write "\r" & " ".repeat(termWidth) & "\r"
  stderr.flushFile()
