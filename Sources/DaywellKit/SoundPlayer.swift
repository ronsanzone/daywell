import AVFoundation
import Foundation

/// Short synthesized cues. Rendered once into memory, so playback has no file I/O.
public enum SoundCue: String, CaseIterable, Sendable {
  case tock, beep, pat, drop, chord
}

/// Plays theme cues through one long-lived audio engine. Opt-in via Preferences.
@MainActor public final class SoundPlayer {
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private let format: AVAudioFormat
  private var buffers: [SoundCue: AVAudioPCMBuffer] = [:]
  private var started = false

  public init() {
    // A 44.1 kHz mono float format is always valid.
    // swiftlint:disable:next force_unwrapping
    format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    for cue in SoundCue.allCases { buffers[cue] = Self.render(cue, format: format) }
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    engine.mainMixerNode.outputVolume = 0.55
  }

  public func play(_ cue: SoundCue) {
    guard let buffer = buffers[cue] else { return }
    if !started {
      do {
        try engine.start()
        started = true
      } catch { return }
    }
    player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    if !player.isPlaying { player.play() }
  }

  /// Duration of a rendered cue, for tests.
  public func duration(of cue: SoundCue) -> Double {
    Double(buffers[cue]?.frameLength ?? 0) / format.sampleRate
  }

  private static func render(_ cue: SoundCue, format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let rate = format.sampleRate
    // (frequency, start, duration, gain, waveform)
    typealias Tone = (Double, Double, Double, Double, Wave)
    let tones: [Tone]
    switch cue {
    case .tock: tones = [(520, 0, 0.12, 0.5, .triangle), (780, 0.015, 0.07, 0.15, .sine)]
    case .beep: tones = [(880, 0, 0.09, 0.18, .square)]
    case .pat: tones = [(220, 0, 0.14, 0.6, .sine), (440, 0, 0.05, 0.12, .triangle)]
    case .drop: tones = [(660, 0, 0.2, 0.35, .sweepDown)]
    case .chord:
      tones = [523.25, 659.25, 783.99, 1046.5].enumerated().map {
        ($0.element, Double($0.offset) * 0.07, 0.9, 0.16, .sine)
      }
    }
    let length = tones.map { $0.1 + $0.2 }.max() ?? 0.1
    let frames = AVAudioFrameCount(length * rate + 64)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
      let samples = buffer.floatChannelData?[0]
    else { return nil }
    buffer.frameLength = frames
    for index in 0..<Int(frames) { samples[index] = 0 }
    for (frequency, start, duration, gain, wave) in tones {
      let first = Int(start * rate)
      let count = Int(duration * rate)
      for offset in 0..<count where first + offset < Int(frames) {
        let t = Double(offset) / rate
        let attack = min(1, t / 0.006)
        let decay = exp(-5 * t / duration)
        let phase = wave.phase(frequency: frequency, time: t, duration: duration)
        samples[first + offset] += Float(wave.sample(phase) * gain * attack * decay)
      }
    }
    return buffer
  }

  private enum Wave {
    case sine, triangle, square, sweepDown

    func phase(frequency: Double, time: Double, duration: Double) -> Double {
      switch self {
      case .sweepDown:
        // Exponential glide from frequency to half of it.
        let k = log(0.5) / duration
        return frequency * (exp(k * time) - 1) / k
      default: return frequency * time
      }
    }

    func sample(_ phase: Double) -> Double {
      let fraction = phase - floor(phase)
      switch self {
      case .sine, .sweepDown: return sin(2 * .pi * fraction)
      case .triangle: return 4 * abs(fraction - 0.5) - 1
      case .square: return fraction < 0.5 ? 1 : -1
      }
    }
  }
}
