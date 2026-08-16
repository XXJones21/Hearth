//
//  JournalBookView.swift
//  Hearth
//
//  An open book. The desktop shows Selene's page beside the entry list as a
//  two-page spread; a phone cannot hold both, so her keeper page leads and the
//  entries follow beneath it. Diary-first with the transcript one deliberate
//  tap deeper (tasks/journal-design.md, decision 1) survives the translation.
//

import SwiftUI
import HearthCore

struct JournalBookView: View {
    let book: JournalBook

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                keeperPage
                stats
                topicAction

                if !book.entries.isEmpty {
                    Text("ENTRIES")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(HearthPalette.fawn)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 6)

                    ForEach(book.entries) { entry in
                        NavigationLink {
                            JournalEntryView(entry: entry, bookTitle: book.title)
                        } label: {
                            EntryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 28)
        }
        .background(HearthPalette.cream.ignoresSafeArea())
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(HearthPalette.parchment, for: .navigationBar)
    }

    /// Selene's summary, on parchment. Her curation pass writes these; a book
    /// she has not reached yet says so rather than showing an empty page.
    private var keeperPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(book.title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(HearthPalette.roast)
            Text(book.pages == 1 ? "1 page" : "\(book.pages) pages")
                .font(.system(size: 11))
                .foregroundStyle(HearthPalette.fawn)
                .padding(.top, 3)

            Text(book.summary.isEmpty ? Self.unwritten : book.summary)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(HearthPalette.roast)
                .padding(.top, 11)

            Text("Selene, keeper of the library")
                .font(.system(size: 11))
                .italic()
                .foregroundStyle(HearthPalette.fawn)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 9)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(HearthPalette.parchment, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HearthPalette.linen, lineWidth: 1)
        )
        .hearthSoftShadow()
        .padding(14)
    }

    private static let unwritten = "Selene has not written this page yet. On her next curation pass she reads the source of truth and leaves a short, factual summary here."

    private var stats: some View {
        HStack(spacing: 8) {
            StatCell(value: "\(book.pages)", label: "Entries")
            StatCell(value: "\(book.entries.count)", label: "Shown")
            StatCell(value: book.entries.first?.date ?? "--", label: "Latest")
        }
        .padding(.horizontal, 14)
    }

    /// A shelf book is an Engram topic (project or life root), and the house
    /// can open a fresh chat that already knows what it is about. The Heart's
    /// living volumes are not topics, so they carry no button.
    @ViewBuilder
    private var topicAction: some View {
        if book.shelf != .heart {
            Button {
                NotificationCenter.default.post(
                    name: .hearthTopicSession, object: nil,
                    userInfo: ["name": book.title]
                )
            } label: {
                Text("Start a session for \(book.title)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(HearthPalette.roast)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(HearthPalette.fennec, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ends the live session and opens a fresh one about this topic")
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
    }
}

private struct StatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(HearthPalette.roast)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(HearthPalette.fawn)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(HearthPalette.fluff, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(HearthPalette.linen, lineWidth: 1)
        )
    }
}

private struct EntryRow: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(HearthPalette.roast)
                .multilineTextAlignment(.leading)

            if !entry.synopsis.isEmpty {
                Text(entry.synopsis)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundStyle(HearthPalette.fawn)
                    .lineLimit(3)
                    .padding(.top, 4)
            }

            HStack(spacing: 7) {
                PersonaChip(name: entry.persona)
                Spacer(minLength: 4)
                Text(entry.date)
                    .font(.system(size: 10.5))
                    .foregroundStyle(HearthPalette.fawn)
            }
            .padding(.top, 9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(HearthPalette.fluff, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(HearthPalette.linen, lineWidth: 1)
        )
        .hearthSoftShadow()
        .padding(.horizontal, 14)
        .padding(.bottom, 9)
    }
}

struct PersonaChip: View {
    let name: String

    var body: some View {
        Text(name.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(name.lowercased() == "selene"
                             ? HearthPalette.roast
                             : Color(red: 1, green: 0.953, blue: 0.894))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(HearthPalette.speaker(name), in: Capsule())
    }
}
