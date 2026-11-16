// ===========================================================================
//  ★ [TERRA-UI] TerraSettingsView.swift —— Settings (official launcher style)
//  ---------------------------------------------------------------------------
//    ┌────────────────┬──────────────────────────────────────────────┐
//    │ [icon] Terra   │ Video & Renderer                             │
//    │ Version 0.1.0  │ RENDERER                                     │
//    │                │ ┌──────────────────────────────────────────┐ │
//    │ ▌General       │ │ Renderer                       Auto  ⌃⌄  │ │
//    │  Video         │ │ Resolution                         100%  │ │
//    │  Java & Memory │ └──────────────────────────────────────────┘ │
//    │  Controls      │ AUDIO                                        │
//    │  ...           │ ...                                          │
//    └────────────────┴──────────────────────────────────────────────┘
//  Narrow widths: category column becomes a horizontal chip row.
//  Every control reads/writes the real preference store through
//  TerraBridge.service (getPrefObject / setPrefObject, dotted keys). Keys and
//  allowed values mirror LauncherPreferencesViewController.m / PLPreferences.m.
//  Deeper screens reuse the legacy UIKit controllers (openLegacyClass), and
//  "Advanced settings" opens the full legacy preference list.
//  ===========================================================================
import SwiftUI
import UIKit
import QuartzCore

// MARK: - Categories

private enum TSCategory: String, CaseIterable, Identifiable {
    case general, video, java, controls, downloads, accounts, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .video: return "Video & Renderer"
        case .java: return "Java & Memory"
        case .controls: return "Controls"
        case .downloads: return "Downloads"
        case .accounts: return "Accounts"
        case .about: return "About"
        }
    }

    var shortTitle: String {
        switch self {
        case .video: return "Video"
        case .java: return "Java"
        default: return title
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .video: return "display"
        case .java: return "memorychip"
        case .controls: return "gamecontroller.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .accounts: return "person.crop.circle.fill"
        case .about: return "info.circle.fill"
        }
    }

    var summary: String {
        switch self {
        case .general: return "Language, updates and launcher behavior"
        case .video: return "Renderer, resolution, framerate and audio"
        case .java: return "Memory allocation, runtimes and JVM arguments"
        case .controls: return "On-screen controls, touch, mouse and gyroscope"
        case .downloads: return "Download sources, mirrors and CurseForge"
        case .accounts: return "Microsoft and local accounts"
        case .about: return "Version, device and credits"
        }
    }
}

// MARK: - Preference store (bridge wrapper)

/// Thin wrapper over the ObjC preference store. `revision` bumps on every write and on
/// external changes (legacy screens, app foreground) so all rows re-read their values.
final class TSPrefStore: ObservableObject {
    @Published private(set) var revision = 0
    let appInfo: [String: Any]
    private var observers: [NSObjectProtocol] = []

