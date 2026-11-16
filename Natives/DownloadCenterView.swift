// ===========================================================================
//  ★ [TERRA-UI] DownloadCenterView.swift —— Download Center (official replica)
//  ---------------------------------------------------------------------------
//  Segmented picker: Minecraft Versions | Fabric Mods
//    · Versions pane: version_manifest_v2 (Mojang / bmclapi per preference),
//      dark cards with one-click Install (creates the installation profile;
//      game files are fetched by the existing launch pipeline on first play).
//    · Mods pane: Modrinth API search (debounced), dark cards with real-time
//      download progress; "One-Click Optimization Pack" = Sodium + Lithium +
//      FerriteCore → selected installation /mods directory.
//  ===========================================================================
import SwiftUI

// MARK: - Modrinth client

struct ModrinthHit: Identifiable, Decodable {
    let projectId: String
    let title: String
    let description: String
    let author: String
    let downloads: Int
    let iconUrl: String?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case title, description, author, downloads
        case iconUrl = "icon_url"
    }

    var id: String { projectId }
    var downloadsText: String {
        if downloads >= 1_000_000 { return String(format: "%.1fM", Double(downloads) / 1_000_000) }
        if downloads >= 1_000 { return String(format: "%.1fK", Double(downloads) / 1_000) }
        return "(downloads)"
    }
}

struct ModrinthVersionFile: Decodable {
    let url: URL
    let filename: String
    let primary: Bool
    let size: Int
}

struct ModrinthVersion: Decodable {
    let files: [ModrinthVersionFile]
    var primaryFile: ModrinthVersionFile? { files.first(where: { $0.primary }) ?? files.first }
}

enum ModrinthClient {
    static func search(query: String, gameVersion: String?) async throws -> [ModrinthHit] {
        var facets: [[String]] = [["project_type:mod"], ["categories:fabric"]]
        if let gameVersion, !gameVersion.isEmpty { facets.append(["versions:(gameVersion)"]) }
        var comps = URLComponents(string: "https://api.modrinth.com/v2/search")!
        comps.queryItems = [
            .init(name: "limit", value: "25"),
            .init(name: "query", value: query),
            .init(name: "facets", value: toJson(facets)),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let decoded = try JSONDecoder().decode([String: [ModrinthHit]].self, from: data)
        return decoded["hits"] ?? []
    }

    /// Latest file of a project compatible with (fabric, gameVersion)
    static func latestCompatibleFile(projectId: String, gameVersion: String?) async throws -> ModrinthVersionFile? {
        var comps = URLComponents(string: "https://api.modrinth.com/v2/project/(projectId)/version")!
        comps.queryItems = [
            .init(name: "loaders", value: toJson(["fabric"])),
            .init(name: "game_versions", value: toJson(gameVersion.map { [$0] } ?? [])),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let versions = try JSONDecoder().decode([ModrinthVersion].self, from: data)
        return versions.first?.primaryFile
    }

    /// Download a file into a directory, reporting progress (0…1) on main queue
    static func download(file: ModrinthVersionFile, toDirectory dir: String,
                         progress: @escaping (Double) -> Void) async throws -> String {
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: file.url)
        let total = max(1, Int(response.expectedContentLength))
        var data = Data(capacity: total)
        var buffered = 0
        for try await byte in asyncBytes {
            data.append(byte)
            buffered += 1
            if buffered % 32768 == 0 {
                let p = min(1.0, Double(buffered) / Double(total))
                DispatchQueue.main.async { progress(p) }
            }
        }
        DispatchQueue.main.async { progress(1.0) }

        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        let destPath = (dir as NSString).appendingPathComponent(file.filename)
        try data.write(to: URL(fileURLWithPath: destPath), options: .atomic)
        return destPath
    }

    private static func toJson(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }
}

/// Download progress, held in one observed store so rows re-render live
enum ModDownloadPhase { case waiting, downloading, done, failed }

struct ModDownloadEntry {
    var progress: Double = 0
    var phase: ModDownloadPhase = .downloading
}

final class ModDownloadsStore: ObservableObject {
    @Published var entries: [String: ModDownloadEntry] = [:]
    func start(_ key: String) { entries[key] = ModDownloadEntry() }
    func progress(_ key: String, _ value: Double) { entries[key, default: .init()].progress = value }
    func finish(_ key: String, _ phase: ModDownloadPhase) {
        entries[key, default: .init()].phase = phase
        if phase == .done { entries[key]?.progress = 1 }
    }
}

// MARK: - Download Center screen

struct TerraDownloadCenterScreen: View {
    @State private var segment = 0
    private let segments = ["Minecraft Versions", "Fabric Mods"]

