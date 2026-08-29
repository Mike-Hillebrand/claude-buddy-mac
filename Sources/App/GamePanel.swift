import AppKit
import SwiftUI

final class GameViewModel: ObservableObject {
    @Published var game = TicTacToe()
    @Published var message = ""
    @Published var wins = 0          // human
    @Published var losses = 0        // buddy won
    @Published var draws = 0
    @Published var buddyThinking = false
    @Published var theme: Theme = .terracotta
    var onCell: ((Int) -> Void)?
    var onNew: (() -> Void)?
    var onClose: (() -> Void)?
}

/// Retro tic-tac-toe board: dark frame, pixel-style X and O.
struct GameView: View {
    @ObservedObject var vm: GameViewModel
    private let cell: CGFloat = 54
    private var accent: Color { Color(nsColor: vm.theme.color) }
    private let ink = Color(white: 0.1)
    private let paper = Color(white: 0.98)
    private var mono: Font { .custom("Menlo", size: 12) }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Tic-Tac-Toe").font(mono.weight(.bold))
                Spacer()
                Button(action: { vm.onClose?() }) {
                    Text("✕").font(mono.weight(.bold))
                }
                .buttonStyle(.plain)
            }
            .foregroundColor(ink)

            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { r in
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { c in
                            let i = r * 3 + c
                            cellView(i)
                        }
                    }
                }
            }
            .padding(4)
            .background(ink)

            Text(vm.message.isEmpty ? " " : vm.message)
                .font(mono)
                .foregroundColor(ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text("\(S.t("ttt.you")) \(vm.wins) · \(S.t("ttt.buddy")) \(vm.losses) · \(S.t("ttt.draw")) \(vm.draws)")
                    .font(mono)
                    .foregroundColor(ink.opacity(0.7))
                Spacer()
                Button(action: { vm.onNew?() }) {
                    Text(S.t("ttt.new"))
                        .font(mono.weight(.bold))
                        .foregroundColor(paper)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(ink)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: cell * 3 + 4 * 4 + 24 + 60)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(paper)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(ink, lineWidth: 2))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        )
        .padding(8)
    }

    @ViewBuilder private func cellView(_ i: Int) -> some View {
        let mark = vm.game.cells[i]
        let winning = vm.game.winningLine.contains(i)
        Button(action: { vm.onCell?(i) }) {
            ZStack {
                Rectangle().fill(winning ? accent.opacity(0.25) : paper)
                if let m = mark {
                    Canvas { ctx, size in
                        let u = size.width / 9      // 9×9 pixel grid per cell
                        func px(_ x: Int, _ y: Int, _ color: Color) {
                            ctx.fill(Path(CGRect(x: CGFloat(x) * u, y: CGFloat(y) * u, width: u + 0.5, height: u + 0.5)), with: .color(color))
                        }
                        if m == .x {
                            for k in 1..<8 { px(k, k, ink); px(8 - k, k, ink) }
                        } else {
                            for k in 2..<7 { px(k, 1, accent); px(k, 7, accent); px(1, k, accent); px(7, k, accent) }
                            px(2, 2, accent); px(6, 2, accent); px(2, 6, accent); px(6, 6, accent)
                        }
                    }
                    .padding(6)
                }
            }
            .frame(width: cell, height: cell)
        }
        .buttonStyle(.plain)
        .disabled(mark != nil || vm.game.isOver || vm.buddyThinking || vm.game.turn != .x)
    }
}

final class GamePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
