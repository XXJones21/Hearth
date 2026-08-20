//
//  GeneratedViewCard.swift
//  Hearth
//
//  Renders the open-ended `generated_view` component: a titled card whose body
//  is a list of typed sections. Swift port of the Echo client's
//  `GeneratedViewComponent` in `ui/dynamic/DynamicComponent.kt`.
//
//  Templates: plain (default) | brief (emphasized title) | hero_stat (first
//  stat shown large) | comparison (stat_row stats render as big side-by-side
//  panels). Sections: text | stat | stat_row | image | divider. Capped at
//  12 sections and 4 stats per row. Images render as path placeholders until
//  an on-device image loader is justified.
//

import SwiftUI
import HearthCore

public struct GeneratedViewCard: View {
    public let descriptor: UiComponentDescriptor

    private static let maxSections = 12
    private static let maxStatsPerRow = 4

    private var template: String { descriptor.str("template", fallback: "plain") }
    private var title: String { descriptor.str("title") }

    private var sections: [[String: Any]] {
        Array(descriptor.objList("sections").prefix(Self.maxSections))
    }

    public var body: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                if !title.isEmpty {
                    CardEyebrow(text: title)
                }
                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    sectionView(section, index: index)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: [String: Any], index: Int) -> some View {
        switch section.optString("kind") {
        case "text":
            // A text section may carry a `heading` (memory/journal cards,
            // 2026-08-20). Headed sections render like a journal page's
            // section blocks; unheaded ones stay plain body text.
            let heading = section.optString("heading")
            if heading.isEmpty {
                Text(section.optString("body"))
                    .font(.body)
                    .foregroundStyle(HearthPalette.roast)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HeadedTextBlock(heading: heading, text: section.optString("body"))
            }

        case "stat":
            let isHero = (template == "hero_stat" && index == 0)
            StatBlock(
                label: section.optString("label"),
                value: section.optString("value"),
                hero: isHero
            )

        case "stat_row":
            let stats = Array(section.childObjList("stats").prefix(Self.maxStatsPerRow))
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                    StatBlock(
                        label: stat.optString("label"),
                        value: stat.optString("value"),
                        hero: template == "comparison"
                    )
                    .frame(maxWidth: .infinity)
                }
            }

        case "image":
            // Resolved against the Valar origin when relative; see RemoteImage.
            let src = section.optString("src")
            if !src.isEmpty {
                RemoteImage(src: src, height: 150)
            }

        case "divider":
            Divider().overlay(HearthPalette.linen)

        default:
            EmptyView()
        }
    }
}

/// A headed text section, styled like the Journal page's section blocks
/// (JournalEntryView.SectionBlock): uppercase ember eyebrow over bullet-aware
/// body lines in a soft panel. Parchment here because the card surface is
/// already fluff.
private struct HeadedTextBlock: View {
    let heading: String
    let text: String

    private var lines: [String] {
        // The bodies arrive as light markdown (Selene reviews); bold markers
        // read as noise in a card line, so they are stripped, not rendered.
        text.replacingOccurrences(of: "**", with: "")
            .split(separator: "\n").map(String.init)
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
                            .font(.system(size: 13))
                            .lineSpacing(2)
                            .foregroundStyle(HearthPalette.roast)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(HearthPalette.parchment, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(HearthPalette.linen, lineWidth: 1)
        )
    }
}

/// One labeled statistic. Hero mode renders the value large and centered.
private struct StatBlock: View {
    public let label: String
    public let value: String
    public let hero: Bool

    public var body: some View {
        VStack(alignment: hero ? .center : .leading, spacing: 2) {
            if !label.isEmpty {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(HearthPalette.fawn)
            }
            Text(value)
                .font(hero
                      ? .system(size: 40, weight: .semibold, design: .rounded)
                      : .title2.weight(.semibold))
                .foregroundStyle(HearthPalette.roast)
        }
        .frame(maxWidth: hero ? .infinity : nil, alignment: hero ? .center : .leading)
    }
}
