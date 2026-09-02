// swift-tools-version: 6.2
import PackageDescription
import Foundation

// SwiftUI's @State and @Bindable are macros, and the Command Line Tools ship SwiftUI
// without its macro plugin — so `swift build` and SourceKit both fail on every property
// wrapper unless the plugin is supplied explicitly. Borrow the dylib from any installed
// Xcode; it loads into the CLT compiler even when that Xcode's own toolchain is too old
// to run on this OS. Declaring it here rather than only in build.sh keeps the editor and
// a bare `swift build` working too.
let swiftUIMacros: [SwiftSetting] = {
    let candidates = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications"))?
        .filter { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }
        .map {
            "/Applications/\($0)/Contents/Developer/Platforms/MacOSX.platform"
                + "/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib"
        } ?? []

    guard let plugin = candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
    else { return [] }          // no Xcode: fall through and let the compiler complain
    return [.unsafeFlags(["-load-plugin-library", plugin])]
}()

let package = Package(
    name: "BudsBar",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "BudsBar",
            path: "Sources/BudsBar",
            // Everything here runs on the main thread apart from two explicit
            // dispatches, and IOBluetooth predates Sendable. Strict concurrency
            // checking buys nothing but ceremony at this size.
            swiftSettings: [.swiftLanguageMode(.v5)] + swiftUIMacros)
    ]
)
