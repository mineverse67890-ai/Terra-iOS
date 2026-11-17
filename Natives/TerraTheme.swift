// ===========================================================================
//  ★ [TERRA-UI] TerraTheme.swift —— Terra-iOS 官方 Minecraft 启动器视觉主题
//  ---------------------------------------------------------------------------
//  深黑曜石/炭灰背景 + 标志性霓虹绿主操作按钮 + 无衬线字体的完整设计系统:
//    · obsidian  #111111 —— 主背景(官方启动器最深底色)
//    · charcoal  #1b1b1b —— 侧栏 / 卡片表面
//    · green     #388E3C —— 主操作按钮
//    · greenBright #4CAF50 —— 主 PLAY 按钮的更亮 Minecraft 绿
//  本文件同时提供:
//    · TerraBridge —— Swift → ObjC(TerraLauncherService)桥(@objc protocol +
//      NSClassFromString,不依赖桥接头,与 CMake 单独 swiftc 编译方式兼容)
//    · TerraLauncherModel —— 全局共享状态(实例列表 / 用户名 / 版本 / JIT)
//  ===========================================================================
import SwiftUI
import UIKit

// MARK: - 调色板

enum MCT {
    /// Content background (official launcher main area) #1E1E1E
    static let obsidian = Color(red: 0x1E/255.0, green: 0x1E/255.0, blue: 0x1E/255.0)
    /// Sidebar / header surface #262626
    static let charcoal = Color(red: 0x26/255.0, green: 0x26/255.0, blue: 0x26/255.0)
    /// Raised surface: play bar, cards #313131
    static let elevated = Color(red: 0x31/255.0, green: 0x31/255.0, blue: 0x31/255.0)
    /// Primary action green (official PLAY button face) #3C8527
    static let green = Color(red: 0x3C/255.0, green: 0x85/255.0, blue: 0x27/255.0)
    /// Brighter green (PLAY top bevel / tab underline) #52A535
    static let greenBright = Color(red: 0x52/255.0, green: 0xA5/255.0, blue: 0x35/255.0)
    /// Darker green (PLAY bottom bevel) #2A641C
    static let greenDark = Color(red: 0x2A/255.0, green: 0x64/255.0, blue: 0x1C/255.0)
    /// Subtle border highlight
    static let border = Color.white.opacity(0.08)
    /// Primary text
    static let text = Color.white
    /// Secondary text
    static let dim = Color(red: 0.70, green: 0.70, blue: 0.70)
    /// Destructive red
    static let danger = Color(red: 0xE5/255.0, green: 0x53/255.0, blue: 0x53/255.0)

    /// PLAY button face
    static let playGradient = LinearGradient(
        colors: [greenBright, green],
        startPoint: .top, endPoint: .bottom)
}

// MARK: - 通用组件

