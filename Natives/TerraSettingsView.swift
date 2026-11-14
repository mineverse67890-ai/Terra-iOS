// ===========================================================================
//  ★ [TERRA-UI] TerraSettingsView.swift —— 设置(玻璃拟态设计)
//  ---------------------------------------------------------------------------
//  纯 SwiftUI 视图,通过 TerraSettingsHost 供 ObjC 调用:
//    UIViewController *vc = [TerraSettingsHost makeHost];
//  与 ObjC 的边界:唯一入口 +[TerraSettingsHost makeHost] → UIViewController
// ===========================================================================
import SwiftUI
import UIKit

// MARK: - 视图

/// 设置页:分组设置列表,全屏毛玻璃背景。
struct TerraSettingsView: View {
    @State private var notificationsEnabled = true
    @State private var autoDownloadEnabled = false
    @State private var rendererSelected = "Auto"

    let renderers = ["Auto", "MobileGlues", "GL4ES", "MetalANGLE"]

    var body: some View {
        ZStack {
            VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // 顶部标题区
                    HStack {
                        Text("设置")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    Divider()
                        .background(Color.white.opacity(0.15))
                        .padding(.horizontal, 20)

                    // 常规设置
                    SettingsSection(title: "常规") {
                        ToggleRow(title: "启用通知", isOn: $notificationsEnabled, icon: "bell.fill", iconColor: .red)
                        ToggleRow(title: "自动下载更新", isOn: $autoDownloadEnabled, icon: "arrow.down.circle.fill", iconColor: .blue)
                    }

                    // 渲染器设置
                    SettingsSection(title: "渲染器") {
                        PickerRow(title: "渲染器", value: rendererSelected, icon: "display", iconColor: .green) {
                            // picker action
                        }
                    }

                    // 关于
                    SettingsSection(title: "关于") {
                        ButtonRow(title: "检查更新", icon: "arrow.clockwise", iconColor: .blue)
                        ButtonRow(title: "用户协议", icon: "doc.text", iconColor: .secondary)
                        ButtonRow(title: "隐私政策", icon: "hand.raised", iconColor: .secondary)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}

/// 设置分组
struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
        }
        .padding(.vertical, 10)
    }
}

/// 切换行
struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let icon: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            isOn.toggle()
        }
    }
}

/// 选择器行
struct PickerRow: View {
    let title: String
    let value: String
    let icon: String
    let iconColor: Color
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
    }
}

/// 按钮行
struct ButtonRow: View {
    let title: String
    let icon: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            // action
        }
    }
}

// MARK: - 毛玻璃辅助视图

struct VisualEffectView: UIViewRepresentable {
    let effect: UIVisualEffect?

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: effect)
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = effect
    }
}

// MARK: - ObjC 入口

@objc(TerraSettingsHost)
public final class TerraSettingsHost: NSObject {
    @objc(makeHost)
    public static func makeHost() -> UIViewController {
        let hosting = UIHostingController(rootView: TerraSettingsView())
        hosting.view.backgroundColor = .clear
        return hosting
    }
}
