import AppKit
import Carbon.HIToolbox

/// Global hotkey via Carbon's RegisterEventHotKey — works without Accessibility permission.
final class HotKey {
    private var ref: EventHotKeyRef?
    private let id: UInt32
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false
    private static var nextID: UInt32 = 1

    /// Returns nil if the shortcut could not be registered (e.g. taken by another app).
    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        Self.installHandlerIfNeeded()
        id = Self.nextID
        Self.nextID += 1
        let hkID = EventHotKeyID(signature: OSType(0x4D41_4F53) /* 'MAOS' */, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        Self.handlers[id] = handler
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.handlers[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async { HotKey.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

struct Shortcut: Equatable {
    let id: String
    let title: String
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let keyEquivalent: String
    let modifierMask: NSEvent.ModifierFlags

    static let presets: [Shortcut] = [
        Shortcut(id: "cmd+shift+2", title: "⇧⌘2", keyCode: UInt32(kVK_ANSI_2),
                 carbonModifiers: UInt32(cmdKey | shiftKey), keyEquivalent: "2", modifierMask: [.command, .shift]),
        Shortcut(id: "cmd+shift+4", title: "⇧⌘4  (turn off macOS's ⇧⌘4 first)", keyCode: UInt32(kVK_ANSI_4),
                 carbonModifiers: UInt32(cmdKey | shiftKey), keyEquivalent: "4", modifierMask: [.command, .shift]),
        Shortcut(id: "ctrl+shift+a", title: "⌃⇧A", keyCode: UInt32(kVK_ANSI_A),
                 carbonModifiers: UInt32(controlKey | shiftKey), keyEquivalent: "a", modifierMask: [.control, .shift]),
        Shortcut(id: "opt+shift+s", title: "⌥⇧S", keyCode: UInt32(kVK_ANSI_S),
                 carbonModifiers: UInt32(optionKey | shiftKey), keyEquivalent: "s", modifierMask: [.option, .shift]),
        Shortcut(id: "f13", title: "F13  (PrtScn on PC keyboards)", keyCode: UInt32(kVK_F13),
                 carbonModifiers: 0, keyEquivalent: String(UnicodeScalar(NSF13FunctionKey)!), modifierMask: []),
    ]

    static let customID = "custom"

    static var current: Shortcut {
        let id = UserDefaults.standard.string(forKey: "hotkey") ?? presets[0].id
        if id == customID, let c = savedCustom { return c }
        return presets.first { $0.id == id } ?? presets[0]
    }

    // MARK: - Custom shortcut

    /// The user's recorded shortcut, if any (kept even while a preset is selected).
    static var savedCustom: Shortcut? {
        guard let d = UserDefaults.standard.dictionary(forKey: "customHotkey"),
              let code = d["keyCode"] as? Int, let mods = d["modifiers"] as? Int,
              let name = d["keyName"] as? String, let equiv = d["keyEquivalent"] as? String else { return nil }
        return custom(keyCode: UInt32(code), carbonModifiers: UInt32(mods), keyName: name, keyEquivalent: equiv)
    }

    static func select(_ s: Shortcut) {
        if s.id == customID {
            UserDefaults.standard.set(["keyCode": Int(s.keyCode), "modifiers": Int(s.carbonModifiers),
                                       "keyName": s.keyName, "keyEquivalent": s.keyEquivalent], forKey: "customHotkey")
        }
        UserDefaults.standard.set(s.id, forKey: "hotkey")
    }

    /// Key name without modifiers (title minus the modifier symbols).
    var keyName: String { String(title.drop { "⌃⌥⇧⌘".contains($0) }) }

    static func custom(keyCode: UInt32, carbonModifiers mods: UInt32, keyName: String, keyEquivalent: String) -> Shortcut {
        var mask: NSEvent.ModifierFlags = []
        var symbols = ""
        if mods & UInt32(controlKey) != 0 { mask.insert(.control); symbols += "⌃" }
        if mods & UInt32(optionKey) != 0 { mask.insert(.option); symbols += "⌥" }
        if mods & UInt32(shiftKey) != 0 { mask.insert(.shift); symbols += "⇧" }
        if mods & UInt32(cmdKey) != 0 { mask.insert(.command); symbols += "⌘" }
        return Shortcut(id: customID, title: symbols + keyName, keyCode: keyCode, carbonModifiers: mods,
                        keyEquivalent: keyEquivalent, modifierMask: mask)
    }

    /// Build a shortcut from a key press. Nil when it isn't usable (no modifier on a normal key, or a lone modifier).
    static func from(event e: NSEvent) -> Shortcut? {
        let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }

        let code = Int(e.keyCode)
        if let n = functionKeys[code] {
            let equiv = String(UnicodeScalar(UInt32(NSF1FunctionKey) + UInt32(n - 1))!)
            return custom(keyCode: UInt32(code), carbonModifiers: mods, keyName: "F\(n)", keyEquivalent: equiv)
        }
        // Normal keys need ⌘, ⌥ or ⌃ so typing isn't hijacked (⇧ alone isn't enough).
        guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) else { return nil }
        if let (name, equiv) = specialKeys[code] {
            return custom(keyCode: UInt32(code), carbonModifiers: mods, keyName: name, keyEquivalent: equiv)
        }
        guard let ch = e.charactersIgnoringModifiers?.lowercased(), ch.count == 1,
              let scalar = ch.unicodeScalars.first, !CharacterSet.controlCharacters.contains(scalar) else { return nil }
        return custom(keyCode: UInt32(code), carbonModifiers: mods, keyName: ch.uppercased(), keyEquivalent: ch)
    }

    /// True for macOS's own screenshot shortcuts (⇧⌘3/4/5), which win over any app.
    var clashesWithSystemScreenshot: Bool {
        carbonModifiers == UInt32(cmdKey | shiftKey)
            && [kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5].contains(Int(keyCode))
    }

    private static let functionKeys: [Int: Int] = [
        kVK_F1: 1, kVK_F2: 2, kVK_F3: 3, kVK_F4: 4, kVK_F5: 5, kVK_F6: 6, kVK_F7: 7, kVK_F8: 8, kVK_F9: 9, kVK_F10: 10,
        kVK_F11: 11, kVK_F12: 12, kVK_F13: 13, kVK_F14: 14, kVK_F15: 15, kVK_F16: 16, kVK_F17: 17, kVK_F18: 18,
        kVK_F19: 19, kVK_F20: 20,
    ]

    private static let specialKeys: [Int: (String, String)] = [
        kVK_Space: ("Space", " "), kVK_Return: ("↩", "\r"), kVK_Tab: ("⇥", "\t"),
        kVK_Delete: ("⌫", "\u{8}"), kVK_ForwardDelete: ("⌦", "\u{7F}"),
        kVK_LeftArrow: ("←", ""), kVK_RightArrow: ("→", ""), kVK_UpArrow: ("↑", ""), kVK_DownArrow: ("↓", ""),
        kVK_Home: ("↖", ""), kVK_End: ("↘", ""), kVK_PageUp: ("⇞", ""), kVK_PageDown: ("⇟", ""),
    ]
}