    var body: some View {
        VStack(spacing: 0) {
            // Header + segmented picker
            VStack(alignment: .leading, spacing: 14) {
                Text("DOWNLOAD CENTER")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2.4)
                    .foregroundStyle(MCT.greenBright)
                    .padding(.top, 18)

                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { i, title in
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) { segment = i }
                        } label: {
                            Text(title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(segment == i ? MCT.text : MCT.dim)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(segment == i ? MCT.elevated : Color.clear)
                                )
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
            .padding(.horizontal, 28)

            if segment == 0 {
                TerraVersionsPane()
            } else {
                TerraModsPane()
            }
        }
    }
}

// MARK: - Versions pane

struct MinecraftManifestVersion: Identifiable, Decodable {
    let id: String
    let type: String
    let url: String
}

struct TerraVersionsPane: View {
    @EnvironmentObject private var model: TerraLauncherModel

    @State private var versions: [MinecraftManifestVersion] = []
    @State private var searchText = ""
    @State private var typeFilter = "All"
    @State private var loading = false
    @State private var installing: Set<String> = []
    @State private var installedNames: Set<String> = []
    @State private var errorText: String?

    private let typeFilters = ["All", "release", "snapshot", "old_beta"]

    private var filtered: [MinecraftManifestVersion] {
        versions.filter { v in
            (typeFilter == "All" || v.type == typeFilter) &&
            (searchText.isEmpty || v.id.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MCT.dim)
                        TextField("Search versions (e.g. 1.20.1)", text: $searchText)
                            .font(.system(size: 14))
                            .foregroundStyle(MCT.text)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(MCT.charcoal)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(MCT.border, lineWidth: 1))
                    )

                    Menu {
                        ForEach(typeFilters, id: \.self) { f in
                            Button(f) { typeFilter = f }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(typeFilter)
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(MCT.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(MCT.elevated)
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(MCT.border, lineWidth: 1))
                        )
                    }
                }
                .padding(.top, 16)

