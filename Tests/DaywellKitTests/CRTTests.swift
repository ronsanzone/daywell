import CoreGraphics
import Foundation
import Metal
import SwiftUI
import Testing

@testable import DaywellKit

struct CRTTests {
  @MainActor @Test func intensityPersistsIncludingZeroAndIsBounded() throws {
    let name = "daywell.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let preferences = Preferences(defaults: defaults)
    #expect(preferences.crtIntensity > 0 && preferences.crtIntensity < 1)
    preferences.crtIntensity = 0.23
    #expect(Preferences(defaults: defaults).crtIntensity == 0.23)
    preferences.crtIntensity = 0
    #expect(Preferences(defaults: defaults).crtIntensity == 0)
    preferences.crtIntensity = 1.8
    #expect(preferences.crtIntensity == 1)
    defaults.set(-0.4, forKey: "crtIntensity")
    #expect(Preferences(defaults: defaults).crtIntensity == 0)
    #expect(Theme.amber.colorScheme == .dark)
    #expect(Theme.sage.colorScheme == .light)
  }

  @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "Requires a Metal GPU"))
  func metalSurfaceHasHorizontalScanlinesAndBoundedVignetteAtBothScales() async throws {
    // Transposed coordinates, wrong Retina scaling, or an opaque overlay must fail.
    for scale in [1.0, 2.0] {
      let image = try await CRTSurfaceRenderer.shared.render(
        width: Int(120 * scale), height: Int(90 * scale), scale: scale)
      let data = try #require(image.dataProvider?.data)
      let bytes = try #require(CFDataGetBytePtr(data))
      func alpha(x: Int, y: Int) -> Int {
        Int(bytes[Int(Double(y) * scale) * image.bytesPerRow + Int(Double(x) * scale) * 4 + 3])
      }
      #expect(image.width == Int(120 * scale))
      #expect(image.height == Int(90 * scale))
      #expect(alpha(x: 60, y: 45) > alpha(x: 60, y: 46) + 15)
      #expect(abs(alpha(x: 60, y: 45) - alpha(x: 61, y: 45)) < 8)
      #expect(alpha(x: 0, y: 0) > alpha(x: 60, y: 45) + 15)
      #expect(stride(from: 3, to: CFDataGetLength(data), by: 4).allSatisfy { bytes[$0] <= 90 })
    }
  }
}
