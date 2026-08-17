//
//  CardLibraryView.swift
//  Hearth
//
//  Every card the house knows how to draw, rendered with the REAL card views
//  and sample props. That is the whole point: a hand-drawn preview drifts from
//  what the timeline actually shows the moment a card changes, and a library
//  that lies about its contents is worse than no library.
//
//  The card list comes from `GET /apps/surface` (card_catalog.yaml), so the
//  server decides what exists. Samples live here because only the client knows
//  each card's prop contract -- and they were written by reading the renderers
//  in Views/Dynamic, not by guessing from the catalog's `data_fields`.
//
//  One contract that bites, learned on desktop: timer_card wants `fire_at` as
//  epoch SECONDS, not an ISO date.
//
//  Valinor also carried samples for the two commissioned cards, whose payload
//  nests under `props.data` rather than sitting flat. Those cards did not come
//  across, and this was the fourth of their four code sites -- the one the
//  inventory missed.
//
//  A card type this build cannot draw says so rather than vanishing. Silence
//  is right in the timeline (forward compatibility) and wrong here, where the
//  question being asked is precisely "what can this thing draw?".
//

import SwiftUI
import HearthCore

public struct CardLibraryView: View {
    let cards: [AppsSurface.CardType]
    @Environment(\.dismiss) private var dismiss

    public init(cards: [AppsSurface.CardType]) {
        self.cards = cards
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ForEach(cards) { card in
                        CardPreview(card: card)
                    }
                    if cards.isEmpty {
                        Text("The house has not listed its cards.")
                            .font(.system(size: 12))
                            .foregroundStyle(HearthPalette.fawn)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                }
                .padding(.bottom, 26)
            }
            .background(HearthPalette.cream.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Apps") { dismiss() }
                        .tint(HearthPalette.ember)
                }
            }
            .toolbarBackground(HearthPalette.parchment, for: .navigationBar)
            .hearthNavigationTitleInline()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Card library")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(HearthPalette.roast)
            Text("everything the house knows how to draw")
                .font(.system(size: 12.5))
                .italic()
                .foregroundStyle(HearthPalette.fawn)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }
}

// MARK: - One card: its name, its purpose, and the real view

private struct CardPreview: View {
    let card: AppsSurface.CardType

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text(card.type)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(HearthPalette.roast)
                Spacer(minLength: 6)
                StateBadge(state: card.state, label: card.stateLabel)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Rectangle().fill(HearthPalette.linen).frame(height: 1)

            if !card.purpose.isEmpty {
                Text(card.purpose)
                    .font(.system(size: 10.5))
                    .foregroundStyle(HearthPalette.fawn)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.top, 7)
            }

            Group {
                if let sample = CardSamples.descriptor(for: card.type) {
                    DynamicComponent(descriptor: sample)
                        // Samples carry invented request ids and labels; the
                        // action cards render but must not be able to answer
                        // a question nobody asked.
                        .environment(\.cardActionsEnabled, false)
                } else {
                    unsupported
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 11)
            .padding(.bottom, card.dataFields.isEmpty ? 13 : 9)

            // The catalog's own description of what the card takes. Prose, not
            // a parsed list, and shown rather than interpreted.
            if !card.dataFields.isEmpty {
                Text(card.dataFields)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(HearthPalette.fawn)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HearthPalette.fluff, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(HearthPalette.linen, lineWidth: 1)
        )
        .hearthSoftShadow()
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private var unsupported: some View {
        Text("Made for another surface.\nThis build does not carry a \(card.type) view.")
            .font(.system(size: 11))
            .multilineTextAlignment(.center)
            .foregroundStyle(HearthPalette.fawn)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(HearthPalette.linen)
            )
    }
}

private struct StateBadge: View {
    let state: String
    let label: String

    private var foreground: Color {
        switch state {
        case "forged":   return HearthPalette.ember
        case "scaffold": return HearthPalette.clay
        default:         return HearthPalette.fawn
        }
    }

