// ===========================================================================
//  ★ [TERRA-UI] TerraDownloadView.swift —— 下载中心(玻璃拟态设计)
//  ---------------------------------------------------------------------------
//  纯 SwiftUI 视图,通过 TerraDownloadHost 供 ObjC 调用:
//    UIViewController *vc = [TerraDownloadHost makeHost];
//  与 ObjC 的边界:唯一入口 +[TerraDownloadHost makeHost] → UIViewController
// ===========================================================================
import SwiftUI
import UIKit

// MARK: - 视图

/// 下载中心:顶部标签(全部/进行中/已完成) + 下载项列表,全屏毛玻璃背景。
struct TerraDownloadView: View {
    @State private var selectedTab = 0
    @State private var showingModrinth = false

    let tabs = ["全部", "进行中", "已完成"]

    var body: some View {
        ZStack {
            VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部标题区
                HStack {
                    Text("下载中心")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        showingModrinth = true
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                Divider()
                    .background(Color.white.opacity(0.15))
                    .padding(.horizontal, 20)

                // 顶部标签
                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { i, tab in
                        Button {
                            selectedTab = i
                        } label: {
                            VStack(spacing: 6) {
                                Text(tab)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(selectedTab == i ? .primary : .secondary)
                                if selectedTab == i {
                                    Capsule()
                                        .fill(Color.blue)
                                        .frame(height: 2)
                                } else {
                                    Capsule()
                                        .fill(Color.clear)
                                        .frame(height: 2)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // 下载列表
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(0..<6) { i in
                            DownloadRow(index: i)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .sheet(isPresented: $showingModrinth) {
            ModrinthSheet()
        }
    }
}

/// 下载行
struct DownloadRow: View {
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("OptiFine HD U \(index + 1)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text("Modrinth · 1.20.1")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("\(index * 12 + 5) MB")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                ProgressView(value: Double(index) / 10.0)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
                Text("\(index * 10)%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Button {
                // 取消/暂停
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
    }
}

/// Modrinth 浏览弹窗
struct ModrinthSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Modrinth 浏览")
                    .font(.system(size: 22, weight: .bold))
                Text("搜索并下载 Mod、光影与整合包")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索 Modrinth", text: .constant(""))
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )

                List {
                    ForEach(0..<5) { i in
                        HStack {
                            Image(systemName: "puzzlepiece.fill")
                                .foregroundStyle(.purple)
                                .frame(width: 24)
                            Text("Mod \(i + 1)")
                                .foregroundStyle(.primary)
                            Spacer()
                            Button("安装") { }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.insetGrouped)

                Spacer()
            }
            .padding(.horizontal, 20)
            .navigationTitle("Modrinth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
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

@objc(TerraDownloadHost)
public final class TerraDownloadHost: NSObject {
    @objc(makeHost)
    public static func makeHost() -> UIViewController {
        let hosting = UIHostingController(rootView: TerraDownloadView())
        hosting.view.backgroundColor = .clear
        return hosting
    }
}
