<div align="center">
  <img src="https://raw.githubusercontent.com/mineverse67890-ai/Terra-iOS/feature/terra-launcher-ui/Natives/Assets.xcassets/AppIcon-Light.appiconset/1024x1024.png" alt="Terra icon" width="120" style="border-radius: 24px;">
</div>

<h1 align="center">Terra</h1>
<p align="center"><sub>A Minecraft: Java Edition launcher for iOS and iPadOS</sub></p>

<div align="center">
  <a href="https://github.com/mineverse67890-ai/Terra-iOS/actions/workflows/development.yml"><img alt="Build Status" src="https://github.com/mineverse67890-ai/Terra-iOS/actions/workflows/development.yml/badge.svg"></a>
  <img alt="License" src="https://img.shields.io/github/license/mineverse67890-ai/Terra-iOS?style=flat">
  <img alt="Platform" src="https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS%2016%2B-lightgrey?style=flat">
</div>

---

Terra is a Minecraft: Java Edition launcher for iPhone and iPad, built on [Angel Aura Amethyst](https://github.com/AngelAuraMC/Amethyst-iOS) and [Amethyst iOS Remastered](https://github.com/herbrine8403/Amethyst-iOS-MyRemastered). It pairs their proven game engine with a redesigned interface modeled on the official desktop launcher, English by default, and downloads that work anywhere in the world.

---

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
  - [Device Requirements](#device-requirements)
  - [Sideload Preparation](#sideload-preparation)
  - [Installation](#installation)
  - [Enabling JIT](#enabling-jit)
- [Building from Source](#building-from-source)
- [Credits](#credits)
- [Third-Party Components](#third-party-components)
- [License](#license)

## Features

### New in Terra

- **Desktop-Launcher Design** -- A dark interface laid out like the official Minecraft Launcher: sidebar navigation, Play / Installations / Download Center / Patch notes tabs, and a green PLAY button with a live JIT status indicator.
- **Live Minecraft News** -- The Play page and News section pull the latest articles from the official launcher news feed. Tap any story to read it on minecraft.net.
- **Official Update Artwork** -- The Play banner shows a different official Minecraft update banner each time you open the app.
- **Installations** -- Each installation shows its Minecraft version, loader badge (Vanilla / Fabric / Quilt / Forge / NeoForge), and size. Launch, manage content, or open its settings with one tap.
- **Download Center** -- Install any Minecraft version with Vanilla, Fabric, Quilt, Forge, or NeoForge, and browse mods, modpacks, shaders, resource packs, and data packs from Modrinth and CurseForge in a store-style browser with filters and project pages.
- **Potato Optimize** -- One tap installs the best performance mods (Sodium, Lithium, FerriteCore, ImmediatelyFast, Entity Culling, ModernFix, and more) for your installation's loader.
- **Competitive Download** -- One tap installs popular PvP mods (zoom, freelook, armor HUD, totem counter, keystrokes/CPS HUD, hitboxes) and PvP texture packs (low fire, short swords, small shield, crosshair).
- **Content Manager** -- A sidebar-based manager for mods, shader packs, resource packs, and data packs with search, filters, sorting, and per-item details.
- **Redesigned Settings** -- Clean, categorized settings for video, Java and memory, controls, downloads, and accounts, plus per-installation settings for Java version, memory, renderer, and game folder.
- **Crash Troubleshooter** -- A clean loading screen with a Troubleshoot button that explains why the game crashed and how to fix it.
- **English by Default** -- The full interface is in English out of the box. Other languages remain available in Settings.
- **Works Worldwide** -- Downloads use Mojang's official servers by default. Regional mirrors are only used automatically in mainland China, so no VPN is needed.
- **Ely.by Accounts** -- Sign in with Ely.by, or any authlib-injector server, alongside Microsoft and offline accounts.

> [!TIP]
> CurseForge requires a free API key. Get one at [console.curseforge.com](https://console.curseforge.com/) and paste it in **Settings → Downloads → CurseForge API key**. Modrinth works without a key.

### Inherited from Amethyst

- **Wide Version Support** -- From early betas to the newest releases and snapshots.
- **Mod Loaders** -- Forge, NeoForge, Fabric, Quilt, and OptiFine.
- **Resource Management** -- View, enable, disable, and delete mods, shader packs, resource packs, and data packs, with Modrinth and CurseForge downloads.
- **Modpack Import** -- Import ZIP modpacks straight from the launcher.
- **Automatic Renderer** -- Picks the best rendering backend for your device, including MobileGlues.
- **Automatic Java** -- Selects Java 8, 17, 21, or 25 based on the game version.
- **Controls** -- Customizable on-screen controls, keyboard and mouse, game controllers, and [TouchController](https://github.com/TouchController/TouchController) mod support.
- **Multiple Accounts** -- Switch between Microsoft, offline, and third-party accounts.

## Quick Start

The [Amethyst wiki](https://wiki.angelauramc.dev/wiki/getting_started/INSTALL.html#ios) covers installation and setup in depth, and almost all of it applies to Terra. Here is the short version.

### Device Requirements

| Tier | iOS Version | Devices |
|------|-------------|---------|
| **Minimum** | iOS 16.0+ | iPhone 8 and later (including iPhone SE 2nd gen), iPad 5th gen+, iPad Air 3rd gen+, iPad mini 5th gen+, all iPad Pro models |
| **Recommended** | iOS 16.0+ | iPhone XS and later (excluding iPhone XR and SE 2nd gen), iPad 10th gen+, iPad Air 4th gen+, iPad mini 6th gen+, iPad Pro (excluding 9.7-inch) |

Recommended devices have more memory and run the game noticeably smoother.

> [!NOTE]
> iOS 17 and later is supported, but enabling JIT the first time requires a computer. See the [official JIT guide](https://wiki.angelauramc.dev/wiki/faq/ios/JIT.html#what-are-the-methods-to-enable-jit).

### Sideload Preparation

Choose a tool that supports permanent signing and automatic JIT if you can:

1. **TrollStore** *(recommended)* -- Permanent signing, automatic JIT, and higher memory limits. Only available on certain iOS versions. [Get it from the official repository.](https://github.com/opa334/TrollStore)
2. **AltStore / SideStore** -- Needs periodic re-signing, and a computer and Wi-Fi for first-time setup. Requires a **development certificate** (it must include the `com.apple.security.get-task-allow` entitlement for JIT). Signing services that use distribution certificates are not supported.

> [!WARNING]
> Only download sideloading tools and Terra builds from official or trusted sources. Jailbroken devices also get permanent signing and automatic JIT, but jailbreaking a device you use every day is not recommended.

### Installation

There are no tagged releases yet. Every build is produced automatically by GitHub Actions.

<details>
<summary><b>TrollStore</b></summary>

1. Open the latest successful run on the [Actions page](https://github.com/mineverse67890-ai/Terra-iOS/actions/workflows/development.yml) (you must be signed in to GitHub to download).
2. Download the `com.terra.terra-ios-ios-trollstore.tipa` artifact and unzip it.
3. Open the `.tipa` file in TrollStore from the share menu.
</details>

<details>
<summary><b>AltStore / SideStore</b></summary>

1. Open the latest successful run on the [Actions page](https://github.com/mineverse67890-ai/Terra-iOS/actions/workflows/development.yml).
2. Download the `com.terra.terra-ios-ios.ipa` artifact and unzip it.
3. Install the `.ipa` with your sideloading app as usual.
</details>

> [!CAUTION]
> These are development builds and may contain bugs, including crashes. Back up important worlds before updating.

### Enabling JIT

JIT (just-in-time compilation) is required for playable performance. Pick the method that fits your setup:

| Tool | Needs another device | Needs Wi-Fi | Enables automatically | Notes |
|------|:---:|:---:|:---:|-------|
| TrollStore | No | No | Yes | Easiest option; nothing extra to do |
| AltStore | Yes | Yes | Yes | AltServer must be running on your network |
| SideStore | First time only | First time only | No | Works on its own after setup |
| StikDebug | First time only | First time only | Yes | Works on its own after setup |
| Jitterbug | Yes (if no VPN) | Yes | No | Must be triggered manually |
| Jailbreak | No | No | Yes | Handled by the system |

## Building from Source

Terra is built on macOS with Xcode and the iOS SDK. Both Intel and Apple Silicon Macs can build it, since the output is cross-compiled for arm64. You will also need CMake, ldid, wget, and JDK 8.

```bash
make all                     # full build: natives, Java, runtimes, assets, app bundle, package
make all TROLLSTORE_JIT_ENT=1   # TrollStore .tipa
make all RELEASE=1              # release build
```

The `.ipa` / `.tipa` files are written to `artifacts/`. Every push is also built automatically by the [Development build](https://github.com/mineverse67890-ai/Terra-iOS/actions/workflows/development.yml) workflow on GitHub Actions.

## Credits

Terra stands on the work of these projects and the people behind them:

- **[Angel Aura Amethyst](https://github.com/AngelAuraMC/Amethyst-iOS)** -- The original iOS launcher. Thanks to [@crystall1nedev](https://github.com/crystall1nedev), [@khanhduytran0](https://github.com/khanhduytran0), [@artdeell](https://github.com/artdeell), [@Mathius-Boulay](https://github.com/Mathius-Boulay), [@zhuowei](https://github.com/zhuowei), [@jkcoxson](https://github.com/jkcoxson), [@Diatrus](https://github.com/Diatrus), and everyone who contributed.
- **[Amethyst iOS Remastered](https://github.com/herbrine8403/Amethyst-iOS-MyRemastered)** -- The remastered fork Terra is built from, by [@herbrine8403](https://github.com/herbrine8403), with contributions from [@yitenchen123](https://github.com/yitenchen123), [@EternityQwQ](https://github.com/EternityQwQ), [@LanRhyme](https://github.com/LanRhyme), [@WeiErLiTeo](https://github.com/WeiErLiTeo), [@Li2548](https://github.com/Li2548), and [@Gsjsjzhznsz](https://github.com/Gsjsjzhznsz).
- **[Boardwalk](https://github.com/zhuowei/Boardwalk)** by [@zhuowei](https://github.com/zhuowei) -- Where it all began.

## Third-Party Components

| Component | Purpose | License | Source |
|-----------|---------|---------|--------|
| Caciocavallo | AWT runtime framework | GPL-2.0 | [GitHub](https://github.com/PojavLauncherTeam/caciocavallo) |
| jsr305 | Code annotation support | BSD-3 | [Google Code](https://code.google.com/p/jsr-305) |
| Boardwalk | Core functionality adaptation | Apache-2.0 | [GitHub](https://github.com/zhuowei/Boardwalk) |
| GL4ES | OpenGL-to-GLES translation | MIT | [GitHub](https://github.com/ptitSeb/gl4es) |
| Mesa 3D | 3D graphics library | MIT | [GitLab](https://gitlab.freedesktop.org/mesa/mesa) |
| MetalANGLE | Metal-to-OpenGL ES translation | BSD-2 | [GitHub](https://github.com/khanhduytran0/metalangle) |
| MoltenVK | Vulkan-to-Metal translation | Apache-2.0 | [GitHub](https://github.com/KhronosGroup/MoltenVK) |
| openal-soft | Cross-platform 3D audio | LGPL-2.0 | [GitHub](https://github.com/kcat/openal-soft) |
| Azul Zulu JDK | Java runtime (8/17/21/25) | GPL-2.0 | [Website](https://www.azul.com/downloads/?package=jdk) |
| LWJGL3 | Java game development library | BSD-3 | [GitHub](https://github.com/PojavLauncherTeam/lwjgl3) |
| LWJGLX | LWJGL2 compatibility layer | -- | [GitHub](https://github.com/PojavLauncherTeam/lwjglx) |
| DBNumberedSlider | UI slider control | Apache-2.0 | [GitHub](https://github.com/khanhduytran0/DBNumberedSlider) |
| fishhook | Dynamic library rebinding | BSD-3 | [GitHub](https://github.com/khanhduytran0/fishhook) |
| shaderc | Vulkan shader compilation | Apache-2.0 | [GitHub](https://github.com/khanhduytran0/shaderc) |
| NRFileManager | File management utilities | MPL-2.0 | [GitHub](https://github.com/mozilla-mobile/firefox-ios) |
| AltKit | AltStore integration | -- | [GitHub](https://github.com/rileytestut/AltKit) |
| UnzipKit | ZIP archive handling | BSD-2 | [GitHub](https://github.com/abbeycode/UnzipKit) |
| DyldDeNeuralyzer | Library validation bypass | -- | [GitHub](https://github.com/xpn/DyldDeNeuralyzer) |
| MobileGlues | Third-party renderer | LGPL-2.1 | [GitHub](https://github.com/MobileGL-Dev/MobileGlues) |
| LTW | OpenGL Core-to-ES wrapper | LGPL-3.0 | [GitHub](https://github.com/MojoLauncher/LTW) |
| authlib-injector | Third-party authentication | AGPL-3.0 | [GitHub](https://github.com/yushijinhun/authlib-injector) |
| TouchController | Touchscreen control mod bridge | -- | [GitHub](https://github.com/TouchController/TouchController) |

Additional thanks to [MCHeads](https://mc-heads.net) for player avatars, [Modrinth](https://modrinth.com) for mod distribution, [Ely.by](https://ely.by) for third-party accounts, and [BMCLAPI](https://bmclapidoc.bangbang93.com) for the download mirror used in mainland China.

## License

Terra is licensed under the [GNU General Public License v3.0](LICENSE), the same license as the projects it is based on.

Terra is not an official Minecraft product and is not approved by or associated with Mojang or Microsoft. Minecraft is a trademark of Mojang AB. News articles and artwork shown in the launcher are loaded from Mojang's official launcher content service and remain the property of their owners. You need to own Minecraft: Java Edition to play the full game.