    init() {
        var info: [String: Any] = [:]
        if let raw = TerraBridge.service?.appInfo() {
            for (key, value) in raw { if let k = key as? String { info[k] = value } }
        }
        appInfo = info
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            Notification.Name("TerraPreferencesChanged"),
            Notification.Name("TerraInstancesChanged"),   // posted when a legacy screen is dismissed
            UIApplication.didBecomeActiveNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.revision += 1
            })
        }
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    // ---- reads (robust against NSNumber / String / Bool storage) ----

    func raw(_ key: String) -> Any? { TerraBridge.service?.prefValue(key) }

    func bool(_ key: String, _ def: Bool) -> Bool {
        switch raw(key) {
        case let n as NSNumber: return n.boolValue
        case let s as String:
            let v = s.lowercased()
            if ["1", "true", "yes", "on"].contains(v) { return true }
            if ["0", "false", "no", "off"].contains(v) { return false }
            return def
        default: return def
        }
    }

    func double(_ key: String, _ def: Double) -> Double {
        switch raw(key) {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s) ?? def
        default: return def
        }
    }

    func string(_ key: String, _ def: String) -> String {
        switch raw(key) {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return def
        }
    }

    // ---- writes ----

    func set(_ value: Any, _ key: String) {
        TerraBridge.service?.setPrefValue(value, forKey: key)
        revision += 1
    }

    func setBool(_ value: Bool, _ key: String) { set(NSNumber(value: value), key) }
    func setInt(_ value: Int, _ key: String) { set(NSNumber(value: value), key) }
    func setString(_ value: String, _ key: String) { set(value as NSString, key) }

    func boolBinding(_ key: String, _ def: Bool) -> Binding<Bool> {
        Binding(get: { self.bool(key, def) }, set: { self.setBool($0, key) })
    }

    func stringBinding(_ key: String, _ def: String) -> Binding<String> {
        Binding(get: { self.string(key, def) }, set: { self.setString($0, key) })
    }

    // ---- app info ----

    var appVersion: String {
        let v = appInfo["version"] as? String ?? ""
        if !v.isEmpty { return v }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var appBuild: String {
        let b = appInfo["build"] as? String ?? ""
        if !b.isEmpty { return b }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    var deviceLine: String {
        let device = appInfo["device"] as? String ?? UIDevice.current.model
        let system = appInfo["system"] as? String
            ?? "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        return "\(device) · \(system)"
    }

    var deviceMemoryMB: Int {
        if let n = appInfo["memoryMB"] as? NSNumber, n.intValue > 0 { return n.intValue }
        return Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))
    }

    var renderers: [TSOption] {
        let raw = TerraBridge.service?.rendererOptions() ?? []
        let list: [TSOption] = raw.compactMap { item in
            guard let key = item["key"] as? String, key != "(default)" else { return nil }
            return TSOption(key: key, name: item["name"] as? String ?? key)
        }
        return list.isEmpty ? [TSOption(key: "auto", name: "Auto")] : list
    }
}

struct TSOption: Identifiable, Hashable {
    let key: String
    let name: String
    var id: String { key }
}

// MARK: - UIKit helpers (legacy screens)

@objc private protocol TSUpdateCheckerClass {
    @objc(performManualCheckFromPresenter:showUpToDate:)
    func performManualCheck(from presenter: UIViewController, showUpToDate: Bool)
}

private enum TSLegacy {
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        var vc = (windows.first(where: { $0.isKeyWindow }) ?? windows.first)?.rootViewController
        while let next = vc?.presentedViewController { vc = next }
        return vc
    }

    static func open(_ className: String, title: String) {
        TerraBridge.invoke("openLegacyClass", ["className": className, "title": title])
    }

    static func openAdvanced() { TerraBridge.invoke("openSettings") }

    /// Same as the legacy "Key tweaks" row: CustomControlsViewController presented directly
    /// (NOT inside a navigation controller) with its default-layout callbacks set.
    static func openControlsEditor() {
        guard let cls = NSClassFromString("CustomControlsViewController") as? NSObject.Type,
              let vc = cls.init() as? UIViewController,
              let top = topViewController() else {
            openAdvanced()
            return
        }
        let getter: @convention(block) () -> NSString = {
            let name = TerraBridge.service?.prefValue("control.default_ctrl") as? String ?? ""
            return (name.isEmpty ? "default.json" : name) as NSString
        }
        let setter: @convention(block) (NSString?) -> Void = { name in
            guard let name else { return }
            TerraBridge.service?.setPrefValue(name, forKey: "control.default_ctrl")
        }
        vc.setValue(unsafeBitCast(getter, to: AnyObject.self), forKey: "getDefaultCtrl")
        vc.setValue(unsafeBitCast(setter, to: AnyObject.self), forKey: "setDefaultCtrl")
        vc.modalPresentationStyle = .overFullScreen
        vc.isModalInPresentation = true
        top.present(vc, animated: true)
    }

    /// UpdateChecker +performManualCheckFromPresenter:showUpToDate: (same as legacy "Check for updates")
    static func checkForUpdates() {
        let sel = NSSelectorFromString("performManualCheckFromPresenter:showUpToDate:")
        guard let cls = NSClassFromString("UpdateChecker"),
              (cls as AnyObject).responds(to: sel),
              let top = topViewController() else {
            openAdvanced()
            return
        }
        let checker = unsafeBitCast(cls as AnyObject, to: TSUpdateCheckerClass.self)
        checker.performManualCheck(from: top, showUpToDate: true)
    }

    static var performanceHUDAvailable: Bool {
        CAMetalLayer.instancesRespond(to: NSSelectorFromString("developerHUDProperties"))
    }
}

// MARK: - Screen

