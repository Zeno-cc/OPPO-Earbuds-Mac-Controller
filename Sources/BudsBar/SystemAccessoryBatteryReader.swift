import Foundation

/// Extracts the aggregate percentage that macOS publishes for a named Bluetooth accessory.
/// `pmset -g accps` is intentionally treated as an aggregate source: it does not identify
/// left and right earbuds independently.
enum SystemAccessoryBatteryParser {
    static func percentage(in output: String, matching deviceName: String) -> Int? {
        let wanted = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }

        for rawLine in output.split(whereSeparator: \Character.isNewline) {
            let line = String(rawLine)
            guard let idMarker = line.range(of: " (id=") else { continue }

            var entryName = String(line[..<idMarker.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if entryName.first == "-" {
                entryName.removeFirst()
                entryName = entryName.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard entryName.caseInsensitiveCompare(wanted) == .orderedSame,
                  let idEnd = line[idMarker.upperBound...].firstIndex(of: ")"),
                  let percent = line[idEnd...].firstIndex(of: "%")
            else { continue }

            let status = line[line.index(after: idEnd)..<percent]
            let digits = status.filter(\.isNumber)
            guard let value = Int(digits), (1...100).contains(value) else { return nil }
            return value
        }
        return nil
    }
}

/// Reads macOS's current aggregate accessory battery in a fresh process.
///
/// IOBluetooth can retain zero-valued battery fields in the app process after the Bluetooth
/// radio is toggled. `pmset` asks the system service from a new process, avoiding that stale
/// wrapper while preserving the source's real limitation: one headset percentage only.
enum SystemAccessoryBatteryReader {
    static func read(deviceName: String) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "accps"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8)
        else { return nil }

        return SystemAccessoryBatteryParser.percentage(in: output, matching: deviceName)
    }
}
