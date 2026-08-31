import AppKit
import SwiftUI

@main
struct SetupPreview {
    @MainActor static func main() throws {
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
