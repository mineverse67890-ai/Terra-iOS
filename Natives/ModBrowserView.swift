import SwiftUI
import UIKit

private struct ModrinthSearchResponse: Codable {
    let hits: [ModrinthProject]
    let totalHits: Int

    enum CodingKeys: String, CodingKey {
        case hits
        case totalHits = "total_hits"
    }
}

private struct ModrinthProject: Codable, Identifiable, Hashable {
    let id: String
    let slug: String
    let title: String
    let description: String
    let author: String?
    let iconURL: URL?
    let downloads: Int
    let followers: Int?
    let categories: [String]?
    let projectType: String?

    enum CodingKeys: String, CodingKey {
        case slug
        case title
        case description
        case author
        case downloads
        case followers
        case categories
        case projectType = "project_type"
        case id = "project_id"
        case iconURL = "icon_url"
    }
}

private struct ModrinthProjectDetails: Codable {
    let id: String
    let title: String
    let description: String
    let body: String?
    let iconURL: URL?
    let downloads: Int
    let followers: Int
    let updated: String?
    let gallery: [ModrinthGalleryImage]?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case body
        case downloads
        case followers
        case updated
        case gallery
        case iconURL = "icon_url"
    }
}

private struct ModrinthGalleryImage: Codable, Identifiable {
    let url: URL
    let featured: Bool?
    let title: String?
    let description: String?

    var id: String { url.absoluteString }
}

private struct ModrinthVersion: Codable, Identifiable {
    let id: String
    let name: String
    let versionNumber: String
    let datePublished: String
    let downloads: Int
    let versionType: String
    let gameVersions: [String]
    let loaders: [String]
    let files: [ModrinthFile]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case downloads
        case loaders
        case files
        case versionNumber = "version_number"
        case datePublished = "date_published"
        case versionType = "version_type"
        case gameVersions = "game_versions"
    }

    var primaryFile: ModrinthFile? {
        files.first(where: \.primary) ?? files.first
    }
}

private struct ModrinthFile: Codable {
    let filename: String
    let url: URL
    let primary: Bool
    let hashes: ModrinthHashes?
}

private struct ModrinthHashes: Codable {
    let sha1: String?
}

private struct ModBrowserFilterOption: Identifiable {
    let title: String
    let value: String?

    var id: String { title }
}

private enum ModrinthAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The Modrinth request URL could not be created."
        case .invalidResponse:
            return "Modrinth returned an invalid response."
        case .httpStatus(let status):
            return "Modrinth returned HTTP \(status). Please try again."
        }
    }
}

private final class ModrinthAPIService {
    static let shared = ModrinthAPIService()

