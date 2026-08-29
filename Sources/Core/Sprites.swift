import Foundation

// MARK: - Species (5 rows × 12 cols, 3 idle frames, `@` = eye slot)

struct Species: Identifiable, Equatable {
    let id: String
    let name: String
    let frames: [[String]]   // 3 frames × 5 rows

    static func == (a: Species, b: Species) -> Bool { a.id == b.id }
}

enum SpriteBank {
    static let cols = 12
    static let rows = 5

    static let all: [Species] = [
        Species(id: "duck", name: "Ente", frames: [
            ["            ",
             "    .-.     ",
             "   ( @ )>   ",
             "  _(   )_   ",
             "   `---´    "],
            ["            ",
             "    .-.     ",
             "   ( @ )>   ",
             "  ~(   )~   ",
             "   `---´    "],
            ["            ",
             "    .-.     ",
             "   ( @ )=   ",
             "  _(   )_   ",
             "   `---´    "],
        ]),
        Species(id: "cat", name: "Katze", frames: [
            ["            ",
             "   /\\_/\\    ",
             "  ( @ . @ ) ",
             "  (   ~   ) ",
             "   `-----´  "],
            ["            ",
             "   /\\_/\\    ",
             "  ( @ . @ ) ",
             "  (   ~   )/",
             "   `-----´  "],
            ["            ",
             "   /\\_/\\    ",
             "  ( @ . @ ) ",
             "  (  ~~   ) ",
             "   `-----´  "],
        ]),
        Species(id: "blob", name: "Blob", frames: [
            ["            ",
             "    .--.    ",
             "   ( @ @ )  ",
             "   (  __ )  ",
             "    `--´    "],
            ["            ",
             "   .----.   ",
             "  ( @  @ )  ",
             "  (  __  )  ",
             "   `----´   "],
            ["    .--.    ",
             "   ( @ @ )  ",
             "   (    )   ",
             "   (  __ )  ",
             "    `--´    "],
        ]),
        Species(id: "ghost", name: "Geist", frames: [
            ["            ",
             "    .--.    ",
             "   ( @ @ )  ",
             "  /|  o  |\\ ",
             "   `^^^^´   "],
            ["            ",
             "    .--.    ",
             "   ( @ @ )  ",
             "   |  o  |  ",
             "  /`^^^^´\\  "],
            ["    .--.    ",
             "   ( @ @ )  ",
             "  /|  o  |\\ ",
             "   `^^^^´   ",
             "            "],
        ]),
        Species(id: "robot", name: "Roboter", frames: [
            ["     _      ",
             "  .-[_]-.   ",
             "  |@   @|   ",
             "  | === |   ",
             "  `-|__|-´  "],
            ["     *      ",
             "  .-[_]-.   ",
             "  |@   @|   ",
             "  | === |   ",
             "  `-|__|-´  "],
            ["     _      ",
             "  .-[_]-.   ",
             "  |@   @|   ",
             "  | ~~~ |   ",
             "  `-|__|-´  "],
        ]),
        Species(id: "octopus", name: "Oktopus", frames: [
            ["            ",
             "    .--.    ",
             "   ( @ @ )  ",
             "   (    )   ",
             "  /\\/\\/\\/\\  "],
            ["            ",
             "    .--.    ",
             "   ( @ @ )  ",
             "   (    )   ",
             "  \\/\\/\\/\\/  "],
            ["            ",
             "    .--.    ",
             "   ( @ @ )  ",
             "   ( ~~ )   ",
             "  /\\/\\/\\/\\  "],
        ]),
        Species(id: "dragon", name: "Drache", frames: [
            ["            ",
             "   ,^-^,    ",
             "  <(@ @)>   ",
             "   ( ww )~  ",
             "   `-''-´   "],
            ["            ",
             "   ,^-^,    ",
             "  <(@ @)>   ",
             "   ( ww )~~ ",
             "   `-''-´   "],
            ["            ",
             "   ,^-^,    ",
             "  <(@ @)>=  ",
             "   ( ww )~  ",
             "   `-''-´   "],
        ]),
        Species(id: "penguin", name: "Pinguin", frames: [
            ["            ",
             "    .--.    ",
             "   (@ v @)  ",
             "   /(  )\\   ",
             "   `-~~-´   "],
            ["            ",
             "    .--.    ",
             "   (@ v @)  ",
             "   \\(  )/   ",
             "   `-~~-´   "],
            ["            ",
             "    .--.    ",
             "   (@ v @)  ",
             "   /(  )\\   ",
             "    `-~~-´  "],
        ]),
        Species(id: "owl", name: "Eule", frames: [
            ["            ",
             "   ,_ _,    ",
             "  ((@)(@))  ",
             "  (( ^ ))   ",
             "   `-''-´   "],
            ["            ",
             "   ,_ _,    ",
             "  ((@)(@))  ",
             "  ((  ^ ))  ",
             "   `-''-´   "],
            ["            ",
             "   ,_ _,    ",
             "  ((@)(@))  ",
             "  ((   ))   ",
             "   `-''-´   "],
        ]),
        Species(id: "axolotl", name: "Axolotl", frames: [
            ["            ",
             " }( .--. ){ ",
             "  }( @ @ ){ ",
             "   (  w  )  ",
             "   `----´~  "],
            ["            ",
             " {( .--. )} ",
             "  {( @ @ )} ",
             "   (  w  )  ",
             "   `----´~  "],
            ["            ",
             " }( .--. ){ ",
             "  }( @ @ ){ ",
             "   (  w  )  ",
             "   `----´ ~ "],
        ]),
        Species(id: "capybara", name: "Capybara", frames: [
            ["            ",
             "   .-----.  ",
             "  ( @   @ ) ",
             "  (  .-.  ) ",
             "   `-`-´-´  "],
            ["            ",
             "   .-----.  ",
             "  ( @   @ ) ",
             "  (  .o.  ) ",
             "   `-`-´-´  "],
            ["     (o)    ",
             "   .-----.  ",
             "  ( @   @ ) ",
             "  (  .-.  ) ",
             "   `-`-´-´  "],
        ]),
        Species(id: "mushroom", name: "Pilz", frames: [
            ["   .-----.  ",
             "  (  o  o ) ",
             "   `-----´  ",
             "    |@ @|   ",
             "    `---´   "],
            ["   .-----.  ",
             "  ( o  o  ) ",
             "   `-----´  ",
             "    |@ @|   ",
             "    `---´   "],
            ["   .-----.  ",
             "  (  o  o ) ",
             "   `-----´  ",
             "   |@   @|  ",
             "   `-----´  "],
        ]),
        Species(id: "cactus", name: "Kaktus", frames: [
            ["     .*.    ",
             "  n |@ @| n ",
             "  |_|   |_| ",
             "    | ~ |   ",
             "   [_____]  "],
            ["     .-.    ",
             "  n |@ @| n ",
             "  |_|   |_| ",
             "    | ~ |   ",
             "   [_____]  "],
            ["     .*.    ",
             "  n |@ @| n ",
             "  |_|   |_| ",
             "    | v |   ",
             "   [_____]  "],
        ]),
        Species(id: "snail", name: "Schnecke", frames: [
            ["            ",
             "  @  @ .--. ",
             "   \\/  ( o )",
             "    |__`--´ ",
             "   ~~~~~~~  "],
            ["            ",
             "  @  @ .--. ",
             "   \\/  ( o )",
             "    |__`--´ ",
             "  ~~~~~~~   "],
            ["            ",
             " @   @ .--. ",
             "  \\ /  ( o )",
             "    |__`--´ ",
             "   ~~~~~~~  "],
        ]),
        Species(id: "turtle", name: "Schildkröte", frames: [
            ["            ",
             "    _.--._  ",
             " (@)(=====) ",
             "   `-|-|-´  ",
             "            "],
            ["            ",
             "    _.--._  ",
             " (@)(=====) ",
             "   `|---|´  ",
             "            "],
            ["            ",
             "    _.--._  ",
             " (@)(#####) ",
             "   `-|-|-´  ",
             "            "],
        ]),
        Species(id: "rabbit", name: "Hase", frames: [
            ["   (\\ /)    ",
             "   ( @ @)   ",
             "  c(  ~ )   ",
             "   (    )   ",
             "   `-oo-´   "],
            ["   (\\ //    ",
             "   ( @ @)   ",
             "  c(  ~ )   ",
             "   (    )   ",
             "   `-oo-´   "],
            ["   (\\ /)    ",
             "   ( @ @)   ",
             "   (  ~ )   ",
             "   (    )   ",
             "   `-oo-´   "],
        ]),
        Species(id: "goose", name: "Gans", frames: [
            ["     _      ",
             "    (@)=    ",
             "     |      ",
             "   _/  \\_   ",
             "   `----´   "],
            ["     _      ",
             "    (@)-    ",
             "     |      ",
             "   _/  \\_   ",
             "   `----´   "],
            ["    _       ",
             "   (@)=     ",
             "    /       ",
             "   _/  \\_   ",
             "   `----´   "],
        ]),
        Species(id: "chonk", name: "Chonk", frames: [
            ["            ",
             "  /\\_____/\\ ",
             " (  @   @  )",
             " (    ~    )",
             "  `-------´ "],
            ["            ",
             "  /\\_____/\\ ",
             " (  @   @  )",
             " (   ~~    )",
             "  `-------´ "],
            ["            ",
             "  /\\_____/\\ ",
             " (  @   @  )",
             " (    ~    )",
             "  `-------´~"],
        ]),
    ]

