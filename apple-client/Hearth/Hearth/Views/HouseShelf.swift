//
//  HouseShelf.swift
//  Hearth
//
//  The house's navigation drawer. Slides in from the RIGHT, under the thumb of
//  the hand already holding the phone — the hamburger sits in the same corner
//  so opening it costs no reach.
//
//  It is the single entry to everything that is not the conversation, which is
//  what keeps the app at three buttons: tap to talk, keyboard, hamburger.
//  Personas switch live; Journal and Apps & Extensions are top-level
//  destinations that will each own a SwiftUI view (designs in
//  tasks/journal-design.md and tasks/apps-design.md) and read as SOON until
//  then. Settings opens the existing view -- its redesign is round 3, tracking
//  the desktop pass in flight.
//

import SwiftUI
import HearthCore

struct HouseShelf: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var transcriptShown: Bool
    @Binding var isOpen: Bool
    var onOpenJournal: () -> Void = {}
    var onOpenApps: () -> Void = {}
    var onOpenPersona: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !viewModel.availablePersonas.isEmpty {
                        SectionLabel("Personas")
                        ForEach(viewModel.availablePersonas, id: \.self) { name in
                            PersonaRow(
                                name: name,
                                isActive: name == viewModel.selectedPersona
                            ) {
                                viewModel.switchPersona(name)
                                close()
                            }
                        }
                        Divider().overlay(HearthPalette.linen).padding(.vertical, 10)
                    }

                    // Top-level destinations, each its own view when built.
                    ShelfRow(title: "Journal", icon: { HearthIcon(shape: BookIcon()) }) {
                        close()
                        onOpenJournal()
                    }
                    ShelfRow(title: "Persona", icon: { HearthIcon(shape: PersonIcon()) }) {
                        close()
                        onOpenPersona()
                    }
                    ShelfRow(title: "Apps & Extensions", icon: { HearthIcon(shape: GridIcon()) }) {
                        close()
                        onOpenApps()
                    }
                }
                .padding(.top, 4)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .frame(width: 268)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(HearthPalette.parchment)
        .overlay(alignment: .leading) {
            HearthPalette.linen.frame(width: 1)
        }
        .shadow(color: HearthPalette.shadow.opacity(2.2), radius: 18, x: -6, y: 0)
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Hearth")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(HearthPalette.roast)
            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(HearthPalette.fawn)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { HearthPalette.linen.frame(height: 1) }
    }

    private var subtitle: String {
        switch viewModel.connectionStatus {
        case .connected:    return "Connected as \(viewModel.currentPersonaName)"
        case .connecting:   return "Connecting..."
        case .disconnected: return "Offline"
        }
    }

    /// Pinned to the bottom: the chat log switch and Settings.
    private var footer: some View {
        VStack(spacing: 0) {
            HearthPalette.linen.frame(height: 1)

            Toggle(isOn: $transcriptShown) {
                Label {
                    Text("Chat log")
                        .font(.system(size: 14))
                        .foregroundStyle(HearthPalette.roast)
                } icon: {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 13))
                        .foregroundStyle(HearthPalette.fawn)
                        .frame(width: 22)
                }
            }
            .tint(HearthPalette.fennec)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            ShelfRow(title: "Settings", icon: { HearthIcon(shape: GearIcon()) }) {
                close()
                viewModel.showSettings = true
            }
            .padding(.bottom, 18)
        }
    }

    private func close() {
        withAnimation(.spring(duration: 0.3)) { isOpen = false }
    }
}

// MARK: - Rows

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.9)
            .foregroundStyle(HearthPalette.fawn)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

private struct ShelfRow<Icon: View>: View {
    let title: String
    @ViewBuilder var icon: Icon
    var badge: String? = nil
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(title: String, badge: String? = nil,
         @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) {
        self.title = title
        self.badge = badge
        self.icon = icon()
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                icon
                    .foregroundStyle(HearthPalette.fawn)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(HearthPalette.roast)
                Spacer(minLength: 8)
                if let badge {
                    Text(badge)
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(HearthPalette.fawn)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(HearthPalette.fluff, in: Capsule())
                        .overlay(Capsule().stroke(HearthPalette.linen, lineWidth: 1))
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.42)
    }
}

private struct PersonaRow: View {
    let name: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Circle()
                    .fill(HearthPalette.speaker(name))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Text(String(name.prefix(1)))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    )
                Text(name)
                    .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(HearthPalette.roast)
                Spacer(minLength: 8)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(HearthPalette.ember)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
