//
//  AppsView.swift
//  Hearth
//
//  Apps and Extensions, round 4. Same shape as Journal and Settings -- full
//  screen, "Hearth" back on the left, large title in the body -- so every
//  destination off the house shelf behaves alike.
//
//  Two classes of thing live here, and the split is by OWNERSHIP, not by
//  platform:
//    - House apps come from `GET /apps/surface` and are READ-ONLY on the
//      phone. Toggling one and granting it to a persona writes tools.yaml and
//      the persona files and then restarts the server; that stays at the desk.
//    - On device is this phone's own -- its recogniser, its widgets -- so
//      those rows still act.
//
//  Valinor's third on-device row was Meta Ray-Ban pairing, and it was the
//  example that made the ownership split worth stating. It goes with MWDAT.
//  The split still holds without it: Speech and Widgets act, house apps do not.
//
//  Mockup of record: hearth-pitch/mockups/hearth-ios-apps-mockup.html
//

import SwiftUI
import HearthCore

struct AppsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var surface = AppsSurfaceLoader()
    @State private var expanded: Set<String> = []
    @State private var showLibrary = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if let loaded = surface.surface, !loaded.toolsEnabled {
                        toolsOffBanner
                    }

                    if let loaded = surface.surface {
                        ForEach(AppsSurface.groupOrder, id: \.self) { state in
                            let rows = loaded.apps(inState: state)
                            if !rows.isEmpty {
                                AppGroup(
                                    state: state,
                                    apps: rows,
                                    personas: loaded.personas,
                                    expanded: $expanded
                                )
                            }
                        }
                    } else if surface.unavailable {
                        houseUnavailable
                    } else {
                        loading
                    }

                    OnDeviceSection(viewModel: viewModel)
                    footer
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cards") { showLibrary = true }
                        .tint(HearthPalette.ember)
                        .disabled(surface.surface == nil)
                }
            }
            .toolbarBackground(HearthPalette.parchment, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showLibrary) {
                CardLibraryView(cards: surface.surface?.cards ?? [])
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Apps")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(HearthPalette.roast)
            Text("what the house can reach, and who may ask")
                .font(.system(size: 12.5))
                .italic()
                .foregroundStyle(HearthPalette.fawn)
            // The rows below are deliberately read-only: applying app changes
            // restarts the house, which is not a thing a phone should do to a
            // machine someone else may be talking to. Without this line the
            // inert rows read as a broken screen.
            Text("Changes are made at the desk, on the machine running the house. This phone reads.")
                .font(.system(size: 11))
                .foregroundStyle(HearthPalette.fawn.opacity(0.85))
                .padding(.top, 3)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }

    /// The house can switch tools off wholesale, and then every row below is
    /// describing something no persona can currently reach. Without this the
    /// list reads exactly as it does when everything is live, which is the
    /// one way this page could actively mislead.
    private var toolsOffBanner: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(HearthPalette.clay)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tools are switched off")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(HearthPalette.clay)
                Text("The house still knows about everything below, but no persona can use any of it until tools are turned back on at the desk.")
                    .font(.system(size: 11))
                    .foregroundStyle(HearthPalette.clay.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(HearthPalette.clayWash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(HearthPalette.clayLine, lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }

    private var loading: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7).tint(HearthPalette.fennec)
            Text("Asking the house what it can reach...")
                .font(.system(size: 12))
                .foregroundStyle(HearthPalette.fawn)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    /// An older Valar has no /apps/surface. The phone still owns the section
    /// below, so this is a note rather than an error state.
    private var houseUnavailable: some View {
        VStack(spacing: 5) {
            Text("The house has not listed its apps")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HearthPalette.roast)
            Text("This Valar is older than the apps surface. Everything below is this device's own.")
                .font(.system(size: 11.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(HearthPalette.fawn)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 34)
    }

    private var footer: some View {
        VStack(spacing: 3) {
            Text("House apps are read-only here -- toggling one and granting it to a persona happens at the desk.")
            Text("On-device entries are this phone's to change.")
        }
        .font(.system(size: 10.5))
        .multilineTextAlignment(.center)
        .foregroundStyle(HearthPalette.fawn)
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
        .padding(.horizontal, 24)
    }
}

// MARK: - A state group (in the house / needs setup / available)

private struct AppGroup: View {
    let state: String
    let apps: [AppsSurface.App]
    let personas: [String]
    @Binding var expanded: Set<String>

    private var title: String {
        switch state {
        case "active":    return "In the house"
        case "setup":     return "Needs setup"
        case "available": return "Available"
        default:          return state
        }
    }

    private var why: String {
        switch state {
        case "active":    return "offered to at least one persona"
        case "setup":     return "known, waiting on a credential"
        case "available": return "found on this machine, not let in yet"
        default:          return ""
        }
    }

    var body: some View {
        AppsSection(title: title, why: why) {
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                if index > 0 { AppsDivider() }
                AppRow(
                    app: app,
                    personas: personas,
                    isExpanded: expanded.contains(app.id),
                    toggle: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            if expanded.contains(app.id) { expanded.remove(app.id) }
                            else { expanded.insert(app.id) }
                        }
                    }
                )
            }
        }
    }
}

