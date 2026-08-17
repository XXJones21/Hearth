//
//  ActionCards.swift
//  Hearth
//
//  The two cards that ANSWER BACK. Everything else in the registry renders
//  and rests; these carry a decision the house is waiting on, which is why
//  they were the first gap worth closing after the read-only set -- a
//  permission_card that renders as nothing leaves the house blocked with an
//  empty gap on the phone where the question should be.
//
//  Ports of the desktop's PermissionCard.tsx and ChoiceCard.tsx, wire shapes
//  and copy included.
//

import SwiftUI

// MARK: - Preview gating

/// False inside the card library, where sample descriptors carry invented
/// request ids and labels -- a preview must show the card without being able
/// to answer a question nobody asked.
private struct CardActionsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    var cardActionsEnabled: Bool {
        get { self[CardActionsEnabledKey.self] }
        set { self[CardActionsEnabledKey.self] = newValue }
    }
}

public extension Notification.Name {
    /// A choice_card chip was tapped. The hosting surface decides what
    /// sending means -- ChatViewModel sends the label as the user's turn,
    /// exactly as if they had typed it (the desktop feed's contract).
    static let hearthChoicePicked = Notification.Name("hearth.choicePicked")
}

// MARK: - Permission (files/decide)

/// The one card the operator must answer before the turn can finish. A folder
/// outside the house's allow-list does not fail and is not silently opened:
/// the tool parks, this card asks, and the same call resumes on Approve.
public struct PermissionCard: View {
    public let descriptor: UiComponentDescriptor

    @Environment(\.cardActionsEnabled) private var actionsEnabled
    @State private var status: String
    @State private var deciding = false
    @State private var error = ""

    public init(descriptor: UiComponentDescriptor) {
        self.descriptor = descriptor
        _status = State(initialValue: descriptor.str("status", fallback: "pending"))
    }

    private var action: String { descriptor.str("action", fallback: "read") }
    private var path: String { descriptor.str("path") }
    private var creating: Bool { action == "create" }
    private var deleting: Bool { action == "delete" }

    public var body: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 6) {
                CardEyebrow(text: deleting ? "Delete a file" : creating ? "New folder" : "Folder access")

                Text(question)
                    .font(.system(size: 14))
                    .foregroundStyle(HearthPalette.roast)
                    .fixedSize(horizontal: false, vertical: true)

                Text(deleting
                     ? "It goes to the house trash, not away for good. This approval covers this one file."
                     : "This grant stays on this house until you remove it from file_grants.yaml.")
                    .font(.system(size: 12))
                    .foregroundStyle(HearthPalette.fawn)
                    .fixedSize(horizontal: false, vertical: true)

                if status == "pending" {
                    HStack(spacing: 8) {
                        Button { decide(true) } label: {
                            Text(deciding ? "Approving" : "Approve")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(HearthPalette.roast)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(HearthPalette.fennec, in: Capsule())
                                .overlay(Capsule().stroke(HearthPalette.ember, lineWidth: 1))
                        }
                        Button { decide(false) } label: {
                            Text("Deny")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(HearthPalette.fawn)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(HearthPalette.fluff, in: Capsule())
                                .overlay(Capsule().stroke(HearthPalette.linen, lineWidth: 1))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(deciding || !actionsEnabled)
                    .opacity(actionsEnabled ? 1 : 0.5)
                    .padding(.top, 4)
                } else {
                    Text(status == "granted" ? "Granted. Continuing." : "Denied.")
                        .font(.system(size: 13))
                        .foregroundStyle(HearthPalette.roast)
                        .padding(.top, 4)
                }

                if !error.isEmpty {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(HearthPalette.clay)
                }
            }
        }
    }

    private var question: String {
        let shown = path.isEmpty ? (deleting ? "this file" : "this folder") : path
        if deleting { return "Delete \(shown)?" }
        if creating { return "Create \(shown) and let Hearth write there?" }
        return "Allow access to \(shown) for \(action)?"
    }

    private func decide(_ approve: Bool) {
        let requestId = descriptor.str("request_id")
        guard !requestId.isEmpty, status == "pending", !deciding else { return }
        deciding = true
        error = ""
        Task { @MainActor in
            defer { deciding = false }
            guard var request = ServerConfig.shared.request("/files/decide", timeout: 10) else {
                error = "No house configured."
                return
            }
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "request_id": requestId, "approve": approve,
            ])
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let payload = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                guard payload["ok"] as? Bool == true else {
                    error = payload.optString("error", fallback: "That did not go through.")
                    return
                }
                status = payload.optString("status", fallback: approve ? "granted" : "denied")
            } catch {
                self.error = "Could not reach the house."
            }
        }
    }
}

// MARK: - Choice (interview chips)

/// A question with persona-authored options. Tapping a chip posts
/// `.hearthChoicePicked`; the free composer always outranks the chips, and
/// the card says so.
public struct ChoiceCard: View {
    public let descriptor: UiComponentDescriptor

    @Environment(\.cardActionsEnabled) private var actionsEnabled
    @State private var picked: String?

    public init(descriptor: UiComponentDescriptor) {
        self.descriptor = descriptor
    }

    private struct Option: Identifiable {
        let label: String
        let detail: String
        var id: String { label }
    }

    private var options: [Option] {
        descriptor.objList("options").compactMap { obj in
            let label = obj.optString("label")
            guard !label.isEmpty else { return nil }
            return Option(label: label, detail: obj.optString("detail"))
        }
    }

    public var body: some View {
        let question = descriptor.str("question")
        let opts = options
        let allowFree = (descriptor.props["allow_free_text"] as? Bool) ?? true

        return Group {
            if question.isEmpty || opts.isEmpty {
                EmptyView()
            } else {
                CardSurface {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(question)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(HearthPalette.fawn)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: 8) {
                            ForEach(opts) { option in
                                chip(option)
                            }
                        }

                        if allowFree && picked == nil {
                            Text("Or answer in your own words below; your words always win.")
                                .font(.system(size: 12))
                                .foregroundStyle(HearthPalette.fawn)
                        }
                    }
                }
            }
        }
    }

    private func chip(_ option: Option) -> some View {
        let isPicked = picked == option.label
        let dimmed = picked != nil && !isPicked
        return Button {
            guard picked == nil, actionsEnabled else { return }
            picked = option.label
            NotificationCenter.default.post(
                name: .hearthChoicePicked, object: nil,
                userInfo: ["label": option.label]
            )
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isPicked ? HearthPalette.cream : HearthPalette.roast)
                if !option.detail.isEmpty {
                    Text(option.detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(isPicked ? HearthPalette.cream : HearthPalette.fawn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isPicked ? HearthPalette.ember : HearthPalette.parchment,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isPicked ? HearthPalette.ember : HearthPalette.linen, lineWidth: 1)
            )
            .opacity(dimmed ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(picked != nil || !actionsEnabled)
    }
}
