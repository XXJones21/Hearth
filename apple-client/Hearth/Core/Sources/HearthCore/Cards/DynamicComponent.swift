//
//  DynamicComponent.swift
//  Hearth
//
//  Renderer registry for generative UI cards. Swift port of the Echo client's
//  `ui/dynamic/DynamicComponent.kt`. Switches over the descriptor type and
//  renders the matching card; unknown types render nothing (forward compat).
//  Styled with iOS 26 materials rather than Echo's palette.
//

import SwiftUI

// MARK: - Registry

struct DynamicComponent: View {
    let descriptor: UiComponentDescriptor

    var body: some View {
        switch descriptor.type {
        case UiComponentDescriptor.typeClock:
            ClockCard(descriptor: descriptor)
        case UiComponentDescriptor.typeWeatherCard:
            WeatherCard(descriptor: descriptor)
        case UiComponentDescriptor.typeTimerCard:
            TimerCard(descriptor: descriptor)
        case UiComponentDescriptor.typeBriefText:
            BriefTextCard(descriptor: descriptor)
        case UiComponentDescriptor.typeSlideshow:
            SlideshowCard(descriptor: descriptor)
        case UiComponentDescriptor.typeCaptions:
            CaptionsCard(descriptor: descriptor)
        case UiComponentDescriptor.typeGeneratedView:
            GeneratedViewCard(descriptor: descriptor)
        case UiComponentDescriptor.typeImageCard:
            ImageCard(descriptor: descriptor)
        // The commissioned pair (choam_portfolio_dashboard, ticker_insight_card)
        // did not come across: they are one house's demo vocabulary, not
        // Hearth's. A server that still sends them falls through to EmptyView,
        // which is the tolerant-descriptor behaviour rather than a gap.
        default:
            EmptyView()
        }
    }
}

/// Vertical stack of all live cards, used by the main screen's bottom zone.
struct DynamicComponentStack: View {
    let descriptors: [UiComponentDescriptor]

    var body: some View {
        VStack(spacing: 16) {
            ForEach(descriptors) { descriptor in
                DynamicComponent(descriptor: descriptor)
            }
        }
    }
}

// MARK: - Shared card chrome

/// Hearth card surface: white (fluff) fill, 1px linen border, 16pt radius, soft
/// warm shadow. The single shell for every card type (mirrors the desktop's
/// `rounded-2xl border-linen bg-fluff shadow-soft`).
struct CardSurface<Content: View>: View {
    @ViewBuilder var content: Content

    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(HearthPalette.fluff, in: shape)
            .overlay(shape.stroke(HearthPalette.linen, lineWidth: 1))
            .hearthSoftShadow()
    }
}

/// Uppercase ember eyebrow (card titles / section headers), per the brand.
struct CardEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11.5, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(HearthPalette.ember)
    }
}

// MARK: - Clock

struct ClockCard: View {
    let descriptor: UiComponentDescriptor

