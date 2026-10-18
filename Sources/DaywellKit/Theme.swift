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

  /// The raw sRGB tokens of a theme, checked for contrast in tests.
  public struct Tokens: Sendable {
    public var background, raised, text, secondary, accent, highlight: UInt32
    public var inks: [UInt32]
  }

  public static func tokens(_ id: ThemeID) -> Tokens {
    switch id {
    case .quietNative:
      Tokens(
        background: 0x242527, raised: 0x2D2F32, text: 0xE8E7E3, secondary: 0xAAACAE,
        accent: 0xB6A48F, highlight: 0xE3D3BF, inks: [0xB6A48F])
    case .phosphor:
      Tokens(
        background: 0x130E08, raised: 0x251A0E, text: 0xFFDBA8, secondary: 0xE0BD8C,
        accent: 0xFFBB59, highlight: 0xFFF1D0, inks: [0xFFBB59])
    case .waffleCat:
      // Secondary is lifted from the terminal's #A58C82 so it reads 4.5:1 on raised rows.
      Tokens(
        background: 0x292025, raised: 0x362D30, text: 0xFFF4D8, secondary: 0xB59D93,
        accent: 0xC87D2A, highlight: 0xE4C56D, inks: [0xC87D2A])
    case .flexokiLight:
      // Flexoki 600-level inks: the 400 yellow and cyan fail 3:1 on this paper.
      Tokens(
        background: 0xFFFCF0, raised: 0xF2F0E5, text: 0x100F0F, secondary: 0x66655F,
        accent: 0x205EA6, highlight: 0x205EA6, inks: flexokiInks)
    }
  }

  public static func named(_ id: ThemeID) -> ThemeProfile {
    let tokens = tokens(id)
    var profile = ThemeProfile(
      id: id, title: "", summary: "", scheme: .dark, background: Color(hex: tokens.background),
      raised: Color(hex: tokens.raised), text: Color(hex: tokens.text),
      secondary: Color(hex: tokens.secondary), accent: Color(hex: tokens.accent),
      highlight: Color(hex: tokens.highlight), separator: Color.white.opacity(0.08),
      inks: tokens.inks.map(Color.init(hex:)), monospaced: false, ring: .circle,
      finish: .spring, token: .roundedSquare, sound: .tock, overlay: .none,
      dayClearTitle: "Day clear")
    switch id {
    case .quietNative:
      profile.title = "Quiet Native"
      profile.summary = "Refined Graphite. The default."
    case .phosphor:
      profile.title = "Phosphor"
      profile.summary = "Amber CRT, committed."
      profile.separator = Color(hex: 0xE0BD8C).opacity(0.16)
      profile.monospaced = true
      profile.ring = .square
      profile.finish = .flare
      profile.token = .bar
      profile.sound = .beep
      profile.overlay = .crt
      profile.dayClearTitle = "DAY CLEAR"
    case .waffleCat:
      profile.title = "Waffle Cat"
      profile.summary = "Your Ghostty palette, in Maple Mono."
      profile.separator = Color(hex: 0x3E3236)
      profile.monospaced = true
      profile.sound = .pat
    case .flexokiLight:
      profile.title = "Flexoki Light"
      profile.summary = "Ink on warm paper; every finish a new ink."
      profile.scheme = .light
      profile.separator = Color(hex: 0xDAD8CE)
      profile.monospaced = true
      profile.finish = .ink
      profile.token = .dot
    }
    return profile
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
  /// The one-time "sort into shelves" suggestion was answered.
  public var shelfSortOffered: Bool {
    didSet { defaults.set(shelfSortOffered, forKey: "shelfSortOffered") }
  }
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
    shelfSortOffered = defaults.bool(forKey: "shelfSortOffered")
    shortcutKey = defaults.object(forKey: "shortcutKey") as? Int ?? 49
    shortcutModifiers = defaults.object(forKey: "shortcutModifiers") as? Int ?? 6144
  }

  private static func boundedIntensity(_ value: Double) -> Double {
    value.isFinite ? min(1, max(0, value)) : 0.65
  }
}
