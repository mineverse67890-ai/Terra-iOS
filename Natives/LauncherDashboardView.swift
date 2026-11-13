import SwiftUI
import UIKit

@objc(AmeLauncherDashboardHostController)
public final class LauncherDashboardHostController: UIViewController {
    private let model: LauncherDashboardViewModel

    private init(model: LauncherDashboardViewModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc(makeHostWithLaunchHandler:settingsControllerProvider:actionHandler:optimizationHandler:)
    public static func makeHost(
        launchHandler: @escaping () -> Void,
        settingsControllerProvider: @escaping () -> UIViewController,
        actionHandler: @escaping (String) -> Void,
        optimizationHandler: @escaping () -> Void
    ) -> LauncherDashboardHostController {
        let model = LauncherDashboardViewModel(
            launchHandler: launchHandler,
            settingsControllerProvider: settingsControllerProvider,
            actionHandler: actionHandler,
            optimizationHandler: optimizationHandler
        )
        return LauncherDashboardHostController(model: model)
    }

    @objc(updateVersionText:launchEnabled:)
    public func update(versionText: String?, launchEnabled: Bool) {
        if let versionText = versionText, !versionText.isEmpty {
            model.versionText = versionText
        }
        model.launchEnabled = launchEnabled
    }

    @objc(updateOptimizationProgress:message:state:)
    public func updateOptimization(progress: Double, message: String, state: Int) {
        model.optimizationProgress = min(max(progress, 0), 1)
        model.optimizationMessage = message
        model.optimizationState = state
        if state == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard self?.model.optimizationState == 2 else { return }
                self?.model.optimizationState = 0
                self?.model.optimizationMessage = ""
            }
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        let hostingController = UIHostingController(rootView: LauncherDashboardView(model: model))
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
}

private final class LauncherDashboardViewModel: ObservableObject {
    @Published var versionText = "26.3"
    @Published var launchEnabled = true
    @Published var isSettingsPresented = false
    @Published var optimizationProgress = 0.0
    @Published var optimizationMessage = ""
    @Published var optimizationState = 0

    private let launchHandler: () -> Void
    let settingsControllerProvider: () -> UIViewController
    let actionHandler: (String) -> Void
    private let optimizationHandler: () -> Void

    init(
        launchHandler: @escaping () -> Void,
        settingsControllerProvider: @escaping () -> UIViewController,
        actionHandler: @escaping (String) -> Void,
        optimizationHandler: @escaping () -> Void
    ) {
        self.launchHandler = launchHandler
        self.settingsControllerProvider = settingsControllerProvider
        self.actionHandler = actionHandler
        self.optimizationHandler = optimizationHandler
    }

    func launch() {
        launchHandler()
    }

    func perform(_ action: String) {
        actionHandler(action)
    }

    func installOptimizationMods() {
        guard optimizationState != 1 else { return }
        optimizationState = 1
        optimizationProgress = 0
        optimizationMessage = "Checking compatible releases…"
        optimizationHandler()
    }
}

private struct DashboardAction: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
}

private struct LauncherDashboardView: View {
    @ObservedObject var model: LauncherDashboardViewModel

    private let actions = [
        DashboardAction(
            id: "instances",
            title: "Instances",
            subtitle: "Profiles and game data",
            symbol: "square.stack.3d.up.fill",
            tint: Color(red: 0.30, green: 0.61, blue: 0.95)
        ),
        DashboardAction(
            id: "mods",
            title: "Browse Mods",
            subtitle: "Discover and install mods",
            symbol: "shippingbox.fill",
            tint: Color(red: 0.62, green: 0.46, blue: 0.92)
        ),
        DashboardAction(
            id: "versionPicker",
            title: "Select Version",
            subtitle: "Choose a Minecraft build",
            symbol: "arrow.triangle.branch",
            tint: Color(red: 0.29, green: 0.68, blue: 0.56)
        ),
        DashboardAction(
            id: "downloadCenter",
            title: "Downloads",
            subtitle: "Installers and download tasks",
            symbol: "arrow.down.circle.fill",
            tint: Color(red: 0.90, green: 0.57, blue: 0.30)
        ),
    ]

    var body: some View {
        NavigationStackContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    launchCard

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(actions) { action in
                            actionCard(action)
                        }
                        optimizationCard
                        settingsCard
                    }

