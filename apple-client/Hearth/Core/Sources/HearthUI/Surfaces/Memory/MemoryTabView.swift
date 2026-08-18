//
//  MemoryTabView.swift
//  HearthUI
//
//  The rail's Memory tab: what the house has come to know about you.
//
//  A port of the desktop's `MemoryTab`, and the only reason it is a NEW view
//  rather than a shared one is that the phone has no rail to put it in. Every
//  other destination in this folder was pulled OUT of the iOS target because
//  two clients wanted it; this one arrives from the other direction, and it
//  lives here rather than in the Vision target so the phone can adopt it
//  without a move.
//
//  Facts are read-only everywhere, deliberately. Curation is conversational --
//  ask Selene to forget something and she will -- so a delete button here would
//  be a second, worse way to do it.
//

import SwiftUI
import HearthCore

public struct MemoryTabView: View {
    @StateObject private var loader = MemoryFactsLoader()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Remembered about you")
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .kerning(0.8)
                    .foregroundStyle(HearthPalette.fawn)

                if loader.unreachable {
                    note("Your second brain is not reachable right now.")
                } else if !loader.hasLoaded {
                    note("Reading.")
                } else if loader.facts.isEmpty {
                    note("Nothing remembered yet. Facts appear here as your persona learns them from talking to you.")
                } else {
                    ForEach(loader.facts) { fact in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(fact.text)
                                .font(.system(size: 12.5))
                                .foregroundStyle(HearthPalette.roast)
                                .fixedSize(horizontal: false, vertical: true)
                            if !fact.date.isEmpty {
                                Text(fact.date)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(HearthPalette.fawn)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(HearthPalette.parchment, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .task { await loader.load() }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(HearthPalette.fawn)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
