import Foundation
import AppKit

enum Theme: String, CaseIterable, Identifiable {
    case terracotta, red, lime, azurio, ink, snow
    var id: String { rawValue }
    var label: String { S.t("theme." + rawValue) }
    var color: NSColor {
        switch self {
        case .terracotta: return NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)   // #D97757
        case .red: return NSColor(red: 0.85, green: 0.24, blue: 0.16, alpha: 1)          // character sheet red
        case .lime: return NSColor(red: 0.60, green: 0.95, blue: 0.38, alpha: 1)         // #98F160
        case .azurio: return NSColor(red: 0.17, green: 0.35, blue: 1.0, alpha: 1)        // readable blue
        case .ink: return NSColor(white: 0.15, alpha: 1)
        case .snow: return NSColor(white: 0.97, alpha: 1)
        }
    }
}

enum PetSize: String, CaseIterable, Identifiable {
    case s, m, l, xl
    var id: String { rawValue }
    var fontSize: CGFloat {
        switch self { case .s: return 11; case .m: return 14; case .l: return 18; case .xl: return 24 }
    }
    /// Edge length of one pixel cell (pixel style).
    var cell: CGFloat { (fontSize * 0.6).rounded() }
    var label: String { S.t("size." + rawValue) }
}


enum OpenTarget: String, CaseIterable, Identifiable {
    case app, browser
    var id: String { rawValue }
    var label: String { S.t("open." + rawValue) }
}

enum SpriteStyle: String, CaseIterable, Identifiable {
    case pixel, ascii
    var id: String { rawValue }
    var label: String { S.t("style." + rawValue) }
}

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private init() {
        d.register(defaults: [
            "card": false, "sounds": true, "quips": true, "updateCheck": true,
            "size": PetSize.m.rawValue, "theme": Theme.terracotta.rawValue, "style": SpriteStyle.pixel.rawValue,
            "mic": true, "usage": true,
        ])
    }

    var style: SpriteStyle {
        get { SpriteStyle(rawValue: d.string(forKey: "style") ?? "") ?? .pixel }
        set { d.set(newValue.rawValue, forKey: "style") }
    }
    /// UI language; defaults to German on German systems, English elsewhere.
    var lang: Lang {
        get {
            if let raw = d.string(forKey: "lang"), let l = Lang(rawValue: raw) { return l }
            let pref = Locale.preferredLanguages.first ?? "en"
            return pref.hasPrefix("de") ? .de : .en
        }
        set { d.set(newValue.rawValue, forKey: "lang") }
    }
    var openTarget: OpenTarget {
        get { OpenTarget(rawValue: d.string(forKey: "openIn") ?? "") ?? .app }
        set { d.set(newValue.rawValue, forKey: "openIn") }
    }
    var speciesId: String {
        get { d.string(forKey: "species") ?? "" }
        set { d.set(newValue, forKey: "species") }
    }
    var hat: Hat {
        get { Hat(rawValue: d.string(forKey: "hat") ?? "") ?? .none }
        set { d.set(newValue.rawValue, forKey: "hat") }
    }
    var eyes: EyeStyle {
        get { EyeStyle(rawValue: d.string(forKey: "eyes") ?? "") ?? .dot }
        set { d.set(newValue.rawValue, forKey: "eyes") }
    }
    var lookInitialized: Bool {
        get { d.bool(forKey: "lookInitialized") }
        set { d.set(newValue, forKey: "lookInitialized") }
    }
    var theme: Theme {
        get { Theme(rawValue: d.string(forKey: "theme") ?? "") ?? .terracotta }
        set { d.set(newValue.rawValue, forKey: "theme") }
    }
    var size: PetSize {
        get { PetSize(rawValue: d.string(forKey: "size") ?? "") ?? .m }
        set { d.set(newValue.rawValue, forKey: "size") }
    }
    var card: Bool { get { d.bool(forKey: "card") } set { d.set(newValue, forKey: "card") } }
    /// Flat look: no outline, no bevel (like the original mascot art).
    var flat: Bool { get { d.bool(forKey: "flat") } set { d.set(newValue, forKey: "flat") } }
    var sounds: Bool { get { d.bool(forKey: "sounds") } set { d.set(newValue, forKey: "sounds") } }
    var quips: Bool { get { d.bool(forKey: "quips") } set { d.set(newValue, forKey: "quips") } }
    /// Check GitHub Releases for a newer version (the only network call Buddy makes).
    var updateCheck: Bool { get { d.bool(forKey: "updateCheck") } set { d.set(newValue, forKey: "updateCheck") } }
    /// Voice button under the buddy (opens Claude Quick Entry / a new chat).
    var mic: Bool { get { d.bool(forKey: "mic") } set { d.set(newValue, forKey: "mic") } }
    /// Walk along the edges of the screen (never across it).
    var wander: Bool { get { d.bool(forKey: "wander") } set { d.set(newValue, forKey: "wander") } }
    /// Show today's local Claude Code token usage under the buddy (read from
    /// ~/.claude/projects; purely local, no network). Also keeps the buddy awake while
    /// there is recent local activity, so it dozes instead of flatlining to sleep.
    var usage: Bool { get { d.bool(forKey: "usage") } set { d.set(newValue, forKey: "usage") } }

    var panelOrigin: CGPoint? {
        get {
            guard d.object(forKey: "panelX") != nil else { return nil }
            return CGPoint(x: d.double(forKey: "panelX"), y: d.double(forKey: "panelY"))
        }
        set {
            if let p = newValue { d.set(p.x, forKey: "panelX"); d.set(p.y, forKey: "panelY") }
            else { d.removeObject(forKey: "panelX"); d.removeObject(forKey: "panelY") }
        }
    }

    /// Account id from ~/.claude.json (used for the deterministic default look).
    static func accountId() -> String {
        let path = NSString(string: "~/.claude.json").expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return NSUserName() }
        if let acc = obj["oauthAccount"] as? [String: Any] {
            if let id = acc["accountUuid"] as? String { return id }
            if let mail = acc["emailAddress"] as? String { return mail }
        }
        if let id = obj["userID"] as? String { return id }
        return NSUserName()
    }

    func currentLook() -> SpriteLook {
        if !lookInitialized || speciesId.isEmpty {
            let l = LookGenerator.look(for: Settings.accountId())
            speciesId = l.species.id; hat = l.hat; eyes = l.eyes; lookInitialized = true
            return l
        }
        return SpriteLook(species: SpriteBank.species(id: speciesId), hat: hat, eyes: eyes)
    }

    /// Pixel species for the current species id (falls back to the first pixel species).
    func currentPixelSpecies() -> PixelSpecies {
        if let sp = PixelBank.all.first(where: { $0.id == speciesId }) { return sp }
        let idx = Int(LookGenerator.fnv1a(speciesId + Settings.accountId()) % UInt32(PixelBank.all.count))
        return PixelBank.all[idx]
    }

    /// Non-nil only while a bitmap species is actually selected (they live under the pixel-style
    /// species menu, so bitmap rendering never activates under the ascii style).
    func currentBitmapSpecies() -> BitmapSpecies? {
        guard style == .pixel else { return nil }
        return BitmapBank.all.first { $0.id == speciesId }
    }
}