    private let baseURL = URL(string: "https://api.modrinth.com/v2")!
    private let session: URLSession
    private let decoder = JSONDecoder()

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 45
        session = URLSession(configuration: configuration)
    }

    func searchProjects(
        query: String,
        gameVersion: String?,
        loader: String?,
        offset: Int,
        completion: @escaping (Result<ModrinthSearchResponse, Error>) -> Void
    ) -> URLSessionDataTask? {
        var facets = [["project_type:mod"]]
        if let gameVersion = gameVersion {
            facets.append(["versions:\(gameVersion)"])
        }
        if let loader = loader {
            facets.append(["categories:\(loader)"])
        }

        guard let facetsData = try? JSONSerialization.data(withJSONObject: facets),
              let facetsJSON = String(data: facetsData, encoding: .utf8) else {
            completion(.failure(ModrinthAPIError.invalidResponse))
            return nil
        }

        let queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "facets", value: facetsJSON),
            URLQueryItem(name: "index", value: "downloads"),
            URLQueryItem(name: "limit", value: "24"),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        return get(path: "search", queryItems: queryItems, completion: completion)
    }

    func projectDetails(
        projectID: String,
        completion: @escaping (Result<ModrinthProjectDetails, Error>) -> Void
    ) -> URLSessionDataTask? {
        get(path: "project/\(escapedPathComponent(projectID))", queryItems: [], completion: completion)
    }

    func projectVersions(
        projectID: String,
        gameVersion: String?,
        loader: String?,
        completion: @escaping (Result<[ModrinthVersion], Error>) -> Void
    ) -> URLSessionDataTask? {
        var queryItems: [URLQueryItem] = []
        if let gameVersion = gameVersion,
           let value = jsonArrayString([gameVersion]) {
            queryItems.append(URLQueryItem(name: "game_versions", value: value))
        }
        if let loader = loader,
           let value = jsonArrayString([loader]) {
            queryItems.append(URLQueryItem(name: "loaders", value: value))
        }
        let path = "project/\(escapedPathComponent(projectID))/version"
        return get(path: path, queryItems: queryItems, completion: completion)
    }

    private func get<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem],
        completion: @escaping (Result<T, Error>) -> Void
    ) -> URLSessionDataTask? {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            completion(.failure(ModrinthAPIError.invalidURL))
            return nil
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            completion(.failure(ModrinthAPIError.invalidURL))
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("AngelAuraAmethyst/1.0 (https://github.com/mineverse67890-ai/Terra-iOS)", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: request) { [decoder] data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let response = response as? HTTPURLResponse, let data = data else {
                completion(.failure(ModrinthAPIError.invalidResponse))
                return
            }
            guard (200...299).contains(response.statusCode) else {
                completion(.failure(ModrinthAPIError.httpStatus(response.statusCode)))
                return
            }
            do {
                completion(.success(try decoder.decode(T.self, from: data)))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
        return task
    }

    private func jsonArrayString(_ values: [String]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: values) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func escapedPathComponent(_ value: String) -> String {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

@objc(AmeModBrowserHostController)
public final class ModBrowserHostController: UIViewController {
    private let viewModel: ModBrowserViewModel

    private init(viewModel: ModBrowserViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc(makeHostWithProfileName:installHandler:)
    public static func makeHost(
        profileName: String,
        installHandler: @escaping (NSDictionary, @escaping (NSError?) -> Void) -> Void
    ) -> ModBrowserHostController {
        let model = ModBrowserViewModel(profileName: profileName, installHandler: installHandler)
        return ModBrowserHostController(viewModel: model)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "Mod Browser"
        view.backgroundColor = .systemBackground

        let hostingController = UIHostingController(rootView: ModBrowserView(model: viewModel))
        hostingController.view.backgroundColor = .systemBackground
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hostingController)
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
    }
}

private final class ModBrowserViewModel: ObservableObject {
    @Published var query = ""
    @Published var gameVersion: String? = "26.3"
    @Published var loader: String?
    @Published var projects: [ModrinthProject] = []
    @Published var totalHits = 0
    @Published var selectedProjectID: String?
    @Published var selectedProject: ModrinthProject?
    @Published var projectDetails: ModrinthProjectDetails?
    @Published var versions: [ModrinthVersion] = []
    @Published var selectedVersionID: String?
    @Published var isLoadingProjects = false
    @Published var isLoadingDetails = false
    @Published var isLoadingVersions = false
    @Published var isInstalling = false
    @Published var searchError: String?
    @Published var detailError: String?
    @Published var installMessage: String?

    private let profileName: String
    private let installHandler: (NSDictionary, @escaping (NSError?) -> Void) -> Void
    private let service = ModrinthAPIService.shared
    private var searchTask: URLSessionDataTask?
    private var detailTask: URLSessionDataTask?
    private var versionsTask: URLSessionDataTask?
    private var debounceWork: DispatchWorkItem?
    private var searchGeneration = 0
    private var detailGeneration = 0
    private var versionsGeneration = 0

    var canInstallSelectedVersion: Bool {
        guard let version = versions.first(where: { $0.id == selectedVersionID }) else { return false }
        return version.primaryFile != nil
    }

    init(
        profileName: String,
        installHandler: @escaping (NSDictionary, @escaping (NSError?) -> Void) -> Void
    ) {
        self.profileName = profileName
        self.installHandler = installHandler
        loadProjects()
    }

    func scheduleSearch() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.loadProjects() }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func loadProjects(loadMore: Bool = false) {
        guard !loadMore || (!isLoadingProjects && projects.count < totalHits) else { return }
        searchGeneration += 1
        let generation = searchGeneration
        searchTask?.cancel()
        searchError = nil
        isLoadingProjects = true
        if !loadMore {
            projects = []
            totalHits = 0
        }
        let offset = loadMore ? projects.count : 0
        searchTask = service.searchProjects(
            query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            gameVersion: gameVersion,
            loader: loader,
            offset: offset
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, generation == self.searchGeneration else { return }
                self.isLoadingProjects = false
                switch result {
                case .success(let response):
                    if loadMore {
                        self.projects.append(contentsOf: response.hits)
                    } else {
                        self.projects = response.hits
                    }
                    self.totalHits = response.totalHits
                case .failure(let error):
                    self.searchError = error.localizedDescription
                }
            }
        }
    }

    func setGameVersion(_ version: String?) {
        guard gameVersion != version else { return }
        gameVersion = version
        loadProjects()
        reloadSelectedProjectVersions()
    }

    func setLoader(_ newLoader: String?) {
        guard loader != newLoader else { return }
        loader = newLoader
        loadProjects()
        reloadSelectedProjectVersions()
    }

    func selectProject(_ project: ModrinthProject) {
        guard selectedProject?.id != project.id else { return }
        selectedProjectID = project.id
        selectedProject = project
        projectDetails = nil
        versions = []
        selectedVersionID = nil
        detailError = nil
        isLoadingDetails = true
        isLoadingVersions = true
        detailGeneration += 1
        let generation = detailGeneration
        detailTask?.cancel()
        versionsTask?.cancel()

        detailTask = service.projectDetails(projectID: project.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, generation == self.detailGeneration else { return }
                self.isLoadingDetails = false
                switch result {
                case .success(let details):
                    self.projectDetails = details
                case .failure(let error):
                    self.detailError = error.localizedDescription
                }
            }
        }
        reloadSelectedProjectVersions()
    }

    func selectProject(id: String?) {
        guard let id = id, let project = projects.first(where: { $0.id == id }) else { return }
        selectProject(project)
    }

    func retryProjectDetails() {
        guard let project = selectedProject else { return }
        selectedProjectID = nil
        selectedProject = nil
        selectProject(project)
    }

    func chooseVersion(_ version: ModrinthVersion) {
        selectedVersionID = version.id
        installMessage = nil
    }

    func installSelectedVersion() {
        guard !isInstalling,
              let project = selectedProject,
              let version = versions.first(where: { $0.id == selectedVersionID }),
              let file = version.primaryFile else {
            return
        }
        guard file.url.scheme?.lowercased() == "https",
              file.url.host != nil,
              !file.filename.isEmpty,
              (file.filename as NSString).lastPathComponent == file.filename,
              file.filename.lowercased().hasSuffix(".jar") else {
            installMessage = "This release does not provide a valid HTTPS JAR file."
            return
        }

        let details = projectDetails
        let payload: NSDictionary = [
            "id": project.id,
            "projectID": project.id,
            "title": project.title,
            "description": project.description,
            "imageUrl": project.iconURL?.absoluteString ?? "",
            "author": project.author ?? "Unknown author",
            "downloads": project.downloads,
            "likes": project.followers ?? 0,
            "lastUpdated": details?.updated ?? "",
            "categories": project.categories ?? [],
            "version": version.versionNumber,
            "gameVersion": version.gameVersions.first ?? gameVersion ?? "",
            "fileName": file.filename,
            "downloadURL": file.url.absoluteString,
            "sha1": file.hashes?.sha1 ?? "",
        ]

        isInstalling = true
        installMessage = "Starting download..."
        installHandler(payload) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isInstalling = false
                self.installMessage = error == nil
                    ? "Download complete. The mod is installed in \(self.profileName)."
                    : error?.localizedDescription
            }
        }
    }

    private func reloadSelectedProjectVersions() {
        guard let project = selectedProject else { return }
        versionsGeneration += 1
        let expectedGeneration = versionsGeneration
        versionsTask?.cancel()
        versions = []
        selectedVersionID = nil
        isLoadingVersions = true
        versionsTask = service.projectVersions(
            projectID: project.id,
            gameVersion: gameVersion,
            loader: loader
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self,
                      expectedGeneration == self.versionsGeneration,
                      self.selectedProject?.id == project.id else { return }
                self.isLoadingVersions = false
                switch result {
                case .success(let versions):
                    self.versions = versions
                    self.selectedVersionID = versions.first?.id
                case .failure(let error):
                    self.detailError = error.localizedDescription
                }
            }
        }
    }
}

