import AVFAudio

/// Activates an audio session intended for user-requested media playback.
/// The `.playback` category continues producing audio when the Ring/Silent
/// switch is enabled.
@MainActor
enum AudioPlaybackSession {
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }
}
