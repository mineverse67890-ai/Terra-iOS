// ===========================================================================
//  ★ [TERRA-UI] TerraDashboardView.swift —— 主页/实例概览(玻璃拟态设计)
//  ---------------------------------------------------------------------------
//  纯 SwiftUI 视图,通过 TerraDashboardHost 供 ObjC 调用:
//    UIViewController *vc = [TerraDashboardHost makeHost];
//  与 ObjC 的边界:唯一入口 +[TerraDashboardHost makeHost] → UIViewController
// ===========================================================================
import SwiftUI
import UIKit

// MARK: - 视图

/// 主页:顶部欢迎语 + 实例网格 + 快速操作卡片,全屏毛玻璃背景。
struct TerraDashboardView: View {
    @State private var showingAddInstance = false

    var body: some View {
        ZStack {
            // 毛玻璃背景
            VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部标题区
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Terra-iOS")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("欢迎回来")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        showingAddInstance = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                Divider()
                    .background(Color.white.opacity(0.15))
                    .padding(.horizontal, 20)

                // 实例网格
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        ForEach(0..<6) { i in
                            InstanceCard(index: i)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .sheet(isPresented: $showingAddInstance) {
            AddInstanceSheet()
        }
    }
}

/// 实例卡片
struct InstanceCard: View {
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                VStack {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 140)

            VStack(alignment: .leading, spacing: 6) {
                Text("实例 \(index + 1)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Minecraft 1.20.1 · Fabric")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // 启动实例
        }
    }
}

/// 添加实例弹窗
struct AddInstanceSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("添加新实例")
                    .font(.system(size: 22, weight: .bold))
                Text("选择要创建的实例类型")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)

                List {
                    Button {
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "gamecontroller.fill")
                                .foregroundStyle(.blue)
                            Text("原版实例")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Button {
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "puzzlepiece.fill")
                                .foregroundStyle(.purple)
                            Text("Fabric 实例")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Button {
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.green)
                            Text("从整合包导入")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .listStyle(.insetGrouped)

                Spacer()
            }
            .navigationTitle("新建实例")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 毛玻璃辅助视图(UIKit UIVisualEffectView 的 SwiftUI 包装)

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

@objc(TerraDashboardHost)
public final class TerraDashboardHost: NSObject {
    @objc(makeHost)
    public static func makeHost() -> UIViewController {
        let hosting = UIHostingController(rootView: TerraDashboardView())
        hosting.view.backgroundColor = .clear
        return hosting
    }
}