// MARK: - One app, collapsed and expanded

private struct AppRow: View {
    let app: AppsSurface.App
    let personas: [String]
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 10) {
                    GlyphTile(text: app.name, kind: app.kind, dimmed: app.state != "active")
                    VStack(alignment: .leading, spacing: 2) {
                        FlowLabel(name: app.name, badges: badges)
                        Text(app.tagline)
                            .font(.system(size: 11))
                            .foregroundStyle(HearthPalette.fawn)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HearthPalette.fawn)
                        .padding(.top, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                facets
                    .padding(.top, 9)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 3)
    }

    private var badges: [(String, BadgeTone)] {
        var out: [(String, BadgeTone)] = []
        if app.locked { out.append(("always on", .locked)) }
        if app.kind == "cli" || app.kind == "mcp" { out.append((app.kindLabel, .plain)) }
        // Read is the floor and says nothing; write and control are worth the ink.
        if app.risk == "write" { out.append(("write", .write)) }
        if app.risk == "control" { out.append(("control", .control)) }
        return out
    }

    private var facets: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !app.needs.isEmpty {
                NeedsNote(text: "Waiting on \(app.needs.formattedList()).")
                    .padding(.bottom, 4)
            }
            Facet(label: "Reaches") {
                Text(app.transport)
                    .font(.system(size: 11.5))
                    .foregroundStyle(HearthPalette.roast)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Facet(label: "Can do") {
                PillWrap(items: app.tools.map { ($0, false) }
                         + (app.more > 0 ? [("+\(app.more) more", false)] : []))
            }
            Facet(label: "Draws") {
                if app.cards.isEmpty {
                    Text("draws nothing")
                        .font(.system(size: 11))
                        .italic()
                        .foregroundStyle(HearthPalette.fawn)
                } else {
                    PillWrap(items: app.cards.map { ($0, true) })
                }
            }
            Facet(label: "Who may") {
                VStack(alignment: .leading, spacing: 6) {
                    PersonaChips(all: personas, granted: Set(app.who))
                    Text(app.who.isEmpty
                         ? "No persona holds this domain yet."
                         : "Permission is granted by domain, so a persona may also gain another app that shares one.")
                        .font(.system(size: 10.5))
                        .italic()
                        .foregroundStyle(HearthPalette.fawn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, 40)
        .padding(.trailing, 2)
        .padding(.bottom, 4)
    }
}

// MARK: - On device (this phone's own, and the only rows here that act)

private struct OnDeviceSection: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        AppsSection(title: "On device", why: "this phone's own, not the house's") {
            speech
            AppsDivider()
            widgets
        }
    }

    // Apple's recogniser rather than one of ours, and the copy says so. It
    // earns the row because SpeechRecognitionManager sets
    // `requiresOnDeviceRecognition = true`, which makes iOS fail the request
    // rather than quietly reach for the network.
    private var speech: some View {
        DeviceRow(
            initials: "Sp",
            label: "Speech",
            hint: "Apple's on-device recogniser, pinned local -- it will not fall back to the network. Replaced the server's Whisper round-trip.",
            status: ("On device, en-US", true),
            action: nil
        )
    }

    private var widgets: some View {
        // No API opens the widget gallery; it is reached by long-pressing
        // the Home Screen. The previous version opened the private
        // "App-prefs:" scheme, which is unreliable and App Review surface --
        // saying where the gallery lives beats pretending to deep-link.
        DeviceRow(
            initials: "Wi",
            label: "Widgets",
            hint: "The persona orb and Tap to talk. Add them by long-pressing the Home Screen and choosing Hearth.",
            status: ("Added from the Home Screen", true),
            action: nil
        )
    }
}

private struct DeviceRow: View {
    let initials: String
    let label: String
    let hint: String
    var status: (String, Bool)? = nil
    var action: (String, () -> Void)? = nil
    var chevron: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        let row = HStack(alignment: .top, spacing: 10) {
            GlyphTile(text: initials, kind: "device", dimmed: false, literal: true)
            VStack(alignment: .leading, spacing: 2) {
                FlowLabel(name: label, badges: [("this phone", .device)])
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(HearthPalette.fawn)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if let status {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(status.1 ? HearthPalette.sage : HearthPalette.fawn.opacity(0.5))
                            .frame(width: 7, height: 7)
                        Text(status.0)
                            .font(.system(size: 11))
                            .foregroundStyle(HearthPalette.fawn)
                    }
                    .padding(.top, 3)
                }
                if let action {
                    Button(action: action.1) {
                        Text(action.0)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(HearthPalette.ember)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 6)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HearthPalette.fawn)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())

        if let onTap {
            Button(action: onTap) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }
}

// MARK: - Shared pieces

