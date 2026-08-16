//
//  HearthSettingsView.swift
//  Hearth
//
//  Settings, round 3. Same shape as the Journal -- full screen, "Hearth" back
//  on the left, large title in the body -- so every destination off the house
//  shelf behaves alike.
//
//  Which sections exist is decided by ClientProfile, never by a platform
//  check: a row declares what it needs, the client declares what it has. iOS
//  carries no capability tags, so the on-disk, theme and developer rows the
//  desktop shows never render here.
//
//  Valinor moved its Ray-Ban rows out of here and into Apps under On device,
//  on the argument that the glasses are this phone's and not the house's. That
//  argument outlived the rows: MWDAT did not come across, so the rows are gone
//  from both places, but the ownership split they demonstrated is what Apps is
//  still organised by.
//
//  Mockup of record: hearth-pitch/mockups/hearth-ios-settings-mockup.html
//  Sections still to come: Personas and Voice (item 12).
//

import SwiftUI
import HearthCore

struct HearthSettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var surface = SettingsSurfaceLoader()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ConnectionSection(viewModel: viewModel)

                    if ClientProfile.can(.devPane) {
                        // Never renders on iOS. Here so the shape is obvious
                        // when macOS is added to the table.
                        SettingsSection(title: "Developer") { EmptyView() }
                    }

                    if let loaded = surface.surface {
                        MemorySection(surface: loaded)
                        ConnectionsSection(connections: loaded.connections)
                    }
                    footer(server: surface.surface?.server)
                }
                .padding(.bottom, 30)
            }
            .task { await surface.load() }
            .background(HearthPalette.cream.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hearth") { dismiss() }
                        .tint(HearthPalette.ember)
                }
            }
            .toolbarBackground(HearthPalette.parchment, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(HearthPalette.roast)
            Text("this device, and what the house allows")
                .font(.system(size: 12.5))
                .italic()
                .foregroundStyle(HearthPalette.fawn)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }

    private func footer(server: SettingsSurface.Server?) -> some View {
        VStack(spacing: 3) {
            if let server, !server.version.isEmpty {
                Text("\(ClientProfile.label), Valar \(server.version) on :\(server.port), brain \(server.brain_backend)")
            } else {
                Text(ClientProfile.label)
            }
            Text("local-first, nothing here leaves the house")
        }
        .font(.system(size: 10.5))
        .multilineTextAlignment(.center)
        .foregroundStyle(HearthPalette.fawn)
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
        .padding(.horizontal, 24)
    }
}

// MARK: - House settings (read-only)

/// Memory and journal. Every value here is an env var read once at Valar
/// start; there is no setter in the protocol, which is why the badge says so
/// rather than offering controls that could not work.
private struct MemorySection: View {
    let surface: SettingsSurface

    var body: some View {
        SettingsSection(title: "Memory & journal", badge: "House, read-only") {
            VStack(alignment: .leading, spacing: 12) {
                SettingsRow(label: "Remember our conversations",
                            hint: "Selene keeps what matters and forgets the rest.") {
                    Text(surface.resolvedValue("memory") ?? "unknown")
                        .font(.system(size: 12.5))
                        .foregroundStyle(HearthPalette.fawn)
                }
                SettingsRow(label: "End a session after",
                            hint: "Quiet time before the house closes the page and writes it up.") {
                    Text(surface.resolvedValue("session idle") ?? "unknown")
                        .font(.system(size: 12.5))
                        .foregroundStyle(HearthPalette.fawn)
                }
            }
        }
    }
}

/// A registry, not a fixed list: render whatever arrives, skip nothing,
/// invent nothing. It grows when the house does.
private struct ConnectionsSection: View {
    let connections: [SettingsSurface.Connection]

