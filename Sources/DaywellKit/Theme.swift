import Observation
import SwiftUI

/// Swift 6.4's macOS 27 SDK declares `@State` as a macro whose plugin ships only with
/// Xcode. This alias names the underlying property wrapper so Command Line Tools builds work.
typealias ViewState = SwiftUI.State

public enum ThemeID: String, CaseIterable, Identifiable, Sendable {
  // Raw values keep existing preferences: "graphite" was the default, "amber" the CRT.
  case quietNative = "graphite"
  case phosphor = "amber"
  case waffleCat
  case flexokiLight

  public var id: String { rawValue }

  public init(stored: String?) {
    self = stored.flatMap(ThemeID.init(rawValue:)) ?? .quietNative
  }
}

/// Everything a theme controls. Layout and keys never vary by theme.
public struct ThemeProfile: Sendable {
  public enum RingShape: Sendable { case circle, square }
  public enum FinishStyle: Sendable {
    /// Fill with one spring overshoot.
    case spring
    /// Flare bright, then settle (Phosphor).
    case flare
    /// Fill in the next ink of a cycle (Flexoki).
    case ink
  }
  public enum TokenStyle: Sendable { case roundedSquare, bar, dot }
  public enum Overlay: Sendable { case none, crt }

  public var id: ThemeID
  public var title: String
  public var summary: String
  public var scheme: ColorScheme
  public var background: Color
  public var raised: Color
  public var text: Color
  public var secondary: Color
  public var accent: Color
  public var highlight: Color
  public var separator: Color
  /// Completion inks. Single-ink themes repeat their accent.
  public var inks: [Color]
  public var monospaced: Bool
  public var ring: RingShape
  public var finish: FinishStyle
  public var token: TokenStyle
  public var sound: SoundCue
  public var overlay: Overlay
  public var dayClearTitle: String

  public func ink(_ index: Int) -> Color { inks[((index % inks.count) + inks.count) % inks.count] }

  public func font(_ size: CGFloat, _ weight: Font.Weight = .regular, italic: Bool = false)
    -> Font
  {
    if monospaced, id != .phosphor, FontRegistry.mapleMonoAvailable {
      let font = Font.custom(FontRegistry.mapleMono, size: size).weight(weight)
      return italic ? font.italic() : font
    }
    let font = Font.system(size: size, weight: weight, design: monospaced ? .monospaced : .default)
    return italic ? font.italic() : font
  }

  public static func named(_ id: ThemeID) -> ThemeProfile {
    switch id {
    case .quietNative:
      ThemeProfile(
        id: id, title: "Quiet Native", summary: "Refined Graphite. The default.", scheme: .dark,
        background: Color(hex: 0x242527), raised: Color(hex: 0x2D2F32),
        text: Color(hex: 0xE8E7E3), secondary: Color(hex: 0xAAACAE),
        accent: Color(hex: 0xB6A48F), highlight: Color(hex: 0xE3D3BF),
        separator: Color.white.opacity(0.08), inks: [Color(hex: 0xB6A48F)], monospaced: false,
        ring: .circle, finish: .spring, token: .roundedSquare, sound: .tock, overlay: .none,
        dayClearTitle: "Day clear")
    case .phosphor:
      ThemeProfile(
        id: id, title: "Phosphor", summary: "Amber CRT, committed.", scheme: .dark,
        background: Color(hex: 0x130E08), raised: Color(hex: 0x251A0E),
        text: Color(hex: 0xFFDBA8), secondary: Color(hex: 0xE0BD8C),
        accent: Color(hex: 0xFFBB59), highlight: Color(hex: 0xFFF1D0),
        separator: Color(hex: 0xE0BD8C).opacity(0.16), inks: [Color(hex: 0xFFBB59)],
        monospaced: true, ring: .square, finish: .flare, token: .bar, sound: .beep,
        overlay: .crt, dayClearTitle: "DAY CLEAR")
    case .waffleCat:
      ThemeProfile(
        id: id, title: "Waffle Cat", summary: "Your Ghostty palette, in Maple Mono.",
        scheme: .dark,
        background: Color(hex: 0x292025), raised: Color(hex: 0x362D30),
        // Secondary is lifted from the terminal's #A58C82 so it reads 4.5:1 on raised rows.
        text: Color(hex: 0xFFF4D8), secondary: Color(hex: 0xB59D93),
        accent: Color(hex: 0xC87D2A), highlight: Color(hex: 0xE4C56D),
        separator: Color(hex: 0x3E3236), inks: [Color(hex: 0xC87D2A)], monospaced: true,
        ring: .circle, finish: .spring, token: .roundedSquare, sound: .pat, overlay: .none,
        dayClearTitle: "Day clear")
    case .flexokiLight:
      ThemeProfile(
        id: id, title: "Flexoki Light", summary: "Ink on warm paper; every finish a new ink.",
        scheme: .light,
        background: Color(hex: 0xFFFCF0), raised: Color(hex: 0xF2F0E5),
        text: Color(hex: 0x100F0F), secondary: Color(hex: 0x66655F),
        accent: Color(hex: 0x205EA6), highlight: Color(hex: 0x205EA6),
        separator: Color(hex: 0xDAD8CE),
        // Flexoki 600-level inks: the 400 yellow and cyan fail 3:1 on this paper.
        inks: ThemeProfile.flexokiInks.map(Color.init(hex:)), monospaced: true, ring: .circle,
        finish: .ink, token: .dot, sound: .tock, overlay: .none, dayClearTitle: "Day clear")
    }
  }