private struct ModBrowserView: View {
    @ObservedObject var model: ModBrowserViewModel

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                splitLayout
            } else {
                adaptiveNavigationLayout
            }
        }
        .accentColor(Color(red: 0.28, green: 0.68, blue: 0.53))
    }

    @available(iOS 16.0, *)
    private var splitLayout: some View {
        NavigationSplitView {
            browserSidebar(selectionEnabled: true)
                .navigationTitle("Discover")
                .navigationBarTitleDisplayMode(.large)
        } detail: {
            if let project = model.selectedProject {
                ModDetailView(model: model, project: project)
            } else {
                emptyDetail
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: model.selectedProjectID) { id in
            model.selectProject(id: id)
        }
    }

    private var adaptiveNavigationLayout: some View {
        NavigationView {
            browserSidebar(selectionEnabled: false)
                .navigationTitle("Discover")
                .navigationBarTitleDisplayMode(.large)
            if let project = model.selectedProject {
                ModDetailView(model: model, project: project)
            } else {
                emptyDetail
            }
        }
        .navigationViewStyle(DoubleColumnNavigationViewStyle())
    }

    private func browserSidebar(selectionEnabled: Bool) -> some View {
        VStack(spacing: 0) {
            searchAndFilters
            if let error = model.searchError, !model.projects.isEmpty {
                HStack(spacing: 8) {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Button("Retry") { model.loadProjects(loadMore: true) }
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            if model.isLoadingProjects && model.projects.isEmpty {
                ProgressView("Loading mods...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.searchError, model.projects.isEmpty {
                errorState(error, retry: { model.loadProjects() })
            } else if model.projects.isEmpty {
                ContentUnavailableViewCompat(
                    title: "No mods found",
                    message: "Try another search or adjust the version and loader filters.",
                    symbol: "square.grid.2x2"
                )
            } else {
                projectList(selectionEnabled: selectionEnabled)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var searchAndFilters: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search mods", text: $model.query)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onChange(of: model.query) { _ in model.scheduleSearch() }
                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                        model.scheduleSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 13).fill(Color(.secondarySystemGroupedBackground)))

            VStack(alignment: .leading, spacing: 10) {
                filterRow(title: "Minecraft", options: [
                    ModBrowserFilterOption(title: "26.3", value: "26.3"),
                    ModBrowserFilterOption(title: "All versions", value: nil),
                ], selected: model.gameVersion, select: model.setGameVersion)
                filterRow(title: "Loader", options: [
                    ModBrowserFilterOption(title: "All", value: nil),
                    ModBrowserFilterOption(title: "Fabric", value: "fabric"),
                    ModBrowserFilterOption(title: "Forge", value: "forge"),
                ], selected: model.loader, select: model.setLoader)
            }

            HStack {
                Text("MODS")
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundColor(.secondary)
                Spacer()
                if model.totalHits > 0 {
                    Text("\(model.totalHits.formattedCount) projects")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func filterRow(
        title: String,
        options: [ModBrowserFilterOption],
        selected: String?,
        select: @escaping (String?) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(options) { option in
                        let isSelected = selected == option.value
                        Button {
                            select(option.value)
                        } label: {
                            Text(option.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .foregroundColor(isSelected ? .white : Color.primary)
                                .background(
                                    Capsule().fill(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func projectList(selectionEnabled: Bool) -> some View {
        if selectionEnabled {
            List(selection: $model.selectedProjectID) {
                ForEach(model.projects) { project in
                    ModProjectRow(project: project)
                        .tag(project.id)
                        .listRowInsets(EdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14))
                }
                loadMoreRow
            }
            .listStyle(.plain)
        } else {
            List {
                ForEach(model.projects) { project in
                    NavigationLink(destination: ModDetailView(model: model, project: project)
                        .onAppear { model.selectProject(project) }) {
                            ModProjectRow(project: project)
                        }
                        .listRowInsets(EdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14))
                }
                loadMoreRow
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var loadMoreRow: some View {
        if model.projects.count < model.totalHits {
            Button {
                model.loadProjects(loadMore: true)
            } label: {
                HStack {
                    Spacer()
                    if model.isLoadingProjects {
                        ProgressView()
                    } else {
                        Text("Load more")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
            }
        }
    }

    private var emptyDetail: some View {
        ContentUnavailableViewCompat(
            title: "Choose a mod",
            message: "Select a project to view screenshots, details, and compatible releases.",
            symbol: "cube.transparent"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func errorState(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Couldn't load mods")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text("Try again")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ModProjectRow: View {
    let project: ModrinthProject

    var body: some View {
        HStack(spacing: 12) {
            ModRemoteImage(url: project.iconURL, contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(project.title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Label(project.downloads.formattedCount, systemImage: "arrow.down.circle")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Text(project.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 5) {
                    Text(project.author ?? "Unknown author")
                    if let category = project.categories?.first {
                        Text("|")
                        Text(category.capitalized)
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct ModDetailView: View {
    @ObservedObject var model: ModBrowserViewModel
    let project: ModrinthProject

    private var details: ModrinthProjectDetails? {
        model.projectDetails?.id == project.id ? model.projectDetails : nil
    }

    private var visibleVersions: [ModrinthVersion] {
        model.versions.filter { version in
            let gameMatches = model.gameVersion.map { version.gameVersions.contains($0) } ?? true
            let loaderMatches = model.loader.map { version.loaders.contains($0) } ?? true
            return gameMatches && loaderMatches
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let error = model.detailError {
                    detailError(error)
                }
                gallery
                description
                versionsSection
            }
            .padding(20)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(project.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.selectProject(project) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ModRemoteImage(url: details?.iconURL ?? project.iconURL, contentMode: .fill)
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 22))

            VStack(alignment: .leading, spacing: 8) {
                Text(details?.title ?? project.title)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("by \(project.author ?? "Unknown author")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack(spacing: 12) {
                    Label((details?.downloads ?? project.downloads).formattedCount, systemImage: "arrow.down.circle")
                    Label((details?.followers ?? project.followers ?? 0).formattedCount, systemImage: "heart")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color(.secondarySystemGroupedBackground)))
    }

    @ViewBuilder
    private var gallery: some View {
        let images = details?.gallery ?? []
        if !images.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Gallery", subtitle: "\(images.count) screenshots")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(images) { image in
                            VStack(alignment: .leading, spacing: 6) {
                                ModRemoteImage(url: image.url, contentMode: .fill)
                                    .frame(width: 280, height: 158)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                if let title = image.title, !title.isEmpty {
                                    Text(title)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("About this mod", subtitle: nil)
            if model.isLoadingDetails && details == nil {
                ProgressView("Loading project details...")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                MarkdownDescription(text: details?.body ?? project.description)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
            }
        }
    }

    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Versions", subtitle: "Minecraft \(model.gameVersion ?? "all versions")")
            if model.isLoadingVersions {
                ProgressView("Loading compatible releases...")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if visibleVersions.isEmpty {
                Text("No releases match these filters.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
            } else {
                VStack(spacing: 8) {
                    ForEach(visibleVersions) { version in
                        versionRow(version)
                    }
                }
                installControl
            }
        }
    }

    private var installControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: model.installSelectedVersion) {
                HStack(spacing: 8) {
                    if model.isInstalling {
                        ProgressView().accentColor(.white)
                    } else {
                        Image(systemName: "arrow.down.to.line")
                    }
                    Text(model.isInstalling ? "Installing..." : "Install selected version")
                        .fontWeight(.bold)
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .disabled(model.isInstalling || !model.canInstallSelectedVersion)
            if let message = model.installMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(model.isInstalling ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    private func versionRow(_ version: ModrinthVersion) -> some View {
        let selected = model.selectedVersionID == version.id
        return Button {
            model.chooseVersion(version)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundColor(selected ? .accentColor : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(version.name.isEmpty ? version.versionNumber : version.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("\(version.versionNumber) - MC \(version.gameVersions.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text("\(version.versionType.capitalized) - \(version.loaders.map(\.capitalized).joined(separator: ", ")) - \(version.downloads.formattedCount) downloads")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(version.datePublished.formattedDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(
                selected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground)
            ))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ title: String, subtitle: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline.weight(.bold))
            Spacer()
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func detailError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't load all project data")
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.footnote)
                .foregroundColor(.secondary)
            Button("Retry") { model.retryProjectDetails() }
                .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }
}

private struct MarkdownDescription: View {
    let text: String

    var body: some View {
        Group {
            if #available(iOS 15.0, *), let markdown = try? AttributedString(markdown: text) {
                Text(markdown)
            } else {
                Text(text)
            }
        }
        .font(.body)
        .lineSpacing(5)
    }
}

private struct ModRemoteImage: View {
    let url: URL?
    let contentMode: ContentMode

    var body: some View {
        Group {
            if #available(iOS 15.0, *) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: contentMode)
                    case .failure:
                        imagePlaceholder
                    case .empty:
                        imagePlaceholder
                    @unknown default:
                        imagePlaceholder
                    }
                }
            } else {
                LegacyModImage(url: url, contentMode: contentMode)
            }
        }
        .background(Color(.tertiarySystemGroupedBackground))
    }

    private var imagePlaceholder: some View {
        Image(systemName: "puzzlepiece.extension.fill")
            .resizable()
            .scaledToFit()
            .foregroundColor(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private final class LegacyModImageLoader: ObservableObject {
    @Published var image: UIImage?
    private var task: URLSessionDataTask?
    private static let cache = NSCache<NSURL, UIImage>()

    func load(_ url: URL?) {
        guard let url = url else { return }
        if let cached = Self.cache.object(forKey: url as NSURL) {
            image = cached
            return
        }
        task?.cancel()
        task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard error == nil, let data = data, let image = UIImage(data: data) else { return }
            Self.cache.setObject(image, forKey: url as NSURL)
            DispatchQueue.main.async { self?.image = image }
        }
        task?.resume()
    }

    deinit {
        task?.cancel()
    }
}

private struct LegacyModImage: View {
    let url: URL?
    let contentMode: ContentMode
    @StateObject private var loader = LegacyModImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Image(systemName: "puzzlepiece.extension.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.secondary)
                    .padding(16)
            }
        }
        .onAppear { loader.load(url) }
    }
}

private struct ContentUnavailableViewCompat: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .light))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
    }
}

private extension Int {
    var formattedCount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: self)) ?? String(self)
    }
}

private extension String {
    var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: self) else { return self }
        let output = DateFormatter()
        output.dateStyle = .medium
        return output.string(from: date)
    }
}