struct TerraSettingsScreen: View {
    @EnvironmentObject private var model: TerraLauncherModel
    @StateObject private var store = TSPrefStore()
    @State private var category: TSCategory = .general

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 720
            Group {
                if wide {
                    HStack(spacing: 0) {
                        categoryColumn
                            .frame(width: 220)
                        Rectangle().fill(MCT.border).frame(width: 1)
                        detailPane(wide: true)
                    }
                } else {
                    VStack(spacing: 0) {
                        chipRow
                        detailPane(wide: false)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(MCT.obsidian.ignoresSafeArea())
        .environmentObject(store)
        .environment(\.colorScheme, .dark)
        .tint(MCT.greenBright)
    }

    // MARK: Category navigation

    private var categoryColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                TSAppIcon(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Terra")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(MCT.text)
                    Text("Version \(store.appVersion)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MCT.dim)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 26)
            .padding(.bottom, 22)

            Text("SETTINGS")
                .font(.system(size: 11, weight: .heavy))
                .tracking(2.0)
                .foregroundStyle(MCT.dim)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(TSCategory.allCases) { item in
                        categoryButton(item)
                    }
                }
                .padding(.horizontal, 10)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MCT.charcoal)
    }

    private func categoryButton(_ item: TSCategory) -> some View {
        let selected = item == category
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { category = item }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? MCT.greenBright : MCT.dim)
                    .frame(width: 22)
                Text(item.title)
                    .font(.system(size: 14, weight: selected ? .bold : .medium))
                    .foregroundStyle(selected ? MCT.text : MCT.dim)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? MCT.elevated : Color.clear)
            )
            .overlay(alignment: .leading) {
                if selected {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(MCT.green)
                        .frame(width: 3, height: 20)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TSCategory.allCases) { item in
                    let selected = item == category
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { category = item }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(item.shortTitle)
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(selected ? Color.white : MCT.dim)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(selected ? MCT.green : MCT.elevated)
                        )
                        .overlay(Capsule().strokeBorder(MCT.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(MCT.charcoal)
    }

    // MARK: Detail

    private func detailPane(wide: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(MCT.text)
                    Text(category.summary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MCT.dim)
                }

                content(for: category)

                if category != .about {
                    TSGroup(title: "More") {
                        TSLinkRow(icon: "slider.horizontal.3", title: "Advanced settings",
                                  detail: "Every option, including MobileGlues and debug tools") {
                            TSLegacy.openAdvanced()
                        }
                    }
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, wide ? 32 : 16)
            .padding(.top, wide ? 28 : 18)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(category)
    }

    @ViewBuilder
    private func content(for category: TSCategory) -> some View {
        switch category {
        case .general: TSGeneralPane()
        case .video: TSVideoPane()
        case .java: TSJavaPane()
        case .controls: TSControlsPane()
        case .downloads: TSDownloadsPane()
        case .accounts: TSAccountsPane(username: model.username) { model.openAccount() }
        case .about: TSAboutPane()
        }
    }
}

// MARK: - Category panes

private let tsPolicyOptions = [
    TSOption(key: "auto", name: "Auto"),
    TSOption(key: "official_first", name: "Official"),
    TSOption(key: "mirror_first", name: "Mirror"),
]

private struct TSGeneralPane: View {
    @EnvironmentObject private var store: TSPrefStore

    var body: some View {
        TSGroup(title: "Launcher") {
            TSLinkRow(icon: "globe", title: "Language", detail: "Launcher display language") {
                TSLegacy.open("LauncherLanguageViewController", title: "Language")
            }
        }
        TSGroup(title: "Updates") {
            TSToggleRow(icon: "arrow.triangle.2.circlepath", title: "Check for updates on launch",
                        detail: "At most once per hour", key: "general.auto_check_update", def: true)
            TSDivider()
            TSLinkRow(icon: "arrow.down.app", title: "Check for updates now",
                      detail: "Looks for a newer Terra release") {
                TSLegacy.checkForUpdates()
            }
        }
        TSGroup(title: "Game") {
            TSToggleRow(icon: "square.on.square.dashed", title: "Isolate versions by default",
                        detail: "Keep mods, config and saves per version",
                        key: "general.version_isolation", def: false)
            TSDivider()
            TSToggleRow(icon: "eyeglasses", title: "Cosmetica capes",
                        detail: "Capes from cosmetica.cc (requires OptiFine)",
                        key: "general.cosmetica", def: true)
        }
        TSGroup(title: "Diagnostics") {
            TSToggleRow(icon: "doc.badge.gearshape", title: "Debug logging",
                        detail: "Write extra detail to latestlog.txt",
                        key: "general.debug_logging", def: false)
        }
    }
}

