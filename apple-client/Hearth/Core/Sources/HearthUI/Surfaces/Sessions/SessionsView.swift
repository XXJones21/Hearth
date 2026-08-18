//
//  SessionsView.swift
//  Hearth
//
//  Earlier conversations, and the way back into one. Same shape as Journal,
//  Apps and Settings -- full screen, "Hearth" back on the left, large title in
//  the body -- so every destination off the house shelf behaves alike.
//
//  Two sources feed one list (see SessionModels.swift): records are what the
//  house has said, written as it happens; journal entries are what it later
//  wrote up. Tapping a row expands a short preview; Resume is a second,
//  deliberate tap, exactly like the desktop rail -- a resume ends the live
//  session, so it must not be reachable by one stray touch.
//

import SwiftUI
import HearthCore

public struct SessionsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    /// The host's way out, when there is no presentation to dismiss. Starting
    /// or resuming a session puts this screen away, and in a volume that has to
    /// go through the host or the panel simply stays open over a live turn.
    @Environment(\.hearthSurfaceClose) private var close
    @StateObject private var store = SessionsStore()
    @State private var expandedRow: String?

    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    /// Session verbs need a live socket and no turn in flight; the view
    /// dims and disables rather than letting a tap fail into a system row.
    private var canAct: Bool {
        viewModel.connectionStatus == .connected && !viewModel.isWaitingForResponse
    }

    /// Put this screen away, however the host put it up.
    private func leave() {
        if let close { close() } else { dismiss() }
    }

    public var body: some View {
        HearthSurfaceShell {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    newSessionBlock

                    if store.isLoading && !store.hasLoaded {
                        loading
                    } else if store.unreachable {
                        unreachable
                    } else if store.rows.isEmpty && store.hasLoaded {
                        empty
                    } else {
                        rowGroups
                    }
                }
                .padding(.bottom, 30)
            }
            .task { await store.load() }
            .refreshable { await store.load() }
            .background(HearthPalette.cream.ignoresSafeArea())
        }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sessions")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(HearthPalette.roast)
            Text("what the house has said, and the way back into it")
                .font(.system(size: 12.5))
                .italic()
                .foregroundStyle(HearthPalette.fawn)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }

    private var newSessionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Start fresh without closing Hearth. The house keeps what it wrote down; the live chat clears.")
                .font(.system(size: 12.5))
                .foregroundStyle(HearthPalette.fawn)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                viewModel.startNewSession()
                leave()
            } label: {
                Text("New session")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(HearthPalette.fluff)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(HearthPalette.ember, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canAct)
            .opacity(canAct ? 1 : 0.5)
            .accessibilityHint("Ends the current conversation and starts a fresh one")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    private var loading: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7).tint(HearthPalette.fennec)
            Text("Asking the house what it remembers...")
                .font(.system(size: 12))
                .foregroundStyle(HearthPalette.fawn)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private var unreachable: some View {
        VStack(spacing: 5) {
            Text("The house is not reachable right now")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HearthPalette.roast)
            Text("Earlier conversations will list here once it answers.")
                .font(.system(size: 12))
                .foregroundStyle(HearthPalette.fawn)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private var empty: some View {
        Text("Nothing yet. Conversations land here as you have them.")
            .font(.system(size: 12.5))
            .foregroundStyle(HearthPalette.fawn)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 24)
    }

    // MARK: - Rows

    private var rowGroups: some View {
        let groups = SessionMerge.grouped(store.rows)
        return VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Earlier conversations")
            ForEach(groups, id: \.date) { group in
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.date)
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(HearthPalette.fawn)
                        .padding(.horizontal, 18)
                    ForEach(group.items) { row in
                        sessionRow(row)
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    private func sessionRow(_ row: SessionRow) -> some View {
        let expanded = expandedRow == row.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedRow = expanded ? nil : row.id
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(HearthPalette.roast)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if !row.persona.isEmpty {
                        Text(row.persona)
                            .font(.system(size: 11))
                            .foregroundStyle(HearthPalette.fawn)
                    }
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .background(expanded ? HearthPalette.parchment : Color.clear)
            .accessibilityLabel("\(row.title), \(row.persona)")
            .accessibilityHint(expanded ? "Collapses the preview" : "Shows a preview and the resume button")

            if expanded {
                rowDetail(row)
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
    }

    private func rowDetail(_ row: SessionRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !row.summary.isEmpty {
                Text(row.summary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(HearthPalette.roast)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let turns = row.turns {
                Text("\(turns) turn\(turns == 1 ? "" : "s")\(row.synced == true ? " · written up in the Journal" : " · not written up yet")")
                    .font(.system(size: 11))
                    .foregroundStyle(HearthPalette.fawn)
            }
            if row.resumable {
                Button {
                    switch row.kind {
                    case .record: viewModel.resumeSession(recordId: row.rowId)
                    case .journal: viewModel.resumeSession(slug: row.rowId)
                    }
                    leave()
                } label: {
                    Text("Resume")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(HearthPalette.fluff)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(HearthPalette.ember, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canAct)
                .opacity(canAct ? 1 : 0.5)
                .accessibilityHint("Ends the live session and picks this conversation back up")
            } else {
                Text("No full transcript was kept for this one.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(HearthPalette.fawn)
            }
        }
    }
}

// MARK: - Section label (matches HouseShelf's)

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.9)
            .foregroundStyle(HearthPalette.fawn)
            .padding(.horizontal, 18)
    }
}
