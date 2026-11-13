import SwiftUI
import UIKit

@objc(AmeTerraSettingsHostController)
public final class TerraSettingsHostController: UIViewController {
    private let openCategoryHandler: (String) -> Void

    private init(openCategoryHandler: @escaping (String) -> Void) {
        self.openCategoryHandler = openCategoryHandler
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc(makeHostWithOpenCategoryHandler:)
    public static func makeHost(openCategoryHandler: @escaping (String) -> Void) -> TerraSettingsHostController {
        TerraSettingsHostController(openCategoryHandler: openCategoryHandler)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        let hostingController = UIHostingController(
            rootView: TerraSettingsView(openCategoryHandler: openCategoryHandler)
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
}

private struct SettingsCategory: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
}

private struct TerraSettingsView: View {
    let openCategoryHandler: (String) -> Void

    private let categories = [
        SettingsCategory(
            id: "general",
            title: "General",
            subtitle: "Language, appearance, and launcher behavior",
            symbol: "slider.horizontal.3",
            tint: Color(red: 0.28, green: 0.52, blue: 0.94)
        ),
        SettingsCategory(
            id: "video",
            title: "Video & Audio",
            subtitle: "Display, sound, and controls",
            symbol: "speaker.wave.2",
            tint: Color(red: 0.44, green: 0.58, blue: 0.88)
        ),
        SettingsCategory(
            id: "renderer",
            title: "Renderer",
            subtitle: "Graphics backends and rendering options",
            symbol: "viewfinder",
            tint: Color(red: 0.49, green: 0.65, blue: 0.50)
        ),
        SettingsCategory(
            id: "java",
            title: "Java Tweaks",
            subtitle: "Runtime selection and JVM arguments",
            symbol: "terminal",
            tint: Color(red: 0.83, green: 0.56, blue: 0.28)
        ),
    ]

    var body: some View {
        NavigationStackContainer {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                    ForEach(categories) { category in
                        Button {
                            openCategoryHandler(category.id)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: category.symbol)
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundColor(category.tint)
                                    .frame(width: 46, height: 46)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(category.tint.opacity(0.14)))

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(category.title)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(category.subtitle)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                            .background(cardBackground)
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if #available(iOS 15.0, *) {
            shape.fill(.regularMaterial)
        } else {
            shape.fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.96))
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
