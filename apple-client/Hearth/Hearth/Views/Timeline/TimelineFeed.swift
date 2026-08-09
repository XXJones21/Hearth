//
//  TimelineFeed.swift
//  Hearth
//
//  The Hearth "Direction B" conversation timeline: one attributed feed. User
//  turns lean right in warm bubbles; persona turns are fluff cards on a linen
//  rail with initial-circle nodes; generative cards (CardStore) are interleaved
//  by arrival time, so a card sits under the persona turn that produced it and
//  STAYS there as the conversation continues (the transcript-history contract —
//  see CardStore). Mirrors hearth-client/src/components/feed semantics (rail at
//  x=21, 44px nodes in a 56px gutter, node colors from HearthPalette.speaker).
//

import SwiftUI
import HearthCore

struct TimelineFeed: View {
    @ObservedObject var viewModel: ChatViewModel

    private static let bottomID = "timeline-bottom"

    /// Messages and cards woven into one chronological transcript. Cards carry
    /// `receivedAt`, so a card emitted mid-turn keeps its slot rather than
    /// being shoved to the tail by every later message.
    private var entries: [TimelineEntry] {
        let rows = viewModel.messages.map { TimelineEntry.message($0) }
            + viewModel.cardStore.cards.map { TimelineEntry.card($0) }
        return rows.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                let rows = entries
                if rows.isEmpty {
                    emptyState
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(rows) { entry in
                            switch entry {
                            case .message(let message): TimelineRow(message: message)
                            case .card(let descriptor): TimelineCardRow(descriptor: descriptor)
                            }
                        }
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                    .background(alignment: .leading) { rail }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .onChange(of: viewModel.messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: viewModel.cardStore.cards.count) { _, _ in scrollToBottom(proxy) }
        }
    }

    /// The vertical rail behind the nodes (2px linen at x=21, inset 8pt top/bottom).
    private var rail: some View {
        HearthPalette.linen
            .frame(width: 2)
            .padding(.vertical, 8)
            .offset(x: 21)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Ask anything, or just start talking")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(HearthPalette.roast)
            Text("Your home server is listening.")
                .font(.system(size: 13))
                .foregroundStyle(HearthPalette.fawn)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.horizontal, 24)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
    }
}

// MARK: - One transcript slot (a turn or a card)

private enum TimelineEntry: Identifiable {
    case message(ChatMessage)
    case card(UiComponentDescriptor)

    var id: String {
        switch self {
        case .message(let m): return "m-\(m.id.uuidString)"
        case .card(let c):    return "c-\(c.id)"
        }
    }

    var timestamp: Date {
        switch self {
        case .message(let m): return m.timestamp
        case .card(let c):    return c.receivedAt
        }
    }
}

// MARK: - Row dispatch

private struct TimelineRow: View {
    let message: ChatMessage

    var body: some View {
        switch message.type {
        case .user:
            HStack(alignment: .top, spacing: 12) {
                PersonaNode(name: "You", isUser: true)
                UserBubble(text: message.text)
            }
        case .ai:
            let name = message.personaName ?? "Sulivan"
            HStack(alignment: .top, spacing: 12) {
                PersonaNode(name: name, isUser: false)
                PersonaEntryCard(name: name, text: message.text, time: message.timestamp)
            }
        case .system:
            HStack(spacing: 12) {
                Color.clear.frame(width: 44, height: 1)
                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundStyle(HearthPalette.fawn)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

/// A live generative card in the feed lane (no node -- it belongs to the persona
/// turn just above it).
private struct TimelineCardRow: View {
    let descriptor: UiComponentDescriptor

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Color.clear.frame(width: 44, height: 1)
            DynamicComponent(descriptor: descriptor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Attribution node

private struct PersonaNode: View {
    let name: String
    let isUser: Bool

    var body: some View {
        let base = HearthPalette.speaker(name)
        Circle()
            .fill(fill(base))
            .frame(width: 44, height: 44)
            .overlay(
                Text(initials)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isUser ? HearthPalette.fawn : Color.white)
            )
            .overlay(Circle().stroke(HearthPalette.fluff, lineWidth: 3))
            .hearthSoftShadow()
    }

    private var initials: String {
        isUser ? "You" : String(name.prefix(2))
    }

    /// User node is a flat linen disc; persona node is a lightened radial gradient
    /// of its speaker color (mockup formula: radial 35%/30%, mix(color,white,55%)).
    private func fill(_ base: Color) -> AnyShapeStyle {
        if isUser {
            return AnyShapeStyle(base)
        }
        return AnyShapeStyle(
            RadialGradient(
                colors: [base.mixed(with: .white, amount: 0.55), base],
                center: UnitPoint(x: 0.35, y: 0.30),
                startRadius: 0, endRadius: 24
            )
        )
    }
}

// MARK: - Message surfaces

private struct UserBubble: View {
    let text: String

    private let shape = UnevenRoundedRectangle(
        cornerRadii: .init(topLeading: 16, bottomLeading: 6, bottomTrailing: 16, topTrailing: 16),
        style: .continuous
    )

    var body: some View {
        HStack {
            Spacer(minLength: 24)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(HearthPalette.roast)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(HearthPalette.bubble, in: shape)
                .overlay(shape.stroke(HearthPalette.bubbleLine, lineWidth: 1))
                .hearthSoftShadow()
                .frame(maxWidth: 520, alignment: .trailing)
        }
    }
}

private struct PersonaEntryCard: View {
    let name: String
    let text: String
    let time: Date

    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    /// A spoken reply arrives as one run-on string; on a phone that reads as a
    /// slab. Break it into paragraphs of up to two sentences. Foundation's
    /// sentence enumeration is used rather than splitting on ". " so decimals
    /// and abbreviations ("39.9% drawdown", "a NAV of $6,312.40") stay intact.
    /// Text that already carries its own line breaks is left alone.
    static func paragraphs(of text: String, sentencesPerBlock: Int = 2) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.contains("\n") {
            let blocks = trimmed
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return blocks.isEmpty ? [trimmed] : blocks
        }

        var sentences: [String] = []
        trimmed.enumerateSubstrings(in: trimmed.startIndex..<trimmed.endIndex,
                                    options: .bySentences) { substring, _, _, _ in
            if let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        guard sentences.count > sentencesPerBlock else { return [trimmed] }

        return stride(from: 0, to: sentences.count, by: sentencesPerBlock).map { start in
            sentences[start..<min(start + sentencesPerBlock, sentences.count)]
                .joined(separator: " ")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HearthPalette.roast)
                Spacer()
                Text(time, format: .dateTime.hour().minute())
                    .font(.system(size: 11))
                    .foregroundStyle(HearthPalette.fawn)
            }
            ForEach(Array(Self.paragraphs(of: text).enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.system(size: 14))
                    .foregroundStyle(HearthPalette.roast)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(HearthPalette.fluff, in: shape)
        .overlay(shape.stroke(HearthPalette.linen, lineWidth: 1))
        .hearthSoftShadow()
        .frame(maxWidth: 560, alignment: .leading)
    }
}
