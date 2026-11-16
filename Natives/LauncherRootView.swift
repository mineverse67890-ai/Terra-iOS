// ===========================================================================
//  ★ [TERRA-UI] LauncherRootView.swift —— Official desktop launcher layout
//  ---------------------------------------------------------------------------
//    ┌──────────────┬────────────────────────────────────────────────┐
//    │ [■] Player ⌄ │ MINECRAFT: JAVA EDITION                        │
//    │              │ Play  Installations  Download Center  Patch notes│
//    │ [■] News     │ ┌──────────────── hero art ──────────────────┐ │
//    │▌[■] MINECRAFT│ │                                            │ │
//    │     Java Ed. │ └───────────────[  PLAY  ]───────────────────┘ │
//    │              │ [■] install ⌄                       [ Player ] │
//    │              │ ┌──── news banner ────┬── TITLE ─────────────┐ │
//    │ [■] Settings │ └─────────────────────┴──────────────────────┘ │
//    └──────────────┴────────────────────────────────────────────────┘
//  Boot: dark splash → grass block pulse + progress → dashboard reveal.
//  One NavigationStack for all content; no legacy tab bar / floating pills.
//  Hero art: random official Java news artwork per launch (TerraNewsFeed),
//  bundle image "TerraHero" overrides it; procedural art while loading/offline.
//  ObjC entry: @objc(TerraLauncherRootHost) +makeHost (SceneDelegate).
//  ===========================================================================
import SwiftUI
import UIKit

// MARK: - Navigation models

/// Top tabs inside the "MINECRAFT: JAVA EDITION" page
enum TerraTab: String, CaseIterable, Identifiable {
    case play, installations, download, patchNotes
    var id: String { rawValue }

    var title: String {
        switch self {
        case .play: return "Play"
        case .installations: return "Installations"
        case .download: return "Download Center"
        case .patchNotes: return "Patch notes"
        }
    }
}

/// Left sidebar sections
enum TerraSection: String, CaseIterable, Identifiable {
    case news, java, settings
    var id: String { rawValue }
}

// MARK: - Root view

struct TerraRootView: View {
    @State private var booted = false
    @State private var section: TerraSection = .java
    @State private var tab: TerraTab = .play
    @State private var dashReveal = false
    @StateObject private var model = TerraLauncherModel()

    var body: some View {
        ZStack {
            MCT.obsidian.ignoresSafeArea()

            if booted {
                mainInterface
                    .opacity(dashReveal ? 1 : 0)
                    .scaleEffect(dashReveal ? 1.0 : 0.985)
            } else {
                TerraBootSplash { finishBoot() }
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.35), value: booted)
        // Prefetch news + pick the hero artwork while the splash is showing
        .task { await TerraNewsFeed.shared.load() }
    }

