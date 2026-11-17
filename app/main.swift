import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?

    private let stateDir = "/Users/Shared/MacServer"
    private let statusPath = "/Users/Shared/MacServer/status"
    private let pausePath = "/Users/Shared/MacServer/paused"
    private let batteryPath = "/Users/Shared/MacServer/keep-awake-battery"
    private let lockPath = "/Users/Shared/MacServer/lock-now"
    private let logPath = "/var/log/macserver.log"

    private var statusMenuItem: NSMenuItem!
    private var detailMenuItem: NSMenuItem!
    private var pauseMenuItem: NSMenuItem!
    private var batteryMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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

        guard let raw = try? String(contentsOfFile: statusPath, encoding: .utf8) else {
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
        let battery = values["battery"] ?? "?"
        let timestamp = Double(values["timestamp"] ?? "0") ?? 0
        let age = Date().timeIntervalSince1970 - timestamp

        if power == "UNKNOWN" || age > 20 {
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
                    detail: "Awake on battery until 20%.",
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
        let size = NSSize(width: 22, height: 22)
        let bounds = NSRect(origin: .zero, size: size)
        let image = NSImage(size: size)

        image.lockFocus()
        color.setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            xRadius: 5,
            yRadius: 5
        ).fill()

        if let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(paletteColors: [NSColor.white])
            let configured = base.withSymbolConfiguration(config) ?? base
            configured.isTemplate = false
            configured.draw(
                in: bounds.insetBy(dx: 5, dy: 5),
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
                .font: NSFont.boldSystemFont(ofSize: 12),
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
        NSApp.terminate(nil)
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
