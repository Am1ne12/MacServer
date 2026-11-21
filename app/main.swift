import Cocoa
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?

    private let stateDir = "/Users/Shared/MacServer"
    private let statusPath = "/Users/Shared/MacServer/status"
    private let pausePath = "/Users/Shared/MacServer/paused"
    private let batteryPath = "/Users/Shared/MacServer/keep-awake-battery"
    private let lockPath = "/Users/Shared/MacServer/lock-now"
    private let compactPath = "/Users/Shared/MacServer/compact"
    private let lidStatePath = "/Users/Shared/MacServer/lid-state.json"
    private let appLogPath = "/Users/Shared/MacServer/app.log"
    private let logPath = "/var/log/macserver.log"

    private let keyboardBacklight = KeyboardBacklight()
    private let systemAudio = SystemAudio()
    private var lidActionsApplied = false
    private var savedKeyboardBrightness: Float?
    private var savedAudioVolume: Int?
    private var savedAudioMuted: Bool?
    private var lastKeyboardSample: Float?

    private var statusMenuItem: NSMenuItem!
    private var detailMenuItem: NSMenuItem!
    private var pauseMenuItem: NSMenuItem!
    private var batteryMenuItem: NSMenuItem!
    private var compactMenuItem: NSMenuItem!
    private var lidKeyboardItem: NSMenuItem!
    private var lidAudioItem: NSMenuItem!

    private struct LidState: Codable {
        var applied: Bool
        var keyboard: Float?
        var audioVolume: Int?
        var audioMuted: Bool?
        var timestamp: Date
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        loadLidState()
        setupMenu()
        refresh()

        timer = Timer.scheduledTimer(
            timeInterval: 2.0,
            target: self,
            selector: #selector(refresh),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer!, forMode: .common)

        enforceSingleInstance()
    }

    private func enforceSingleInstance() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let bundleID = Bundle.main.bundleIdentifier ?? "com.am1ne.macserver"
            let pids = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .map { $0.processIdentifier }

            guard pids.count > 1, let firstPID = pids.min() else { return }
            if firstPID != ProcessInfo.processInfo.processIdentifier {
                NSApp.terminate(nil)
            }
        }
    }

    private func setupMenu() {
        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "MacServer", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        detailMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        detailMenuItem.isEnabled = false
        menu.addItem(detailMenuItem)

        menu.addItem(NSMenuItem.separator())

        pauseMenuItem = NSMenuItem(
            title: "Pause Server",
            action: #selector(togglePause),
            keyEquivalent: ""
        )
        pauseMenuItem.target = self
        menu.addItem(pauseMenuItem)

        batteryMenuItem = NSMenuItem(
            title: "Stay Awake on Battery (max 20%)",
            action: #selector(toggleBattery),
            keyEquivalent: ""
        )
        batteryMenuItem.target = self
        batteryMenuItem.toolTip = "Keeps the Mac awake on battery until 20%. It will drain the battery and get warm."
        menu.addItem(batteryMenuItem)

        compactMenuItem = NSMenuItem(
            title: "Compact Menu Bar Icon",
            action: #selector(toggleCompact),
            keyEquivalent: ""
        )
        compactMenuItem.target = self
        menu.addItem(compactMenuItem)

        lidKeyboardItem = NSMenuItem(
            title: "Turn Off Keyboard Backlight",
            action: #selector(toggleLidKeyboard),
            keyEquivalent: ""
        )
        lidKeyboardItem.target = self
        lidKeyboardItem.state = (keyboardBacklight.isAvailable && boolDefaultTrue("LidTurnOffKeyboard")) ? .on : .off
        lidKeyboardItem.isEnabled = keyboardBacklight.isAvailable
        if !keyboardBacklight.isAvailable {
            lidKeyboardItem.toolTip = "Keyboard backlight control is unavailable on this macOS."
        }

        lidAudioItem = NSMenuItem(
            title: "Mute Audio",
            action: #selector(toggleLidAudio),
            keyEquivalent: ""
        )
        lidAudioItem.target = self
        lidAudioItem.state = boolDefaultTrue("LidMuteAudio") ? .on : .off

        let lidMenu = NSMenu()
        lidMenu.addItem(lidKeyboardItem)
        lidMenu.addItem(lidAudioItem)

        let lidRootItem = NSMenuItem(title: "Lid Actions", action: nil, keyEquivalent: "")
        lidRootItem.submenu = lidMenu
        menu.addItem(lidRootItem)

        menu.addItem(NSMenuItem.separator())

        let lockItem = NSMenuItem(
            title: "Lock Screen Now",
            action: #selector(lockScreen),
            keyEquivalent: "l"
        )
        lockItem.target = self
        menu.addItem(lockItem)

        let logItem = NSMenuItem(
            title: "Open Log",
            action: #selector(openLog),
            keyEquivalent: ""
        )
        logItem.target = self
        menu.addItem(logItem)

        let uninstallItem = NSMenuItem(
            title: "Uninstall MacServer…",
            action: #selector(uninstall),
            keyEquivalent: ""
        )
        uninstallItem.target = self
        menu.addItem(uninstallItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Icon (service keeps running)",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleProportionallyDown
        statusItem.isVisible = true
    }

    @objc private func refresh() {
        let pausedFlag = FileManager.default.fileExists(atPath: pausePath)
        let batteryFlag = FileManager.default.fileExists(atPath: batteryPath)
        batteryMenuItem.state = batteryFlag ? .on : .off
        compactMenuItem.state = FileManager.default.fileExists(atPath: compactPath) ? .on : .off
        lidKeyboardItem.state = (keyboardBacklight.isAvailable && boolDefaultTrue("LidTurnOffKeyboard")) ? .on : .off
        lidKeyboardItem.isEnabled = keyboardBacklight.isAvailable
        lidAudioItem.state = boolDefaultTrue("LidMuteAudio") ? .on : .off

        guard let raw = try? String(contentsOfFile: statusPath, encoding: .utf8) else {
            restoreLidActionsIfNeeded()
            pauseMenuItem.isHidden = true
            applyState(
                icon: "exclamationmark",
                color: .systemRed,
                title: "Service Stopped",
                detail: "The MacServer service is not responding.",
                paused: pausedFlag
            )
            return
        }

        var values: [String: String] = [:]
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                values[parts[0]] = parts[1]
            }
        }

        let power = values["power"] ?? "UNKNOWN"
        let sleepDisabled = values["sleep_disabled"] == "1"
        let pausedStatus = values["paused"] == "1"
        let batteryModeStatus = values["keep_awake_battery"] == "1"
        let thermal = values["thermal"] == "1"
        let lowPower = values["low_power"] == "1"
        let battery = values["battery"] ?? "?"
        let lidClosed = values["lid"] == "closed"
        let timestamp = Double(values["timestamp"] ?? "0") ?? 0
        let age = Date().timeIntervalSince1970 - timestamp

        if power == "UNKNOWN" || age > 20 {
            restoreLidActionsIfNeeded()
            pauseMenuItem.isHidden = true
            applyState(
                icon: "exclamationmark",
                color: .systemRed,
                title: "Service Stopped",
                detail: "The MacServer service is not responding.",
                paused: pausedFlag
            )
            return
        }

        let serverActive = sleepDisabled && (
            power == "AC" ||
            (power == "BATTERY" && (batteryModeStatus || batteryFlag))
        )
        pauseMenuItem.isHidden = !(serverActive || pausedStatus || pausedFlag)

        let externalDisplay = hasExternalDisplay()
        if !lidClosed && !externalDisplay && serverActive && keyboardBacklight.isAvailable && !keyboardBacklight.isSuppressedOrDimmed() && userIsActive() {
            if let value = keyboardBacklight.currentBrightness() {
                lastKeyboardSample = value
            }
        }
        syncLidActions(lidClosed: lidClosed, serverActive: serverActive, externalDisplay: externalDisplay)

        if thermal {
            pauseMenuItem.isHidden = true
            applyState(
                icon: "exclamationmark",
                color: .systemRed,
                title: "Thermal Protection",
                detail: "Sleep was re-enabled because the Mac is too hot.",
                paused: false
            )
            return
        }

        if pausedStatus || pausedFlag {
            applyState(
                icon: "pause.fill",
                color: .systemOrange,
                title: "Paused",
                detail: "Sleep behaves normally.",
                paused: true
            )
        } else if power == "AC" {
            if sleepDisabled {
                applyState(
                    icon: "bolt.fill",
                    color: .systemGreen,
                    title: "Active — AC Power",
                    detail: "The Mac stays awake, lid open or closed.",
                    paused: false
                )
            } else {
                applyState(
                    icon: "exclamationmark",
                    color: .systemRed,
                    title: "Error — AC Power",
                    detail: "The service could not disable sleep.",
                    paused: false
                )
            }
        } else if power == "BATTERY" {
            if sleepDisabled && (batteryModeStatus || batteryFlag) {
                applyState(
                    icon: "bolt.fill",
                    color: .systemOrange,
                    title: "Server — Battery \(battery)%",
                    detail: lowPower
                        ? "Awake on battery until 20%. Low Power Mode is on."
                        : "Awake on battery until 20%.",
                    paused: false
                )
            } else if !sleepDisabled {
                applyState(
                    icon: "pause.fill",
                    color: .systemOrange,
                    title: "Normal — Battery \(battery)%",
                    detail: "The Mac is not in server mode.",
                    paused: true
                )
            } else {
                applyState(
                    icon: "exclamationmark",
                    color: .systemRed,
                    title: "Error — Battery",
                    detail: "Sleep is still disabled on battery.",
                    paused: false
                )
            }
        } else {
            applyState(
                icon: "exclamationmark",
                color: .systemRed,
                title: "Unknown State",
                detail: "Power source not recognized.",
                paused: pausedFlag
            )
        }
    }

    private func applyState(icon: String, color: NSColor, title: String, detail: String, paused: Bool, visible: Bool = true) {
        statusItem.button?.image = makeStatusImage(color: color, symbol: icon)
        statusItem.button?.contentTintColor = nil
        statusItem.button?.toolTip = "MacServer — \(title)"
        statusMenuItem.title = "MacServer — \(title)"
        detailMenuItem.title = detail
        pauseMenuItem.title = paused ? "Resume Server" : "Pause Server"
        statusItem.isVisible = visible
    }

    private func makeStatusImage(color: NSColor, symbol: String) -> NSImage {
        let compact = FileManager.default.fileExists(atPath: compactPath)
        let side: CGFloat = compact ? 16 : 22
        let size = NSSize(width: side, height: side)
        let bounds = NSRect(origin: .zero, size: size)
        let backgroundInset: CGFloat = compact ? 0.5 : 1
        let cornerRadius: CGFloat = compact ? 4 : 5
        let symbolInset: CGFloat = compact ? 3.5 : 5
        let fontSize: CGFloat = compact ? 9 : 12
        let image = NSImage(size: size)

        image.lockFocus()
        color.setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: backgroundInset, dy: backgroundInset),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        ).fill()

        if let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(paletteColors: [NSColor.white])
            let configured = base.withSymbolConfiguration(config) ?? base
            configured.isTemplate = false
            configured.draw(
                in: bounds.insetBy(dx: symbolInset, dy: symbolInset),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
        } else {
            let fallback: String
            switch symbol {
            case "bolt.fill": fallback = "S"
            case "pause.fill": fallback = "II"
            case "exclamationmark": fallback = "!"
            default: fallback = "•"
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: NSColor.white
            ]
            let text = NSAttributedString(string: fallback, attributes: attributes)
            let textSize = text.size()
            text.draw(at: NSPoint(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2
            ))
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    @objc private func toggleCompact() {
        let enabled = FileManager.default.fileExists(atPath: compactPath)
        if enabled {
            try? FileManager.default.removeItem(atPath: compactPath)
        } else {
            ensureStateDir()
            if !FileManager.default.createFile(atPath: compactPath, contents: Data()) {
                showError("Could not enable the compact menu bar icon.")
            }
        }
        refresh()
    }

    @objc private func togglePause() {
        let paused = FileManager.default.fileExists(atPath: pausePath)
        if paused {
            try? FileManager.default.removeItem(atPath: pausePath)
        } else {
            ensureStateDir()
            if !FileManager.default.createFile(atPath: pausePath, contents: Data()) {
                showError("Could not pause MacServer.")
            }
        }
        refresh()
    }

    @objc private func toggleLidKeyboard() {
        let key = "LidTurnOffKeyboard"
        let newValue = !boolDefaultTrue(key)
        UserDefaults.standard.set(newValue, forKey: key)
        lidKeyboardItem.state = newValue ? .on : .off
    }

    @objc private func toggleLidAudio() {
        let key = "LidMuteAudio"
        let newValue = !boolDefaultTrue(key)
        UserDefaults.standard.set(newValue, forKey: key)
        lidAudioItem.state = newValue ? .on : .off
    }

    private func boolDefaultTrue(_ key: String) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func syncLidActions(lidClosed: Bool, serverActive: Bool, externalDisplay: Bool) {
        let shouldApply = lidClosed && serverActive && !externalDisplay
        if shouldApply && !lidActionsApplied {
            applyLidActions()
        } else if !shouldApply && lidActionsApplied {
            restoreLidActions()
        }
    }

    private func applyLidActions() {
        let turnOffKeyboard = keyboardBacklight.isAvailable && boolDefaultTrue("LidTurnOffKeyboard")
        let muteAudio = boolDefaultTrue("LidMuteAudio")

        var keyboardValue: Float?
        if turnOffKeyboard {
            keyboardValue = lastKeyboardSample
            if keyboardValue == nil && !keyboardBacklight.isSuppressedOrDimmed() {
                keyboardValue = keyboardBacklight.currentBrightness()
            }
            if keyboardValue == nil {
                appLog("lid: no trusted keyboard brightness; leaving keyboard alone")
            }
        }

        var audioSettings: SystemAudio.Settings?
        if muteAudio {
            audioSettings = systemAudio.read()
            if audioSettings == nil {
                appLog("lid: no audio settings; leaving audio alone")
            }
        }

        let state = LidState(
            applied: true,
            keyboard: keyboardValue,
            audioVolume: audioSettings?.volume,
            audioMuted: audioSettings?.muted,
            timestamp: Date()
        )
        saveLidState(state)
        lidActionsApplied = true
        savedKeyboardBrightness = keyboardValue
        savedAudioVolume = audioSettings?.volume
        savedAudioMuted = audioSettings?.muted

        if let keyboardValue {
            keyboardBacklight.setBrightness(0)
            appLog("lid: keyboard backlight off (saved \(keyboardValue))")
        }
        if audioSettings != nil {
            systemAudio.setMuted(true)
            appLog("lid: audio muted")
        }

        runPmsetDisplaySleep()
        appLog("lid: applied")
    }

    private func restoreLidActions() {
        guard lidActionsApplied else { return }

        if let savedKeyboardBrightness, keyboardBacklight.isAvailable {
            keyboardBacklight.setBrightness(savedKeyboardBrightness)
            appLog("lid: keyboard backlight restored to \(savedKeyboardBrightness)")
        }
        if let savedAudioVolume, let savedAudioMuted {
            systemAudio.restore(volume: savedAudioVolume, muted: savedAudioMuted)
            appLog("lid: audio restored (volume \(savedAudioVolume), muted \(savedAudioMuted))")
        }

        lidActionsApplied = false
        savedKeyboardBrightness = nil
        savedAudioVolume = nil
        savedAudioMuted = nil
        removeLidState()
        appLog("lid: restored")
    }

    private func restoreLidActionsIfNeeded() {
        if lidActionsApplied {
            restoreLidActions()
        }
    }

    private func loadLidState() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: lidStatePath)),
              let state = try? JSONDecoder().decode(LidState.self, from: data),
              state.applied else {
            return
        }
        lidActionsApplied = true
        savedKeyboardBrightness = state.keyboard
        savedAudioVolume = state.audioVolume
        savedAudioMuted = state.audioMuted
        appLog("lid: loaded pending state")
    }

    private func saveLidState(_ state: LidState) {
        ensureStateDir()
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: URL(fileURLWithPath: lidStatePath), options: .atomic)
    }

    private func removeLidState() {
        try? FileManager.default.removeItem(atPath: lidStatePath)
    }

    private func hasExternalDisplay() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }

    private func userIsActive() -> Bool {
        let anyInput = CGEventType(rawValue: UInt32.max)!
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput) < 30
    }

    private func runPmsetDisplaySleep() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                appLog("lid: pmset displaysleepnow failed")
            }
        } catch {
            appLog("lid: could not run pmset: \(error.localizedDescription)")
        }
    }

    @objc private func toggleBattery() {
        let enabled = FileManager.default.fileExists(atPath: batteryPath)
        if enabled {
            try? FileManager.default.removeItem(atPath: batteryPath)
            refresh()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Stay awake on battery?"
        alert.informativeText = "The Mac will stay awake until 20% battery, even with the lid closed. It will drain the battery and get warm. Do not put it in a bag."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        ensureStateDir()
        if !FileManager.default.createFile(atPath: batteryPath, contents: Data()) {
            showError("Could not enable battery mode.")
        }
        refresh()
    }

    @objc private func lockScreen() {
        ensureStateDir()
        if !FileManager.default.createFile(atPath: lockPath, contents: Data()) {
            showError("Could not request screen lock.")
        }
    }

    @objc private func openLog() {
        if !FileManager.default.fileExists(atPath: logPath) {
            showError("The log is empty for now.")
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }

    @objc private func uninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall MacServer?"
        alert.informativeText = "The service will be stopped, normal sleep restored, and the icon removed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        restoreLidActionsIfNeeded()

        guard FileManager.default.fileExists(atPath: "/usr/local/libexec/macserver-uninstall") else {
            showError("The uninstall script is missing. MacServer may not be installed correctly.")
            return
        }

        let source = "do shell script \"/usr/local/libexec/macserver-uninstall\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else {
            showError("Could not start the uninstall.")
            return
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if error != nil {
            showError("The uninstall was cancelled or failed.")
        } else {
            NSApp.terminate(nil)
        }
    }

    @objc private func quit() {
        restoreLidActionsIfNeeded()
        NSApp.terminate(nil)
    }

    private func appLog(_ message: String) {
        NSLog("%@", "MacServer \(message)")
        ensureStateDir()

        if let attributes = try? FileManager.default.attributesOfItem(atPath: appLogPath),
           let size = attributes[.size] as? NSNumber,
           size.intValue > 1_048_576 {
            try? FileManager.default.removeItem(atPath: appLogPath)
        }

        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: appLogPath)) {
            defer { try? handle.close() }
            do {
                _ = try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // Logging must never affect the lid actions.
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: appLogPath), options: .atomic)
        }
    }

    private func ensureStateDir() {
        try? FileManager.default.createDirectory(
            atPath: stateDir,
            withIntermediateDirectories: true
        )
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "MacServer"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
