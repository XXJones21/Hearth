//
//  ClientPrefs.swift
//  Hearth
//
//  This phone's own preferences -- nothing here is the house's to know.
//  Mirrors the desktop client's settings.ts surface where iOS carries the
//  same behaviour: the start-with persona pin, the auto-reconnect switch,
//  and the voice output pair. Plain UserDefaults; none of it is a secret.
//

import Foundation

public enum ClientPrefs {
    private static let startPersonaKey = "hearth.startPersona"
    private static let autoReconnectKey = "hearth.autoReconnect"
    private static let speakRepliesKey = "hearth.speakReplies"
    private static let voiceVolumeKey = "hearth.voiceVolume"

    /// The persona this phone asks the house for on connect, or nil to adopt
    /// whatever the house is on. Enforcement lives in ChatViewModel and uses
    /// desktop's rule: only when the pin differs and actually exists in the
    /// served list, so a stale pin cannot strand the client.
    public static var startPersona: String? {
        get {
            guard let v = UserDefaults.standard.string(forKey: startPersonaKey),
                  !v.isEmpty else { return nil }
            return v
        }
        set {
            if let v = newValue, !v.isEmpty {
                UserDefaults.standard.set(v, forKey: startPersonaKey)
            } else {
                UserDefaults.standard.removeObject(forKey: startPersonaKey)
            }
        }
    }

    /// Someone debugging a server can stop the client from dialing back
    /// every second. Defaults on: a phone that silently stays offline is
    /// worse than one that retries.
    public static var autoReconnect: Bool {
        get { UserDefaults.standard.object(forKey: autoReconnectKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoReconnectKey) }
    }

    /// Voice output on this phone. Off keeps the whole turn intact -- the
    /// caption still reveals in playback time -- with the volume at zero.
    public static var speakReplies: Bool {
        get { UserDefaults.standard.object(forKey: speakRepliesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: speakRepliesKey) }
    }

    /// 0...1, applied to the playback mixer.
    public static var voiceVolume: Double {
        get {
            guard let v = UserDefaults.standard.object(forKey: voiceVolumeKey) as? Double
            else { return 1.0 }
            return min(1.0, max(0.0, v))
        }
        set { UserDefaults.standard.set(min(1.0, max(0.0, newValue)), forKey: voiceVolumeKey) }
    }

    /// Whether the volume's typing bar is up.
    ///
    /// OFF by default, which is the opposite of every other preference here and
    /// is a judgement rather than an oversight: a model persona stands in front
    /// of the bar, and someone meeting the headset client for the first time
    /// should see the persona rather than a control across her legs. Voice is
    /// the headset's primary way in -- a pinch on the persona starts a turn --
    /// and this brings back typing for the times speaking aloud is the wrong
    /// move.
    ///
    /// The KEY is public because the volume reads it through `@AppStorage`
    /// rather than through this accessor: the settings panel and the ornament
    /// are in the same window, so toggling has to take effect on the next frame
    /// rather than the next launch. One key, stated once, read two ways.
    public static let stageTypingBarKey = "hearth.stageTypingBar"

    public static var stageTypingBar: Bool {
        get { UserDefaults.standard.object(forKey: stageTypingBarKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: stageTypingBarKey) }
    }

    /// What the player should actually run at, both prefs folded together.
    public static var effectiveVolume: Float {
        speakReplies ? Float(voiceVolume) : 0
    }
}