    private var background: Color {
        switch state {
        case "forged":   return HearthPalette.glowtint
        case "scaffold": return HearthPalette.clayWash
        default:         return HearthPalette.parchment
        }
    }

    private var border: Color {
        switch state {
        case "forged":   return HearthPalette.bubbleLine
        case "scaffold": return HearthPalette.clayLine
        default:         return HearthPalette.linen
        }
    }

    var body: some View {
        Text(label.uppercased())
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background, in: Capsule())
            .overlay(Capsule().stroke(border, lineWidth: 1))
    }
}

// MARK: - Samples

/// One sample payload per renderable type, in the shape its renderer actually
/// reads. Keep these in step with Views/Dynamic: a sample that stops matching
/// its card shows an empty preview, which is exactly the drift this view is
/// meant to prevent.
enum CardSamples {
    static func descriptor(for type: String) -> UiComponentDescriptor? {
        guard let props = props(for: type) else { return nil }
        return UiComponentDescriptor(
            id: "sample-\(type)",
            type: type,
            version: UiComponentDescriptor.supportedVersion,
            props: props,
            receivedAt: Date()
        )
    }

    private static func props(for type: String) -> [String: Any]? {
        switch type {
        case UiComponentDescriptor.typeClock:
            return ["time": "9:41", "date": "Monday, Aug 3"]

        case UiComponentDescriptor.typeWeatherCard:
            return ["location": "Portland", "temp": "54", "condition": "Light rain",
                    "high": "58", "low": "47", "day": "today"]

        case UiComponentDescriptor.typeTimerCard:
            // Epoch SECONDS, not an ISO date -- see the file header.
            let now = Int(Date().timeIntervalSince1970)
            return ["timers": [["label": "Bread", "fire_at": now + 724],
                               ["label": "Tea", "fire_at": now + 47]]]

        case UiComponentDescriptor.typeBriefText:
            return ["title": "Note", "body": "The kiln reaches temperature at about four."]

        case UiComponentDescriptor.typeCaptions:
            return ["text": "...and the second movement is where it opens up."]

        case UiComponentDescriptor.typeGeneratedView:
            return ["template": "plain", "title": "This week",
                    "sections": [["kind": "text", "body": "Three sessions, all on the Apple client."],
                                 ["kind": "stats",
                                  "stats": [["label": "Commits", "value": "14"],
                                            ["label": "Cards drawn", "value": "31"]]]]]

        // House-relative paths, resolved by RemoteImage against the running
        // server, so this sample also proves the resolution rule works on
        // whatever host the phone reached.
        //
        // Valinor pointed these at /Persona/Selene/Assets/, which resolved only
        // where Selene's asset set existed. Hearth ships no persona imagery at
        // pre-alpha -- backend/personas/Sulivan carries a voice and nothing else
        // -- so there is no path that resolves everywhere, and inventing one
        // would only move the 404. Sulivan is named instead because Sulivan is
        // the one persona guaranteed to EXIST on any install; a house with no
        // images for her shows the card's honest failure state, which is the
        // same behaviour the drawing card was kept for.
        case UiComponentDescriptor.typeSlideshow:
            return ["images": ["/Persona/Sulivan/Assets/portrait.png",
                               "/Persona/Sulivan/Assets/portrait-alt.png"],
                    "interval_ms": 4000]

        case UiComponentDescriptor.typePermissionCard:
            return ["request_id": "sample", "path": "D:\\Recipes",
                    "action": "read", "status": "pending"]

        case UiComponentDescriptor.typeChoiceCard:
            return ["question": "Which room should the reading light live in?",
                    "options": [["label": "The study", "detail": "Where the books already are."],
                                ["label": "The porch", "detail": "Evening light, no outlet."]],
                    "allow_free_text": true]

        // terminal_card has no iOS renderer, so it falls through to "made for
        // another surface" -- true, rather than an empty box.
        default:
            return nil
        }
    }
}