                    HStack(spacing: 10) {
                        toolButton("Execute JAR", symbol: "play.rectangle", action: "executeJar")
                        toolButton("Customize", symbol: "slider.horizontal.3", action: "customize")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 24)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Terra-iOS")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $model.isSettingsPresented) {
            settingsNavigation
        }
    }

    private var launchCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background {
                        RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.16))
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Minecraft")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Text("Selected profile · \(model.versionText)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.76))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    model.isSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                        .background {
                            Circle().fill(Color.white.opacity(0.16))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }

            Button(action: model.launch) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Launch Minecraft \(model.versionText)")
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(Color(red: 0.12, green: 0.20, blue: 0.34))
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background {
                    RoundedRectangle(cornerRadius: 16).fill(Color.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(!model.launchEnabled)
            .opacity(model.launchEnabled ? 1 : 0.58)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.20, green: 0.43, blue: 0.82),
                        Color(red: 0.34, green: 0.30, blue: 0.72),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.20), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 6)
    }

    private func actionCard(_ action: DashboardAction) -> some View {
        Button {
            model.perform(action.id)
        } label: {
            VStack(alignment: .leading, spacing: 13) {
                Image(systemName: action.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(action.tint)
                    .frame(width: 42, height: 42)
                    .background {
                        RoundedRectangle(cornerRadius: 14).fill(action.tint.opacity(0.14))
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)
                    Text(action.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
            .background(cardBackground(cornerRadius: 21))
            .overlay(cardOutline(cornerRadius: 21))
        }
        .buttonStyle(.plain)
    }

    private var optimizationCard: some View {
        Button(action: model.installOptimizationMods) {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Image(systemName: model.optimizationState == 2 ? "checkmark.circle.fill" : "bolt.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(model.optimizationState == 2 ? .green : .orange)
                        .frame(width: 42, height: 42)
                        .background {
                            RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.14))
                        }
                    Spacer(minLength: 0)
                    if model.optimizationState == 1 {
                        ProgressView(value: model.optimizationProgress)
                            .frame(width: 50)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.optimizationState == 2 ? "Optimization ready" : "Install optimization mods")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    Text(model.optimizationMessage.isEmpty
                         ? "Sodium, Lithium, FerriteCore, and Entity Culling"
                         : model.optimizationMessage)
                        .font(.caption)
                        .foregroundColor(model.optimizationState == 3 ? .red : .secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
            .background(cardBackground(cornerRadius: 21))
            .overlay(cardOutline(cornerRadius: 21))
        }
        .buttonStyle(.plain)
        .disabled(model.optimizationState == 1)
    }

    private var settingsCard: some View {
        Button {
            model.isSettingsPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 13) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 42, height: 42)
                    .background {
                        RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.07))
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)
                    Text("Launcher and Java preferences")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
            .background(cardBackground(cornerRadius: 21))
            .overlay(cardOutline(cornerRadius: 21))
        }
        .buttonStyle(.plain)
    }

    private func toolButton(_ title: String, symbol: String, action: String) -> some View {
        Button {
            model.perform(action)
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(cardBackground(cornerRadius: 16))
                .overlay(cardOutline(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func cardBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 15.0, *) {
            shape.fill(.regularMaterial)
        } else {
            shape.fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.96))
        }
    }

    private func cardOutline(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
    }

    @ViewBuilder
    private var settingsNavigation: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                NativeSettingsControllerRepresentable(
                    settingsControllerProvider: model.settingsControllerProvider,
                    isPresented: $model.isSettingsPresented
                )
                .toolbar(.hidden, for: .navigationBar)
            }
        } else {
            NavigationView {
                NativeSettingsControllerRepresentable(
                    settingsControllerProvider: model.settingsControllerProvider,
                    isPresented: $model.isSettingsPresented
                )
                .navigationBarHidden(true)
            }
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

private struct NativeSettingsControllerRepresentable: UIViewControllerRepresentable {
    let settingsControllerProvider: () -> UIViewController
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let settingsController = settingsControllerProvider()
        let navigationController = UINavigationController(rootViewController: settingsController)
        navigationController.navigationBar.prefersLargeTitles = true
        let isPresented = _isPresented
        context.coordinator.dismissHandler = {
            isPresented.wrappedValue = false
        }
        settingsController.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: context.coordinator,
            action: #selector(Coordinator.closeSettings)
        )
        return navigationController
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    final class Coordinator: NSObject {
        var dismissHandler: (() -> Void)?

        @objc func closeSettings() {
            dismissHandler?()
        }
    }
}
