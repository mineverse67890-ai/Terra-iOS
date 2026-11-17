// ===========================================================================
//  ★ [TERRA-UI] DownloadCenterView.swift —— Download Center
//  ---------------------------------------------------------------------------
//  Header: title + Competitive Download + Potato Optimize (one-tap Modrinth sets,
//  TerraPotatoOptimizer). Segmented: Minecraft Versions | Mods & More.
//    · Minecraft Versions: version_manifest_v2 (official ↔ BMCLAPI fallback),
//      Release / Snapshot / Old filter, search, grouped by major version, clear
//      install state (which loaders are already installed). Install opens the
//      loader picker (Vanilla / Fabric / Forge / NeoForge / Quilt) through
//      TerraVersionInstaller, which runs the same install path as the legacy UI.
//    · Mods & More: TerraBrowseViewController (UIKit, Modrinth/CurseForge browser)
//      embedded with UIViewControllerRepresentable.
//  ObjC is reached via NSClassFromString + perform (no bridging header).
//  ===========================================================================
import SwiftUI
import UIKit

// MARK: - ObjC bridge

enum DownloadCenterBridge {
    /// Calls a class method `+sel:with:` on an ObjC class looked up by name.
    static func callClass(_ className: String, _ selector: String, _ first: Any?, _ second: Any?) {
        guard let cls = NSClassFromString(className),
              let obj = (cls as AnyObject) as? NSObjectProtocol else { return }
        let sel = NSSelectorFromString(selector)
        guard obj.responds(to: sel) else { return }
        _ = obj.perform(sel, with: first, with: second)
    }

    /// Top-most presented view controller of the key window.
    static func presenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        var vc = window?.rootViewController
        while let next = vc?.presentedViewController, !next.isBeingDismissed { vc = next }
        return vc
    }

    static func potatoOptimize(_ profile: String?) {
        callClass("TerraPotatoOptimizer", "optimizeProfile:presenter:", profile as NSString?, presenter())
    }

    static func competitiveDownload(_ profile: String?) {
        callClass("TerraPotatoOptimizer", "competitiveProfile:presenter:", profile as NSString?, presenter())
    }

    static func installVersion(_ versionId: String) {
        callClass("TerraVersionInstaller", "presentInstallForVersion:from:", versionId as NSString, presenter())
    }
}

// MARK: - Minecraft-style bevelled button

struct DCBlockButtonStyle: ButtonStyle {
    var primary = true

    func makeBody(configuration: Configuration) -> some View {
        let face = primary ? MCT.green : Color(white: 0x48 / 255.0)
        let top = primary ? MCT.greenBright : Color(white: 0x6A / 255.0)
        let bottom = primary ? MCT.greenDark : Color(white: 0x2C / 255.0)
        let down = configuration.isPressed
        return configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, 11)
            .background(
                ZStack(alignment: .top) {
                    Rectangle().fill(down ? bottom : face)
                    if !down {
                        Rectangle().fill(top).frame(height: 3)
                        VStack { Spacer(); Rectangle().fill(bottom).frame(height: 4) }
                    }
                }
            )
            .overlay(Rectangle().strokeBorder(Color(white: 0x12 / 255.0), lineWidth: 2))
    }
}

// MARK: - Download Center screen