private struct TSVideoPane: View {
    @EnvironmentObject private var store: TSPrefStore

    var body: some View {
        TSGroup(title: "Renderer") {
            TSMenuRow(icon: "cpu", title: "Renderer", detail: "Auto picks the best one per version",
                      key: "video.renderer", def: "auto", options: store.renderers)
            TSDivider()
            TSSliderRow(icon: "viewfinder", title: "Resolution", detail: "Lower it for more FPS",
                        key: "video.resolution", def: 100, range: 25...150, unit: "%")
        }
        TSGroup(title: "Display") {
            TSToggleRow(icon: "hare", title: "Unlock framerate",
                        detail: "Turns VSync off so FPS can exceed the refresh rate",
                        key: "video.disable_game_vsync", def: true)
            TSDivider()
            TSToggleRow(icon: "waveform.path.ecg", title: "Performance HUD",
                        detail: TSLegacy.performanceHUDAvailable ? "Metal overlay with FPS and GPU stats"
                                                                 : "Not available on this iOS version",
                        key: "video.performance_hud", def: false,
                        enabled: TSLegacy.performanceHUDAvailable)
            TSDivider()
            TSToggleRow(icon: "airplayvideo", title: "Fullscreen AirPlay",
                        detail: "Game fills external displays instead of mirroring",
                        key: "video.fullscreen_airplay", def: true)
        }
        TSGroup(title: "Audio") {
            TSToggleRow(icon: "speaker.slash", title: "Pause other audio",
                        detail: "Stops Music and other apps when the game starts",
                        key: "video.silence_other_audio", def: false)
            TSDivider()
            TSToggleRow(icon: "speaker.zzz", title: "Respect silent switch",
                        detail: "Mute in Silent Mode (headphones unaffected)",
                        key: "video.silence_with_switch", def: false)
            TSDivider()
            TSToggleRow(icon: "mic", title: "Microphone input",
                        detail: "Only needed for voice chat mods",
                        key: "video.allow_microphone", def: false)
        }
    }
}

private struct TSJavaPane: View {
    @EnvironmentObject private var store: TSPrefStore

    var body: some View {
        let ram = store.deviceMemoryMB
        let autoRAM = store.bool("java.auto_ram", false)
        let maxMB = max(500, Int(Double(ram) * 0.85))
        let allocated = Int(store.double("java.allocated_memory", Double(ram) * 0.25))

        TSGroup(title: "Memory") {
            TSMemoryBar(deviceMB: ram, allocatedMB: autoRAM ? nil : allocated)
            TSDivider()
            TSToggleRow(icon: "wand.and.stars", title: "Automatic memory",
                        detail: "Let Terra choose the allocation",
                        key: "java.auto_ram", def: false)
            TSDivider()
            TSSliderRow(icon: "memorychip", title: "Memory allocation",
                        detail: autoRAM ? "Turn off automatic memory to adjust" : "Memory given to Minecraft",
                        key: "java.allocated_memory", def: Double(ram) * 0.25,
                        range: 250...Double(maxMB), unit: " MB", enabled: !autoRAM,
                        warnAbove: Double(ram) * 0.37,
                        warnText: "iOS may close the game at this level")
        }
        TSGroup(title: "Runtime") {
            TSLinkRow(icon: "cube", title: "Manage Java runtimes",
                      detail: "Java 8, 17, 21 and imported runtimes") {
                TSLegacy.open("LauncherPrefManageJREViewController", title: "Java Runtimes")
            }
            TSDivider()
            TSTextFieldRow(icon: "slider.vertical.3", title: "JVM arguments",
                           detail: "Wrong arguments can stop the game from starting",
                           key: "java.java_args", placeholder: "-XX:+UseG1GC")
            TSDivider()
            TSTextFieldRow(icon: "terminal", title: "Environment variables",
                           detail: "Space-separated KEY=value pairs",
                           key: "java.env_variables", placeholder: "KEY=value")
        }
    }
}

private struct TSControlsPane: View {
    @EnvironmentObject private var store: TSPrefStore

