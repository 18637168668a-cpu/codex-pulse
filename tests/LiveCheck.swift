import Foundation

// Opt-in integration check: reads real quota through the local bridge, prints no values.
// Not run in CI. Start `node bridge/server.mjs` first.
@main
struct LiveCheck {
    static func main() async {
        let payload = await PulseLoader.load()
        guard payload.isLive, payload.updatedAt != nil,
              payload.fiveHourUsed != nil || payload.weeklyUsed != nil else {
            fatalError("Live native decoding failed. Check the bridge and Codex login.")
        }
        print("Live native decoding passed; account values withheld.")
    }
}
