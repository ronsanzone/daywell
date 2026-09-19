import Observation
import SwiftUI

public enum Theme: String, CaseIterable, Identifiable {
  case graphite, sage, plum, amber
  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .graphite: "Graphite & Taupe"
    case .sage: "Porcelain & Sage"
    case .plum: "Linen & Plum"
    case .amber: "Amber CRT · experimental"
    }
  }
  public var colorScheme: ColorScheme {
    switch self {
    case .graphite, .amber: .dark
    case .sage, .plum: .light
    }
  }
  public var colors: Palette {
    switch self {
    case .graphite:
      Palette(
        background: 0x242527, raised: 0x2D2F32, text: 0xE8E7E3, secondary: 0xAAACAE,
        accent: 0xB6A48F)
    case .sage:
      Palette(
        background: 0xF4F1E8, raised: 0xE9E8DF, text: 0x323633, secondary: 0x64685F,
        accent: 0x52654F)
    case .plum:
      Palette(
        background: 0xF7F3F5, raised: 0xEBE4EC, text: 0x392D3D, secondary: 0x6F6373,
        accent: 0x795C80)
    case .amber:
      Palette(
        background: 0x130E08, raised: 0x251A0E, text: 0xFFDBA8, secondary: 0xE0BD8C,
        accent: 0xFFBB59)
    }
  }
}

public struct Palette {
  public var background: Color
  public var raised: Color
  public var text: Color
  public var secondary: Color
  public var accent: Color
  init(background: UInt32, raised: UInt32, text: UInt32, secondary: UInt32, accent: UInt32) {
    self.background = Color(hex: background)
    self.raised = Color(hex: raised)
    self.text = Color(hex: text)
    self.secondary = Color(hex: secondary)
    self.accent = Color(hex: accent)
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 255) / 255,
      green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
  }
}

@MainActor @Observable public final class Preferences {
  @ObservationIgnored private let defaults: UserDefaults
  public var theme: Theme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
  private var storedCRTIntensity: Double
  public var crtIntensity: Double {
    get { storedCRTIntensity }
    set {
      storedCRTIntensity = Self.boundedIntensity(newValue)
      defaults.set(storedCRTIntensity, forKey: "crtIntensity")
    }
  }
  public var showCount: Bool { didSet { defaults.set(showCount, forKey: "showCount") } }
  public var inboxID: String { didSet { defaults.set(inboxID, forKey: "inboxID") } }
  public var shortcutKey: Int { didSet { defaults.set(shortcutKey, forKey: "shortcutKey") } }
  public var shortcutModifiers: Int {
    didSet { defaults.set(shortcutModifiers, forKey: "shortcutModifiers") }
  }
  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    theme = Theme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .graphite
    storedCRTIntensity = Self.boundedIntensity(
      defaults.object(forKey: "crtIntensity") as? Double ?? 0.65)
    showCount = defaults.bool(forKey: "showCount")
    inboxID = defaults.string(forKey: "inboxID") ?? ""
    shortcutKey = defaults.object(forKey: "shortcutKey") as? Int ?? 49
    shortcutModifiers = defaults.object(forKey: "shortcutModifiers") as? Int ?? 6144
  }

  private static func boundedIntensity(_ value: Double) -> Double {
    value.isFinite ? min(1, max(0, value)) : 0.65
  }
}