  static let flexokiInks: [UInt32] = [
    0xAF3029, 0xBC5215, 0xAD8301, 0x66800B, 0x24837B, 0x205EA6, 0x5E409D, 0xA02F6F,
  ]
}

private struct ThemeKey: EnvironmentKey {
  static let defaultValue = ThemeProfile.named(.quietNative)
}

extension EnvironmentValues {
  public var theme: ThemeProfile {
    get { self[ThemeKey.self] }
    set { self[ThemeKey.self] = newValue }
  }
}

extension Color {
  public init(hex: UInt32) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 255) / 255,
      green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
  }
}

/// WCAG relative-luminance contrast between two sRGB hex colors.
public func contrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
  func luminance(_ hex: UInt32) -> Double {
    let channels = [(hex >> 16) & 255, (hex >> 8) & 255, hex & 255].map { value -> Double in
      let c = Double(value) / 255
      return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
  }
  let (a, b) = (luminance(first), luminance(second))
  return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

@MainActor @Observable public final class Preferences {
  @ObservationIgnored private let defaults: UserDefaults
  public var theme: ThemeID { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
  public var profile: ThemeProfile { ThemeProfile.named(theme) }
  private var storedCRTIntensity: Double
  public var crtIntensity: Double {
    get { storedCRTIntensity }
    set {
      storedCRTIntensity = Self.boundedIntensity(newValue)
      defaults.set(storedCRTIntensity, forKey: "crtIntensity")
    }
  }
  /// Menu bar shows the current task as text (default) instead of a plain icon.
  public var tickerShowsTask: Bool {
    didSet { defaults.set(tickerShowsTask, forKey: "tickerShowsTask") }
  }
  public var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: "soundEnabled") } }
  public var finishHotKeyEnabled: Bool {
    didSet { defaults.set(finishHotKeyEnabled, forKey: "finishHotKeyEnabled") }
  }
  public var inboxID: String { didSet { defaults.set(inboxID, forKey: "inboxID") } }
  public var shortcutKey: Int { didSet { defaults.set(shortcutKey, forKey: "shortcutKey") } }
  public var shortcutModifiers: Int {
    didSet { defaults.set(shortcutModifiers, forKey: "shortcutModifiers") }
  }

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    theme = ThemeID(stored: defaults.string(forKey: "theme"))
    storedCRTIntensity = Self.boundedIntensity(
      defaults.object(forKey: "crtIntensity") as? Double ?? 0.65)
    tickerShowsTask = defaults.object(forKey: "tickerShowsTask") as? Bool ?? true
    soundEnabled = defaults.bool(forKey: "soundEnabled")
    finishHotKeyEnabled = defaults.bool(forKey: "finishHotKeyEnabled")
    inboxID = defaults.string(forKey: "inboxID") ?? ""
    shortcutKey = defaults.object(forKey: "shortcutKey") as? Int ?? 49
    shortcutModifiers = defaults.object(forKey: "shortcutModifiers") as? Int ?? 6144
  }

  private static func boundedIntensity(_ value: Double) -> Double {
    value.isFinite ? min(1, max(0, value)) : 0.65
  }
}