                if loading && versions.isEmpty {
                    ProgressView()
                        .tint(MCT.greenBright)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if let errorText {
                    Text(errorText)
                        .font(.system(size: 12))
                        .foregroundStyle(MCT.danger)
                        .padding(.vertical, 20)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered.prefix(120)) { v in
                            versionRow(v)
                        }
                    }
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 28)
        }
        .task { await loadManifest() }
        .onAppear { installedNames = Set(model.instances.map(\.name)) }
    }


    private func versionRow(_ v: MinecraftManifestVersion) -> some View {
        let isInstalled = installedNames.contains(v.id)
        let isInstalling = installing.contains(v.id)
        return HStack(spacing: 14) {
            Image(systemName: v.type == "release" ? "checkmark.seal.fill" : "flask.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(v.type == "release" ? MCT.greenBright : MCT.dim)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(v.id)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MCT.text)
                Text(v.type.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(MCT.dim)
            }
            Spacer()

            if isInstalled {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .labelStyle(TerraIconFirstLabel())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MCT.greenBright)
            } else if isInstalling {
                ProgressView()
                    .tint(MCT.greenBright)
            } else {
                Button {
                    install(v)
                } label: {
                    Text("Install")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(MCT.green))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .mcSurface()
    }

    private func loadManifest() async {
        loading = true
        errorText = nil
        let base = model.downloadSource == "bmclapi"
            ? "https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json"
            : "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
        do {
            let (data, _) = try await URLSession.shared.data(from: URL(string: base)!)
            let decoded = try JSONDecoder().decode([String: [MinecraftManifestVersion]].self, from: data)
            versions = decoded["versions"] ?? []
        } catch {
            errorText = "Failed to load version manifest: (error.localizedDescription)"
        }
        loading = false
    }

    private func install(_ v: MinecraftManifestVersion) {
        installing.insert(v.id)
        model.installVersion(v.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            model.refresh()
            installedNames = Set(model.instances.map(\.name))
            installing.remove(v.id)
        }
    }
}

// MARK: - Mods pane (Modrinth search + optimization pack)

struct TerraModsPane: View {
    @EnvironmentObject private var model: TerraLauncherModel

    @State private var searchText = ""
    @State private var hits: [ModrinthHit] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @StateObject private var store = ModDownloadsStore()
    private let optKey = "__optimization_pack__"
    @State private var toast: String?

    private var fabricTarget: TerraInstance? {
        model.instances.first(where: { $0.isFabric }) ?? model.selected
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                targetBar
                searchField
                optimizePackCard

                if searching && hits.isEmpty {
                    ProgressView().tint(MCT.greenBright)
                        .frame(maxWidth: .infinity).padding(.vertical, 36)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(hits) { hit in
                            modRow(hit)
                        }
                    }
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Capsule().fill(MCT.green))
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var targetBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "target")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MCT.greenBright)
            Text("Install to:")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MCT.dim)
            Text(fabricTarget?.name ?? "No Fabric installation")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(MCT.text)
            Text("MC \(fabricTarget?.version ?? "—")")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MCT.dim)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .mcSurface()
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MCT.dim)
            TextField("Search Fabric Mods (Modrinth)", text: $searchText)
                .font(.system(size: 14))
                .foregroundStyle(MCT.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: searchText) { newValue in
                    scheduleSearch(newValue)
                }
            if searching { ProgressView().tint(MCT.greenBright) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(MCT.charcoal)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(MCT.border, lineWidth: 1))
        )
    }

    private var optimizePackCard: some View {
        let opt = store.entries[optKey]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("One-Click Optimization Pack")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(MCT.text)
                    Text("Sodium · Lithium · FerriteCore → \(fabricTarget?.name ?? "—")/mods")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(MCT.dim)
                }
                Spacer()
                Button {
                    installOptimizationPack()
                } label: {
                    Text(opt?.phase == .downloading ? "Installing…" : "Install Pack")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(fabricTarget?.isFabric == true ? MCT.green : MCT.elevated))
                }
                .buttonStyle(.plain)
                .disabled(opt?.phase == .downloading)
            }
            if let opt, opt.phase == .downloading {
                ProgressView(value: opt.progress)
                    .tint(MCT.greenBright)
            }
        }
        .padding(14)
        .mcSurface()
    }

    private func modRow(_ hit: ModrinthHit) -> some View {
        let state = store.entries[hit.projectId]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: hit.iconUrl ?? "")) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "puzzlepiece.fill")
                        .foregroundStyle(MCT.dim)
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(MCT.border, lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text(hit.title)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(MCT.text)
                        .lineLimit(1)
                    Text(hit.description)
                        .font(.system(size: 11.5))
                        .foregroundStyle(MCT.dim)
                        .lineLimit(2)
                    Text("by (hit.author) · ⬇ (hit.downloadsText)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(MCT.dim.opacity(0.75))
                }
                Spacer()

                if let state {
                    phaseView(state)
                } else {
                    Button {
                        install(hit)
                    } label: {
                        Text("Install")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(MCT.green))
                    }
                    .buttonStyle(.plain)
                }
            }
            if let state, state.phase == .downloading {
                ProgressView(value: state.progress)
                    .tint(MCT.greenBright)
                    .animation(.easeInOut(duration: 0.2), value: state.progress)
            }
        }
        .padding(14)
        .mcSurface()
    }

    @ViewBuilder
    private func phaseView(_ state: ModDownloadEntry) -> some View {
        switch state.phase {
        case .waiting, .downloading:
            Text("(Int(state.progress * 100))%")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MCT.greenBright)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(MCT.greenBright)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(MCT.danger)
        }
    }

    // MARK: Actions

    private func scheduleSearch(_ query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            hits = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            searching = true
            do {
                let result = try await ModrinthClient.search(query: query,
                                                             gameVersion: fabricTarget?.version)
                if !Task.isCancelled { hits = result }
            } catch {
                if !Task.isCancelled { hits = [] }
            }
            searching = false
        }
    }

    private func install(_ hit: ModrinthHit) {
        guard let target = fabricTarget, !target.modsPath.isEmpty else {
            showToast("Create a Fabric installation first")
            return
        }
        let key = hit.projectId
        store.start(key)
        Task {
            do {
                guard let file = try await ModrinthClient.latestCompatibleFile(
                    projectId: hit.projectId, gameVersion: target.version) else {
                    store.finish(key, .failed)
                    showToast("No version compatible with MC \(target.version)")
                    return
                }
                _ = try await ModrinthClient.download(file: file, toDirectory: target.modsPath) { p in
                    store.progress(key, p)
                }
                store.finish(key, .done)
                showToast("Installed \(hit.title) → \(target.name)/mods")
            } catch {
                store.finish(key, .failed)
                showToast("Download failed: \(error.localizedDescription)")
            }
        }
    }

    private func installOptimizationPack() {
        guard let target = fabricTarget, target.isFabric, !target.modsPath.isEmpty else {
            showToast("Select a Fabric installation first")
            return
        }
        let key = optKey
        store.start(key)
        Task {
            // Modrinth project slugs (stable, avoids fuzzy title search)
            let mods = [("Sodium", "sodium"), ("Lithium", "lithium"), ("FerriteCore", "ferrite-core")]
            var failed: [String] = []
            for (index, mod) in mods.enumerated() {
                do {
                    guard let file = try await ModrinthClient.latestCompatibleFile(
                        projectId: mod.1, gameVersion: target.version) else {
                        failed.append(mod.0)
                        continue
                    }
                    _ = try await ModrinthClient.download(file: file, toDirectory: target.modsPath) { p in
                        store.progress(key, (Double(index) + p) / Double(mods.count))
                    }
                } catch {
                    failed.append(mod.0)
                }
            }
            if failed.isEmpty {
                store.finish(key, .done)
                showToast("Optimization pack installed to \(target.name)/mods")
            } else {
                store.finish(key, .failed)
                showToast("Partially failed: \(failed.joined(separator: ", "))")
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { toast = nil }
        }
    }
}
