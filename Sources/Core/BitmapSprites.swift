import Foundation

// MARK: - Bitmap species (real artwork, frame-strip PNGs — not code-drawn like Sprites/PixelSprites)
//
// Each animation is one horizontal strip of equal-width frames, bundled under
// Resources/<folder>/<resource>.png and loaded via BitmapImageCache (Sources/App/PetView.swift).
// The source art faces left; PetView mirrors it when the buddy should face right.

struct BitmapStrip: Equatable {
    let folder: String       // Resources subfolder, also the name bundled into Contents/Resources
    let resource: String     // file name without extension
    let frameCount: Int
    let frameSize: CGSize    // pixel size of ONE frame in the source strip
}

struct BitmapSpecies: Identifiable, Equatable {
    let id: String
    let name: String
    var displayName: String { S.name(id) }
    let idle: BitmapStrip
    var walk: BitmapStrip?
    var attention: BitmapStrip?
    var sleep: BitmapStrip?
    static func == (a: BitmapSpecies, b: BitmapSpecies) -> Bool { a.id == b.id }
}

enum BitmapBank {
    // "Codex v2" character-sheet generator, 8×11 atlas at 192×208/frame (rows used here: 0 idle,
    // 1 walk, 3 wave). Rows 2, 4–10 exist but aren't wired to a buddy state yet.
    static let all: [BitmapSpecies] = [
        BitmapSpecies(
            id: "bulldog", name: "Bulldog",
            idle: BitmapStrip(folder: "Bulldog", resource: "bulldog-idle", frameCount: 7, frameSize: CGSize(width: 192, height: 208)),
            walk: BitmapStrip(folder: "Bulldog", resource: "bulldog-walk", frameCount: 8, frameSize: CGSize(width: 192, height: 208)),
            attention: BitmapStrip(folder: "Bulldog", resource: "bulldog-attention", frameCount: 4, frameSize: CGSize(width: 192, height: 208)),
            sleep: BitmapStrip(folder: "Bulldog", resource: "bulldog-sleep", frameCount: 6, frameSize: CGSize(width: 262, height: 201))
        ),
    ]
}
