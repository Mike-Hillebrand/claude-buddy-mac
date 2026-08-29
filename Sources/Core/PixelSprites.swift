import Foundation

// MARK: - Pixel species (16 × 14 cells, 2 frames)
//
// Legend:  .  empty     #  body (theme color)   s  shade (darker body)   l  light (lighter body)
//          w  white     d  dark                  a  accent (warm yellow)  e  eye slot (2×2, top-left marks origin)

struct PixelSpecies: Identifiable, Equatable {
    let id: String
    let name: String
    let frames: [[String]]
    static func == (a: PixelSpecies, b: PixelSpecies) -> Bool { a.id == b.id }
}

enum PixelKind { case body, shade, light, white, dark, accent, outline }

struct Pixel: Equatable {
    let x: Int
    let y: Int
    let kind: PixelKind
}

enum PixelBank {
    static let cols = 16
    static let rows = 14
    static let hatRows = 4      // extra rows above the grid reserved for hats

    static let all: [PixelSpecies] = [
        // Block body with a groove top-left, two tall eyes, stubby arms, four legs in pairs —
        // proportions taken from the "cube robot" character sheet.
        PixelSpecies(id: "clawd", name: "Clawd", frames: [
            ["................",
             "................",
             "..##s#########..",
             "..##s#########..",
             "..##see###ee##..",
             "#####ee###ee####",
             "#####ee###ee####",
             "################",
             "..############..",
             "..############..",
             "..##.##..##.##..",
             "..##.##..##.##..",
             "..##.##..##.##..",
             "................"],
            ["................",
             "................",
             "..##s#########..",
             "..##s#########..",
             "####see###ee##..",
             "#####ee###ee##..",
             "#####ee###ee####",
             "..##############",
             "..##############",
             "..############..",
             "..##.##..##.##..",
             "..##.##..##.##..",
             "..##.##..##.##..",
             "................"],
            ["................",
             "................",
             "..##s#########..",
             "..##s#########..",
             "..##see###ee####",
             "..###ee###ee####",
             "#####ee###ee####",
             "##############..",
             "##############..",
             "..############..",
             "..##.##..##.##..",
             "..##.##..##.##..",
             "..##.##..##.##..",
             "................"],
        ]),
        PixelSpecies(id: "blob", name: "Blob", frames: [
            ["................",
             "................",
             "......####......",
             "....########....",
             "...##########...",
             "..############..",
             "..##ee####ee##..",
             "..##ee####ee##..",
             "..#l########l#..",
             "..#####dd#####..",
             "..############..",
             "...##########...",
             "....########....",
             "................"],
            ["................",
             "................",
             "................",
             ".....######.....",
             "...##########...",
             "..############..",
             ".###ee####ee###.",
             ".###ee####ee###.",
             ".##l########l##.",
             ".######dd######.",
             ".##############.",
             "..############..",
             "...##########...",
             "................"],
        ]),
        PixelSpecies(id: "cat", name: "Katze", frames: [
            ["..##........##..",
             "..#l#......#l#..",
             "..####....####..",
             "..############..",
             "..############..",
             "..##ee####ee##..",
             "..##ee####ee##..",
             "..############..",
             "..#####dd#####..",
             "..############..",
             "..############..",
             "...##########...",
             "...###....###...",
             "................"],
            ["..##........##..",
             "..#l#......#l#..",
             "..####....####..",
             "..############..",
             "..############..",
             "..##ee####ee##..",
             "..##ee####ee##..",
             "..############..",
             "..#####dd#####..",
             "..############..",
             "..############.#",
             "...##########.#.",
             "...###....###...",
             "................"],
        ]),
        PixelSpecies(id: "duck", name: "Ente", frames: [
            ["................",
             "......######....",
             ".....########...",
             ".....###ee###aa.",
             ".....###ee##aaa.",
             ".....########aa.",
             "......######....",
             "..############..",
             ".##############.",
             ".####sss#######.",
             ".####ssss######.",
             "..############..",
             "....aa....aa....",
             "................"],
            ["................",
             "......######....",
             ".....########...",
             ".....###ee###aa.",
             ".....###ee##aaa.",
             ".....########aa.",
             "......######....",
             "..############..",
             ".#####sss######.",
             ".####ssss######.",
             ".##############.",
             "..############..",
             "....aa....aa....",
             "................"],
        ]),
        PixelSpecies(id: "ghost", name: "Geist", frames: [
            ["................",
             ".....######.....",
             "....########....",
             "...##########...",
             "..############..",
             "..##ee####ee##..",
             "..##ee####ee##..",
             "..############..",
             "..#####dd#####..",
             "..#####dd#####..",
             "..############..",
             "..############..",
             "..###.####.###..",
             "................"],
            ["................",
             ".....######.....",
             "....########....",
             "...##########...",
             "..############..",
             "..##ee####ee##..",
             "..##ee####ee##..",
             "..############..",
             "..#####dd#####..",
             "..#####dd#####..",
             "..############..",
             "..############..",
             "..###.###.####..",
             "................"],
        ]),
        PixelSpecies(id: "robot", name: "Roboter", frames: [
            [".......a........",
             ".......d........",
             "...##########...",
             "..############..",
             "..#ee######ee#..",
             "..#ee######ee#..",
             "..############..",
             "..##dddddddd##..",
             "..############..",
             "...##########...",
             "..############..",
             ".s############s.",
             "...###....###...",
             "................"],
            [".......s........",
             ".......d........",
             "...##########...",
             "..############..",
             "..#ee######ee#..",
             "..#ee######ee#..",
             "..############..",
             "..##d.d.d.d.##..",
             "..############..",
             "...##########...",
             "..############..",
             ".s############s.",
             "...###....###...",
             "................"],
        ]),
        PixelSpecies(id: "penguin", name: "Pinguin", frames: [
            ["................",
             ".....######.....",
             "....########....",
             "...##########...",
             "...##ee##ee##...",
             "...##ee##ee##...",
             "...####aa####...",
             "..###wwwwww###..",
             ".####wwwwww####.",
             ".####wwwwww####.",
             ".####wwwwww####.",
             "..###wwwwww###..",
             "...aa......aa...",
             "................"],
            ["................",
             ".....######.....",
             "....########....",
             "...##########...",
             "...##ee##ee##...",
             "...##ee##ee##...",
             "...####aa####...",
             "..###wwwwww###..",
             "s####wwwwww####s",
             ".####wwwwww####.",
             ".####wwwwww####.",
             "..###wwwwww###..",
             "...aa......aa...",
             "................"],
        ]),
        PixelSpecies(id: "octopus", name: "Oktopus", frames: [
            ["................",
             ".....######.....",
             "...##########...",
             "..############..",
             "..##ee####ee##..",
             "..##ee####ee##..",
             "..#l########l#..",
             "..############..",
             "..############..",
             "..#.##.##.##.#..",
             "..#.##.##.##.#..",
             ".#..##..##..##..",
             ".#..##..##..##..",
             "................"],
            ["................",
             ".....######.....",
             "...##########...",
             "..############..",
             "..##ee####ee##..",
             "..##ee####ee##..",
             "..#l########l#..",
             "..############..",
             "..############..",
             "..#.##.##.##.#..",
             "..#.##.##.##.#..",
             "..##..##..##..#.",
             "..##..##..##..#.",
             "................"],
        ]),
        PixelSpecies(id: "rabbit", name: "Hase", frames: [
            ["...##.....##....",
             "...#l#...#l#....",
             "...#l#...#l#....",
             "...###...###....",
             "..############..",
             "..############..",
             "..##ee####ee##..",
             "..##ee####ee##..",
             "..#####dd#####..",
             "..############..",
             "...##########...",
             "..############..",
             "..############..",
             "...###....###..."],
            ["...##......##...",
             "...#l#....#l#...",
             "...#l#...#l#....",
             "...###...###....",
             "..############..",
             "..############..",
             "..##ee####ee##..",
             "..##ee####ee##..",
             "..#####dd#####..",
             "..############..",
             "...##########...",
             "..############..",
             "..############..",
             "...###....###..."],
        ]),
    ]