    var body: some View {
        let gyro = store.bool("control.gyroscope_enable", false)
        let touchController = store.bool("control.mod_touch_enable", false)
        let tapClick = store.bool("control.tap_click_enable", true)

        TSGroup(title: "On-screen controls") {
            TSLinkRow(icon: "square.grid.3x3.square", title: "Edit control layout",
                      detail: "Drag, resize and add on-screen buttons") {
                TSLegacy.openControlsEditor()
            }
            TSDivider()
            TSSliderRow(icon: "aspectratio", title: "Button scale", detail: "Enlarge buttons on big screens",
                        key: "control.button_scale", def: 100, range: 50...500, unit: "%")
            TSDivider()
            TSToggleRow(icon: "eye.slash", title: "Hide with hardware input",
                        detail: "Hide controls when a mouse or controller connects",
                        key: "control.hardware_hide", def: true)
            TSDivider()
            TSToggleRow(icon: "record.circle", title: "Hide from recordings",
                        detail: "Controls stay off screenshots and recordings",
                        key: "control.recording_hide", def: true)
            TSDivider()
            TSToggleRow(icon: "gearshape", title: "In-game menu button",
                        detail: "Show the floating gear while playing",
                        key: "control.menu_button_visible", def: true)
        }
        TSGroup(title: "Touch") {
            TSToggleRow(icon: "hand.tap", title: "Tap to click",
                        detail: "A quick tap sends one full click",
                        key: "control.tap_click_enable", def: true)
            TSDivider()
            TSSegmentRow(icon: "cursorarrow.click", title: "Tap button",
                         detail: "Auto chooses attack or use by target",
                         key: "control.tap_click_mode", def: "auto",
                         options: [TSOption(key: "auto", name: "Auto"),
                                   TSOption(key: "left", name: "Left"),
                                   TSOption(key: "right", name: "Right")],
                         enabled: tapClick)
            TSDivider()
            TSSliderRow(icon: "timer", title: "Long-press duration", detail: "Hold time to break blocks",
                        key: "control.press_duration", def: 400, range: 100...1000, unit: " ms")
            TSDivider()
            TSToggleRow(icon: "cursorarrow.click.2", title: "Mouse gestures",
                        detail: "Tap to place, hold to break, two-finger scroll",
                        key: "control.gesture_mouse", def: true)
            TSDivider()
            TSToggleRow(icon: "hand.draw", title: "Hotbar gestures",
                        detail: "Tap slots, swap hands, throw items",
                        key: "control.gesture_hotbar", def: true)
            TSDivider()
            TSToggleRow(icon: "slider.horizontal.below.rectangle", title: "Slideable hotbar",
                        detail: touchController ? "Unavailable while TouchController is on"
                                                : "Swipe the hotbar like a scroll wheel",
                        key: "control.slideable_hotbar", def: false, enabled: !touchController)
            TSDivider()
            TSToggleRow(icon: "wave.3.left", title: "Disable haptics",
                        detail: "No vibration from on-screen controls",
                        key: "control.disable_haptics", def: false)
        }
        TSGroup(title: "Mouse") {
            TSToggleRow(icon: "cursorarrow.rays", title: "Start with virtual mouse",
                        detail: "Virtual cursor is on when the game opens",
                        key: "control.virtmouse_enable", def: false)
            TSDivider()
            TSSliderRow(icon: "cursorarrow.motionlines", title: "Mouse speed", detail: nil,
                        key: "control.mouse_speed", def: 100, range: 25...300, unit: "%")
            TSDivider()
            TSSliderRow(icon: "arrow.up.left.and.arrow.down.right", title: "Cursor size", detail: nil,
                        key: "control.mouse_scale", def: 100, range: 25...300, unit: "%")
            TSDivider()
            TSToggleRow(icon: "computermouse", title: "Bluetooth mouse & trackpad",
                        detail: "Use a paired pointer as a real mouse",
                        key: "control.bt_pointer_enable", def: true)
        }
        TSGroup(title: "Gyroscope") {
            TSToggleRow(icon: "gyroscope", title: "Gyroscope aiming",
                        detail: "Turn in game by moving your device",
                        key: "control.gyroscope_enable", def: false)
            TSDivider()
            TSToggleRow(icon: "arrow.left.and.right", title: "Invert horizontal axis", detail: nil,
                        key: "control.gyroscope_invert_x_axis", def: false, enabled: gyro)
            TSDivider()
            TSSliderRow(icon: "move.3d", title: "Gyroscope sensitivity", detail: nil,
                        key: "control.gyroscope_sensitivity", def: 100, range: 50...300, unit: "%",
                        enabled: gyro)
        }
        TSGroup(title: "Controllers & mods") {
            TSLinkRow(icon: "gamecontroller", title: "Controller mapping",
                      detail: "Gamepad button bindings") {
                TSLegacy.open("LauncherPrefContCfgViewController", title: "Controller Mapping")
            }
            TSDivider()
            TSLinkRow(icon: "hand.point.up.left", title: "TouchController mod",
                      detail: touchController ? "Enabled" : "Native touch controls for supported mods") {
                TSLegacy.open("TouchControllerPreferencesViewController", title: "TouchController")
            }
        }
    }
}

