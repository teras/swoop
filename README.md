# 🧹 Swoop

**Smart build artifact cleaner** — scans your project directories, detects build systems, reads their configuration files, and identifies build artifacts that can be safely removed.

No more manually hunting down `target/`, `build/`, `node_modules/`, or `.gradle/` directories eating up your disk space and bloating your backups.

## ✨ Features

- 🔍 **Auto-detection** — Recognizes 11 project types by reading their build files
- 📖 **Reads build scripts** — Doesn't just guess; actually parses `pom.xml`, `build.gradle`, `Cargo.toml`, `Makefile`, `package.json`, `.nimble`, and more
- 🏗️ **Understands project structure** — Knows what's source (skip), what's output (clean), and what's unknown (explore)
- 🌳 **Recursive with aggregation** — Traverses nested projects and rolls up results to the root project
- ⚡ **Parallel size computation** — Uses multiple threads to calculate directory sizes
- 🎨 **Colored output** — Size-coded colors and grouped-by-type display
- 🛡️ **Safe by default** — Dry-run mode, confirmation prompt, no symlink following
- 🔧 **Zero-config** — Works out of the box, per-project `.swoop.toml` for overrides

## 📦 Supported Project Types

| Type | Detection | What it reads | Clean targets |
|------|-----------|---------------|---------------|
| 🦀 **Cargo** (Rust) | `Cargo.toml` | `target-dir`, `.cargo/config.toml` | `target/` |
| 🐘 **Gradle** | `build.gradle(.kts)` | `buildDir`, `layout.buildDirectory` | `build/`, `.gradle/`* |
| ☕ **Maven** | `pom.xml` | `<build><directory>`, `<sourceDirectory>` | `target/` |
| 👑 **Nim** (Nimble) | `*.nimble` | `bin`, `srcDir` | Binary files, `nimcache/`, `nimbledeps/`* |
| 🟢 **Node.js** | `package.json` | `dependencies` for framework detection | `.next/`, `.nuxt/`, `dist/`, `node_modules/`* |
| 🐍 **Python** | `pyproject.toml`, `setup.py` | — | `__pycache__/`, `build/`, `*.egg-info/`, `.venv/`* |
| 🔧 **CMake** | `CMakeLists.txt` | Scans for `CMakeCache.txt` in subdirs | Build directories, `cmake-build-*/` |
| 🐜 **Ant** | `build.xml` | `<property name="build.dir">` | `build/`, `dist/` |
| ⚙️ **Makefile** | `Makefile` with `clean:` target | Parses `rm -r` commands, resolves included variables | Whatever `clean:`/`distclean:` removes |
| 🌿 **Hugo** | `config.yaml/toml` + `content/` | — | `public/`, `resources/_gen/` |

\* *Marked with `*` = only removed with `--purge` (distclean level)*

> 💡 A project can be detected as **multiple types** simultaneously (e.g. Nim + Makefile, or Gradle + Maven). Each analyzer contributes its targets independently.

## 🚀 Quick Start

```bash
# Build
nimble build

# Scan current directory (dry-run, safe)
swoop

# Scan a specific path
swoop ~/Projects

# Actually delete (with confirmation)
swoop -x ~/Projects

# Deep clean (also remove node_modules, .venv, .gradle, etc.)
swoop --purge ~/Projects

# Delete without confirmation
swoop -x -f ~/Projects

# Only show Rust projects
swoop --type cargo ~/Projects
```

## 🖥️ Output

```
[DRY RUN] /home/user/Projects

cargo ──────────────────────────────────────────────────── 24.45 GB ─
  rust/keydeck                                     target/    8.17 GB
                                     keydeck-types/target/   32.3 MB
                          keydeck-config/src-tauri/target/   13.42 GB
  rust/basil                                       target/    2.22 GB
gradle ──────────────────────────────────────────────────── 1.76 GB ─
  MyMultiProject                                    build/  390.4 MB
                                         composeApp/build/   30.0 MB
nim ──────────────────────────────────────────────────────── 3.9 MB ─
  tools/keepalive                                  target/    1.2 MB
  tools/dpr                                        target/    2.7 MB

Total: 5 projects, 24.27 GB reclaimable
```

- 📊 Projects grouped by type, sorted by size (largest first)
- 📐 Adaptive layout — paths and folder names shorten intelligently when terminal is narrow
- 🎨 Colors: red (≥1 GB), yellow (≥100 MB), blue headers

## 🔧 Configuration

Swoop needs **no configuration** to work. It automatically skips `.git`, `.idea`, `.vscode`, `.svn`, and `.hg` directories.

For per-project customization, place a `.swoop.toml` in any directory. You only need the options you want — everything is optional.

## 🧠 How It Works

### Three-category traversal

When Swoop finds a project, it classifies every subdirectory:

1. **➖ Negative** (artifacts) — marked for deletion (`target/`, `build/`, etc.)
2. **➕ Positive** (source) — known source dirs, never entered (`src/`, `tests/`, etc.)
3. **❓ Neutral** (unknown) — entered to search for nested projects

This is driven by each analyzer reading the actual build files, not hardcoded lists.

### Two clean levels

| Level | Flag | What it removes |
|-------|------|-----------------|
| **clean** | *(default)* | Build output only |
| **distclean** | `--purge` | + dependencies, caches, virtual environments |

### Root project aggregation

