import AppKit
import HotKey

// A global keyboard shortcut: a key + modifiers + the display character (e.g. "L").
struct Shortcut: Equatable {
    let key: Key
    let modifiers: NSEvent.ModifierFlags
    let displayChar: String

    var displayString: String { modifiers.glyphs + displayChar }

    var keyCombo: KeyCombo { KeyCombo(key: key, modifiers: modifiers) }

    static let defaultLike = Shortcut(key: .l, modifiers: [.option], displayChar: "L")
}

extension NSEvent.ModifierFlags {
    var glyphs: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option)  { s += "⌥" }
        if contains(.shift)   { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

// MARK: -

@MainActor
final class HotkeySettings: ObservableObject {
    static let shared = HotkeySettings()

    @Published var likeShortcut: Shortcut? {
        didSet { saveLike(); register() }
    }

    var likeAction: (() -> Void)?
    private var likeHotKey: HotKey?

    private init() {
        likeShortcut = loadLike()
        register()
    }

    private func register() {
        likeHotKey = nil
        guard let s = likeShortcut else { return }
        let hk = HotKey(keyCombo: s.keyCombo)
        hk.keyDownHandler = { [weak self] in self?.likeAction?() }
        likeHotKey = hk
    }

    // MARK: - Persistence

    private enum Defaults {
        static let keyCode  = "hotkey.like.keyCode"
        static let mods     = "hotkey.like.mods"
        static let char     = "hotkey.like.char"
        static let isCustom = "hotkey.like.isCustom"
    }

    private func loadLike() -> Shortcut? {
        let d = UserDefaults.standard
        guard d.bool(forKey: Defaults.isCustom) else { return .defaultLike }
        guard d.object(forKey: Defaults.keyCode) != nil else { return nil }
        let kc   = UInt32(d.integer(forKey: Defaults.keyCode))
        let mods = NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: Defaults.mods)))
        let char = d.string(forKey: Defaults.char) ?? "?"
        guard let key = Key(carbonKeyCode: kc) else { return .defaultLike }
        return Shortcut(key: key, modifiers: mods, displayChar: char)
    }

    private func saveLike() {
        let d = UserDefaults.standard
        d.set(true, forKey: Defaults.isCustom)
        if let s = likeShortcut {
            d.set(Int(s.key.carbonKeyCode), forKey: Defaults.keyCode)
            d.set(Int(s.modifiers.rawValue), forKey: Defaults.mods)
            d.set(s.displayChar, forKey: Defaults.char)
        } else {
            d.removeObject(forKey: Defaults.keyCode)
            d.removeObject(forKey: Defaults.mods)
            d.removeObject(forKey: Defaults.char)
        }
    }
}