    static func species(id: String) -> Species {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - Eyes & hats

enum EyeStyle: String, CaseIterable, Identifiable {
    case dot, wide, sleepy, sparkle, happy
    var id: String { rawValue }
    var glyph: Character {
        switch self {
        case .dot: return "\u{00B7}"   // ·
        case .wide: return "O"
        case .sleepy: return "-"
        case .sparkle: return "*"
        case .happy: return "^"
        }
    }
    var label: String {
        switch self {
        case .dot: return "Punkt"
        case .wide: return "Groß"
        case .sleepy: return "Müde"
        case .sparkle: return "Funkeln"
        case .happy: return "Happy"
        }
    }
}

enum Hat: String, CaseIterable, Identifiable {
    case none, tophat, cap, crown, beanie, party, halo, wizard, bow
    var id: String { rawValue }
    var art: String {
        switch self {
        case .none: return ""
        case .tophat: return "[___]"
        case .cap: return ".-==-"
        case .crown: return "wWw"
        case .beanie: return "(=)"
        case .party: return "/^\\"
        case .halo: return "( )"
        case .wizard: return "/*\\"
        case .bow: return "><"
        }
    }
    var label: String {
        switch self {
        case .none: return "Kein Hut"
        case .tophat: return "Zylinder"
        case .cap: return "Cap"
        case .crown: return "Krone"
        case .beanie: return "Beanie"
        case .party: return "Partyhut"
        case .halo: return "Heiligenschein"
        case .wizard: return "Zauberhut"
        case .bow: return "Schleife"
        }
    }
}

// MARK: - Sprite composer

struct SpriteLook {
    var species: Species
    var hat: Hat
    var eyes: EyeStyle
}

enum SpriteComposer {
    /// Renders one frame: applies eye glyph (or an override) and the hat overlay on row 0.
    static func render(look: SpriteLook, frame: Int, eyeOverride: Character? = nil) -> [String] {
        let frames = look.species.frames
        let f = frames[((frame % frames.count) + frames.count) % frames.count]
        var rows = f.map { normalize($0) }
        let eye = eyeOverride ?? look.eyes.glyph
        rows = rows.map { String($0.map { $0 == "@" ? eye : $0 }) }
        if look.hat != .none {
            rows[0] = overlayHat(row0: rows[0], anchorRow: rows[1].contains(where: { $0 != " " }) ? rows[1] : rows[2], hat: look.hat.art)
        }
        return rows
    }

    static func normalize(_ s: String) -> String {
        var chars = Array(s)
        if chars.count > SpriteBank.cols { chars = Array(chars[0..<SpriteBank.cols]) }
        while chars.count < SpriteBank.cols { chars.append(" ") }
        return String(chars)
    }

    /// Centers the hat over the visible span of the anchor row.
    static func overlayHat(row0: String, anchorRow: String, hat: String) -> String {
        let a = Array(anchorRow)
        guard let first = a.firstIndex(where: { $0 != " " }), let last = a.lastIndex(where: { $0 != " " }) else { return row0 }
        let center = (first + last) / 2
        let h = Array(hat)
        var start = center - h.count / 2
        start = max(0, min(SpriteBank.cols - h.count, start))
        var out = Array(row0)
        for (i, ch) in h.enumerated() where start + i < out.count { out[start + i] = ch }
        return String(out)
    }
}

// MARK: - Speech bubble

enum Bubble {
    static let maxWidth = 24
    static let maxLines = 3

    static func wrap(_ text: String, width: Int = maxWidth, maxLines: Int = maxLines) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: true) {
            var w = String(word)
            if w.count > width { w = String(w.prefix(width - 1)) + "…" }
            if current.isEmpty { current = w }
            else if current.count + 1 + w.count <= width { current += " " + w }
            else { lines.append(current); current = w }
            if lines.count == maxLines { break }
        }
        if lines.count < maxLines && !current.isEmpty { lines.append(current) }
        if lines.count == maxLines, let lastLine = lines.last, text.count > lines.joined(separator: " ").count {
            lines[maxLines - 1] = String(lastLine.prefix(width - 1)) + "…"
        }
        return lines
    }

    /// Box-drawn bubble with a tail on the left, e.g.
    /// ╭──────────╮
    /// │ hallo    │
    /// ╰─┬────────╯
    static func box(_ text: String, tailCol: Int = 6) -> [String] {
        let lines = wrap(text)
        guard !lines.isEmpty else { return [] }
        let inner = max(lines.map { $0.count }.max() ?? 0, 3)
        let top = "╭" + String(repeating: "─", count: inner + 2) + "╮"
        var out = [top]
        for l in lines {
            out.append("│ " + l + String(repeating: " ", count: inner - l.count) + " │")
        }
        var bottom = Array("╰" + String(repeating: "─", count: inner + 2) + "╯")
        let t = max(1, min(inner, tailCol))
        bottom[t] = "┬"
        out.append(String(bottom))
        return out
    }
}