    private func finishBoot() {
        withAnimation(.easeOut(duration: 0.3)) { booted = true }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.1)) {
            dashReveal = true
        }
    }

    // MARK: Main interface

    private var mainInterface: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 640
            HStack(spacing: 0) {
                TerraSidebar(section: $section, tab: $tab, model: model,
                             compact: compact,
                             width: compact ? 72 : (geo.size.width < 1000 ? 214 : 260))
                contentArea
            }
        }
        .environmentObject(model)
        .alert("Pick a Minecraft version first",
               isPresented: Binding(get: { model.missingVersionInstance != nil },
                                    set: { if !$0 { model.missingVersionInstance = nil } })) {
            Button("Open Download Center") {
                section = .java
                tab = .download
                model.missingVersionInstance = nil
            }
            Button("Cancel", role: .cancel) { model.missingVersionInstance = nil }
        } message: {
            Text("\"\(model.missingVersionInstance ?? "This installation")\" doesn't have a Minecraft version installed yet. Install one from the Download Center, then press Play.")
        }
    }

    /// Content: one NavigationStack (no legacy root controllers underneath)
    private var contentArea: some View {
        NavigationStack {
            ZStack {
                MCT.obsidian.ignoresSafeArea()
                switch section {
                case .settings:
                    TerraSettingsScreen()
                case .news:
                    TerraNewsScreen()
                case .java:
                    VStack(spacing: 0) {
                        TerraProductHeader(tab: $tab)
                        switch tab {
                        case .play: TerraPlayDashboard()
                        case .installations: TerraInstancesScreen()
                        case .download: TerraDownloadCenterScreen()
                        case .patchNotes: TerraPatchNotesScreen()
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Pixel block icons (original art, drawn in code)

/// Small block-style tile used for sidebar / version icons.
struct TerraBlockIcon: View {
    enum Kind { case grass, news, settings, forge, fabric }
    let kind: Kind
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            switch kind {
            case .grass:
                grassBlock
            case .news:
                tile(Color(white: 0.86), symbol: "newspaper.fill", tint: Color(white: 0.35))
            case .settings:
                tile(Color.clear, symbol: "slider.vertical.3", tint: .white)
            case .forge:
                tile(Color(red: 0.16, green: 0.18, blue: 0.24), symbol: "hammer.fill", tint: .white)
            case .fabric:
                tile(Color(red: 0.86, green: 0.80, blue: 0.66), symbol: "puzzlepiece.fill",
                     tint: Color(red: 0.36, green: 0.30, blue: 0.22))
            }
        }
        .frame(width: size, height: size)
    }

    private func tile(_ bg: Color, symbol: String, tint: Color) -> some View {
        Rectangle()
            .fill(bg)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }

    /// Grass block: green cap with ragged edge over speckled dirt (4×4 grid).
    private var grassBlock: some View {
        let dirt = [Color(red: 0.52, green: 0.36, blue: 0.24),
                    Color(red: 0.44, green: 0.30, blue: 0.20),
                    Color(red: 0.60, green: 0.43, blue: 0.29)]
        let grass = [Color(red: 0.38, green: 0.62, blue: 0.24),
                     Color(red: 0.32, green: 0.54, blue: 0.20)]
        // 0 = grass, 1..3 = dirt shades
        let grid: [[Int]] = [[0, 0, 0, 0],
                             [0, 1, 0, 2],
                             [3, 2, 1, 2],
                             [2, 1, 3, 1]]
        return VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { c in
                        let v = grid[r][c]
                        Rectangle().fill(v == 0 ? grass[(r + c) % 2] : dirt[v - 1])
                    }
                }
            }
        }
    }
}

// MARK: - Left sidebar (official desktop style)

private struct TerraSidebar: View {
    @Binding var section: TerraSection
    @Binding var tab: TerraTab
    @ObservedObject var model: TerraLauncherModel
    let compact: Bool
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            accountHeader
                .padding(.top, 18)
                .padding(.bottom, 26)

            TerraSidebarItem(icon: .news, caption: nil, title: "News",
                             selected: section == .news, compact: compact) {
                section = .news
            }
            TerraSidebarItem(icon: .grass, caption: "MINECRAFT:", title: "Java Edition",
                             selected: section == .java, compact: compact) {
                section = .java
                tab = .play
            }

            Spacer()

            TerraSidebarItem(icon: .settings, caption: nil, title: "Settings",
                             selected: section == .settings, compact: compact) {
                section = .settings
            }
            .padding(.bottom, 18)
        }
        .frame(width: width)
        .background(MCT.charcoal.ignoresSafeArea())
    }

    /// Avatar + username + "Microsoft account" + chevron (opens account list)
    private var accountHeader: some View {
        Button {
            model.openAccount()
        } label: {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(MCT.green)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    )
                if !compact {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.username)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(MCT.text)
                            .lineLimit(1)
                        Text("Minecraft account")
                            .font(.system(size: 13))
                            .foregroundStyle(MCT.dim)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MCT.text)
                }
            }
            .padding(.horizontal, compact ? 16 : 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Sidebar item: block icon + (caption / title); selected = white bar at the left edge
private struct TerraSidebarItem: View {
    let icon: TerraBlockIcon.Kind
    let caption: String?
    let title: String
    let selected: Bool
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                TerraBlockIcon(kind: icon, size: 40)
                if !compact {
                    VStack(alignment: .leading, spacing: 0) {
                        if let caption {
                            Text(caption)
                                .font(.system(size: 13, weight: selected ? .bold : .regular))
                                .foregroundStyle(MCT.text)
                        }
                        Text(title)
                            .font(.system(size: 18, weight: selected ? .bold : .regular))
                            .foregroundStyle(MCT.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, compact ? 16 : 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) {
                Rectangle()
                    .fill(selected ? Color.white : Color.clear)
                    .frame(width: 4, height: 30)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Product header (title + tabs)

private struct TerraProductHeader: View {
    @Binding var tab: TerraTab

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MINECRAFT: JAVA EDITION")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(MCT.text)
                .padding(.top, 26)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 34) {
                    ForEach(TerraTab.allCases) { item in
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { tab = item }
                        } label: {
                            VStack(spacing: 8) {
                                Text(item.title)
                                    .font(.system(size: 18, weight: tab == item ? .bold : .regular))
                                    .foregroundStyle(tab == item ? MCT.text : MCT.dim)
                                Rectangle()
                                    .fill(tab == item ? MCT.green : Color.clear)
                                    .frame(width: 36, height: 3)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MCT.charcoal)
    }
}

// MARK: - Boot splash

struct TerraBootSplash: View {
    /// Called once when the boot sequence finishes
    let onFinish: () -> Void

    @State private var progress: Double = 0
    @State private var logoPulse = false
    @State private var appeared = false
    @State private var hasFinished = false

    var body: some View {
        ZStack {
            MCT.obsidian.ignoresSafeArea()

            VStack(spacing: 30) {
                TerraBlockIcon(kind: .grass, size: 92)
                    .shadow(color: MCT.greenBright.opacity(logoPulse ? 0.55 : 0.15),
                            radius: logoPulse ? 26 : 8)
                    .scaleEffect(logoPulse ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                               value: logoPulse)

                VStack(spacing: 6) {
                    Text("TERRA")
                        .font(.system(size: 34, weight: .heavy))
                        .tracking(10)
                        .foregroundStyle(MCT.text)
                    Text("LAUNCHER")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(4)
                        .foregroundStyle(MCT.dim)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.1))
                        Rectangle()
                            .fill(MCT.green)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(width: 220, height: 4)
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.96)
        }
        .onAppear { runSequence() }
    }

    private func runSequence() {
        withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        logoPulse = true
        withAnimation(.easeInOut(duration: 1.8).delay(0.3)) { progress = 1.0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
            guard !hasFinished else { return }
            hasFinished = true
            withAnimation(.easeIn(duration: 0.25)) { appeared = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onFinish() }
        }
    }
}

// MARK: - PLAY dashboard

struct TerraPlayDashboard: View {
    @EnvironmentObject private var model: TerraLauncherModel
    @ObservedObject private var feed = TerraNewsFeed.shared
    /// JIT is often turned on (StikDebug / SideStore) while the app is open ⇒ poll it
    private let jitTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private let barHeight: CGFloat = 84

    var body: some View {
        GeometryReader { geo in
            // Hero fills the visible area above the play bar (official proportions ~0.46)
            let heroHeight = max(180, min(geo.size.width * 0.46, geo.size.height - barHeight))
            ScrollView {
                VStack(spacing: 0) {
                    TerraHeroArt()
                        .frame(height: heroHeight)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    playBar(width: geo.size.width)
                    newsSection
                }
            }
        }
        .onAppear { model.refreshJIT() }
        .onReceive(jitTimer) { _ in model.refreshJIT() }
    }

    // MARK: Play bar (version selector · PLAY · username)

    private func playBar(width: CGFloat) -> some View {
        ZStack {
            MCT.elevated
            HStack {
                TerraVersionSelector()
                Spacer()
                if width >= 760 {
                    Text(model.username)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MCT.text)
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .frame(minWidth: 110, minHeight: 50)
                        .background(Rectangle().fill(MCT.obsidian))
                        .overlay(Rectangle().strokeBorder(MCT.border, lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)

            // PLAY straddles the hero's bottom edge
            Button("PLAY") { model.launch(model.selected) }
                .buttonStyle(TerraPlayButtonStyle(width: min(380, max(200, width * 0.3))))
                .offset(y: -24)

            // JIT status, just above PLAY on the banner's bottom edge (tap to re-check).
            // Above rather than below so it never collides with the installation picker
            // on narrow (iPhone landscape) widths.
            TerraJITStatus(state: model.jitState, label: model.jitLabel)
                .onTapGesture { model.refreshJIT() }
                .offset(y: -68)
        }
        .frame(height: barHeight)
        .zIndex(1)
    }

    // MARK: News

    private var newsSection: some View {
        TerraNewsList(feed: feed, entries: feed.javaEntries, limit: 6)
        .frame(maxWidth: 1000)
        .padding(.horizontal, 36)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .background(MCT.charcoal)
    }
}

/// Small "● JIT: Enabled" capsule shown just above the PLAY button.
struct TerraJITStatus: View {
    let state: TerraLauncherModel.JITState
    let label: String

    private var color: Color {
        switch state {
        case .enabled: return MCT.greenBright
        case .pending: return Color(red: 0.95, green: 0.75, blue: 0.2)
        case .disabled: return MCT.danger
        case .unknown: return MCT.dim
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label.isEmpty ? "JIT: Checking…" : label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.6)))
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Tap to check again")
    }
}

/// Official-style PLAY button: flat green face, bright top bevel, dark bottom bevel, black outline.
struct TerraPlayButtonStyle: ButtonStyle {
    var width: CGFloat = 300

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.system(size: 28, weight: .heavy, design: .monospaced))
            .tracking(3)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 0, x: 2, y: 2)
            .frame(width: width, height: 62)
            .background(
                ZStack {
                    Rectangle().fill(pressed ? MCT.greenDark : MCT.green)
                    VStack(spacing: 0) {
                        Rectangle().fill(pressed ? Color.clear : MCT.greenBright).frame(height: 4)
                        Spacer()
                        Rectangle().fill(MCT.greenDark).frame(height: pressed ? 0 : 5)
                    }
                }
            )
            .overlay(Rectangle().strokeBorder(Color(red: 0.12, green: 0.12, blue: 0.12), lineWidth: 3))
            .offset(y: pressed ? 2 : 0)
    }
}

/// Installation picker (bottom-left of the play bar)
private struct TerraVersionSelector: View {
    @EnvironmentObject private var model: TerraLauncherModel

    var body: some View {
        let instance = model.selected
        Menu {
            ForEach(model.instances) { inst in
                Button {
                    model.selectInstance(inst)
                } label: {
                    if inst.name == model.selectedName {
                        Label("\(inst.name) — \(inst.version)", systemImage: "checkmark")
                    } else {
                        Text("\(inst.name) — \(inst.version)")
                    }
                }
            }
            if model.instances.isEmpty {
                Text("No installations yet")
            }
        } label: {
            HStack(spacing: 12) {
                TerraBlockIcon(kind: iconKind(instance), size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(instance?.name ?? "No installation")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(MCT.text)
                        .lineLimit(1)
                    Text(instance?.version ?? "Open the Download Center")
                        .font(.system(size: 13))
                        .foregroundStyle(MCT.dim)
                        .lineLimit(1)
                }
                .frame(maxWidth: 180, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MCT.text)
            }
            .padding(6)
            .contentShape(Rectangle())
        }
    }

    private func iconKind(_ inst: TerraInstance?) -> TerraBlockIcon.Kind {
        switch inst?.loader.lowercased() {
        case "fabric": return .fabric
        case "forge": return .forge
        default: return .grass
        }
    }
}

// MARK: - Hero art

/// Priority: bundle image "TerraHero" (user override) → random official Java news
/// artwork from the launcher content feed → procedural art (loading / offline).
struct TerraHeroArt: View {
    @ObservedObject private var feed = TerraNewsFeed.shared

    var body: some View {
        if let image = UIImage(named: "TerraHero") {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                procedural
                if let url = feed.heroURL {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.5))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill().transition(.opacity)
                        } else {
                            Color.clear
                        }
                    }
                }
            }
        }
    }

    private var procedural: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(red: 0.22, green: 0.04, blue: 0.04),
                                        Color(red: 0.50, green: 0.12, blue: 0.06),
                                        Color(red: 0.30, green: 0.06, blue: 0.05)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color.orange.opacity(0.65), .clear],
                               center: UnitPoint(x: 0.55, y: 0.55), startRadius: 4,
                               endRadius: geo.size.width * 0.35)
                RadialGradient(colors: [Color(red: 0.1, green: 0.85, blue: 0.75).opacity(0.55), .clear],
                               center: UnitPoint(x: 0.08, y: 0.95), startRadius: 4,
                               endRadius: geo.size.width * 0.28)
                RadialGradient(colors: [Color(red: 0.1, green: 0.85, blue: 0.75).opacity(0.4), .clear],
                               center: UnitPoint(x: 0.95, y: 0.9), startRadius: 4,
                               endRadius: geo.size.width * 0.22)
                pixelTerrain(size: geo.size)
                lavaFalls(size: geo.size)

                VStack(spacing: 2) {
                    Text("MINECRAFT")
                        .font(.system(size: min(64, geo.size.width * 0.06), weight: .black, design: .monospaced))
                    Text("JAVA EDITION")
                        .font(.system(size: min(30, geo.size.width * 0.028), weight: .heavy, design: .monospaced))
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 0, x: 3, y: 3)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.2)
            }
        }
    }

    /// Deterministic blocky silhouettes along both sides and the floor
    private func pixelTerrain(size: CGSize) -> some View {
        let cell = max(18, size.width / 40)
        let cols = Int(size.width / cell) + 1
        return Canvas { ctx, _ in
            for c in 0..<cols {
                let x = CGFloat(c) * cell
                // edge distance → taller columns near the sides
                let edge = min(c, cols - 1 - c)
                let base = edge < 6 ? (6 - edge) * 3 : 1
                let h = base + (c * 7 + 3) % 4
                for r in 0..<h {
                    let y = size.height - CGFloat(r + 1) * cell
                    let shade = Double((c * 13 + r * 7) % 5) * 0.03
                    ctx.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)),
                             with: .color(Color(red: 0.16 + shade, green: 0.04, blue: 0.05)))
                }
            }
        }
    }

    private func lavaFalls(size: CGSize) -> some View {
        let w = max(10, size.width / 70)
        return ZStack {
            ForEach([0.3, 0.41, 0.66, 0.78], id: \.self) { fx in
                Rectangle()
                    .fill(LinearGradient(colors: [Color.yellow.opacity(0.9), Color.orange, Color.red.opacity(0.6)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: w, height: size.height * 0.75)
                    .position(x: size.width * fx, y: size.height * 0.375)
                    .blur(radius: 0.5)
            }
        }
    }
}

// MARK: - Patch notes

struct TerraPatchNotesScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TerraPatchCard(version: "Terra-iOS Launcher", date: "Latest",
                               lines: ["Redesigned launcher in the official desktop layout.",
                                       "Installations, Download Center and one-tap Optimization Pack.",
                                       "Boot animation and single NavigationStack routing."])
                TerraPatchCard(version: "Minecraft: Java Edition", date: "Release",
                               lines: ["Game files are fetched and verified automatically on first launch",
                                       "via the built-in download pipeline for the selected installation."])
                Spacer(minLength: 28)
            }
            .padding(.horizontal, 36)
            .padding(.top, 22)
        }
    }
}

struct TerraPatchCard: View {
    let version: String
    let date: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(version)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MCT.text)
                Spacer()
                Text(date)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MCT.dim)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle().fill(MCT.green).frame(width: 5, height: 5).padding(.top, 6)
                        Text(line)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MCT.dim)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mcSurface()
    }
}

// MARK: - ObjC entry point

private final class TerraHostingController: UIHostingController<TerraRootView> {
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}

/// The only entry used by SceneDelegate:
///   UIViewController *root = [TerraLauncherRootHost makeHost];
@objc(TerraLauncherRootHost)
public final class TerraLauncherRootHost: NSObject {
    @objc(makeHost)
    public static func makeHost() -> UIViewController {
        let hosting = TerraHostingController(rootView: TerraRootView())
        hosting.view.backgroundColor = UIColor(red: 0x1E/255.0, green: 0x1E/255.0, blue: 0x1E/255.0, alpha: 1)
        // Attach the ObjC bridge (launch pipeline + instance scan) to this root VC
        TerraBridge.service?.attach(toRoot: hosting)
        return hosting
    }
}