Nested projects automatically aggregate under their nearest root. A Maven multi-module project with 50 submodules appears as **one entry** with combined size. Use `root = true` in `.swoop.toml` to break out a nested project into its own root.

## 📋 All Options

```
swoop [options] [path...]

  -x, --execute       Actually delete (without this = dry-run)
  -f, --force         Don't ask for confirmation (with -x)
  --purge              Distclean level (node_modules, .venv, .gradle, etc.)
  -v, --verbose       Verbose output (show errors)
  -q, --quiet         Suppress progress output
  -t, --threads N     Worker threads (default: auto = CPU count)
  --type TYPE         Only show/clean this project type
  --depth N           Max scan depth (default: unlimited)
  --no-color          Disable colored output
  --make-config PATH  Create a default .swoop.toml
  -h, --help          Show help
```

## 🏗️ Building from source

```bash
# Requirements: Nim >= 2.0.0

# Install dependencies & build
nimble build

# Or manually
nim c --threads:on -d:release -d:strip -d:lto --opt:speed -o:target/swoop src/swoop.nim
```

### 💡 Tips

- You **don't need** `.swoop.toml` for most projects — auto-detection handles the common cases.
- Place it at the **top-level scan directory** (e.g. `~/Projects/.swoop.toml`) to set defaults like `max_depth` for everything underneath.
- Use `root = true` to prevent unrelated projects from being merged together.
- Use `swoop --make-config .` to generate a template with all options commented out.

### 📝 Generate a template

```bash
swoop --make-config .              # Creates .swoop.toml in current dir
swoop --make-config myconfig.toml  # Creates at specific path
```

## 📖 Options reference

#### `ignore` (bool, default: `false`)

Skip this directory entirely. Swoop won't detect projects here, won't clean anything, and won't descend into subdirectories.

```toml
ignore = true
```

**When to use:** You have a directory with build files that you don't want Swoop to touch — e.g. a vendored dependency, an archived project, or a directory managed by another tool.

---

#### `root` (bool, default: `false`)

Break the parent-child aggregation chain. Normally, nested projects roll up their clean targets to the nearest ancestor project. Setting `root = true` makes this directory appear as its own independent entry in the output.

```toml
root = true
```

**When to use:** You have a monorepo where `~/Projects` contains unrelated projects. Without `root = true` at the top level, a stray `Makefile` there could absorb everything underneath. Place `.swoop.toml` with `root = true` in each independent project, or at the top-level directory to prevent unwanted aggregation.

---

#### `type` (string, default: auto-detected)

Override or extend the detected project type. Space-separated for multiple types.

Supported values: `gradle`, `maven`, `cargo`, `nim`, `node`, `python`, `cmake`, `ant`, `makefile`, `hugo`.

```toml
type = "gradle maven"
```

**When to use:** Swoop misdetects the project type, or you want to force a specific type. For example, a project has both `pom.xml` and `build.gradle` but you only want Gradle cleaning behavior.

---

#### `extra_clean` (array of strings, default: `[]`)

Additional directories or files to mark as clean targets, on top of what the analyzer detects. Paths are relative to the directory containing this `.swoop.toml` and only apply to that project.

```toml
extra_clean = ["generated/", "custom-output/", "temp-data"]
```

**When to use:** Your build system produces output that Swoop doesn't know about — e.g. a custom code generator that writes to `generated/`, or a Nimble project that builds to `target/` (non-standard for Nimble).

---

#### `keep` (array of strings, default: `[]`)

Protect specific targets from cleaning, even if an analyzer or `extra_clean` marks them for deletion.

```toml
keep = ["build/resources/", "dist/vendor.js"]
```

**When to use:** An analyzer marks a directory for deletion but it contains files you need to preserve — e.g. `build/resources/` has manually curated data, or `dist/` has a checked-in vendor bundle.

---

#### `skip_scan` (array of strings, default: `[]`)

Additional directories that Swoop should not descend into when looking for nested projects. These are added on top of the built-in skip list (`.git`, `.idea`, `.vscode`, `.svn`, `.hg`).

```toml
skip_scan = ["vendor/", "third-party/", "legacy/"]
```

**When to use:** You have large directories with no projects inside them — e.g. a `vendor/` folder with copied source code, or a `third-party/` tree that would waste scan time.

---

#### `traverse_scan` (array of strings, default: `[]`)

Override the built-in skip list, parent `skip_scan` entries, and analyzer-detected source dirs. Forces Swoop to enter directories it would normally skip. Skip sets are inherited from parent configs, so a child `traverse_scan` can undo a parent's `skip_scan`.

```toml
traverse_scan = [".idea", "src"]
```

**When to use:**
- You have a project inside `.idea/` (unlikely but possible) — Swoop normally skips `.idea/` globally.
- A parent `.swoop.toml` has `skip_scan = ["vendor/"]` but a child project needs Swoop to enter `vendor/` to find nested projects.
- An analyzer marks `src/` as a source directory (positive, don't enter), but you have nested projects inside `src/` that you want Swoop to find.

**Conflict resolution:** If the same entry appears in both `skip_scan` and `traverse_scan`, they cancel out — the entry is removed from both.

---

#### `max_depth` (integer, default: `0` = unlimited)

Limit how deep Swoop scans from this directory. Depth resets at each detected project root.

```toml
max_depth = 3
```

**When to use:** You have a very deep directory tree and want to limit scan time, or you know there are no interesting projects beyond a certain depth.

---

## 📄 License

MIT