/// Same card chrome as SettingsSection, with a why-line the settings sections
/// do not carry (the groups here need explaining; "Connections" does not).
private struct AppsSection<Content: View>: View {
    let title: String
    var why: String = ""
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(HearthPalette.ember)
                if !why.isEmpty {
                    Text(why)
                        .font(.system(size: 10.5))
                        .italic()
                        .foregroundStyle(HearthPalette.fawn)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 7)

            VStack(spacing: 0) { content }
                .padding(.horizontal, 13)
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

private struct AppsDivider: View {
    var body: some View {
        Rectangle()
            .fill(HearthPalette.linen)
            .frame(height: 1)
            .padding(.vertical, 8)
    }
}

/// Two-letter tile coloured by kind. No per-app art: the server knows nothing
/// about logos, so inventing them here would be shipping a second source of
/// truth about what an app is.
private struct GlyphTile: View {
    let text: String
    let kind: String
    let dimmed: Bool
    var literal: Bool = false

    private var initials: String {
        literal ? text : String(text.prefix(2))
    }

    private var tint: Color {
        if dimmed { return HearthPalette.fawn.opacity(0.55) }
        switch kind {
        case "core":   return HearthPalette.ember
        case "cli":    return HearthPalette.slate
        case "local":  return HearthPalette.sage
        case "device": return HearthPalette.roast
        default:       return HearthPalette.fawn
        }
    }

    var body: some View {
        Text(initials)
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(tint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .padding(.top, 1)
    }
}

enum BadgeTone { case plain, write, control, locked, device }

/// Name plus its badges, wrapping when the badges do not fit beside it.
private struct FlowLabel: View {
    let name: String
    let badges: [(String, BadgeTone)]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(name)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(HearthPalette.roast)
            ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                AppBadge(text: badge.0, tone: badge.1)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct AppBadge: View {
    let text: String
    let tone: BadgeTone

    private var foreground: Color {
        switch tone {
        case .plain:   return HearthPalette.fawn
        case .write:   return HearthPalette.clay
        case .control: return .white
        case .locked:  return HearthPalette.ember
        case .device:  return HearthPalette.roast
        }
    }

    private var background: Color {
        switch tone {
        case .plain:   return HearthPalette.parchment
        case .write:   return HearthPalette.clayWash
        case .control: return HearthPalette.clay
        case .locked:  return HearthPalette.glowtint
        case .device:  return HearthPalette.glowtint
        }
    }

    private var border: Color {
        switch tone {
        case .plain:   return HearthPalette.linen
        case .write:   return HearthPalette.clayLine
        case .control: return .clear
        case .locked, .device: return HearthPalette.bubbleLine
        }
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background, in: Capsule())
            .overlay(Capsule().stroke(border, lineWidth: 1))
    }
}

private struct Facet<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(HearthPalette.fawn)
                .frame(width: 56, alignment: .leading)
                .padding(.top, 2)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
    }
}

/// Monospaced pills that wrap. `isCard` tints the card names ember so a tool
/// and a card are never mistaken for one another.
private struct PillWrap: View {
    /// (text, isCard)
    let items: [(String, Bool)]

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(item.0)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(item.1 ? HearthPalette.ember : HearthPalette.roast)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(item.1 ? HearthPalette.glowtint : HearthPalette.fluff, in: Capsule())
                    .overlay(Capsule().stroke(item.1 ? HearthPalette.bubbleLine : HearthPalette.linen,
                                              lineWidth: 1))
            }
        }
    }
}

private struct PersonaChips: View {
    let all: [String]
    let granted: Set<String>

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(all, id: \.self) { name in
                let on = granted.contains(name)
                HStack(spacing: 5) {
                    Text(name.prefix(2))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(on ? HearthPalette.fennec : HearthPalette.fawn.opacity(0.55),
                                    in: Circle())
                    Text(name)
                        .font(.system(size: 11))
                        .foregroundStyle(HearthPalette.roast)
                }
                .padding(.leading, 3)
                .padding(.trailing, 8)
                .padding(.vertical, 2)
                .background(HearthPalette.fluff, in: Capsule())
                .overlay(Capsule().stroke(HearthPalette.linen, lineWidth: 1))
                // Dimmed rather than hidden: which personas do NOT hold an app
                // is as much of the answer as which do.
                .opacity(on ? 1 : 0.38)
            }
        }
    }
}

struct NeedsNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(HearthPalette.clay)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(HearthPalette.clayWash,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(HearthPalette.clayLine, lineWidth: 1)
            )
    }
}

/// Wrapping row of chips. SwiftUI has no wrap-capable HStack before the
/// layout protocol, and the pills here are server-named so their widths cannot
/// be assumed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

extension Array where Element == String {
    /// "A", "A and B", "A, B and C" -- the needs row reads as a sentence.
    func formattedList() -> String {
        switch count {
        case 0:  return ""
        case 1:  return self[0]
        case 2:  return "\(self[0]) and \(self[1])"
        default: return dropLast().joined(separator: ", ") + " and " + (last ?? "")
        }
    }
}