/// 官方启动器风格卡片:炭灰表面 + 细描边 + 连续圆角
struct MCShadowSurface: ViewModifier {
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(MCT.charcoal)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(MCT.border, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func mcSurface(radius: CGFloat = 12) -> some View { modifier(MCShadowSurface(radius: radius)) }
}

/// 主操作按钮样式(绿底白字,按下微缩)
struct MCPrimaryButtonStyle: ButtonStyle {
    var bright = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(bright ? AnyShapeStyle(MCT.playGradient) : AnyShapeStyle(MCT.green))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 次级按钮样式(炭灰底 + 描边)
struct MCGhostButtonStyle: ButtonStyle {
    var tint: Color = MCT.text
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(MCT.elevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(MCT.border, lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 加载器徽章(Fabric=绿 / Vanilla=灰)
struct MCLoaderBadge: View {
    let loader: String
    var body: some View {
        Text(loader.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.8)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(loader.lowercased() == "fabric" ? MCT.green.opacity(0.24) : Color.white.opacity(0.08))
            )
            .foregroundStyle(loader.lowercased() == "fabric" ? MCT.greenBright : MCT.dim)
    }
}

/// Label with icon before title, tight spacing (used by action buttons)
struct TerraIconFirstLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: - Swift → ObjC 桥(不依赖桥接头)

/// TerraLauncherService(TerraLauncherBridge.m)的 Swift 侧接口声明。
/// 运行期通过 NSClassFromString 取类、unsafeBitCast 绑协议 ——
/// 与本工程「swiftc 单独编译、无 -Swift.h」的构建方式兼容。
@objc protocol TerraLauncherServiceObjC {
    /// 一次性快照:instances / selected / username / version / downloadSource 等
    @objc(snapshot)
    func snapshot() -> [AnyHashable: Any]
    /// 通用命令入口:invoke("launch"/"deleteInstance"/"openMods"/"openSettings"/"openAccount"/"installVersion"/"stateRequest")
    @objc(invoke:payload:)
    func invoke(_ cmd: String, payload: [AnyHashable: Any])
    /// 挂到根 VC:装载不可见 LauncherRightPanelViewController(启动全链路)并开始监听通知
    @objc(attachToRoot:)
    func attach(toRoot root: UIViewController)
    /// {"state": "enabled"|"pending"|"disabled", "text": localized label}
    @objc(jitStatus)
    func jitStatus() -> [AnyHashable: Any]
    /// getPrefObject / setPrefObject for dotted keys ("video.renderer", "java.allocated_memory", …)
    @objc(prefValue:)
    func prefValue(_ key: String) -> Any?
    @objc(setPrefValue:forKey:)
    func setPrefValue(_ value: Any?, forKey key: String)
    /// [{"key", "name"}] of bundled renderers
    @objc(rendererOptions)
    func rendererOptions() -> [[AnyHashable: Any]]
    /// {"version", "build", "device", "system", "memoryMB"}
    @objc(appInfo)
    func appInfo() -> [AnyHashable: Any]
}

enum TerraBridge {
    /// 进程内单例(首次访问时创建并永久持有)
    static let service: TerraLauncherServiceObjC? = {
        guard let cls = NSClassFromString("TerraLauncherService") as? NSObject.Type else { return nil }
        let raw = cls.init() as AnyObject
        return unsafeBitCast(raw, to: TerraLauncherServiceObjC.self)
    }()

    static func snapshot() -> [String: Any] {
        guard let dict = service?.snapshot() as? [String: Any] else { return [:] }
        return dict
    }

    static func invoke(_ cmd: String, _ payload: [String: Any] = [:]) {
        service?.invoke(cmd, payload: payload)
    }
}

// MARK: - 实例模型

/// 一个隔离实例目录:Documents/instances/<name>/minecraft/
struct TerraInstance: Identifiable, Equatable {
    let id: String          // 实例名
    let name: String
    let version: String     // Minecraft 版本
    let loader: String      // "fabric" / "vanilla" / "forge"
    let sizeText: String    // 目录大小(人类可读)
    let modsPath: String    // <实例>/minecraft/mods 绝对路径
    let lastPlayed: String  // 最近游玩(可能为空)

    var isFabric: Bool { loader.lowercased() == "fabric" }
}

extension TerraBridge {
    /// 从 ObjC 快照解析实例列表
    static func instances() -> [TerraInstance] {
        let snap = snapshot()
        guard let raw = snap["instances"] as? [[String: Any]] else { return [] }
        return raw.map { item in
            TerraInstance(
                id: item["name"] as? String ?? "",
                name: item["name"] as? String ?? "",
                version: item["version"] as? String ?? "—",
                loader: item["loader"] as? String ?? "vanilla",
                sizeText: item["sizeText"] as? String ?? "—",
                modsPath: item["modsPath"] as? String ?? "",
                lastPlayed: item["lastPlayed"] as? String ?? "")
        }
    }
}

// MARK: - 全局状态模型

/// 根视图持有并注入 environment 的共享状态。
/// 数据源:TerraBridge.snapshot() + 两路通知(AmeRightPanelState / TerraInstancesChanged)。
final class TerraLauncherModel: ObservableObject {
    @Published var instances: [TerraInstance] = []
    @Published var selectedName: String = ""
    @Published var username: String = "Player"
    @Published var version: String = "—"
    @Published var jitText: String = ""
    @Published var downloadSource: String = "official"
    /// JIT state shown under the PLAY button
    @Published var jitState: JITState = .unknown
    @Published var jitLabel: String = ""
    /// Set when PLAY is pressed on an installation with no Minecraft version
    @Published var missingVersionInstance: String? = nil

    enum JITState: String { case enabled, pending, disabled, unknown }

    /// 选中的实例(找不到则取列表第一个)
    var selected: TerraInstance? {
        instances.first(where: { $0.name == selectedName }) ?? instances.first
    }

    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NotificationCenter.default
        // 右栏状态广播(用户名/版本/JIT)
        observers.append(center.addObserver(forName: NSNotification.Name("AmeRightPanelState"),
                                            object: nil, queue: .main) { [weak self] note in
            guard let self, let info = note.userInfo else { return }
            if let user = info["user"] as? String, !user.isEmpty { self.username = user }
            if let ver = info["version"] as? String, !ver.isEmpty { self.version = ver }
            if let jit = info["jit"] as? String { self.jitText = jit }
        })
        // 桥广播:实例列表变化(删除/安装/选择)
        observers.append(center.addObserver(forName: NSNotification.Name("TerraInstancesChanged"),
                                            object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// 重新拉快照
    func refresh() {
        let snap = TerraBridge.snapshot()
        instances = TerraBridge.instances()
        if let sel = snap["selected"] as? String, !sel.isEmpty { selectedName = sel }
        else if selectedName.isEmpty { selectedName = instances.first?.name ?? "" }
        if let user = snap["username"] as? String, !user.isEmpty { username = user }
        if let ver = snap["version"] as? String, !ver.isEmpty { version = ver }
        if let src = snap["downloadSource"] as? String { downloadSource = src }
    }

    // ---- 动作(全部转发 ObjC 桥,复用既有启动/管理链路)----

    /// 启动指定实例(先选中对应 profile,再走原右栏启动全链路)
    func launch(_ instance: TerraInstance?) {
        guard let instance else { return }
        // No Minecraft version yet → explain and offer the Download Center instead of the
        // legacy "Unable to fetch version information" tip.
        let v = instance.version.trimmingCharacters(in: .whitespaces)
        if v.isEmpty || v == "—" || v == "-" {
            missingVersionInstance = instance.name
            return
        }
        TerraBridge.invoke("launch", ["name": instance.name])
    }

    func openMods(_ instance: TerraInstance?) {
        guard let instance else { return }
        TerraBridge.invoke("openMods", ["name": instance.name, "modsPath": instance.modsPath])
    }

    /// Per-installation settings (Java version, renderer, memory, JVM arguments…)
    func openSettings(_ instance: TerraInstance?) {
        guard let instance else { return }
        TerraBridge.invoke("openInstanceSettings", ["name": instance.name])
    }

    func deleteInstance(_ instance: TerraInstance) {
        TerraBridge.invoke("deleteInstance", ["name": instance.name])
    }

    func installVersion(_ versionId: String) {
        TerraBridge.invoke("installVersion", ["versionId": versionId])
    }

    /// Change the active installation without launching
    func selectInstance(_ instance: TerraInstance) {
        selectedName = instance.name
        TerraBridge.invoke("selectInstance", ["name": instance.name])
    }

    func openAccount() { TerraBridge.invoke("openAccount") }
    func openFullSettings() { TerraBridge.invoke("openSettings") }
    func requestState() { TerraBridge.invoke("stateRequest") }

    /// Re-check JIT (cheap: csops + flag checks). JIT is often enabled by StikDebug /
    /// SideStore while the app is open, so the Play screen polls this.
    func refreshJIT() {
        guard let status = TerraBridge.service?.jitStatus() else { return }
        let state = JITState(rawValue: status["state"] as? String ?? "") ?? .unknown
        let text = status["text"] as? String ?? ""
        if state != jitState { jitState = state }
        if text != jitLabel { jitLabel = text }
    }
}
