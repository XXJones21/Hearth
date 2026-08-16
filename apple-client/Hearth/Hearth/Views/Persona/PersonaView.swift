//
//  PersonaView.swift
//  Hearth
//
//  The persona page, round 5. Same shape as Journal, Apps and Settings --
//  full screen, "Hearth" back on the left -- so every destination off the
//  house shelf behaves alike.
//
//  Six sections in the desktop's order, because the order is the argument:
//  who they are, how they are, voice, presence, what they may do, how they
//  think.
//
//  TWO fields are editable here and nothing else. See PersonaSurface for why.
//  A locked row shows its value and a padlock; it is never drawn as a
//  disabled control, because a control that cannot be used should not look
//  like a control.
//
//  Mockup of record: hearth-pitch/mockups/hearth-ios-persona-mockup.html
//

import SwiftUI
import HearthCore

struct PersonaView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var loader = PersonaSurfaceLoader()

    @State private var selected: String?
    /// Pending edits, batched behind Save. Nothing writes on a field change.
    @State private var draftPrompt: String?
    @State private var draftColors: [String: String]?
    @State private var editingState: String?
    @State private var showPromptEditor = false

    private var persona: PersonaSurface.Persona? {
        let household = loader.surface?.household ?? []
        return household.first { $0.id == selected } ?? household.first
    }

    private var hasEdits: Bool { draftPrompt != nil || draftColors != nil }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        if let surface = loader.surface, !surface.household.isEmpty {
                            householdStrip(surface.household)
                            if let persona {
                                sections(for: persona)
                            }
                        } else if loader.unavailable {
                            unavailableNote
                        } else {
                            loading
                        }
                    }
                    .padding(.bottom, hasEdits ? 96 : 30)
                }
                if hasEdits { saveBar }
            }
            .background(HearthPalette.cream.ignoresSafeArea())
            .overlay { if loader.isSaving { restartingOverlay } }
            .task { await loader.load() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hearth") { dismiss() }
                        .tint(HearthPalette.ember)
                }
            }
            .toolbarBackground(HearthPalette.parchment, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPromptEditor) {
                if let persona {
                    PromptEditor(
                        name: persona.name,
                        text: draftPrompt ?? persona.systemPrompt,
                        onSave: { draftPrompt = $0 == persona.systemPrompt ? nil : $0 }
                    )
                }
            }
            .sheet(item: Binding(
                get: { editingState.map { StateEdit(state: $0) } },
                set: { editingState = $0?.state }
            )) { edit in
                if let persona {
                    ColorSheet(
                        state: edit.state,
                        hex: colors(for: persona)[edit.state] ?? "#E39A5B",
                        onPick: { hex in
                            var next = draftColors ?? colors(for: persona)
                            next[edit.state] = hex
                            draftColors = next
                        }
                    )
                }
            }
        }
    }

    /// Identifiable wrapper so `sheet(item:)` can drive the colour picker.
    private struct StateEdit: Identifiable {
        let state: String
        var id: String { state }
    }

    private func colors(for persona: PersonaSurface.Persona) -> [String: String] {
        draftColors ?? persona.stateColors ?? [:]
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Who lives here")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(HearthPalette.roast)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }

    private var loading: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7).tint(HearthPalette.fennec)
            Text("Asking the house who lives here...")
                .font(.system(size: 12))
                .foregroundStyle(HearthPalette.fawn)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var unavailableNote: some View {
        VStack(spacing: 5) {
            Text("The house has not listed its personas")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HearthPalette.roast)
            Text("This Valar is older than the personas surface.")
                .font(.system(size: 11.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(HearthPalette.fawn)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 34)
    }

    /// The household IS the navigation, and doubles as the answer to the
    /// page's real question. It replaces the desktop's sidebar.
    private func householdStrip(_ people: [PersonaSurface.Persona]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(people) { person in
                    let on = person.id == persona?.id
                    Button {
                        guard !hasEdits else { return }
                        selected = person.id
                    } label: {
                        VStack(spacing: 5) {
                            Text(person.name.prefix(2))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(accent(person), in: Circle())
                                .overlay(Circle().stroke(on ? HearthPalette.ember : .clear, lineWidth: 2))
                                .padding(2)
                                .overlay(Circle().stroke(on ? HearthPalette.glowtint : .clear, lineWidth: 3))
                            Text(person.name)
                                .font(.system(size: 11, weight: on ? .semibold : .regular))
                                .foregroundStyle(on ? HearthPalette.roast : HearthPalette.fawn)
                        }
                        .frame(width: 66)
                    }
                    .buttonStyle(.plain)
                    // Switching with edits pending would silently drop them.
                    .opacity(hasEdits && !on ? 0.35 : 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }

    private func accent(_ person: PersonaSurface.Persona) -> Color {
        Color(hex: person.stateColors?["idle"] ?? person.accent) ?? HearthPalette.fawn
    }

    // MARK: - The six sections

    @ViewBuilder
    private func sections(for persona: PersonaSurface.Persona) -> some View {
        PersonaSection(title: "Who they are") {
            LockedRow(label: "Name", value: persona.name)
            if !persona.description.isEmpty {
                PersonaDivider()
                LockedRow(label: "Description", value: persona.description)
            }
            if !persona.classification.isEmpty {
                PersonaDivider()
                LockedRow(label: "Classification", value: persona.classification.capitalized)
            }
        }

        promptSection(persona)
        voiceSection(persona)
        presenceSection(persona)

        if !persona.domains.isEmpty || !persona.deny.isEmpty {
            PersonaSection(title: "What they may do") {
                HStack(alignment: .top, spacing: 10) {
                    FlowLayout(spacing: 5) {
                        ForEach(persona.domains, id: \.self) { DomainPill(text: $0, denied: false) }
                        ForEach(persona.deny, id: \.self) { DomainPill(text: $0, denied: true) }
                    }
                    Padlock()
                }
            }
        }

        PersonaSection(title: "How they think") {
            LockedRow(label: "Model", value: persona.model.isEmpty ? "House default" : persona.model,
                      mono: !persona.model.isEmpty)
            PersonaDivider()
            LockedRow(label: "Temperature", value: persona.temperature > 0
                      ? String(format: "%.2g", persona.temperature) : "House default")
            PersonaDivider()
            LockedRow(label: "Reasoning",
                      value: persona.reasoning ? "On, \(persona.rounds) rounds" : "Off")
        }
        // The NAME, never a path: which file it resolves to is the home
        // machine's business, and a path here would be unopenable anyway.
        InlineNote("The model name, never a path. Which file that resolves to is the home machine's business.")
    }

    private func promptSection(_ persona: PersonaSurface.Persona) -> some View {
        let text = draftPrompt ?? persona.systemPrompt
        let edited = draftPrompt != nil
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "How they are", why: "this is the persona")
            Button { showPromptEditor = true } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(text)
                        .font(.system(size: 12.5))
                        .lineSpacing(3)
                        .foregroundStyle(HearthPalette.roast)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 208, alignment: .top)
                        .clipped()
                        .overlay(alignment: .bottom) {
                            LinearGradient(colors: [HearthPalette.fluff.opacity(0), HearthPalette.fluff],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: 44)
                        }
                }
                .padding(14)
                .background(HearthPalette.fluff, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(edited ? HearthPalette.ember : HearthPalette.bubbleLine,
                                lineWidth: edited ? 2 : 1)
                )
                .hearthSoftShadow()
                .padding(.horizontal, 14)
            }
            .buttonStyle(.plain)

            HStack {
                Text("\(text.count) characters")
                Spacer()
                Text(edited ? "Edited" : "Tap to edit")
                    .foregroundStyle(edited ? HearthPalette.ember : HearthPalette.fawn)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(HearthPalette.fawn)
            .padding(.horizontal, 20)
            .padding(.top, 6)
        }
        .padding(.top, 15)
    }

    private func voiceSection(_ persona: PersonaSurface.Persona) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PersonaSection(title: "Voice") {
                if !persona.voice.voiceDescription.isEmpty {
                    LockedRow(label: "Manner", value: persona.voice.voiceDescription)
                    PersonaDivider()
                }
                LockedRow(label: "Clip",
                          value: persona.voice.clipName.isEmpty ? "None" : persona.voice.clipName,
                          mono: true)
                if !persona.voice.referenceText.isEmpty {
                    PersonaDivider()
                    LockedRow(label: "What the clip says", value: persona.voice.referenceText, dim: true)
                }
            }
            // No Hear it, and no Replace. Both need the home machine: the
            // preview is interlocked against the visualizer state on the
            // desktop, and a second client firing a generation would collide
            // on the single GPU that OmniVoice already fills.
            InlineNote("The clip lives on the home machine. Replacing it, and hearing it, both happen at the desk.")
        }
    }

    private func presenceSection(_ persona: PersonaSurface.Persona) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PersonaSection(title: "Presence") {
                LockedRow(label: "Form", value: persona.formLabel)
            }
            animationsRow(persona)
            colorsSection(persona)
        }
    }

    /// The way into the face's own room, and only for the persona actually on
    /// the stage: the panel plays live geometry, and the household strip can
    /// be showing someone whose config this client has never been handed.
    @ViewBuilder
    private func animationsRow(_ persona: PersonaSurface.Persona) -> some View {
        if persona.name.lowercased() == viewModel.currentPersonaName.lowercased(),
           viewModel.personaVisualization.canRenderFace,
           let geometry = viewModel.personaVisualization.faceGeometry {
            NavigationLink {
                FaceAnimationsView(geometry: geometry, palette: viewModel.personaPalette)
            } label: {
                HStack {
                    Text("Animations")
                        .font(.system(size: 15))
                        .foregroundStyle(HearthPalette.roast)
                    Spacer()
                    Text("every state and reaction")
                        .font(.system(size: 12.5))
                        .foregroundStyle(HearthPalette.fawn)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HearthPalette.fawn)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
            }
        }
    }

    // MARK: - Colours by state

    @ViewBuilder
    private func colorsSection(_ persona: PersonaSurface.Persona) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Colours by state",
                          why: persona.usesModelAsset ? "" : "tap one to change it")

            if persona.stateColors == nil && !persona.usesModelAsset {
                seedCard(persona)
            } else {
                let live = colors(for: persona)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 9),
                                    GridItem(.flexible(), spacing: 9)], spacing: 9) {
                    ForEach(PersonaSurface.stateOrder, id: \.self) { state in
                        StateCard(
                            state: state,
                            hex: live[state] ?? PersonaSurface.seedColors[state] ?? "#E39A5B",
                            edited: draftColors?[state] != nil
                                && draftColors?[state] != persona.stateColors?[state],
                            inert: persona.usesModelAsset
                        )
                        .onTapGesture {
                            guard !persona.usesModelAsset else { return }
                            editingState = state
                        }
                    }
                }
                .padding(.horizontal, 14)
                // Shown inert rather than hidden: it should be obvious the
                // control exists and why it does not apply here.
                .opacity(persona.usesModelAsset ? 0.42 : 1)
                .saturation(persona.usesModelAsset ? 0.35 : 1)
                .allowsHitTesting(!persona.usesModelAsset)

                if persona.usesModelAsset {
                    LockedNote(persona: persona.name)
                } else {
                    InlineNote("The four have to agree with each other, so they are shown at a size you can judge rather than as a row of squares.")
                }
            }
        }
        .padding(.top, 15)
    }

    private func seedCard(_ persona: PersonaSurface.Persona) -> some View {
        VStack(spacing: 4) {
            Text("\(persona.name) has no colours yet")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(HearthPalette.roast)
            Text("They wear the house palette. Give them four of their own and every client picks them up.")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundStyle(HearthPalette.fawn)
            Button {
                draftColors = PersonaSurface.seedColors
            } label: {
                Text("Start from the house colours")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(HearthPalette.roast)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(HearthPalette.fennec, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 5)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(HearthPalette.glowtint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(HearthPalette.bubbleLine)
        )
        .padding(.horizontal, 14)
    }

    // MARK: - Save

    private var saveBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(editSummary)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(HearthPalette.roast)
                Text("Saving restarts the house.")
                    .font(.system(size: 11))
                    .foregroundStyle(HearthPalette.fawn)
            }
            Spacer(minLength: 0)
            Button("Discard") {
                draftPrompt = nil
                draftColors = nil
            }
            .font(.system(size: 12.5))
            .tint(HearthPalette.fawn)
            Button {
                Task { await save() }
            } label: {
                Text("Save")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HearthPalette.roast)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(HearthPalette.fennec, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 22)
        .background(HearthPalette.parchment)
        .overlay(Rectangle().fill(HearthPalette.linen).frame(height: 1), alignment: .top)
    }

    private var editSummary: String {
        switch (draftPrompt != nil, draftColors != nil) {
        case (true, true):  return "Two changes, not yet saved."
        case (true, false): return "The prompt has changed."
        default:            return "Colours have changed."
        }
    }

    private func save() async {
        guard let persona else { return }
        let ok = await loader.apply(persona: persona.id,
                                    prompt: draftPrompt,
                                    colors: draftColors)
        if ok {
            draftPrompt = nil
            draftColors = nil
        }
    }

    /// The socket dropping is the SHAPE of a successful save, not a failure,
    /// so this reads as the house going away and coming back.
    private var restartingOverlay: some View {
        ZStack {
            HearthPalette.cream.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(HearthPalette.ember)
                Text("Saving")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HearthPalette.roast)
                Text("The house is coming back. A persona reads its file once when it wakes, so the change needs it to wake again.")
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(HearthPalette.fawn)
                    .padding(.horizontal, 44)
            }
        }
    }
}
