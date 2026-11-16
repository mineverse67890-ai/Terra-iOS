// ===========================================================================
//  ★ [TERRA-UI] TerraNewsFeed.swift —— Live Minecraft news + hero artwork
//  ---------------------------------------------------------------------------
//  Source: the official launcher content feed (same data the desktop
//  Minecraft Launcher shows):  https://launchercontent.mojang.com/v2/news.json
//    · entries[]: title / text / date / newsType[] / newsPageImage / readMoreLink
//    · newsType contains "Java" for Java Edition news
//  Images are loaded at runtime from Mojang's server — nothing is bundled.
//  Hero banner: a random Java news artwork (772×350) on every app launch,
//  never the same one twice in a row (last pick kept in UserDefaults).
//  ===========================================================================
import SwiftUI

struct MojangNewsEntry: Identifiable, Decodable, Equatable {
    struct Image: Decodable, Equatable { let url: String }

    let id: String
    let title: String
    let text: String
    let date: String
    let category: String?
    let newsType: [String]?
    let newsPageImage: Image?
    let playPageImage: Image?
    let readMoreLink: String?

    var isJava: Bool { newsType?.contains("Java") ?? false }

    /// Wide (772×350) artwork, falling back to the play-page image
    var imageURL: URL? {
        guard let path = (newsPageImage ?? playPageImage)?.url else { return nil }
        return URL(string: TerraNewsFeed.baseURL + path)
    }

    var link: URL? { readMoreLink.flatMap(URL.init(string:)) }

    /// "2026-11-15" → "Nov 15, 2026"
    var displayDate: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let d = parser.date(from: date) else { return date }
        let out = DateFormatter()
        out.dateStyle = .medium
        return out.string(from: d)
    }
}

@MainActor
final class TerraNewsFeed: ObservableObject {
    static let shared = TerraNewsFeed()
    nonisolated static let baseURL = "https://launchercontent.mojang.com"

    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    @Published private(set) var entries: [MojangNewsEntry] = []
    @Published private(set) var heroURL: URL?
    @Published private(set) var state: LoadState = .idle

    private let lastHeroKey = "TerraLastHeroImage"

    var javaEntries: [MojangNewsEntry] { entries.filter(\.isJava) }

    /// Fetch once per app session (call again with force: true to retry/refresh)
    func load(force: Bool = false) async {
        if state == .loading { return }
        if state == .loaded && !force { return }
        state = .loading
        do {
            var request = URLRequest(url: URL(string: Self.baseURL + "/v2/news.json")!)
            request.cachePolicy = .reloadRevalidatingCacheData
            request.timeoutInterval = 20
            let (data, _) = try await URLSession.shared.data(for: request)
            // Lossy decode: one malformed entry must not drop the whole feed
            struct Lossy: Decodable {
                let value: MojangNewsEntry?
                init(from decoder: Decoder) throws { value = try? MojangNewsEntry(from: decoder) }
            }
            struct Feed: Decodable { let entries: [Lossy] }
            let feed = try JSONDecoder().decode(Feed.self, from: data)
            entries = feed.entries.compactMap(\.value).sorted { $0.date > $1.date }
            if heroURL == nil { pickHero() }
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Random Java artwork, different from the one shown on the previous launch
    private func pickHero() {
        let candidates = javaEntries.compactMap(\.imageURL)
        guard !candidates.isEmpty else { return }
        let last = UserDefaults.standard.string(forKey: lastHeroKey)
        let pool = candidates.count > 1 ? candidates.filter { $0.absoluteString != last } : candidates
        guard let pick = pool.randomElement() else { return }
        heroURL = pick
        UserDefaults.standard.set(pick.absoluteString, forKey: lastHeroKey)
    }
}

// MARK: - Views

/// Wide news banner: artwork left, bold title on black right. Tap opens the article.
struct TerraNewsBanner: View {
    let entry: MojangNewsEntry
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let link = entry.link { openURL(link) }
        } label: {
            HStack(spacing: 0) {
                AsyncImage(url: entry.imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        MCT.elevated.overlay(TerraBlockIcon(kind: .grass, size: 40).opacity(0.5))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.title.uppercased())
                        .font(.system(size: 22, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.leading)
                    Text(entry.text)
                        .font(.system(size: 13))
                        .foregroundStyle(MCT.dim)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Text(entry.category ?? "Minecraft")
                        Text("·")
                        Text(entry.displayDate)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MCT.dim.opacity(0.8))
                    .lineLimit(1)
                }
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(Color.black)
            }
            .frame(height: 180)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Loading / error / list wrapper shared by the Play page and the News screen
struct TerraNewsList: View {
    @ObservedObject var feed: TerraNewsFeed
    let entries: [MojangNewsEntry]
    var limit: Int? = nil

    var body: some View {
        VStack(spacing: 18) {
            if !entries.isEmpty {
                ForEach(limit.map { Array(entries.prefix($0)) } ?? entries) { entry in
                    TerraNewsBanner(entry: entry)
                }
            } else if case .failed(let message) = feed.state {
                VStack(spacing: 10) {
                    Text("Couldn't load Minecraft news")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MCT.text)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(MCT.dim)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await feed.load(force: true) } }
                        .buttonStyle(MCPrimaryButtonStyle())
                        .frame(width: 140)
                }
                .padding(.vertical, 30)
            } else if feed.state == .loaded {
                Text("No news right now")
                    .font(.system(size: 13))
                    .foregroundStyle(MCT.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            } else {
                ProgressView()
                    .tint(MCT.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
        }
    }
}

/// Sidebar "News" section: all Minecraft news, filterable to Java Edition
struct TerraNewsScreen: View {
    @ObservedObject private var feed = TerraNewsFeed.shared
    @State private var javaOnly = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("NEWS")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(MCT.text)
                    Spacer()
                    Picker("Filter", selection: $javaOnly) {
                        Text("All").tag(false)
                        Text("Java Edition").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                .padding(.top, 26)

                TerraNewsList(feed: feed, entries: javaOnly ? feed.javaEntries : feed.entries)
                Spacer(minLength: 28)
            }
            .frame(maxWidth: 1000)
            .padding(.horizontal, 36)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await feed.load(force: true) }
    }
}