    var body: some View {
        if !connections.isEmpty {
            SettingsSection(title: "Connections", badge: "House, read-only") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(connections) { connection in
                        HStack(alignment: .top, spacing: 9) {
                            Circle()
                                .fill(connection.isLive
                                      ? HearthPalette.fennec
                                      : HearthPalette.fawn.opacity(0.45))
                                .frame(width: 7, height: 7)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(connection.name)
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(HearthPalette.roast)
                                Text(connection.role)
                                    .font(.system(size: 11))
                                    .foregroundStyle(HearthPalette.fawn)
                                if !connection.detail.isEmpty {
                                    Text(connection.detail)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(HearthPalette.fawn.opacity(0.85))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 6)
                            Text(connection.isLive ? "live" : "off")
                                .font(.system(size: 11.5))
                                .foregroundStyle(HearthPalette.fawn)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Connection

/// The section that matters most on a phone, because away-from-home (M7)
/// lands in this field.
private struct ConnectionSection: View {
    @ObservedObject var viewModel: ChatViewModel

    @State private var address = ServerConfig.shared.address
    @State private var probe: ProbeState = .idle
    @State private var confirmForget = false
    @FocusState private var addressFocused: Bool

    private enum ProbeState: Equatable {
        case idle
        case testing
        case ok(String)
        case failed
    }

    var body: some View {
        SettingsSection(title: "Connection") {
            VStack(alignment: .leading, spacing: 0) {
                Text("Server address")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(HearthPalette.roast)
                Text("Hostname or IP of the Valar server. A tailnet name works from anywhere.")
                    .font(.system(size: 11))
                    .lineSpacing(1)
                    .foregroundStyle(HearthPalette.fawn)
                    .padding(.top, 2)

                // Plain keyboard on purpose: the old field used .decimalPad,
                // which made a hostname literally untypeable.
                // Placeholder, not a default. Valinor shipped a hardcoded house
                // address here and this field offered to restore it; Hearth has
                // no house until the person names one.
                //
                // The same words as first run, and deliberately NOT an example
                // address: a plausible-looking literal in the source is exactly
                // what the RFC1918 gate hunts, and it was right to stop the one
                // that was here first.
                TextField("hostname or IP", text: $address)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(HearthPalette.roast)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .focused($addressFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(HearthPalette.parchment, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(HearthPalette.linen, lineWidth: 1)
                    )
                    .padding(.top, 7)
                    .onSubmit { addressFocused = false }

                HStack(spacing: 8) {
                    Button { test() } label: {
                        Label2(text: probe == .testing ? "Testing..." : "Test", style: .ghost)
                    }
                    .buttonStyle(.plain)
                    .disabled(probe == .testing)

                    Button { apply() } label: {
                        Label2(text: "Apply & reconnect", style: .primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 9)

                status.padding(.top, 9)

                Divider().overlay(HearthPalette.linen).padding(.vertical, 11)

                // The local half of unpairing. The house still lists this
                // device until someone revokes it at the desk, and the copy
                // must not promise more than that.
                Button { confirmForget = true } label: {
                    Text("Forget this house")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(HearthPalette.clay)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(HearthPalette.parchment, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(HearthPalette.clayLine, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!ServerConfig.shared.isConfigured)
                .confirmationDialog(
                    "Forget this house?",
                    isPresented: $confirmForget,
                    titleVisibility: .visible
                ) {
                    Button("Forget", role: .destructive) { forgetHouse() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Clears the address and this phone's key, and returns to first run. The house still lists this device until it is revoked there.")
                }
            }
        }
    }

    /// Both halves at once: the key and the address. Clearing the address
    /// posts the configured notification, and the root view answers by
    /// swapping back to first run; the redial tears the dead socket down.
    private func forgetHouse() {
        Pairing.forget()
        ServerConfig.shared.address = ""
        address = ""
        Task { await viewModel.redial() }
    }

    private var status: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.system(size: 11.5))
                .foregroundStyle(HearthPalette.fawn)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var statusColor: Color {
        switch probe {
        case .ok:     return HearthPalette.fennec
        case .failed: return Color(red: 0.66, green: 0.31, blue: 0.23)
        default:
            return viewModel.connectionStatus == .connected
                ? HearthPalette.fennec
                : HearthPalette.fawn.opacity(0.5)
        }
    }

    private var statusText: String {
        switch probe {
        case .testing:
            return "Testing \(ServerConfig.shared.address)..."
        case .ok(let detail):
            return detail
        case .failed:
            return "No answer from \(ServerConfig.shared.address). Check the address, or clear the field to forget this house."
        case .idle:
            switch viewModel.connectionStatus {
            case .connected:    return "Connected to \(ServerConfig.shared.address)"
            case .connecting:   return "Connecting to \(ServerConfig.shared.address)..."
            case .disconnected: return "Not connected"
            }
        }
    }

    /// Test probes whatever is TYPED, not what is saved, so a bad address is
    /// discovered before it takes the live socket down. The typed value is
    /// staged, probed, then rolled back if the user does not apply it.
    private func test() {
        addressFocused = false
        let previous = ServerConfig.shared.address
        ServerConfig.shared.address = address
        probe = .testing
        Task { @MainActor in
            let result = await ChatViewModel.probeHealth()
            if let result {
                probe = .ok("\(ServerConfig.shared.address) answered in \(result.latencyMs) ms, brain \(result.brainReady ? "ready" : "not ready") (\(result.brainBackend))")
            } else {
                probe = .failed
            }
            // Leave the saved config as it was; Apply is what commits.
            ServerConfig.shared.address = previous
        }
    }

    private func apply() {
        addressFocused = false
        // commitAddress, not the raw setter: pointing at a different house
        // surrenders the old house's token, and the root view walks the
        // person through pairing with the new one.
        ServerConfig.shared.commitAddress(address)
        // Normalised (scheme stripped, default port folded away).
        address = ServerConfig.shared.address
        probe = .idle
        Task { await viewModel.redial() }
    }
}

// MARK: - Section chrome

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var badge: String? = nil

    init(title: String, badge: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.badge = badge
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(HearthPalette.ember)
                if let badge {
                    Text(badge.uppercased())
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(HearthPalette.fawn)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(HearthPalette.fluff, in: Capsule())
                        .overlay(Capsule().stroke(HearthPalette.linen, lineWidth: 1))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 7)

            VStack(spacing: 0) { content }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HearthPalette.fluff, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(HearthPalette.linen, lineWidth: 1)
                )
                .hearthSoftShadow()
                .padding(.horizontal, 14)
        }
        .padding(.top, 16)
    }
}

struct SettingsRow<Accessory: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(HearthPalette.roast)
                if let hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .lineSpacing(1)
                        .foregroundStyle(HearthPalette.fawn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            accessory
        }
        .contentShape(Rectangle())
    }
}

/// Small pill button used by the Connection actions.
private struct Label2: View {
    enum Style { case primary, ghost }
    let text: String
    let style: Style

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(HearthPalette.roast)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                style == .primary ? HearthPalette.fennec : HearthPalette.parchment,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(style == .primary ? .clear : HearthPalette.linen, lineWidth: 1)
            )
    }
}
