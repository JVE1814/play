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
    case win
    /// A button with no other feedback (hint, undo).
    case tap
    /// Something was let go: a bowstring released.
    case release
    /// A shot struck home: an arrow into the target.
    case hit
    /// Something small was picked up.
    case coin
    /// A leap off the ground.
    case jump
    /// Running into something: the end of a run.
    case crash
    /// A power-up was picked up.
    case powerUp
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
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
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
        case .release: rigid.impactOccurred(intensity: 0.8)
        case .hit, .powerUp: medium.impactOccurred(intensity: 0.9)
        case .coin: soft.impactOccurred(intensity: 0.35)
        case .jump: light.impactOccurred(intensity: 0.6)
        case .crash: notification.notificationOccurred(.error)
        }
    }

    public static func soundURL(for event: FeedbackEvent) -> URL? {
        Bundle.module.url(forResource: event.rawValue, withExtension: "wav")
            ?? Bundle.module.url(forResource: event.rawValue, withExtension: "wav", subdirectory: "Sounds")
    }

    private func sound(for event: FeedbackEvent) {
        if !audioSessionConfigured {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            audioSessionConfigured = true
        }
        let player: AVAudioPlayer?
        if let cached = players[event] {
            player = cached
        } else if let url = Self.soundURL(for: event) {
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
