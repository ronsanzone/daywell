import AppKit
import CoreText

/// Registers the bundled Maple Mono (SIL OFL 1.1, see Resources/Fonts/OFL.txt) for this
/// process only. Falls back to an installed copy, then to the system monospaced face.
public enum FontRegistry {
  public static let mapleMono = "Maple Mono"
  nonisolated(unsafe) private static var registered = false

  public static var mapleMonoAvailable: Bool {
    NSFontManager.shared.availableFontFamilies.contains(mapleMono)
  }

  /// Call once at launch, on the main thread.
  @MainActor public static func registerBundledFonts() {
    guard !registered else { return }
    registered = true
    guard !mapleMonoAvailable else { return }
    for directory in candidateDirectories() {
      guard
        let files = try? FileManager.default.contentsOfDirectory(
          at: directory, includingPropertiesForKeys: nil)
      else { continue }
      let fonts = files.filter { $0.pathExtension == "ttf" }
      guard !fonts.isEmpty else { continue }
      for font in fonts { CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil) }
      return
    }
  }

  private static func candidateDirectories() -> [URL] {
    var urls: [URL] = []
    if let resources = Bundle.main.resourceURL {
      urls.append(resources.appendingPathComponent("Fonts"))
    }
    if let override = ProcessInfo.processInfo.environment["DAYWELL_FONTS"] {
      urls.append(URL(fileURLWithPath: override))
    }
    // Development builds run from .build; the repository keeps the fonts in Resources.
    let source = URL(fileURLWithPath: #filePath)
    urls.append(
      source.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Fonts"))
    return urls
  }
}
