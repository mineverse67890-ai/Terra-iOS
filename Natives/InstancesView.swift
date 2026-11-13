import SwiftUI
import UIKit
import Combine

@objc(AmeTerraInstancesHostController)
public final class TerraInstancesHostController: UIViewController {
    private let model: TerraInstancesViewModel

    private init(model: TerraInstancesViewModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc(makeHostWithProfilesProvider:actionHandler:)
    public static func makeHost(
        profilesProvider: @escaping () -> [[String: String]],
        actionHandler: @escaping (String, String) -> Void
    ) -> TerraInstancesHostController {
        TerraInstancesHostController(
            model: TerraInstancesViewModel(
                profilesProvider: profilesProvider,
                actionHandler: actionHandler
            )
        )
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        let hostingController = UIHostingController(rootView: TerraInstancesView(model: model))
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
}

private struct TerraInstance: Identifiable {
    let id: String
    let version: String
    let path: String
    let size: String
    let isSelected: Bool
}

private final class TerraInstancesViewModel: ObservableObject {
    @Published var instances: [TerraInstance] = []

    private let profilesProvider: () -> [[String: String]]
    private let actionHandler: (String, String) -> Void
    private var refreshGeneration = 0

    init(
        profilesProvider: @escaping () -> [[String: String]],
        actionHandler: @escaping (String, String) -> Void
    ) {
        self.profilesProvider = profilesProvider
        self.actionHandler = actionHandler
    }

    func refresh() {
        let profiles = profilesProvider()
        refreshGeneration += 1
        let generation = refreshGeneration
        let snapshot = profiles.compactMap { profile in
            guard let name = profile["name"], !name.isEmpty else { return nil }
            return TerraInstance(
                id: name,
                version: profile["version"] ?? "No version selected",
                path: profile["path"] ?? "",
                size: profile["size"] ?? "Calculating…",
                isSelected: profile["selected"] == "true"
            )
        }
        instances = snapshot

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var sizes: [String: String] = [:]
            for instance in snapshot {
                sizes[instance.id] = Self.directorySize(at: instance.path)
            }
            DispatchQueue.main.async {
                guard let self = self, self.refreshGeneration == generation else { return }
                self.instances = self.instances.map { instance in
                    TerraInstance(
                        id: instance.id,
                        version: instance.version,
                        path: instance.path,
                        size: sizes[instance.id] ?? "Unavailable",
                        isSelected: instance.isSelected
                    )
                }
            }
        }
    }

    func perform(_ action: String, for instance: TerraInstance? = nil) {
        actionHandler(action, instance?.id ?? "")
    }

    private static func directorySize(at path: String) -> String {
        guard !path.isEmpty else { return "Unavailable" }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else { return "0 bytes" }

        var totalBytes: UInt64 = 0
        var failed = false
        let root = URL(fileURLWithPath: path, isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [],
            errorHandler: { _, _ in
                failed = true
                return false
            }
        ) else {
            return "Unavailable"
        }

        while let fileURL = enumerator.nextObject() as? URL {
            do {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, let fileSize = values.fileSize, fileSize >= 0 else {
                    continue
                }
                let (nextTotal, overflow) = totalBytes.addingReportingOverflow(UInt64(fileSize))
                totalBytes = overflow ? UInt64.max : nextTotal
            } catch {
                return "Unavailable"
            }
        }

        guard !failed else { return "Unavailable" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(min(totalBytes, UInt64(Int64.max))))
    }
}

private struct TerraInstancesView: View {
    @ObservedObject var model: TerraInstancesViewModel

    var body: some View {
        NavigationStackContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .lastTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your Minecraft profiles")
                                .font(.title2.bold())
                            Text("Each profile stores worlds, mods, and configuration separately.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button {
                            model.perform("create")
                        } label: {
                            Label("New", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .foregroundColor(.white)
                                .background {
                                    Capsule().fill(Color.accentColor)
                                }
                        }
                        .buttonStyle(.plain)
                    }

                    if model.instances.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "shippingbox")
                                .font(.system(size: 30, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("No instances")
                                .font(.headline)
                            Text("Create a profile to get started.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                            ForEach(model.instances) { instance in
                                instanceCard(instance)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Instances")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        model.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh instances")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SelectedProfileChanged"))) { _ in
                model.refresh()
            }
        }
    }

    private func instanceCard(_ instance: TerraInstance) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(instance.isSelected ? .white : Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background {
                        RoundedRectangle(cornerRadius: 15).fill(
                            instance.isSelected ? Color.accentColor : Color.accentColor.opacity(0.12)
                        )
                    }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(instance.id)
                            .font(.headline)
                            .lineLimit(1)
                        if instance.isSelected {
                            Text("ACTIVE")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background {
                                    Capsule().fill(Color.accentColor.opacity(0.15))
                                }
                        }
                    }
                    Text(instance.version)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    model.perform("edit", for: instance)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .frame(width: 34, height: 34)
                        .background {
                            Circle().fill(Color.primary.opacity(0.06))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(instance.id)")
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(instance.size, systemImage: "externaldrive")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(instance.path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Button {
                    model.perform("launch", for: instance)
                } label: {
                    Label("Launch", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .foregroundColor(.white)
                        .background {
                            RoundedRectangle(cornerRadius: 12).fill(Color.accentColor)
                        }
                }
                .buttonStyle(.plain)

                Button {
                    model.perform("edit", for: instance)
                } label: {
                    Label("Manage", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .foregroundColor(Color.accentColor)
                        .background {
                            RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.10))
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            cardBackground
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        if #available(iOS 15.0, *) {
            shape.fill(.regularMaterial)
        } else {
            shape.fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.96))
        }
    }
}

private struct NavigationStackContainer<Content: View>: View {
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
