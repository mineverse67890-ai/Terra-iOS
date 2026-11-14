// ===========================================================================
//  ★ [TERRA-UI] TerraInstancesView.swift —— 实例列表(玻璃拟态设计)
//  ---------------------------------------------------------------------------
//  纯 SwiftUI 视图,通过 TerraInstancesHost 供 ObjC 调用:
//    UIViewController *vc = [TerraInstancesHost makeHost];
//  与 ObjC 的边界:唯一入口 +[TerraInstancesHost makeHost] → UIViewController
// ===========================================================================
import SwiftUI
import UIKit

// MARK: - 视图

/// 实例列表页:顶部标题 + 搜索 + 实例列表,全屏毛玻璃背景。
struct TerraInstancesView: View {
    @State private var searchText = ""
    @State private var showingAdd = false

    var body: some View {
        ZStack {
            VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部标题区
                HStack {
                    Text("实例")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        showingAdd = true
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

                // 搜索栏
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索实例", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // 实例列表
                List {
                    ForEach(0..<8) { i in
                        InstanceRow(index: i)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddInstanceSheet()
        }
    }
}

/// 实例行
struct InstanceRow: View {
    let index: Int

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.15))
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.blue)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text("实例 \(index + 1)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Minecraft 1.20.1 · Fabric · 已安装")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    // 启动
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
                Button {
                    // 设置
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
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

@objc(TerraInstancesHost)
public final class TerraInstancesHost: NSObject {
    @objc(makeHost)
    public static func makeHost() -> UIViewController {
        let hosting = UIHostingController(rootView: TerraInstancesView())
        hosting.view.backgroundColor = .clear
        return hosting
    }
}
