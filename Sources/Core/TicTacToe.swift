import Foundation

/// Tic-tac-toe. Human is X (0), the buddy is O (1). Pure logic, no UI.
struct TicTacToe: Equatable {
    enum Player: Int { case x = 0, o = 1
        var other: Player { self == .x ? .o : .x }
    }
    enum Outcome: Equatable { case ongoing, win(Player), draw }

    private(set) var cells: [Player?] = Array(repeating: nil, count: 9)
    private(set) var turn: Player = .x
    private(set) var winningLine: [Int] = []

    static let lines: [[Int]] = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]]

    var outcome: Outcome {
        for l in TicTacToe.lines {
            if let p = cells[l[0]], cells[l[1]] == p, cells[l[2]] == p { return .win(p) }
        }
        return cells.contains(nil) ? .ongoing : .draw
    }

    var isOver: Bool { outcome != .ongoing }
    var freeCells: [Int] { cells.indices.filter { cells[$0] == nil } }

    /// Plays `i` for the player whose turn it is. Returns false for illegal moves.
    @discardableResult
    mutating func play(_ i: Int) -> Bool {
        guard !isOver, i >= 0, i < 9, cells[i] == nil else { return false }
        cells[i] = turn
        turn = turn.other
        if case .win(let p) = outcome {
            winningLine = TicTacToe.lines.first { l in l.allSatisfy { cells[$0] == p } } ?? []
        }
        return true
    }

    mutating func reset(starter: Player) {
        cells = Array(repeating: nil, count: 9)
        turn = starter
        winningLine = []
    }

    // MARK: AI

    /// Best move for the current player (minimax, perfect play).
    func bestMove() -> Int? {
        guard !isOver else { return nil }
        var best: (score: Int, move: Int)? = nil
        for m in freeCells {
            var g = self; g.play(m)
            let s = -g.negamax()
            if best == nil || s > best!.score { best = (s, m) }
        }
        return best?.move
    }

    /// Move with a bit of imperfection so a human can win now and then:
    /// `skill` 1.0 = perfect, 0.0 = random. Deterministic when `random` is supplied.
    func move(skill: Double, random: () -> Double = { Double.random(in: 0..<1) }) -> Int? {
        guard !isOver else { return nil }
        let free = freeCells
        if random() > skill, free.count > 1 {
            return free[Int(random() * Double(free.count)) % free.count]
        }
        return bestMove()
    }

    /// Score from the perspective of the player to move: +1 win, 0 draw, -1 loss.
    private func negamax() -> Int {
        switch outcome {
        case .win(let p): return p == turn ? 1 : -1
        case .draw: return 0
        case .ongoing:
            var best = -2
            for m in freeCells {
                var g = self; g.play(m)
                best = max(best, -g.negamax())
                if best == 1 { break }
            }
            return best
        }
    }
}