struct TerraDownloadCenterScreen: View {
    @EnvironmentObject private var model: TerraLauncherModel
    @State private var segment = 0
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let segments: [(String, String)] = [
        ("Minecraft Versions", "cube.fill"),
        ("Mods & More", "puzzlepiece.extension.fill"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 18)
            segmentPicker
                .padding(.horizontal, 28)
                .padding(.top, 14)
                .padding(.bottom, 4)

            if segment == 0 {
                TerraVersionsPane()
            } else {
                TerraBrowseHost(profileName: model.selected?.name)
                    .padding(.horizontal, 12)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DOWNLOAD CENTER")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2.4)
                    .foregroundStyle(MCT.greenBright)
                Text("Minecraft, mods & more")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(MCT.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let sel = model.selected {
                    Text("Installing into \(sel.name) · \(sel.version)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MCT.dim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            let compact = sizeClass == .compact
            Button {
                DownloadCenterBridge.competitiveDownload(model.selected?.name)
            } label: {
                Label(compact ? "" : "Competitive Download", systemImage: "trophy.fill")
                    .labelStyle(TerraIconFirstLabel())
            }
            .buttonStyle(DCBlockButtonStyle(primary: false))
            .accessibilityLabel("Competitive Download")

            Button {
                DownloadCenterBridge.potatoOptimize(model.selected?.name)
            } label: {
                Label(compact ? "" : "Potato Optimize", systemImage: "bolt.fill")
                    .labelStyle(TerraIconFirstLabel())
            }
            .buttonStyle(DCBlockButtonStyle(primary: true))
            .accessibilityLabel("Potato Optimize")
        }
    }

    private var segmentPicker: some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { i, item in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { segment = i }
                } label: {
                    Label(item.0, systemImage: item.1)
                        .labelStyle(TerraIconFirstLabel())
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(segment == i ? MCT.text : MCT.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(segment == i ? MCT.elevated : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(MCT.charcoal)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(MCT.border, lineWidth: 1))
        )
    }
}

// MARK: - Mods & More (UIKit browser)

struct TerraBrowseHost: UIViewControllerRepresentable {
    let profileName: String?

    func makeUIViewController(context: Context) -> UIViewController {
        guard let cls = NSClassFromString("TerraBrowseViewController") as? UIViewController.Type else {
            let fallback = UIHostingController(rootView:
                Text("The mod browser isn't available in this build.")
                    .foregroundStyle(MCT.dim))
            fallback.view.backgroundColor = .clear
            return fallback
        }
        let vc = cls.init()
        // The SwiftUI header already shows Potato Optimize / Competitive Download.
        if vc.responds(to: NSSelectorFromString("setShowsOptimizeButtons:")) {
            vc.setValue(false, forKey: "showsOptimizeButtons")
        }
        apply(profileName, to: vc)
        context.coordinator.lastProfile = profileName
        return vc
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        guard context.coordinator.lastProfile != profileName else { return }
        context.coordinator.lastProfile = profileName
        apply(profileName, to: vc)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastProfile: String?
    }

    private func apply(_ profile: String?, to vc: UIViewController) {
        guard let profile, !profile.isEmpty,
              vc.responds(to: NSSelectorFromString("setProfileName:")) else { return }
        vc.setValue(profile, forKey: "profileName")
    }
}

// MARK: - Versions pane

struct MinecraftManifestVersion: Identifiable, Decodable, Equatable {
    let id: String
    let type: String
    let url: String
    let releaseTime: String?

    var isRelease: Bool { type == "release" }
    var isSnapshot: Bool { type == "snapshot" }
    var isOld: Bool { type == "old_beta" || type == "old_alpha" }

    var releaseDate: Date? {
        guard let releaseTime else { return nil }
        return ISO8601DateFormatter().date(from: releaseTime)
    }

    /// "1.21.4" → "1.21", snapshots by year, old versions by Beta/Alpha
    var groupKey: String {
        if isRelease {
            let parts = id.split(separator: ".")
            return parts.count >= 2 ? "\(parts[0]).\(parts[1])" : id
        }
        if isSnapshot { return "Snapshots \(releaseTime?.prefix(4) ?? "")" }
        return type == "old_beta" ? "Beta" : "Alpha"
    }
}

enum VersionKindFilter: String, CaseIterable, Identifiable {
    case release = "Release", snapshot = "Snapshot", old = "Old"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .release: return "checkmark.seal.fill"
        case .snapshot: return "flask.fill"
        case .old: return "clock.arrow.circlepath"
        }
    }
    func matches(_ v: MinecraftManifestVersion) -> Bool {
        switch self {
        case .release: return v.isRelease
        case .snapshot: return v.isSnapshot
        case .old: return v.isOld
        }
    }
}

/// What is already installed for a Minecraft version: "Vanilla", "Fabric", "Forge"…
enum InstalledVersionScanner {
    static func scan() -> [String: [String]] {
        guard let raw = getenv("POJAV_GAME_DIR") else { return [:] }
        let versionsDir = (String(cString: raw) as NSString).appendingPathComponent("versions")
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(atPath: versionsDir) else { return [:] }
        var result: [String: [String]] = [:]
        for dir in dirs {
            let jsonPath = ((versionsDir as NSString).appendingPathComponent(dir) as NSString)
                .appendingPathComponent("\(dir).json")
            guard let data = fm.contents(atPath: jsonPath),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let text = (String(data: data, encoding: .utf8) ?? "").lowercased()
            let base = (obj["inheritsFrom"] as? String) ?? dir
            var loader = "Vanilla"
            if text.contains("net.neoforged") { loader = "NeoForge" }
            else if text.contains("org.quiltmc:quilt-loader") { loader = "Quilt" }
            else if text.contains("net.fabricmc:fabric-loader") { loader = "Fabric" }
            else if text.contains("net.minecraftforge") { loader = "Forge" }
            else if obj["inheritsFrom"] != nil { loader = "Modded" }
            var list = result[base] ?? []
            if !list.contains(loader) { list.append(loader) }
            result[base] = list
        }
        return result
    }
}

struct TerraVersionsPane: View {
    @EnvironmentObject private var model: TerraLauncherModel

