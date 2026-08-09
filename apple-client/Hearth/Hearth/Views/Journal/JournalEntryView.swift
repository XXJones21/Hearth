//
//  JournalEntryView.swift
//  Hearth
//
//  One page of a book. Selene's diary bodies carry markdown headings
//  (Summary / Key Decisions / Open Questions / Action Items), so the view
//  parses those sections rather than dumping the raw text.
//
//  "Discuss this memory" is the only editing affordance by design: curation is
//  CONVERSATIONAL, not a form (tasks/journal-design.md, decision 2). It
//  pre-fills the composer and hands the thread back to Sulivan, who consults
//  Selene through the existing consult_memory seam.
//

import SwiftUI
import HearthCore

struct JournalEntryView: View {
    let entry: JournalEntry
    let bookTitle: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(HearthPalette.roast)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    PersonaChip(name: entry.persona)
                    Text(bookTitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(HearthPalette.fawn)
                    Spacer(minLength: 4)
                    Text(entry.date)
                        .font(.system(size: 11.5))
                        .foregroundStyle(HearthPalette.fawn)
                }
                .padding(.top, 8)

                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    if section.heading.isEmpty {
                        Text(section.body)
                            .font(.system(size: 13))
                            .lineSpacing(3)
                            .foregroundStyle(HearthPalette.roast)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 14)
                    } else {
                        SectionBlock(heading: section.heading, text: section.body)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)

            actions
        }
        .background(HearthPalette.cream.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(HearthPalette.parchment, for: .navigationBar)
    }

    private var actions: some View {
        HStack(spacing: 9) {
            Button {
                // Wiring lands with the composer hand-off; the shape is fixed
                // by the design (pre-fill, do not edit in place).
                dismiss()
            } label: {
                Text("Discuss this memory")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(HearthPalette.roast)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(HearthPalette.fennec, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 20)
        .padding(.bottom, 28)
    }

    // MARK: - Diary parsing

    private struct Section {
        let heading: String
        let body: String
    }

    /// Splits on markdown headings. Text before the first heading (or a body
    /// with none at all, which is what the session summaries are) comes back as
    /// one unheaded section.
    private var sections: [Section] {
        let lines = entry.synopsis.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [Section] = []
        var heading = ""
        var buffer: [String] = []

        func flush() {
            let body = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty || !heading.isEmpty {
                out.append(Section(heading: heading, body: body))
            }
            buffer.removeAll()
        }

        for line in lines {
            if line.hasPrefix("#") {
                flush()
                heading = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            } else {
                buffer.append(line)
            }
        }
        flush()
        return out.filter { !($0.heading.isEmpty && $0.body.isEmpty) }
    }
}

private struct SectionBlock: View {
    let heading: String
    let text: String

    private var lines: [String] {
        text.split(separator: "\n").map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(heading.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(HearthPalette.ember)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    let isBullet = line.hasPrefix("-") || line.hasPrefix("*")
                    HStack(alignment: .top, spacing: 6) {
                        if isBullet {
                            Circle()
                                .fill(HearthPalette.fawn)
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)
                        }
                        Text(isBullet
                             ? line.dropFirst().trimmingCharacters(in: .whitespaces)
                             : line)
                            .font(.system(size: 12.5))
                            .lineSpacing(2)
                            .foregroundStyle(HearthPalette.roast)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(HearthPalette.fluff, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(HearthPalette.linen, lineWidth: 1)
        )
        .hearthSoftShadow()
        .padding(.top, 16)
    }
}
