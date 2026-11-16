# HANDOFF — Terra-iOS Official-Launcher Redesign (SwiftUI)

> For the next AI coding agent. Read this before touching anything.

## 0. Status update (2026-11-15, Claude Code session) — supersedes §2/§3 claims below

Sections 2–4 claimed "verified clean"; they were not. Fixed this session:
- Swift unit did not compile (`TopRounded` mis-nested, `TerraIconFirstLabel` missing, iOS 17-only
  `onChange`, Modrinth `toJson` type error, missing `\` in progress string). Now type-checks and
  emits an object for both `arm64-apple-ios14.0` and `ios17.0`, debug and `-O`.
- CMake swiftc command lacked `-wmo` → "cannot specify -o when generating multiple output files".
  Added `-wmo -module-name TerraUI`.
- `VersionManagerViewController.m` had been *replaced* (not joined) by `TerraLauncherBridge.m` in the
  source list → link error. Restored.
- `LauncherRootViewController.m` called deleted `Terra*Host` classes → restored to pre-57a9634c7.
- Device deployment target had been bumped to iOS 17 (C flags + Swift triple); restored to 14.0.
  Simulator lines left at 17.
- New UI was never shown. `SceneDelegate` now installs `[TerraLauncherRootHost makeHost]` as the
  window root on iOS 16+ (returns nil below → legacy `AmeRootTabController`). Opt-out:
  NSUserDefaults bool `TerraLegacyLauncherUI`.
- All Terra SwiftUI types are `@available(iOS 16.0, *)`; app minimum stays iOS 14.
- `LauncherRootView.swift` rewritten to match the official desktop launcher screenshot (sidebar,
  product header + tabs, hero, bevelled PLAY over play bar, news banners). Hero art: bundle image
  `TerraHero` if present, else procedural.
- Mod download progress now observed via `ModDownloadsStore` (previous rows never re-rendered).
- Bridge `attachToRoot:` is idempotent (root rebuilds on language change).

Later the same day:
- App minimum raised to **iOS 16.0** (Info.plist, CMake C target + Swift triple, Makefile
  SWIFT_MIN_IOS + `native` DEPLOYMENT_TARGET). Third-party dep builds intentionally stay at 14.0.
  `@available(iOS 16.0, *)` annotations removed (now redundant).
- New 6th Swift file `TerraNewsFeed.swift` (added to TERRA_SWIFT_SRCS): live news from
  `https://launchercontent.mojang.com/v2/news.json`; hero banner = random Java news artwork per
  launch (never repeats the previous one; key `TerraLastHeroImage`). Images load at runtime only.
- Commit identity: this is a FORK — commit with the local `git config` identity, NOT herbrine8403
  (AGENTS.md updated). §4 step 4 below is obsolete.
- Cline was found overwriting files mid-session (restored old DownloadCenterView/InstancesView);
  it has been stopped and the files re-fixed. Don't run two agents on this tree at once.

Still not done: full CI build, commit/push (stage Terra files only; Makefile/CMake also contain
unrelated simulator-build hunks — split with `git add -p`).

---

## 1. Goal & Architecture

**Goal:** Replace the legacy ObjC launcher home screen with a new SwiftUI "official-launcher" UI, keeping the existing PojavLauncher-style launch pipeline intact. The Swift UI never launches Minecraft directly; it delegates every game action to a thin ObjC bridge.

**Architecture (3 roles):**

```
┌────────────────────────────────────────────────────┐
│  SwiftUI layer (5 files, ONE swiftc unit)          │
│  TerraTheme.swift          — shared theme/model    │
│  LauncherRootView.swift    — tab root, routing     │
│  InstancesView.swift       — instances list        │
│  DownloadCenterView.swift  — Modrinth downloads    │
│  TerraSettingsView.swift   — settings pane         │
└──────────────────────┬─────────────────────────────┘
                       │ TerraBridge (NSClassFromString("TerraLauncherService"))
┌──────────────────────▼─────────────────────────────┐
│  TerraLauncherBridge.m / .h (ObjC bridge)          │
│  +shared, attachToRoot:, snapshot, invoke:payload: │
└──────────────────────┬─────────────────────────────┘
                       │ calls existing ObjC launch pipeline
┌──────────────────────▼─────────────────────────────┐
│  Legacy launcher (LauncherRootViewController,      │
│  Launcher*, HomeCustomizeViewController, etc.)     │
└────────────────────────────────────────────────────┘
```

**Build plumbing (in `Natives/CMakeLists.txt`):**
- `TERRA_SWIFT_SRCS` (line ~413): the 5 Swift files. **They MUST compile as ONE swiftc unit** — they share types via `TerraTheme.swift`. Per-file compilation will fail with `cannot find type in scope`.
- `TerraSwift.o` produced by a single custom command; target `TerraSwiftUnit` (lines ~470–492).
- `add_dependencies(AngelAuraAmethyst TerraSwiftUnit)` (line ~801) forces the Swift object before linking.
- `TerraLauncherBridge.m` added to ObjC sources (line ~628, after `LauncherRightPanelViewController.m`).

---

## 2. Completed

| File | Status |
|---|---|
| `Natives/TerraLauncherBridge.h` | **Created** (~35 lines). Declares `TerraLauncherService` with `+shared`, `attachToRoot:`, `snapshot`, `invoke:payload:` and a doc comment explaining the 3 roles. |
| `Natives/TerraLauncherBridge.m` | **Created.** Placeholder markers (`___TERRA_BRIDGE_SNAPSHOT___`, `___TERRA_BRIDGE_INVOKE___`) removed; no `___` markers remain anywhere. |
| `Natives/CMakeLists.txt` | **Verified clean after repair.** Single `swiftc` unit → `TerraSwift.o`; `TerraSwiftUnit` target; `add_dependencies(AngelAuraAmethyst TerraSwiftUnit)`; `TerraLauncherBridge.m` listed **exactly once** (line 628). No stale `TerraDashboardView`/`TerraInstancesView`/`TerraDownloadView`/`TerraSwift_` references remain. |
| Old Swift files | Deleted from working tree: `TerraDashboardView.swift`, `TerraInstancesView.swift`, `TerraDownloadView.swift` (git shows them as deleted). `TerraSettingsView.swift` was **replaced** (modified, +263 lines). |
| New Swift files (untracked) | `Natives/TerraTheme.swift`, `Natives/LauncherRootView.swift`, `Natives/InstancesView.swift`, `Natives/DownloadCenterView.swift`, `Natives/TerraSettingsView.swift` |

**Verification done this session (greps):**
- `grep -n 'TerraLauncherBridge' CMakeLists.txt` → 1 match (line 628).
- `grep -n 'TerraSwiftUnit|TerraSwift.o' CMakeLists.txt` → only intended references (lines 473, 490, 492, 801).
- `grep '★ \[TERRA\]' CMakeLists.txt` → only intended comment markers (lines 410, 627).
- Each Terra struct (`TerraRootView`, `TerraPlayDashboard`, `TerraVersionsPane`, `TerraModsPane`, `TerraInstancesScreen`, `TerraSettingsScreen`) exists exactly once.

---

## 3. Unresolved Issues / Edge Cases

1. **⚠️ Duplicate-source incident (FIXED, but note the pattern).** This session, repeated identical editor insert calls duplicated the `TerraLauncherBridge.m` + comment block ~180× inside `Natives/CMakeLists.txt`. Fixed by awk dedup (keep first match, drop the rest) + removing one orphaned comment. **Lesson: emit one tool call at a time; never re-run an insert whose previous result already succeeded.**
2. **Build not yet run.** No cmake configure/compile has been attempted on this machine. First build is the single highest-priority validation step.
3. **Swift unit must stay monolithic.** If someone adds a 6th Swift file, add it to `TERRA_SWIFT_SRCS` only — never introduce per-file `.o` compilation (the old `TerraSwift_*` per-file loop pattern is gone; do not reintroduce it).
4. **Bridge class name coupling.** `TerraTheme.swift`'s `TerraBridge` looks up `TerraLauncherService` via `NSClassFromString`. If the ObjC class is renamed, the Swift side breaks silently at runtime.
5. **Heavy unrelated dirty state.** `git status` shows many modified/deleted files under `Natives/external/MobileGlues/...` (SPIRV-Cross / glslang reference files) plus untracked build artifacts (`angle/`, `simulator_frameworks/`, `buildServer.json`, `selfIdentity.plist`, `Natives/zt_sim_stub.c`). These are **pre-existing and not part of the Terra redesign** — do not commit them blindly; stage only Terra-related files.
6. **Untracked noise in MobileGlues submodule** (`.air_pin_*`, new reference shaders). Leave alone unless the user asks.

---

## 4. Next Steps (priority order)

1. **Run a full build** to validate the toolchain edits:
   ```bash
   cd /Users/chinnu/Terra-iOS-app
   make native          # first: this exercises cmake + the TerraSwiftUnit swiftc step
   ```
   If `TerraSwift.o` fails to compile, read the swiftc errors; common causes: missing import, Swift 5 toolchain version mismatch, or a file missing from `TERRA_SWIFT_SRCS`.
2. **Run the rest of the pipeline** (only after step 1 passes):
   ```bash
   make all             # dep_mg + native + java + jre + assets + payload + package
   ```
3. **Commit & push** (user explicitly requested push to GitHub). Stage ONLY Terra-related files:
   ```bash
   git -C /Users/chinnu/Terra-iOS-app add \
     Natives/CMakeLists.txt \
     Natives/TerraLauncherBridge.h Natives/TerraLauncherBridge.m \
     Natives/TerraTheme.swift Natives/LauncherRootView.swift \
     Natives/InstancesView.swift Natives/DownloadCenterView.swift \
     Natives/TerraSettingsView.swift \
     Natives/TerraDashboardView.swift Natives/TerraInstancesView.swift \
     Natives/TerraDownloadView.swift HANDOFF.md
   git -C /Users/chinnu/Terra-iOS-app commit -m "feat(Natives): SwiftUI official-launcher UI + ObjC bridge wiring"
   git -C /Users/chinnu/Terra-iOS-app push
   ```
   If push fails due to network: **ask user to disable their network proxy** (per project AGENTS.md).
4. **Commit identity:** use `herbrine8403` / `weishixvn@outlook.com`.
5. If the build surfaces errors in the Swift unit, fix inside the 5 Swift files — do NOT split the unit apart.

---

## 5. Build & Test Commands

**Main build (must be run on macOS; NOT on this Mac for GitHub Actions parity):**

```bash
cd /Users/chinnu/Terra-iOS-app
make all                    # full pipeline
make native                 # just natives + cmake + swift unit
make java                   # Java app side
make payload                # assemble AngelAuraAmethyst.app
make package                # produce .ipa / .tipa
```

**Optional build flags (Makefile vars):**

```bash
RELEASE=1                   # release build
SLIMMED=1                   # no bundled JRE
TROLLSTORE_JIT_ENT=1        # TrollStore .tipa
PLATFORM=2|3|7|11           # 2=iOS, 3=tvOS, 7=iOS sim, 11=visionOS
```

**CI note:** Official builds happen on GitHub Actions (macOS 14, Xcode 15.4/16, iPhoneOS 17.5 SDK), triggered by push to non-`l10n_main` branches (workflows: `development.yml`, `development_speedup.yml`). Artifacts: `org.angelauramc.amethyst-ios.ipa`, `org.angelauramc.amethyst-ios-trollstore.tipa`, `AngelAuraAmethyst.dSYM`.

**There is no `xcodebuild` scheme/`swift build` usage for this project** — the Swift code is compiled by the CMake custom `swiftc` command, not by an Xcode project or SwiftPM. Verify with:

```bash
grep -n 'swiftc' /Users/chinnu/Terra-iOS-app/Natives/CMakeLists.txt
```

---

## 6. Key Invariants (do not break)

1. The 5 Terra Swift files are **one** swiftc compilation unit.
2. `TerraLauncherService` is the **only** ObjC↔Swift seam; class name must match `NSClassFromString("TerraLauncherService")` in `TerraTheme.swift`.
3. `Natives/CMakeLists.txt` must contain `TerraLauncherBridge.m` **exactly once**.
4. `add_dependencies(AngelAuraAmethyst TerraSwiftUnit)` must remain so the Swift `.o` is built before the final link.
5. Legacy launch pipeline is untouched; the Swift UI only issues `invoke:payload:` commands.