    @State private var versions: [MinecraftManifestVersion] = []
    @State private var latestRelease: String?
    @State private var latestSnapshot: String?
    @State private var searchText = ""
    @State private var kind: VersionKindFilter = .release
    @State private var loading = false
    @State private var errorText: String?
    @State private var installed: [String: [String]] = [:]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private var filtered: [MinecraftManifestVersion] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        return versions.filter { v in
            (q.isEmpty ? kind.matches(v) : true) &&
            (q.isEmpty || v.id.localizedCaseInsensitiveContains(q))
        }
    }

    /// Ordered groups preserving manifest order (newest first)
    private var groups: [(key: String, items: [MinecraftManifestVersion])] {
        var order: [String] = []
        var map: [String: [MinecraftManifestVersion]] = [:]
        for v in filtered {
            let key = v.groupKey
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(v)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                controls
                    .padding(.top, 12)

                if loading && versions.isEmpty {
                    ForEach(0..<6, id: \.self) { _ in skeletonRow }
                } else if let errorText, versions.isEmpty {
                    errorCard(errorText)
                } else {
                    if searchText.isEmpty, kind == .release, let latest = latestRelease,
                       let v = versions.first(where: { $0.id == latest }) {
                        latestCard(v, snapshot: latestSnapshot.flatMap { s in versions.first { $0.id == s } })
                    }
                    if filtered.isEmpty {
                        emptyCard
                    }
                    ForEach(groups, id: \.key) { group in
                        Section {
                            ForEach(group.items) { v in versionRow(v) }
                        } header: {
                            sectionHeader(group.key, count: group.items.count)
                        }
                    }
                }
                Spacer(minLength: 28)
            }
            .padding(.horizontal, 28)
        }
        .task { if versions.isEmpty { await loadManifest() } }
        .onAppear { rescanInstalled() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TerraInstancesChanged"))) { _ in rescanInstalled() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ReloadProfileList"))) { _ in rescanInstalled() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TerraVersionInstallerDidFinishNotification"))) { _ in
            rescanInstalled()
            model.refresh()
        }
    }

    // MARK: Pieces

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MCT.dim)
                TextField("Search all versions (e.g. 1.20.1)", text: $searchText)
                    .font(.system(size: 14))
                    .foregroundStyle(MCT.text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(MCT.dim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MCT.charcoal)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(MCT.border, lineWidth: 1))
            )

            HStack(spacing: 8) {
                ForEach(VersionKindFilter.allCases) { k in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { kind = k }
                    } label: {
                        Label(k.rawValue, systemImage: k.symbol)
                            .labelStyle(TerraIconFirstLabel())
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(kind == k ? Color.white : MCT.dim)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(kind == k ? MCT.green : MCT.elevated))
                    }
                    .buttonStyle(.plain)
                    .disabled(!searchText.isEmpty)
                    .opacity(searchText.isEmpty ? 1 : 0.5)
                }
                Spacer()
                Text("\(filtered.count) versions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MCT.dim)
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title.hasPrefix("1.") ? "Minecraft \(title)" : title)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(MCT.text)
            Text("\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(MCT.dim)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(MCT.elevated))
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.top, 6)
        .background(MCT.obsidian.opacity(0.97))
    }

    private func latestCard(_ v: MinecraftManifestVersion, snapshot: MinecraftManifestVersion?) -> some View {
        HStack(spacing: 16) {
            TerraGrassIcon(size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("LATEST RELEASE")
                    .font(.system(size: 10.5, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(MCT.greenBright)
                Text("Minecraft \(v.id)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(MCT.text)
                if let snapshot {
                    Text("Latest snapshot: \(snapshot.id)")
                        .font(.system(size: 12))
                        .foregroundStyle(MCT.dim)
                }
            }
            Spacer()
            installControl(v, prominent: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [MCT.green.opacity(0.22), MCT.charcoal],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(MCT.green.opacity(0.45), lineWidth: 1))
        )
        .padding(.bottom, 4)
    }

    private func versionRow(_ v: MinecraftManifestVersion) -> some View {
        let loaders = installed[v.id] ?? []
        return HStack(spacing: 14) {
            Image(systemName: v.isRelease ? "cube.fill" : (v.isSnapshot ? "flask.fill" : "clock.fill"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(v.isRelease ? MCT.greenBright : MCT.dim)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(MCT.elevated))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(v.id)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(MCT.text)
                    typeBadge(v)
                }
                HStack(spacing: 6) {
                    if let date = v.releaseDate {
                        Text(Self.dateFormatter.string(from: date))
                            .font(.system(size: 11.5))
                            .foregroundStyle(MCT.dim)
                    }
                    ForEach(loaders, id: \.self) { l in
                        Label(l, systemImage: "checkmark")
                            .labelStyle(TerraIconFirstLabel())
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(MCT.greenBright)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(MCT.green.opacity(0.18)))
                    }
                }
            }
            Spacer()
            installControl(v, prominent: false)
        }
        .padding(12)
        .mcSurface(radius: 10)
    }

    @ViewBuilder
    private func installControl(_ v: MinecraftManifestVersion, prominent: Bool) -> some View {
        let isInstalled = !(installed[v.id] ?? []).isEmpty
        Button {
            DownloadCenterBridge.installVersion(v.id)
        } label: {
            Label(isInstalled ? "Add loader" : "Install",
                  systemImage: isInstalled ? "plus" : "arrow.down")
                .labelStyle(TerraIconFirstLabel())
        }
        .buttonStyle(DCBlockButtonStyle(primary: !isInstalled || prominent))
    }

    private func typeBadge(_ v: MinecraftManifestVersion) -> some View {
        let text: String
        switch v.type {
        case "release": text = "RELEASE"
        case "snapshot": text = "SNAPSHOT"
        case "old_beta": text = "BETA"
        default: text = "ALPHA"
        }
        return Text(text)
            .font(.system(size: 9.5, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(v.isRelease ? MCT.greenBright : MCT.dim)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(v.isRelease ? MCT.green.opacity(0.2) : Color.white.opacity(0.08)))
    }

    private var skeletonRow: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8).fill(MCT.elevated).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(MCT.elevated).frame(width: 120, height: 13)
                RoundedRectangle(cornerRadius: 4).fill(MCT.elevated).frame(width: 80, height: 10)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 4).fill(MCT.elevated).frame(width: 86, height: 34)
        }
        .padding(12)
        .mcSurface(radius: 10)
        .redacted(reason: .placeholder)
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(MCT.dim)
            Text("No versions match \"\(searchText)\"")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(MCT.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func errorCard(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(MCT.dim)
            Text("Couldn't load the version list")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(MCT.text)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(MCT.dim)
                .multilineTextAlignment(.center)
            Button {
                Task { await loadManifest() }
            } label: {
                Label("Try again", systemImage: "arrow.clockwise").labelStyle(TerraIconFirstLabel())
            }
            .buttonStyle(DCBlockButtonStyle(primary: true))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: Data

    private func rescanInstalled() {
        Task.detached(priority: .userInitiated) {
            let result = InstalledVersionScanner.scan()
            await MainActor.run { installed = result }
        }
    }

    private func loadManifest() async {
        loading = true
        errorText = nil
        let official = "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
        let mirror = "https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json"
        let urls = model.downloadSource == "bmclapi" ? [mirror, official] : [official, mirror]
        struct Manifest: Decodable {
            struct Latest: Decodable { let release: String; let snapshot: String }
            let latest: Latest?
            let versions: [MinecraftManifestVersion]
        }
        var lastError: Error?
        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                let manifest = try JSONDecoder().decode(Manifest.self, from: data)
                versions = manifest.versions
                latestRelease = manifest.latest?.release
                latestSnapshot = manifest.latest?.snapshot
                loading = false
                return
            } catch {
                lastError = error
            }
        }
        errorText = lastError?.localizedDescription ?? "Check your internet connection and try again."
        loading = false
    }
}

// MARK: - Grass block icon (4×4 pixels, same art as TerraStyle grassBlockOfSize:)

struct TerraGrassIcon: View {
    var size: CGFloat = 40
    private let grid: [[Int]] = [[0, 0, 0, 0], [0, 1, 0, 2], [3, 2, 1, 2], [2, 1, 3, 1]]
    private let dirt: [Color] = [Color(red: 0.52, green: 0.36, blue: 0.24),
                                 Color(red: 0.44, green: 0.30, blue: 0.20),
                                 Color(red: 0.60, green: 0.43, blue: 0.29)]
    private let grass: [Color] = [Color(red: 0.38, green: 0.62, blue: 0.24),
                                  Color(red: 0.32, green: 0.54, blue: 0.20)]

    var body: some View {
        let cell = size / 4
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { c in
                        let v = grid[r][c]
                        Rectangle()
                            .fill(v == 0 ? grass[(r + c) % 2] : dirt[v - 1])
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}
