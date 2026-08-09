//
//  EaselStore.swift
//  Hearth
//
//  Where a drawing's outcome lives, and the reason it does not live in the
//  card.
//
//  `TimelineFeed` is a LazyVStack, so a card's `@State` is thrown away when it
//  scrolls out of view and rebuilt from its props when it comes back. Those
//  props are whatever arrived at submit time -- `status: "running"`, empty
//  `src` -- so a card holding its own polled result would go blank on the way
//  back, re-poll, find that a NEWER drawing is now the current job, never
//  match its own `job_id`, and sit on an empty canvas forever. The desktop can
//  hold per-card state because its timeline is not virtualized; this one
//  cannot.
//
//  So the outcome is held here, keyed by `job_id`, and a card renders the
//  store's entry for its own job or falls back to its props. That also means
//  ONE timer for the screen rather than one per card.
//
//  Three rules, from the desktop's own test:
//    1. Poll only while the job is unsettled, and stop for good once it is.
//       A settled card is a transcript entry and must never mutate.
//    2. Match `job_id` before applying anything. `/imagery/state` reports the
//       CURRENT drawing; a second request replaces it, and a card applying the
//       response blindly would show someone else's picture.
//    3. Never drive the render from the client. A daemon thread on the server
//       collects the PNG whether or not anyone is looking, so a backgrounded
//       phone loses nothing and cancelling a poll costs nothing.
//

import Foundation

@MainActor
public final class EaselStore: ObservableObject {
    public static let shared = EaselStore()

    public struct Outcome {
        var status: String
        var src: String
        var note: String

        var isSettled: Bool { status == "done" || status == "error" }
    }

    /// Settled and in-flight outcomes by job. Small and bounded: the server
    /// draws one at a time, so this holds one entry per drawing the session
    /// has seen rather than anything that grows with the transcript.
    @Published public private(set) var outcomes: [String: Outcome] = [:]

    /// True while a drawing is still on the easel. The stage reads this so the
    /// persona does not drop to idle the moment the turn ends: the house IS
    /// still working, and showing it at rest while a render runs is what made
    /// "I'll let you know when it's done" look like a broken promise.
    @Published public private(set) var isDrawing = false

    private var pollTask: Task<Void, Never>?
    /// Jobs already settled. Kept separately so a late poll cannot reopen one.
    private var settled: Set<String> = []
    /// How many cards are currently on screen for the live job. The SAME card
    /// can be rendered twice at once -- the stage spotlights the newest card
    /// while the feed also lists it -- so one of them disappearing must not
    /// cancel the poll the other still needs.
    private var watchers = 0

    /// Desktop's interval. Matching it keeps the two clients honest about how
    /// hard they lean on a machine that is also rendering.
    private let interval: TimeInterval = 2.5

    private init() {}

    public func outcome(for jobID: String) -> Outcome? {
        outcomes[jobID]
    }

    /// Start watching a job, if it is not already settled and not already
    /// being watched. Safe to call from every card's `onAppear`.
    public func watch(jobID: String) {
        guard !jobID.isEmpty, !settled.contains(jobID) else { return }
        watchers += 1
        if let known = outcomes[jobID] {
            isDrawing = !known.isSettled
        } else {
            // Unseen job: it was emitted running, which is the only state a
            // card is ever born in.
            isDrawing = true
        }
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.poll()
        }
    }

    /// Stop watching from one card. The render continues on the server
    /// regardless, so cancelling is free -- there is nothing to lose and
    /// nothing to resume.
    public func stop() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        pollTask?.cancel()
        pollTask = nil
        // `isDrawing` is deliberately NOT cleared: the easel is still busy
        // whether or not a card is on screen to watch it, and the stage should
        // keep saying so.
    }

    private func poll() async {
        while !Task.isCancelled {
            if let state = await fetchState() {
                let job = state.jobID
                if !job.isEmpty {
                    let outcome = Outcome(status: state.status, src: state.src, note: state.note)
                    outcomes[job] = outcome
                    isDrawing = !outcome.isSettled
                    if outcome.isSettled {
                        settled.insert(job)
                        // Nothing left to watch: the current drawing is done
                        // and the next request starts its own poll.
                        pollTask = nil
                        watchers = 0
                        return
                    }
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    private struct State: Decodable {
        var jobID: String = ""
        var status: String = ""
        var src: String = ""
        var note: String = ""

        private enum CodingKeys: String, CodingKey {
            case status, src, note
            case jobID = "job_id"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            jobID = (try? c.decode(String.self, forKey: .jobID)) ?? ""
            status = (try? c.decode(String.self, forKey: .status)) ?? ""
            src = (try? c.decode(String.self, forKey: .src)) ?? ""
            note = (try? c.decode(String.self, forKey: .note)) ?? ""
        }
    }

    /// An older server 404s and an unreachable one throws. Both mean "keep
    /// what the card already has" rather than an error: a picture that has
    /// already arrived must not disappear because a poll missed.
    private func fetchState() async -> State? {
        guard let url = ServerConfig.shared.url("/imagery/state") else { return nil }
        var request = URLRequest(url: url)
        ServerConfig.shared.authorize(&request)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            return nil
        }
        return try? JSONDecoder().decode(State.self, from: data)
    }
}
