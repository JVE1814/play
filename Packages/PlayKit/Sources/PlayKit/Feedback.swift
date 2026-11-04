import AVFoundation
import UIKit

/// Moments that can produce a sound and/or a haptic.
public enum FeedbackEvent: String, CaseIterable, Sendable {
    /// A card or piece was placed.
    case place
    /// Cards were drawn or dealt.
    case draw
    /// The tap had no legal move.
    case invalid
    /// The game was won.
    case win
    /// A button with no other feedback (hint, undo).
    case tap
}

/// Plays sounds (off by default) and light haptics (on by default) according to `AppSettings`.
/// Sounds use the ambient audio session, so they respect the silent switch and never stop
/// the music or podcast you are listening to on the train.
@MainActor
public final class Feedback {
    private let settings: AppSettings
    private var players: [FeedbackEvent: AVAudioPlayer] = [:]
    private var audioSessionConfigured = false
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let notification = UINotificationFeedbackGenerator()

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public func play(_ event: FeedbackEvent) {
        if settings.hapticsEnabled { haptic(for: event) }
        if settings.soundEnabled { sound(for: event) }
    }

    private func haptic(for event: FeedbackEvent) {
        switch event {
        case .place: light.impactOccurred(intensity: 0.7)
        case .draw, .tap: soft.impactOccurred(intensity: 0.5)
        case .invalid: notification.notificationOccurred(.warning)
        case .win: notification.notificationOccurred(.success)
        }
    }

    private func sound(for event: FeedbackEvent) {
        if !audioSessionConfigured {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            audioSessionConfigured = true
        }
        let player: AVAudioPlayer?
        if let cached = players[event] {
            player = cached
        } else if let url = Bundle.module.url(forResource: event.rawValue, withExtension: "wav")
                    ?? Bundle.module.url(forResource: event.rawValue, withExtension: "wav", subdirectory: "Sounds") {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.volume = 0.6
            player?.prepareToPlay()
            players[event] = player
        } else {
            player = nil
        }
        player?.currentTime = 0
        player?.play()
    }
}