private struct TSDownloadsPane: View {
    @EnvironmentObject private var store: TSPrefStore

    var body: some View {
        let hasKey = !store.string("general.curseforge_api_key", "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        TSGroup(title: "Download sources") {
            TSSegmentRow(icon: "arrow.down.circle", title: "Game files",
                         detail: "Versions, libraries and assets",
                         key: "download.fileSource", def: "auto", options: tsPolicyOptions)
            TSDivider()
            TSSegmentRow(icon: "magnifyingglass", title: "Mod & resource search",
                         detail: "Modrinth and CurseForge queries",
                         key: "download.assetSearchSource", def: "auto", options: tsPolicyOptions)
            TSDivider()
            TSSegmentRow(icon: "square.and.arrow.down", title: "Mod & resource files",
                         detail: "Mod, shader and pack downloads",
                         key: "download.assetDownloadSource", def: "auto", options: tsPolicyOptions)
            TSDivider()
            TSSegmentRow(icon: "wrench.and.screwdriver", title: "Mod loaders",
                         detail: "Fabric, Forge and NeoForge",
                         key: "download.modLoaderSource", def: "auto", options: tsPolicyOptions)
            TSDivider()
            TSSegmentRow(icon: "network", title: "Mod mirror",
                         detail: "API and file mirror for content downloads",
                         key: "general.mod_mirror", def: "official",
                         options: [TSOption(key: "official", name: "Official"),
                                   TSOption(key: "mcim", name: "MCIM")])
        }
        TSGroup(title: "Behavior") {
            TSToggleRow(icon: "bolt.fill", title: "Multi-threaded downloads",
                        detail: "Download several files at once",
                        key: "general.multi_threaded", def: false)
            TSDivider()
            TSToggleRow(icon: "lock.shield", title: "Verify downloads",
                        detail: "Check file hashes to catch broken files",
                        key: "general.check_sha", def: true)
        }
        TSGroup(title: "CurseForge") {
            TSLinkRow(icon: "key.fill", title: "CurseForge API key",
                      detail: "Search needs a free key from console.curseforge.com",
                      trailing: hasKey ? "Set" : "Not set") {
                TSLegacy.open("CurseForgeAPIKeyViewController", title: "CurseForge API Key")
            }
        }
    }
}

private struct TSAccountsPane: View {
    let username: String
    let manage: () -> Void

    var body: some View {
        TSGroup(title: "Current account") {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.square.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(MCT.greenBright)
                VStack(alignment: .leading, spacing: 3) {
                    Text(username.isEmpty ? "Not signed in" : username)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(MCT.text)
                        .lineLimit(1)
                    Text("Used for the next launch")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MCT.dim)
                }
                Spacer(minLength: 8)
                Button(action: manage) {
                    Label("Manage accounts", systemImage: "person.2.fill")
                        .labelStyle(TerraIconFirstLabel())
                }
                .buttonStyle(MCPrimaryButtonStyle())
                .fixedSize()
            }
            .padding(16)
        }
        TSGroup(title: "Accounts") {
            TSLinkRow(icon: "plus.circle", title: "Add or switch account",
                      detail: "Microsoft, local or third-party sign-in", action: manage)
        }
    }
}

private struct TSAboutPane: View {
    @EnvironmentObject private var store: TSPrefStore
    @Environment(\.openURL) private var openURL

