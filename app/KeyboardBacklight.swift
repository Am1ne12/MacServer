import Cocoa
import ObjectiveC

/// Bridge to the private CoreBrightness keyboard backlight client.
///
/// This is a private Apple API. Before using it, the required selectors and
/// their Objective-C type encodings are checked; if anything changed, the
/// component refuses to run instead of calling a method with the wrong
/// signature.
@objc protocol KeyboardBrightnessClientBridge: NSObjectProtocol {
    @objc(copyKeyboardBacklightIDs) func copyKeyboardBacklightIDs() -> NSArray?
    @objc(isKeyboardBuiltIn:) func isKeyboardBuiltIn(_ id: UInt64) -> Bool
    @objc(brightnessForKeyboard:) func brightness(forKeyboard id: UInt64) -> Float
    @objc(setBrightness:forKeyboard:) func setBrightness(_ value: Float, forKeyboard id: UInt64) -> Bool
    @objc(isBacklightSuppressedOnKeyboard:) func isBacklightSuppressed(onKeyboard id: UInt64) -> Bool
    @objc(isBacklightDimmedOnKeyboard:) func isBacklightDimmed(onKeyboard id: UInt64) -> Bool
}

final class KeyboardBacklight {
    private var client: KeyboardBrightnessClientBridge?
    private var keyboardID: UInt64?
    private(set) var refusal: String?

    private static let frameworkPath = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
    private static let className = "KeyboardBrightnessClient"

    private static let requiredSelectors: [String: String] = [
        "copyKeyboardBacklightIDs": "@@:",
        "isKeyboardBuiltIn:": "B@:Q",
        "brightnessForKeyboard:": "f@:Q",
        "setBrightness:forKeyboard:": "B@:fQ"
    ]

    private static let optionalSelectors: [String: String] = [
        "isBacklightSuppressedOnKeyboard:": "B@:Q",
        "isBacklightDimmedOnKeyboard:": "B@:Q"
    ]

    var isAvailable: Bool {
        client != nil && keyboardID != nil
    }

    init() {
        load()
    }

    private func load() {
        guard dlopen(Self.frameworkPath, RTLD_LAZY) != nil else {
            refusal = "CoreBrightness.framework could not be loaded"
            return
        }

        guard let cls = NSClassFromString(Self.className) as? NSObject.Type else {
            refusal = "KeyboardBrightnessClient was not found"
            return
        }

        for (selector, expected) in Self.requiredSelectors {
            guard let method = class_getInstanceMethod(cls, NSSelectorFromString(selector)) else {
                refusal = "KeyboardBrightnessClient is missing \(selector)"
                return
            }
            guard let raw = method_getTypeEncoding(method) else {
                refusal = "KeyboardBrightnessClient has no type encoding for \(selector)"
                return
            }
            let actual = String(cString: raw).filter { !$0.isNumber }
            guard actual == expected else {
                refusal = "KeyboardBrightnessClient \(selector) has encoding \(actual), expected \(expected)"
                return
            }
        }

        for (selector, expected) in Self.optionalSelectors {
            guard let method = class_getInstanceMethod(cls, NSSelectorFromString(selector)) else {
                continue
            }
            guard let raw = method_getTypeEncoding(method) else {
                refusal = "KeyboardBrightnessClient has no type encoding for \(selector)"
                return
            }
            let actual = String(cString: raw).filter { !$0.isNumber }
            guard actual == expected else {
                refusal = "KeyboardBrightnessClient \(selector) has encoding \(actual), expected \(expected)"
                return
            }
        }

        // The private class does not declare our protocol; the selectors and
        // encodings above are what make this cast safe.
        let instance = cls.init()
        let bridge = unsafeBitCast(instance, to: (any KeyboardBrightnessClientBridge).self)

        guard let ids = bridge.copyKeyboardBacklightIDs() as? [NSNumber] else {
            refusal = "No keyboard backlight IDs"
            return
        }

        guard let id = ids.map({ $0.uint64Value }).first(where: { bridge.isKeyboardBuiltIn($0) }) else {
            refusal = "No built-in keyboard backlight"
            return
        }

        client = bridge
        keyboardID = id
    }

    func currentBrightness() -> Float? {
        guard let client, let keyboardID else { return nil }
        return client.brightness(forKeyboard: keyboardID)
    }

    func setBrightness(_ value: Float) {
        guard let client, let keyboardID else { return }
        let clamped = min(max(value, 0), 1)
        if !client.setBrightness(clamped, forKeyboard: keyboardID) {
            NSLog("MacServer: could not set keyboard backlight")
        }
    }

    func isSuppressedOrDimmed() -> Bool {
        guard let client, let keyboardID else { return false }
        if client.responds(to: NSSelectorFromString("isBacklightSuppressedOnKeyboard:")),
           client.isBacklightSuppressed(onKeyboard: keyboardID) {
            return true
        }
        if client.responds(to: NSSelectorFromString("isBacklightDimmedOnKeyboard:")),
           client.isBacklightDimmed(onKeyboard: keyboardID) {
            return true
        }
        return false
    }
}
