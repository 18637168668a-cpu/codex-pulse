import AppKit
import SwiftUI

@main
struct SetupPreview {
    @MainActor static func main() throws {
        precondition(QuotaMeterColor.components(0) == [0.12, 0.75, 0.32])
        precondition(QuotaMeterColor.components(50) == [1.0, 0.80, 0.10])
        let red = QuotaMeterColor.components(100)!
        precondition(abs(red[0] - 0.95) < 0.00001 && abs(red[1] - 0.18) < 0.00001)
        precondition(QuotaMeterColor.components(nil) == nil && QuotaMeterColor.components(.nan) == nil)
        precondition(QuotaMeterColor.components(-10) == QuotaMeterColor.components(0))
        precondition(QuotaMeterColor.components(120) == QuotaMeterColor.components(100))
        let fixture = Data(#"{"rateLimits":{"primary":{"usedPercent":0,"windowDurationMins":300},"secondary":{"usedPercent":100,"windowDurationMins":10080}},"stale":false}"#.utf8)
        let meter = try QuotaMeterState.decode(fixture)
        precondition(meter.fiveHour == 0 && meter.weekly == 100 && !meter.stale)
        let missing = try QuotaMeterState.decode(Data(#"{"rateLimits":{"primary":{"usedPercent":30,"windowDurationMins":60}},"stale":true}"#.utf8))
        precondition(missing.fiveHour == nil && missing.weekly == nil && missing.stale)
        print("Menu CP color boundaries and quota mapping passed")
        let renderer = ImageRenderer(content: ContentView().frame(width: 570, height: 510).environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Setup preview rendering failed")
        }
        let file = ProcessInfo.processInfo.environment["PULSE_SETUP_PREVIEW"] ?? "/tmp/codex-pulse-setup.png"
        try data.write(to: URL(fileURLWithPath: file))
        print("Setup preview rendered")
    }
}