    private let repo = "https://github.com/mineverse67890-ai/Terra-iOS"

    var body: some View {
        VStack(spacing: 14) {
            TSAppIcon(size: 88)
            VStack(spacing: 4) {
                Text("Terra")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(MCT.text)
                Text(store.appBuild.isEmpty || store.appBuild == store.appVersion
                     ? "Version \(store.appVersion)"
                     : "Version \(store.appVersion) (\(store.appBuild))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MCT.greenBright)
                Text(store.deviceLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MCT.dim)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .mcSurface()

        TSGroup(title: "Links") {
            TSLinkRow(icon: "chevron.left.forwardslash.chevron.right", title: "GitHub",
                      detail: "Source code and releases", trailing: nil, external: true) {
                if let url = URL(string: repo) { openURL(url) }
            }
            TSDivider()
            TSLinkRow(icon: "exclamationmark.bubble", title: "Report an issue",
                      detail: "Open a GitHub issue", trailing: nil, external: true) {
                if let url = URL(string: repo + "/issues") { openURL(url) }
            }
        }
        TSGroup(title: "Credits") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Based on Angel Aura Amethyst")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MCT.text)
                Text("Not an official Minecraft product. Not approved by or associated with Mojang or Microsoft.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MCT.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}

// MARK: - Building blocks

private struct TSAppIcon: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = UIImage(named: "AppLogo-Current") {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                ZStack {
                    MCT.green
                    Image(systemName: "cube.fill")
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct TSGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(MCT.dim)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .mcSurface()
        }
    }
}

private struct TSDivider: View {
    var body: some View {
        Rectangle()
            .fill(MCT.border)
            .frame(height: 1)
            .padding(.leading, 60)
    }
}

/// Icon tile + title + one secondary line + trailing control
private struct TSRowShell<Trailing: View>: View {
    let icon: String
    let title: String
    let detail: String?
    var detailColor: Color = MCT.dim
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MCT.greenBright)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(MCT.green.opacity(0.16))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MCT.text)
                    .lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(detailColor)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct TSToggleRow: View {
    @EnvironmentObject private var store: TSPrefStore
    let icon: String
    let title: String
    let detail: String?
    let key: String
    let def: Bool
    var enabled = true

    var body: some View {
        TSRowShell(icon: icon, title: title, detail: detail) {
            Toggle("", isOn: store.boolBinding(key, def))
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: MCT.green))
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

private struct TSLinkRow: View {
    let icon: String
    let title: String
    let detail: String?
    var trailing: String? = nil
    var external = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TSRowShell(icon: icon, title: title, detail: detail) {
                HStack(spacing: 8) {
                    if let trailing {
                        Text(trailing)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MCT.dim)
                    }
                    Image(systemName: external ? "arrow.up.right" : "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MCT.dim.opacity(0.7))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Dropdown for long option lists (renderer)
private struct TSMenuRow: View {
    @EnvironmentObject private var store: TSPrefStore
    let icon: String
    let title: String
    let detail: String?
    let key: String
    let def: String
    let options: [TSOption]

    var body: some View {
        let current = store.string(key, def)
        let currentName = options.first(where: { $0.key == current })?.name ?? current
        TSRowShell(icon: icon, title: title, detail: detail) {
            Menu {
                ForEach(options) { option in
                    Button {
                        store.setString(option.key, key)
                    } label: {
                        if option.key == current {
                            Label(option.name, systemImage: "checkmark")
                        } else {
                            Text(option.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(currentName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(MCT.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(MCT.elevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(MCT.border, lineWidth: 1)
                        )
                )
                .frame(maxWidth: 220, alignment: .trailing)
            }
        }
    }
}

/// Minecraft-style segmented control (green selected segment), shown under the title
private struct TSSegmentRow: View {
    @EnvironmentObject private var store: TSPrefStore
    let icon: String
    let title: String
    let detail: String?
    let key: String
    let def: String
    let options: [TSOption]
    var enabled = true

    var body: some View {
        let current = store.string(key, def)
        ViewThatFits(in: .horizontal) {
            TSRowShell(icon: icon, title: title, detail: detail) {
                segments(current).frame(width: CGFloat(options.count) * 78)
            }
            VStack(alignment: .leading, spacing: 0) {
                TSRowShell(icon: icon, title: title, detail: detail) { EmptyView() }
                segments(current)
                    .padding(.leading, 60)
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
            }
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private func segments(_ current: String) -> some View {
        HStack(spacing: 3) {
            ForEach(options) { option in
                let selected = option.key == current
                Button {
                    store.setString(option.key, key)
                } label: {
                    Text(option.name)
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selected ? Color.white : MCT.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selected ? MCT.green : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MCT.obsidian)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(MCT.border, lineWidth: 1)
                )
        )
    }
}

/// Slider with live value; writes once when the drag ends
private struct TSSliderRow: View {
    @EnvironmentObject private var store: TSPrefStore
    let icon: String
    let title: String
    let detail: String?
    let key: String
    let def: Double
    let range: ClosedRange<Double>
    let unit: String
    var enabled = true
    var warnAbove: Double? = nil
    var warnText: String? = nil

    @State private var draft: Double = 0
    @State private var editing = false
    @State private var loaded = false

    private var warning: Bool {
        guard let warnAbove, enabled else { return false }
        return draft >= warnAbove
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TSRowShell(icon: icon, title: title,
                       detail: warning ? (warnText ?? detail) : detail,
                       detailColor: warning ? MCT.danger : MCT.dim) {
                Text("\(Int(draft.rounded()))\(unit)")
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(warning ? MCT.danger : MCT.text)
                    .fixedSize()
            }
            Slider(value: $draft, in: range, step: 1) { isEditing in
                editing = isEditing
                if !isEditing { commit() }
            }
            .tint(warning ? MCT.danger : MCT.green)
            .padding(.leading, 60)
            .padding(.trailing, 16)
            .padding(.bottom, 12)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .onAppear { reload() }
        .onChange(of: store.revision) { _ in if !editing { reload() } }
    }

    private func clamp(_ v: Double) -> Double { min(max(v, range.lowerBound), range.upperBound) }

    private func reload() {
        draft = clamp(store.double(key, def).rounded())
        loaded = true
    }

    private func commit() {
        guard loaded else { return }
        let value = Int(clamp(draft).rounded())
        if Int(store.double(key, def).rounded()) != value { store.setInt(value, key) }
    }
}

/// Text field with explicit Save
private struct TSTextFieldRow: View {
    @EnvironmentObject private var store: TSPrefStore
    let icon: String
    let title: String
    let detail: String?
    let key: String
    let placeholder: String

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let stored = store.string(key, "")
        VStack(alignment: .leading, spacing: 0) {
            TSRowShell(icon: icon, title: title, detail: detail) { EmptyView() }
            HStack(spacing: 8) {
                TextField(placeholder, text: $draft)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(MCT.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit { save() }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(MCT.obsidian)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(focused ? MCT.green : MCT.border, lineWidth: 1)
                            )
                    )
                Button("Save") { save() }
                    .buttonStyle(MCPrimaryButtonStyle())
                    .frame(width: 84)
                    .disabled(draft == stored)
                    .opacity(draft == stored ? 0.45 : 1)
            }
            .padding(.leading, 60)
            .padding(.trailing, 16)
            .padding(.bottom, 12)
        }
        .onAppear { draft = stored }
        .onChange(of: store.revision) { _ in if !focused { draft = store.string(key, "") } }
    }

    private func save() {
        store.setString(draft.trimmingCharacters(in: .whitespacesAndNewlines), key)
        draft = store.string(key, "")
        focused = false
    }
}

/// Device RAM vs. allocation
private struct TSMemoryBar: View {
    let deviceMB: Int
    let allocatedMB: Int?

    var body: some View {
        let fraction = allocatedMB.map { min(1, max(0, Double($0) / Double(max(deviceMB, 1)))) } ?? 0
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DEVICE MEMORY")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(MCT.dim)
                    Text(String(format: "%.1f GB", Double(deviceMB) / 1024))
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                        .foregroundStyle(MCT.text)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("FOR MINECRAFT")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(MCT.dim)
                    Text(allocatedMB.map { "\($0) MB" } ?? "Automatic")
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                        .foregroundStyle(MCT.greenBright)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(MCT.obsidian)
                    Capsule()
                        .fill(MCT.playGradient)
                        .frame(width: max(allocatedMB == nil ? 0 : 6, geo.size.width * fraction))
                }
            }
            .frame(height: 8)
        }
        .padding(16)
    }
}