    static func species(id: String) -> PixelSpecies {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - Pixel hats (drawn above the body, `#` dark, `a` accent)

enum PixelHats {
    static func art(_ hat: Hat) -> [String] {
        switch hat {
        case .none: return []
        case .tophat: return ["..####..", "..####..", "########"]
        case .cap: return [".######.", "#########"]
        case .crown: return ["#.#.#.#", "#######"]
        case .beanie: return ["...aa...", ".######.", "########"]
        case .party: return ["...a....", "..###...", ".#####.."]
        case .halo: return [".aaaaaa.", "a......a"]
        case .wizard: return ["...#....", "..###...", ".#####..", "########"]
        case .bow: return ["##.##", "#####", "##.##"]
        }
    }
}

// MARK: - Renderer

enum PixelRenderer {
    /// Returns pixels in grid coordinates. y may be negative (hat rows above the sprite).
    /// `wink` closes one eye (0 = leftmost) on top of the regular style; `flat` skips outline + bevel.
    static func render(species: PixelSpecies, frame: Int, hat: Hat, eyes: EyeStyle, eyeOverride: Character? = nil,
                       wink: Int? = nil, flat: Bool = false) -> [Pixel] {
        let frames = species.frames
        let grid = frames[((frame % frames.count) + frames.count) % frames.count].map { Array($0) }
        var out: [Pixel] = []
        var eyeVisited = Set<Int>()
        var eyeSlots: [(x: Int, y: Int, w: Int, h: Int)] = []

        func isEye(_ x: Int, _ y: Int) -> Bool {
            y >= 0 && y < grid.count && x >= 0 && x < grid[y].count && grid[y][x] == "e"
        }

        for (y, row) in grid.enumerated() {
            for (x, ch) in row.enumerated() {
                switch ch {
                case "#": out.append(Pixel(x: x, y: y, kind: .body))
                case "s": out.append(Pixel(x: x, y: y, kind: .shade))
                case "l": out.append(Pixel(x: x, y: y, kind: .light))
                case "w": out.append(Pixel(x: x, y: y, kind: .white))
                case "d": out.append(Pixel(x: x, y: y, kind: .dark))
                case "a": out.append(Pixel(x: x, y: y, kind: .accent))
                case "e":
                    // Eye slot cells render as body first; the eye pattern is stamped on top.
                    out.append(Pixel(x: x, y: y, kind: .body))
                    let key = y * PixelBank.cols + x
                    if !eyeVisited.contains(key) {
                        // Slot = run of `e` cells to the right (max 3) × rows below (max 4).
                        var w = 1; while w < 3 && isEye(x + w, y) { w += 1 }
                        var h = 1; while h < 4 && isEye(x, y + h) { h += 1 }
                        eyeSlots.append((x, y, w, h))
                        for dy in 0..<h { for dx in 0..<w { eyeVisited.insert((y + dy) * PixelBank.cols + (x + dx)) } }
                    }
                default: break
                }
            }
        }

        // Eye patterns (relative to the slot origin; slots are w×h, usually 2×2 or 2×3).
        let style: Character = eyeOverride ?? {
            switch eyes {
            case .dot: return "."
            case .wide: return "O"
            case .sleepy: return "-"
            case .sparkle: return "*"
            case .happy: return "^"
            }
        }()
        let sortedEyes = eyeSlots.sorted { $0.x < $1.x }
        for (i, slot) in sortedEyes.enumerated() {
            let (ox, oy, w, h) = (slot.x, slot.y, slot.w, slot.h)
            var pattern: [(Int, Int, PixelKind)] = []
            let eyeStyle: Character = (wink == i) ? "-" : style
            func fill(_ rows: Range<Int>, _ kind: PixelKind = .dark) {
                for dy in rows { for dx in 0..<w { pattern.append((dx, dy, kind)) } }
            }
            switch eyeStyle {
            case "-":
                fill((h - 1)..<h)
            case "O":
                fill(-1..<h); pattern.append((w - 1, -1, .white))
            case "^":
                let mid = max(0, h / 2 - 1)
                pattern = [(0, mid + 1, .dark), (1, mid, .dark), (2, mid + 1, .dark)]
            case "x":
                pattern = [(0, 0, .dark), (2, 0, .dark), (1, 1, .dark), (0, 2, .dark), (2, 2, .dark)]
            case "*":
                fill(0..<h); pattern.append((0, 0, .white))
            default:
                fill(0..<h)
            }
            for (dx, dy, kind) in pattern {
                let px = ox + dx, py = oy + dy
                guard px >= 0, px < PixelBank.cols, py >= 0, py < PixelBank.rows else { continue }
                out.removeAll { $0.x == px && $0.y == py }
                out.append(Pixel(x: px, y: py, kind: kind))
            }
        }

        // Hat: centered over the topmost body row, its last row overlapping that row.
        let hatArt = PixelHats.art(hat)
        if !hatArt.isEmpty, let top = grid.firstIndex(where: { $0.contains(where: { $0 != "." }) }) {
            let rowCells = grid[top]
            let xs = rowCells.enumerated().filter { $0.element != "." }.map { $0.offset }
            let center = (xs.min()! + xs.max()!) / 2
            let width = hatArt.map { $0.count }.max() ?? 0
            let startX = center - width / 2 + (width % 2 == 0 ? 1 : 0)
            // Wide heads: the hat's brim overlaps the top row. Narrow tops (ears, antennas): hat sits above.
            let startY = xs.count >= 8 ? top - hatArt.count + 1 : top - hatArt.count
            for (i, row) in hatArt.enumerated() {
                for (j, ch) in row.enumerated() where ch != "." {
                    let px = startX + j, py = startY + i
                    guard px >= 0, px < PixelBank.cols, py >= -PixelBank.hatRows else { continue }
                    out.removeAll { $0.x == px && $0.y == py }
                    out.append(Pixel(x: px, y: py, kind: ch == "a" ? .accent : .dark))
                }
            }
        }
        return flat ? out : finish(out)
    }

    /// Adds a 1-cell dark outline around everything and a simple bevel
    /// (lighter top edges, darker bottom edges) so the sprite reads as a solid figure.
    static func finish(_ pixels: [Pixel]) -> [Pixel] {
        var map: [Int: PixelKind] = [:]
        func key(_ x: Int, _ y: Int) -> Int { (y + 64) * 256 + (x + 64) }
        for p in pixels { map[key(p.x, p.y)] = p.kind }

        var out: [Pixel] = []
        for p in pixels {
            var kind = p.kind
            if kind == .body {
                let below = map[key(p.x, p.y + 1)]
                let above = map[key(p.x, p.y - 1)]
                if below == nil || below == .outline { kind = .shade }
                else if above == nil { kind = .light }
            }
            out.append(Pixel(x: p.x, y: p.y, kind: kind))
        }
        var outline: [Pixel] = []
        var seen = Set<Int>()
        for p in pixels {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let x = p.x + dx, y = p.y + dy
                let k = key(x, y)
                if map[k] == nil && !seen.contains(k) {
                    seen.insert(k)
                    outline.append(Pixel(x: x, y: y, kind: .outline))
                }
            }
        }
        return out + outline
    }
}
