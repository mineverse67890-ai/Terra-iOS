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

    @objc(makeHostWithLaunchHandler:settingsControllerProvider:)
    public static func makeHost(
        launchHandler: @escaping () -> Void,
        settingsControllerProvider: @escaping () -> UIViewController
    ) -> LauncherDashboardHostController {
        let model = LauncherDashboardViewModel(
            launchHandler: launchHandler,
            settingsControllerProvider: settingsControllerProvider
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

    private let launchHandler: () -> Void
    let settingsControllerProvider: () -> UIViewController

    init(
        launchHandler: @escaping () -> Void,
        settingsControllerProvider: @escaping () -> UIViewController
    ) {
        self.launchHandler = launchHandler
        self.settingsControllerProvider = settingsControllerProvider
    }

    func launch() {
        launchHandler()
    }
}

private struct LauncherDashboardView: View {
    @ObservedObject var model: LauncherDashboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.16))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString(
                        "dashboard.title",
                        tableName: nil,
                        bundle: .main,
                        value: "Minecraft",
                        comment: "Dashboard title"
                    ))
                        .font(.headline.weight(.bold))
                        .foregroundColor(.white)
                    Text("\(NSLocalizedString(
                        "dashboard.version.label",
                        tableName: nil,
                        bundle: .main,
                        value: "SELECTED VERSION",
                        comment: "Selected version label"
                    ))  \(model.versionText)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white.opacity(0.76))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 4)

                Button {
                    model.isSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString(
                    "dashboard.settings",
                    tableName: nil,
                    bundle: .main,
                    value: "Settings",
                    comment: "Settings button"
                ))
            }

            Button(action: model.launch) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(NSLocalizedString(
                        "dashboard.launch",
                        tableName: nil,
                        bundle: .main,
                        value: "Launch Minecraft 26.3",
                        comment: "Launch Minecraft button"
                    ))
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(Color(red: 0.12, green: 0.20, blue: 0.34))
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)
                )
            }
            .buttonStyle(.plain)
            .disabled(!model.launchEnabled)
            .opacity(model.launchEnabled ? 1 : 0.58)
            .padding(.top, 12)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.20, green: 0.43, blue: 0.82),
                            Color(red: 0.34, green: 0.30, blue: 0.72),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 5)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .sheet(isPresented: $model.isSettingsPresented) {
            settingsNavigation
        }
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
