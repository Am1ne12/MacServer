import Cocoa

final class SystemAudio {
    struct Settings {
        let volume: Int
        let muted: Bool
    }

    func read() -> Settings? {
        guard let output = runAppleScript("get volume settings") else { return nil }

        var volume: Int?
        var muted: Bool?

        for part in output.split(separator: ",") {
            let fields = part
                .split(separator: ":", maxSplits: 1)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            guard fields.count == 2 else { continue }

            switch fields[0] {
            case "output volume":
                volume = Int(fields[1])
            case "output muted":
                muted = fields[1] == "true"
            default:
                break
            }
        }

        guard let volume, let muted else { return nil }
        return Settings(volume: volume, muted: muted)
    }

    func setMuted(_ muted: Bool) {
        _ = runAppleScript("set volume output muted \(muted ? "true" : "false")")
    }

    func restore(volume: Int, muted: Bool) {
        let script = """
        set volume output volume \(max(0, min(100, volume)))
        set volume output muted \(muted ? "true" : "false")
        """
        _ = runAppleScript(script)
    }

    private func runAppleScript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            NSLog("MacServer audio: could not run osascript: \(error.localizedDescription)")
            return nil
        }

        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8) ?? ""
            NSLog("MacServer audio: osascript failed: \(message)")
            return nil
        }

        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
