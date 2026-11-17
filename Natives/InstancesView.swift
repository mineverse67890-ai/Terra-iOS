// ===========================================================================
//  ★ [TERRA-UI] InstancesView.swift —— Installations tab (official replica)
//  ---------------------------------------------------------------------------
//  Each card maps to an isolated instance directory:
//      Documents/instances/<name>/minecraft/
//  Shows: Minecraft version · loader badge (Fabric/Vanilla) · folder size.
//  Actions: Launch (green) · Open Mods · Settings (Java version etc.) · Delete (red, confirmed).
//  Data source: TerraBridge (ObjC TerraLauncherService) snapshot.
//  ===========================================================================
import SwiftUI

struct TerraInstancesScreen: View {
    @EnvironmentObject private var model: TerraLauncherModel
    @State private var searchText = ""
    @State private var pendingDelete: TerraInstance?

    private var filtered: [TerraInstance] {
        guard !searchText.isEmpty else { return model.instances }
        return model.instances.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Search + count
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MCT.dim)
                        TextField("Search installations", text: $searchText)
                            .font(.system(size: 14))
                            .foregroundStyle(MCT.text)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(MCT.charcoal)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(MCT.border, lineWidth: 1))
                    )
                    Text("\(model.instances.count) installations")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MCT.dim)
                }
                .padding(.top, 18)

                if filtered.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { instance in
                            TerraInstanceRow(instance: instance,
                                             isCurrent: instance.name == model.selectedName,
                                             onDelete: { pendingDelete = instance })
                        }
                    }
                }
                Spacer(minLength: 30)
            }
            .padding(.horizontal, 28)
        }
        .confirmationDialog("Delete installation \"\(pendingDelete?.name ?? "")\"?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete installation", role: .destructive) {
                if let target = pendingDelete { model.deleteInstance(target) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Removes this installation from the list. Your downloaded game files, worlds and mods are kept.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 34))
                .foregroundStyle(MCT.dim)
            Text("No installations found")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MCT.text)
            Text("Pick a version in the Download Center to create a new installation")
                .font(.system(size: 12))
                .foregroundStyle(MCT.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .mcSurface()
        .padding(.top, 6)
    }
}

// MARK: - Installation card

struct TerraInstanceRow: View {
    let instance: TerraInstance
    let isCurrent: Bool
    let onDelete: () -> Void

    @EnvironmentObject private var model: TerraLauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                // Instance icon block
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [MCT.green.opacity(0.5), MCT.green.opacity(0.12)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: instance.isFabric ? "puzzlepiece.fill" : "cube.transparent.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(MCT.border, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(instance.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(MCT.text)
                            .lineLimit(1)
                        if isCurrent {
                            Text("ACTIVE")
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(MCT.green.opacity(0.3)))
                                .foregroundStyle(MCT.greenBright)
                        }
                    }
                    HStack(spacing: 8) {
                        MCLoaderBadge(loader: instance.loader)
                        Text("MC \(instance.version)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MCT.dim)
                        Text(instance.sizeText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MCT.dim.opacity(0.8))
                    }
                }
                Spacer()
            }

            // Action row: Launch (green) / Open Mods / Delete (red)
            HStack(spacing: 10) {
                Button {
                    model.launch(instance)
                } label: {
                    Label("Launch", systemImage: "play.fill")
                        .labelStyle(TerraIconFirstLabel())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(MCT.green)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    model.openMods(instance)
                } label: {
                    Label("Open Mods", systemImage: "puzzlepiece")
                        .labelStyle(TerraIconFirstLabel())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MCT.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(MCT.elevated)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(MCT.border, lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    model.openSettings(instance)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MCT.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(MCT.elevated)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(MCT.border, lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Installation settings")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MCT.danger)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(MCT.elevated)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(MCT.danger.opacity(0.35), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .mcSurface()
    }
}
