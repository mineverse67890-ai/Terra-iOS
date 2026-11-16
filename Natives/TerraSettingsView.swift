// ===========================================================================
//  ★ [TERRA-UI] TerraSettingsView.swift —— Settings (official launcher style)
//  ---------------------------------------------------------------------------
//  Official settings look: charcoal group cards + green accents.
//  Deep preferences (renderer/memory/language) still reuse the existing
//  LauncherPreferencesViewController, presented modally via TerraBridge.
//  ===========================================================================
import SwiftUI

struct TerraSettingsScreen: View {
    @EnvironmentObject private var model: TerraLauncherModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("SETTINGS")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2.4)
                    .foregroundStyle(MCT.greenBright)
                    .padding(.top, 18)

                settingsSection("Account") {
                    settingsRow(icon: "person.crop.circle.fill", title: "Account Management",
                                subtitle: model.username) {
                        model.openAccount()
                    }
                }

                settingsSection("Launcher") {
                    settingsRow(icon: "slider.horizontal.3", title: "Full Preferences",
                                subtitle: "Renderer · Memory · Language · Control layout") {
                        model.openFullSettings()
                    }
                }

                settingsSection("About") {
                    settingsRow(icon: "info.circle.fill", title: "Terra-iOS",
                                subtitle: "Minecraft launcher for iOS · Official dark style") {}
                    settingsRow(icon: "bolt.fill", title: "Download source",
                                subtitle: model.downloadSource) {}
                }

                Spacer(minLength: 30)
            }
            .padding(.horizontal, 28)
        }
    }

    // MARK: Groups

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(MCT.dim)
            VStack(spacing: 0) { content() }
                .mcSurface()
        }
    }

    private func settingsRow(icon: String, title: String,
                             subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(MCT.greenBright)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MCT.text)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MCT.dim)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MCT.dim.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}