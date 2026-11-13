import SwiftUI
import UIKit
import Combine

@objc(TerraDownloadCenterHostController)
public final class DownloadCenterHostController: UIViewController {
    private let model: DownloadCenterViewModel

    private init(model: DownloadCenterViewModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc(makeHostWithTasksProvider:actionHandler:)
    public static func makeHost(
        tasksProvider: @escaping () -> [[String: Any]],
        actionHandler: @escaping (String, String) -> Void
    ) -> DownloadCenterHostController {
        DownloadCenterHostController(
            model: DownloadCenterViewModel(
                tasksProvider: tasksProvider,
                actionHandler: actionHandler
            )
        )
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        let hostingController = UIHostingController(
            rootView: DownloadCenterView(model: model) { [weak self] in
                self?.closeCenter()
            }
        )
        hostingController.view.backgroundColor = .clear
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

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.refresh()
    }

    @objc public func downloadManagerDidUpdate(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.model.refresh()
        }
    }

    @objc public func closeCenter() {
        NotificationCenter.default.post(name: Notification.Name("DownloadCenterDidDismiss"), object: nil)
        dismiss(animated: true)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

private enum DownloadCenterTaskState: Int, Equatable {
    case pending = 0
    case downloading
    case paused
    case completed
    case cancelled
    case failed

    var title: String {
        switch self {
        case .pending: return "Queued"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        case .failed: return "Failed"
        }
    }

    var symbol: String {
        switch self {
        case .pending: return "clock"
        case .downloading: return "arrow.down.circle.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pending: return .secondary
        case .downloading: return .accentColor
        case .paused: return .orange
        case .completed: return .green
        case .cancelled, .failed: return .red
        }
    }
}

private struct DownloadCenterTask: Identifiable {
    let id: String
    let title: String
    let resourceType: String
    let downloadSource: String
    let state: DownloadCenterTaskState
    let progress: Double
    let totalSize: Int64
    let downloadedSize: Int64
    let speed: Double
    let estimatedTimeRemaining: TimeInterval
    let supportsResume: Bool
    let canRetry: Bool
    let errorMessage: String

    init?(dictionary: [String: Any]) {
        guard let id = dictionary["taskId"] as? String, !id.isEmpty,
              let rawState = dictionary["state"] as? Int,
              let state = DownloadCenterTaskState(rawValue: rawState) else {
            return nil
        }
        self.id = id
        title = dictionary["displayName"] as? String ?? "Download"
        resourceType = dictionary["resourceType"] as? String ?? ""
        downloadSource = dictionary["downloadSource"] as? String ?? "official"
        self.state = state
        progress = dictionary["progress"] as? Double ?? -1
        totalSize = dictionary["totalSize"] as? Int64 ?? -1
        downloadedSize = dictionary["downloadedSize"] as? Int64 ?? 0
        speed = dictionary["speed"] as? Double ?? 0
        estimatedTimeRemaining = dictionary["estimatedTimeRemaining"] as? TimeInterval ?? 0
        supportsResume = dictionary["supportsResume"] as? Bool ?? false
        canRetry = dictionary["canRetry"] as? Bool ?? false
        errorMessage = dictionary["errorMessage"] as? String ?? ""
    }

    var typeTitle: String {
        Self.title(forResourceType: resourceType)
    }

    var sourceTitle: String {
        downloadSource == "bmclapi" ? "BMCLAPI" : "Official"
    }

    static func title(forResourceType resourceType: String) -> String {
        switch resourceType.lowercased() {
        case "minecraft": return "Minecraft"
        case "modloader": return "Mod loader"
        case "mod": return "Mod"
        case "shader": return "Shader"
        case "resourcepack": return "Resource pack"
        case "datapack": return "Data pack"
        case "modpack": return "Modpack"
        case "world": return "World"
        case "javaruntime": return "Java runtime"
        default: return resourceType.isEmpty ? "Download" : resourceType.capitalized
        }
    }

    var clampedProgress: Double? {
        guard progress >= 0 else { return state == .completed ? 1 : nil }
        return min(max(progress, 0), 1)
    }

    var progressSummary: String {
        let downloaded = Self.byteCount(downloadedSize)
        guard totalSize >= 0 else { return downloaded ?? "Preparing…" }
        return "\(downloaded ?? "0 bytes") of \(Self.byteCount(totalSize) ?? "Unknown size")"
    }

    var activitySummary: String? {
        guard state == .downloading else { return nil }
        var details: [String] = []
        if speed > 0 {
            details.append("\(Self.byteCount(Int64(speed)) ?? "")/s")
        }
        if estimatedTimeRemaining > 0 {
            details.append("\(Int(estimatedTimeRemaining)) sec remaining")
        }
        return details.isEmpty ? nil : details.joined(separator: " · ")
    }

    private static func byteCount(_ bytes: Int64) -> String? {
        guard bytes >= 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private enum DownloadCenterFilter: String, CaseIterable, Identifiable, Hashable {
    case all = "All"
    case active = "Active"
    case completed = "Completed"
    case failed = "Failed"

    var id: String { rawValue }

    func includes(_ state: DownloadCenterTaskState) -> Bool {
        switch self {
        case .all:
            return true
        case .active:
            return state == .pending || state == .downloading || state == .paused
        case .completed:
            return state == .completed
        case .failed:
            return state == .failed || state == .cancelled
        }
    }
}

private final class DownloadCenterViewModel: ObservableObject {
    @Published var tasks: [DownloadCenterTask] = []
    @Published var selectedFilter = DownloadCenterFilter.all
    @Published var selectedResourceType = "all"
    @Published var searchText = ""

    private let tasksProvider: () -> [[String: Any]]
    private let actionHandler: (String, String) -> Void

    init(
        tasksProvider: @escaping () -> [[String: Any]],
        actionHandler: @escaping (String, String) -> Void
    ) {
        self.tasksProvider = tasksProvider
        self.actionHandler = actionHandler
        refresh()
    }

    var resourceTypes: [String] {
        Array(Set(tasks.map(\.resourceType).filter { !$0.isEmpty })).sorted()
    }

    var filteredTasks: [DownloadCenterTask] {
        tasks.filter { task in
            selectedFilter.includes(task.state)
                && (selectedResourceType == "all" || task.resourceType == selectedResourceType)
                && (searchText.isEmpty || task.title.localizedCaseInsensitiveContains(searchText))
        }
    }

    func refresh() {
        tasks = tasksProvider().compactMap(DownloadCenterTask.init(dictionary:))
        if selectedResourceType != "all" && !resourceTypes.contains(selectedResourceType) {
            selectedResourceType = "all"
        }
    }

    func perform(_ action: String, for task: DownloadCenterTask) {
        actionHandler(action, task.id)
        refresh()
    }

    func openHistory() {
        actionHandler("history", "")
    }
}

private struct DownloadCenterView: View {
    @ObservedObject var model: DownloadCenterViewModel
    let closeAction: () -> Void

    var body: some View {
        DownloadCenterNavigationContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    searchField
                    statusFilter
                    resourceTypeFilter

                    if model.filteredTasks.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(model.filteredTasks) { task in
                                taskCard(task)
                            }
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: closeAction) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close downloads")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: model.openHistory) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Download history")
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search downloads", text: $model.searchText)
                .font(.body)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(cardBackground(cornerRadius: 15))
    }

    private var statusFilter: some View {
        Picker("Status", selection: $model.selectedFilter) {
            ForEach(DownloadCenterFilter.allCases) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(5)
        .background(cardBackground(cornerRadius: 15))
    }

    private var resourceTypeFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                resourceChip("All types", value: "all")
                ForEach(model.resourceTypes, id: \.self) { type in
                    resourceChip(typeTitle(for: type), value: type)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func resourceChip(_ title: String, value: String) -> some View {
        let isSelected = model.selectedResourceType == value
        return Button {
            model.selectedResourceType = value
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(Capsule().fill(isSelected ? Color.accentColor : Color(UIColor.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 34, weight: .medium))
                .foregroundColor(.secondary)
            Text(model.tasks.isEmpty ? "No download tasks" : "No matching downloads")
                .font(.headline)
            Text(model.tasks.isEmpty
                 ? "Downloads and installations will appear here."
                 : "Try changing the filters or search terms.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 230)
        .padding(20)
    }

    private func taskCard(_ task: DownloadCenterTask) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: task.state.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(task.state.tint)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 14).fill(task.state.tint.opacity(0.13)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    Text("\(task.typeTitle) · \(task.state.title) · \(task.sourceTitle)")
                        .font(.caption)
                        .foregroundColor(task.state.tint)
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Use Official Source") {
                        model.perform("source:official", for: task)
                    }
                    .disabled(task.downloadSource == "official")
                    Button("Use BMCLAPI Source") {
                        model.perform("source:bmclapi", for: task)
                    }
                    .disabled(task.downloadSource == "bmclapi")
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Download options")
            }

            if let progress = task.clampedProgress {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .accentColor(task.state.tint)
                HStack {
                    Text(task.progressSummary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .fontWeight(.semibold)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            } else {
                ProgressView()
                    .progressViewStyle(LinearProgressViewStyle())
                Text("Preparing download…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let activity = task.activitySummary {
                Text(activity)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !task.errorMessage.isEmpty {
                Text(task.errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actionButtons(for: task)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(cornerRadius: 21))
        .overlay(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func actionButtons(for task: DownloadCenterTask) -> some View {
        HStack(spacing: 10) {
            if task.state == .downloading {
                taskAction("Pause", symbol: "pause.fill", action: "pause", task: task)
            } else if task.state == .pending {
                taskAction("Pause", symbol: "pause.fill", action: "pause", task: task)
            } else if task.state == .paused {
                taskAction(
                    "Resume",
                    symbol: "play.fill",
                    action: "resume",
                    task: task,
                    isEnabled: task.supportsResume
                )
            } else if (task.state == .failed || task.state == .cancelled) && task.canRetry {
                taskAction("Retry", symbol: "arrow.clockwise", action: "retry", task: task)
            }

            Spacer(minLength: 0)

            if task.state == .pending || task.state == .downloading || task.state == .paused {
                taskAction("Cancel", symbol: "xmark", action: "cancel", task: task, isDestructive: true)
            } else {
                taskAction("Remove", symbol: "trash", action: "remove", task: task, isDestructive: true)
            }
        }
    }

    private func taskAction(
        _ title: String,
        symbol: String,
        action: String,
        task: DownloadCenterTask,
        isDestructive: Bool = false,
        isEnabled: Bool = true
    ) -> some View {
        Button {
            model.perform(action, for: task)
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundColor(isDestructive ? .red : .accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Capsule().fill(isDestructive ? Color.red.opacity(0.09) : Color.accentColor.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }

    private func typeTitle(for type: String) -> String {
        DownloadCenterTask.title(forResourceType: type)
    }

    @ViewBuilder
    private func cardBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 15.0, *) {
            shape.fill(.regularMaterial)
        } else {
            shape.fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.96))
        }
    }
}

private struct DownloadCenterNavigationContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content }
        } else {
            NavigationView { content }
                .navigationViewStyle(.stack)
        }
    }
}
