//
//  PersonaComponents.swift
//  Hearth
//
//  The pieces the persona page is built from: locked rows, the state cards,
//  and the two sheets that carry the only edits the phone may make.
//

import SwiftUI
import HearthCore

// MARK: - Section chrome

struct SectionHeader: View {
    let title: String
    var why: String = ""

    var body: some View {
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
    }
}

struct PersonaSection<Content: View>: View {
    let title: String
    var why: String = ""
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: title, why: why)
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
        .padding(.top, 15)
    }
}

struct PersonaDivider: View {
    var body: some View {
        Rectangle()
            .fill(HearthPalette.linen)
            .frame(height: 1)
            .padding(.vertical, 9)
    }
}

struct InlineNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5))
            .italic()
            .foregroundStyle(HearthPalette.fawn)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.top, 7)
    }
}

/// A padlock, and nothing else. The value is the point; the padlock says why
/// it stops there. Drawing a greyed-out control instead would suggest the
/// control is what is missing, when what is missing is the home machine.
struct Padlock: View {
    var body: some View {
        Image(systemName: "lock")
            .font(.system(size: 10.5))
            .foregroundStyle(HearthPalette.fawn.opacity(0.6))
            .padding(.top, 3)
    }
}

struct LockedRow: View {
    let label: String
    let value: String
    var mono: Bool = false
    var dim: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(HearthPalette.fawn)
                Text(value)
                    .font(mono ? .system(size: 11.5, design: .monospaced)
                               : .system(size: 13.5))
                    .foregroundStyle(dim ? HearthPalette.fawn : HearthPalette.roast)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 6)
            Padlock()
        }
    }
}

struct DomainPill: View {
    let text: String
    let denied: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .strikethrough(denied)
            .foregroundStyle(denied ? HearthPalette.clay : HearthPalette.roast)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(denied ? HearthPalette.clayWash : HearthPalette.fluff, in: Capsule())
            .overlay(Capsule().stroke(denied ? HearthPalette.clayLine : HearthPalette.linen, lineWidth: 1))
    }
}

struct LockedNote: View {
    let persona: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock")
                .font(.system(size: 11))
                .foregroundStyle(HearthPalette.fawn.opacity(0.65))
            VStack(alignment: .leading, spacing: 2) {
                Text("Persona utilizes a custom 3D asset.")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(HearthPalette.roast)
                Text("\(persona) is drawn as a model rather than an orb, so these colours drive nothing. Their look changes with the asset, at the desk.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(HearthPalette.fawn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HearthPalette.parchment, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(HearthPalette.linen, lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.top, 9)
    }
}

// MARK: - A state's colour, at a size you can judge

struct StateCard: View {
    let state: String
    let hex: String
    var edited: Bool = false
    var inert: Bool = false

    private var color: Color { Color(hex: hex) ?? HearthPalette.fennec }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HearthPalette.glowtint
                Circle()
                    .fill(color)
                    .frame(width: 44, height: 44)
                    // The glow is the thing being judged, not the fill: a flat
                    // swatch cannot show whether four states agree.
                    .shadow(color: inert ? .clear : color.opacity(0.6), radius: 9)
            }
            .frame(height: 74)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.capitalized)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HearthPalette.roast)
                Text(PersonaSurface.whenItAppears(state))
                    .font(.system(size: 10))
                    .foregroundStyle(HearthPalette.fawn)
                Text(hex.uppercased())
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(HearthPalette.fawn)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.top, 7)
            .padding(.bottom, 8)
            .background(HearthPalette.fluff)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(edited ? HearthPalette.ember : HearthPalette.linen,
                        lineWidth: edited ? 2 : 1)
        )
    }
}

// MARK: - The two editors

/// The prompt gets a sheet of its own because it IS the persona: a
/// single-line field would make the most important field on the page the
/// smallest thing on it.
struct PromptEditor: View {
    let name: String
    @State var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .background(HearthPalette.fluff)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .background(HearthPalette.cream.ignoresSafeArea())
                .navigationTitle("How \(name) is")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }.tint(HearthPalette.fawn)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { onSave(text); dismiss() }
                            .tint(HearthPalette.ember)
                            .fontWeight(.semibold)
                    }
                }
                .toolbarBackground(HearthPalette.parchment, for: .navigationBar)
        }
    }
}

/// The system colour picker, on a sheet that deliberately does NOT cover the
/// whole screen: the persona stays visible above it wearing the colour while
/// you choose. The desktop animates a swatch on hover; the phone has no
/// hover, and showing the real glow is better than showing a preview of one.
struct ColorSheet: View {
    let state: String
    @State var hex: String
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var color: Color = .orange

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(HearthPalette.linen)
                .frame(width: 36, height: 5)
                .padding(.top, 9)

            VStack(spacing: 2) {
                Text(state.capitalized)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HearthPalette.roast)
                Text(PersonaSurface.whenItAppears(state))
                    .font(.system(size: 11))
                    .foregroundStyle(HearthPalette.fawn)
            }
            .padding(.top, 10)

            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .scaleEffect(2.2)
                .frame(height: 96)
                .padding(.top, 18)

            Text(hex.uppercased())
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(HearthPalette.roast)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(HearthPalette.fluff, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(HearthPalette.linen, lineWidth: 1)
                )
                .padding(.horizontal, 60)
                .padding(.top, 4)

            Text("The persona wears this while you choose, so you are judging the glow and not a swatch.")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundStyle(HearthPalette.fawn)
                .padding(.horizontal, 32)
                .padding(.top, 14)

            Spacer(minLength: 0)
        }
        .background(HearthPalette.cream.ignoresSafeArea())
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.hidden)
        .onAppear { color = Color(hex: hex) ?? .orange }
        .onChange(of: color) { _, next in
            if let updated = next.hexString { hex = updated }
        }
        .onDisappear { onPick(hex) }
    }
}
