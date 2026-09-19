import Metal
import SwiftUI

/// A static, non-interactive surface. Native text fields never enter a shader-filtered layer.
struct CRTSurface: View {
  @Environment(\.displayScale) private var displayScale
  @State private var image: CGImage?
  @State private var failed = false

  var body: some View {
    GeometryReader { geometry in
      let size = SIMD3(
        Double(geometry.size.width), Double(geometry.size.height), Double(displayScale))
      ZStack(alignment: .bottom) {
        if let image {
          Image(decorative: image, scale: displayScale)
            .resizable().interpolation(.none)
            .accessibilityHidden(true)
        }
        if failed {
          Text("CRT texture unavailable; amber colors remain.")
            .font(.system(size: 10)).foregroundStyle(.white)
            .padding(4).background(.black)
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .task(id: size) {
        guard size.x > 0, size.y > 0 else { return }
        do {
          let rendered = try await CRTSurfaceRenderer.shared.render(
            width: Int((size.x * size.z).rounded()),
            height: Int((size.y * size.z).rounded()), scale: size.z)
          try Task.checkCancellation()
          image = rendered
          failed = false
        } catch is CancellationError {
          return
        } catch {
          image = nil
          failed = true
        }
      }
    }
    .allowsHitTesting(false)
  }
}

/// Owns the Metal resources off the main actor. The shader runs only on surface creation/resize;
/// SwiftUI composites the resulting image, so intensity changes need no GPU readback or timer.
actor CRTSurfaceRenderer {
  static let shared = CRTSurfaceRenderer()
  private var resources:
    (device: any MTLDevice, queue: any MTLCommandQueue, pipeline: any MTLComputePipelineState)?

  enum RenderError: Error { case unavailable, failed }

  func render(width: Int, height: Int, scale: Double) throws -> CGImage {
    if resources == nil {
      guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
      else {
        throw RenderError.unavailable
      }
      // Runtime compilation keeps the Command Line Tools build usable without Xcode's metal tool.
      let library = try device.makeLibrary(source: Self.source, options: nil)
      guard let function = library.makeFunction(name: "crtSurface") else {
        throw RenderError.unavailable
      }
      resources = (device, queue, try device.makeComputePipelineState(function: function))
    }
    guard let resources else { throw RenderError.unavailable }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
    descriptor.usage = .shaderWrite
    descriptor.storageMode = .shared
    guard let texture = resources.device.makeTexture(descriptor: descriptor),
      let command = resources.queue.makeCommandBuffer(),
      let encoder = command.makeComputeCommandEncoder()
    else { throw RenderError.failed }
    encoder.setComputePipelineState(resources.pipeline)
    encoder.setTexture(texture, index: 0)
    var pixelScale = Float(scale)
    encoder.setBytes(&pixelScale, length: MemoryLayout<Float>.size, index: 0)
    let threadWidth = resources.pipeline.threadExecutionWidth
    encoder.dispatchThreads(
      MTLSize(width: width, height: height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: threadWidth, height: 1, depth: 1))
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    guard command.status == .completed else { throw command.error ?? RenderError.failed }

    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    texture.getBytes(
      &bytes, bytesPerRow: width * 4,
      from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
      let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { throw RenderError.failed }
    return image
  }

  private static let source = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void crtSurface(texture2d<float, access::write> output [[texture(0)]],
                           constant float &scale [[buffer(0)]], uint2 pixel [[thread_position_in_grid]]) {
      if (pixel.x >= output.get_width() || pixel.y >= output.get_height()) return;
      float2 size = float2(output.get_width(), output.get_height());
      float2 center = (float2(pixel) + 0.5) / size * 2.0 - 1.0;
      // Three-point phosphor rows, independent of the display's backing scale.
      float scanline = pow(0.5 + 0.5 * cos(float(pixel.y) / scale * 2.0943951), 12.0);
      uint seed = pixel.x * 1973u + pixel.y * 9277u + 89173u;
      seed = (seed ^ (seed >> 13u)) * 1274126177u;
      float grain = float(seed & 255u) / 255.0;
      float vignette = pow(dot(center, center) * 0.5, 2.0);
      // Bound attenuation even at full intensity; keep text and focus outlines readable.
      float alpha = min(0.32, 0.16 * scanline + 0.015 * grain + 0.16 * vignette);
      output.write(float4(0.0, 0.0, 0.0, alpha), pixel);
    }
    """
}