    var body: some View {
        let time = descriptor.str("time")
        let date = descriptor.str("date")
        return CardSurface {
            VStack(alignment: .center, spacing: 4) {
                Text(time)
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(HearthPalette.roast)
                if !date.isEmpty {
                    Text(date)
                        .font(.subheadline)
                        .foregroundStyle(HearthPalette.fawn)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - Weather

struct WeatherCard: View {
    let descriptor: UiComponentDescriptor

    var body: some View {
        let temp = descriptor.str("temp")
        let condition = descriptor.str("condition")
        let location = descriptor.str("location")
        let high = descriptor.str("high")
        let low = descriptor.str("low")
        let day = descriptor.str("day")
        let isTomorrow = day.hasPrefix("tomorrow")

        // Forecast mode (tomorrow): no current temp, lead with high.
        let leadValue = isTomorrow ? high : temp
        let locationLabel = isTomorrow && !location.isEmpty
            ? "\(location) · tomorrow"
            : (isTomorrow ? "tomorrow" : location)

        return CardSurface {
            VStack(alignment: .leading, spacing: 6) {
                CardEyebrow(text: locationLabel.isEmpty ? "Weather" : "Weather · \(locationLabel)")
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if !leadValue.isEmpty {
                        Text(leadValue)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(HearthPalette.roast)
                    }
                    Text(condition)
                        .font(.title3)
                        .foregroundStyle(HearthPalette.fawn)
                }
                if !high.isEmpty || !low.isEmpty {
                    HStack(spacing: 12) {
                        if !high.isEmpty { Text("H \(high)") }
                        if !low.isEmpty { Text("L \(low)") }
                    }
                    .font(.footnote)
                    .foregroundStyle(HearthPalette.fawn)
                }
            }
        }
    }
}

// MARK: - Timer

struct TimerCard: View {
    let descriptor: UiComponentDescriptor

    private struct TimerRow: Identifiable {
        let id = UUID()
        let label: String
        let fireAt: TimeInterval
    }

    private var timers: [TimerRow] {
        descriptor.objList("timers").map { obj in
            TimerRow(
                label: obj.optString("label", fallback: "Timer"),
                fireAt: TimeInterval(obj.optInt("fire_at", fallback: 0))
            )
        }
    }

    var body: some View {
        let rows = timers
        return CardSurface {
            VStack(alignment: .leading, spacing: 10) {
                CardEyebrow(text: rows.count > 1 ? "Timers" : "Timer")

                if rows.isEmpty {
                    Text("No active timers")
                        .font(.subheadline)
                        .foregroundStyle(HearthPalette.fawn)
                } else {
                    // One shared tick drives every row's countdown.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let now = context.date.timeIntervalSince1970
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(rows) { row in
                                HStack {
                                    Text(row.label)
                                        .foregroundStyle(HearthPalette.fawn)
                                    Spacer()
                                    Text(Self.formatRemaining(row.fireAt - now))
                                        .font(.system(.body, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(HearthPalette.roast)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// m:ss under an hour, h:mm:ss above; "Done" once elapsed.
    static func formatRemaining(_ remaining: TimeInterval) -> String {
        guard remaining > 0 else { return "Done" }
        let total = Int(remaining.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Brief text

struct BriefTextCard: View {
    let descriptor: UiComponentDescriptor

    var body: some View {
        let title = descriptor.str("title")
        let body = descriptor.str("body")
        return CardSurface {
            VStack(alignment: .leading, spacing: 6) {
                if !title.isEmpty {
                    CardEyebrow(text: title)
                }
                Text(body)
                    .font(.body)
                    .foregroundStyle(HearthPalette.roast)
            }
        }
    }
}

// MARK: - Slideshow (placeholder until an on-device image loader is justified)

struct SlideshowCard: View {
    let descriptor: UiComponentDescriptor
    @State private var index = 0

    var body: some View {
        let images = descriptor.strList("images")
        let intervalMs = max(1000, descriptor.int("interval_ms", fallback: 6000))
        let interval = Double(intervalMs) / 1000.0

        return Group {
            if images.isEmpty {
                EmptyView()
            } else {
                CardSurface {
                    VStack(alignment: .leading, spacing: 7) {
                        // The picture itself, resolved against the Valar
                        // origin. Keyed by index so SwiftUI treats each turn
                        // of the cycle as a new view and cross-fades rather
                        // than swapping the image inside one AsyncImage.
                        RemoteImage(src: images[min(index, images.count - 1)], height: 190)
                            .id(index)
                            .transition(.opacity)
                        if images.count > 1 {
                            Text("\(min(index + 1, images.count)) of \(images.count)")
                                .font(.caption)
                                .foregroundStyle(HearthPalette.fawn)
                        }
                    }
                    .animation(.easeInOut(duration: 0.35), value: index)
                }
                .onAppear { startCycling(count: images.count, interval: interval) }
            }
        }
    }

    private func startCycling(count: Int, interval: Double) {
        guard count > 1 else { return }
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                index = (index + 1) % count
            }
        }
    }
}

// MARK: - Captions (breathing glow conveys "live")

struct CaptionsCard: View {
    let descriptor: UiComponentDescriptor
    @State private var glow = 0.10

    var body: some View {
        let text = descriptor.str("text")
        return Group {
            if text.isEmpty {
                EmptyView()
            } else {
                Text(text)
                    .font(.title3)
                    .foregroundStyle(HearthPalette.roast)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(HearthPalette.honey.opacity(glow))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(HearthPalette.bubbleLine, lineWidth: 1)
                    )
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                            glow = 0.20
                        }
                    }
            }
        }
    }
}
