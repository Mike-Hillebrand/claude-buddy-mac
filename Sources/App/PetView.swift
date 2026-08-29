import SwiftUI
import AppKit

struct Particle: Identifiable {
    let id: Int
    let x0: CGFloat, y0: CGFloat, vx: CGFloat, vy: CGFloat
    let gravity: CGFloat
    let char: String
    let color: Color
    let born: Date
    let life: TimeInterval
}

final class PetViewModel: ObservableObject {
    @Published var style: SpriteStyle = .pixel
    @Published var rows: [String] = []                 // ascii style
    @Published var pixels: [Pixel] = []                // pixel style
    @Published var bubble: [String] = []               // ascii box lines
    @Published var bubbleText = ""                     // pixel-style bubble text
    @Published var bubbleAccent = false
    @Published var floatText = ""
    @Published var floatUp = false
    @Published var jump = false
    @Published var breath = false
    @Published var walking = false
    @Published var facingLeft = false
    @Published var wobble: CGFloat = 0
    @Published var state: PetState = .sleeping
    @Published var sessions: [TrackedSession] = []
    @Published var label = ""
    @Published var usageMode: UsageMode = .bar
    @Published var usageLine = ""                      // bar mode
    @Published var tickerText = ""                     // ticker mode
    @Published var particles: [Particle] = []
    @Published var theme: Theme = .terracotta
    @Published var fontSize: CGFloat = 14
    @Published var cell: CGFloat = 8
    @Published var card = false
}

/// Speech bubble with a tail at the bottom-left, drawn as one path so the border stays continuous.
struct BubbleShape: Shape {
    var tailX: CGFloat = 22
    var tail: CGFloat = 8
    var radius: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tail)
        p.addRoundedRect(in: body, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        var t = Path()
        t.move(to: CGPoint(x: tailX - tail, y: body.maxY - 1))
        t.addLine(to: CGPoint(x: tailX, y: body.maxY + tail))
        t.addLine(to: CGPoint(x: tailX + tail, y: body.maxY - 1))
        t.closeSubpath()
        p.addPath(t)
        return p
    }
}

struct Marquee: View {
    let text: String
    let font: Font
    let charWidth: CGFloat
    let width: CGFloat
    let color: Color

    var body: some View {
        let gap: CGFloat = 48
        let textW = CGFloat(text.count) * charWidth + gap
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let offset = CGFloat((t * 36).truncatingRemainder(dividingBy: Double(textW)))
            HStack(spacing: gap) {
                Text(text)
                Text(text)
            }
            .font(font)
            .foregroundColor(color)
            .fixedSize()
            .offset(x: -offset)
        }
        .frame(width: width, alignment: .leading)
        .clipped()
    }
}

struct PetView: View {
    @ObservedObject var vm: PetViewModel

    private var mono: Font { .custom("Menlo", size: vm.fontSize) }
    private var small: Font { .custom("Menlo", size: max(9, vm.fontSize * 0.72)) }
    private var smallCharWidth: CGFloat { max(9, vm.fontSize * 0.72) * 0.602 }
    private var themeColor: Color { Color(nsColor: vm.theme.color) }
    private var accent: Color { Color(red: 1.0, green: 0.42, blue: 0.2) }
    private var textColor: Color { vm.card ? .primary : .white }
    private var lineHeight: CGFloat { vm.fontSize * 1.2 }
    private var spriteWidth: CGFloat {
        vm.style == .pixel ? vm.cell * CGFloat(PixelBank.cols + 2) : vm.fontSize * 0.602 * 12 + 4
    }
    private var spriteHeight: CGFloat {
        vm.style == .pixel ? vm.cell * CGFloat(PixelBank.rows + PixelBank.hatRows + 2) : lineHeight * 5
    }
    private var contentWidth: CGFloat { max(spriteWidth, vm.fontSize * 0.602 * 26 + 20) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            bubbleView
            ZStack(alignment: .topLeading) {
                spriteView
                    .offset(x: vm.wobble, y: vm.jump ? -6 : (vm.walking && vm.breath ? -2 : 0))
                    .animation(.spring(response: 0.25, dampingFraction: 0.45), value: vm.jump)
                    .animation(.easeInOut(duration: 0.12), value: vm.wobble)
                if !vm.floatText.isEmpty {
                    Text(vm.floatText)
                        .font(mono.weight(.bold))
                        .foregroundColor(vm.state == .attention ? accent : (vm.card ? themeColor : .white))
                        .offset(x: spriteWidth * 0.8, y: vm.floatUp ? (vm.style == .pixel ? 4 : -4) : (vm.style == .pixel ? 10 : 2))
                        .animation(.easeInOut(duration: 0.3), value: vm.floatUp)
                        .shadow(color: .black.opacity(0.6), radius: 1.5)
                }
                if !vm.particles.isEmpty {
                    TimelineView(.animation) { ctx in
                        ZStack {
                            ForEach(vm.particles) { p in
                                let t = CGFloat(ctx.date.timeIntervalSince(p.born))
                                let alpha = max(0, 1 - t / CGFloat(p.life))
                                Text(p.char)
                                    .font(small.weight(.bold))
                                    .foregroundColor(p.color)
                                    .position(x: p.x0 + p.vx * t, y: p.y0 + p.vy * t + p.gravity * t * t)
                                    .opacity(Double(alpha))
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(width: spriteWidth, height: spriteHeight, alignment: .topLeading)

            HStack(spacing: 5) {
                ForEach(vm.sessions.prefix(12)) { s in
                    Circle()
                        .fill(color(for: s.state))
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.5))
                }
                Text(vm.label)
                    .font(small)
                    .foregroundColor(vm.card ? .secondary : .white.opacity(0.9))
                    .lineLimit(1)
                    .shadow(color: vm.card ? .clear : .black.opacity(0.8), radius: 1.5)
            }
            .padding(.top, 3)

            usageView
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Group {
                if vm.card {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .allowsHitTesting(false)
    }

    // MARK: Sprite

    @ViewBuilder private var spriteView: some View {
        if vm.style == .pixel {
            Canvas { ctx, _ in
                let c = vm.cell
                let base = vm.theme.color
                for p in vm.pixels {
                    let col = vm.facingLeft ? CGFloat(PixelBank.cols - p.x) : CGFloat(p.x + 1)
                    let rect = CGRect(x: col * c, y: CGFloat(p.y + PixelBank.hatRows + 1) * c, width: c, height: c)
                    ctx.fill(Path(rect), with: .color(pixelColor(p.kind, base: base)))
                }
            }
            .frame(width: spriteWidth, height: spriteHeight)
            .scaleEffect(x: vm.breath ? 1.0 : 1.025, y: vm.breath ? 1.0 : 0.975, anchor: .bottom)
            .animation(.easeInOut(duration: 0.5), value: vm.breath)
            .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
        } else {
            Text(vm.rows.joined(separator: "\n"))
                .font(mono)
                .foregroundColor(themeColor)
                .lineSpacing(0)
                .fixedSize()
                .shadow(color: vm.card ? .clear : .black.opacity(0.55), radius: 2)
        }
    }

    private func pixelColor(_ kind: PixelKind, base: NSColor) -> Color {
        switch kind {
        case .body: return Color(nsColor: base)
        case .shade: return Color(nsColor: base.blended(withFraction: 0.22, of: .black) ?? base)
        case .light: return Color(nsColor: base.blended(withFraction: 0.3, of: .white) ?? base)
        case .white: return Color(white: 0.97)
        case .dark: return Color(white: 0.09)
        case .accent: return Color(red: 0.96, green: 0.70, blue: 0.22)
        case .outline: return Color(nsColor: base.blended(withFraction: 0.62, of: .black) ?? .black)
        }
    }

    // MARK: Bubble

    @ViewBuilder private var bubbleView: some View {
        if vm.style == .pixel {
            if !vm.bubbleText.isEmpty {
                Text(vm.bubbleText)
                    .font(mono)
                    .foregroundColor(vm.bubbleAccent ? accent : Color(white: 0.1))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: vm.fontSize * 0.602 * 26, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.top, 5)
                    .padding(.bottom, 5 + 8)
                    .background(
                        BubbleShape(tailX: vm.cell * 6)
                            .fill(Color(white: 0.98))
                            .overlay(BubbleShape(tailX: vm.cell * 6).stroke(Color(white: 0.1), lineWidth: 2))
                            .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                    )
                    .padding(.bottom, 2)
                    .transition(.opacity)
            }
        } else if !vm.bubble.isEmpty {
            Text(vm.bubble.joined(separator: "\n"))
                .font(mono)
                .foregroundColor(vm.bubbleAccent ? accent : textColor)
                .lineSpacing(0)
                .fixedSize()
                .shadow(color: vm.card ? .clear : .black.opacity(0.7), radius: 1.5)
                .transition(.opacity)
        }
    }

    // MARK: Usage

    @ViewBuilder private var usageView: some View {
        switch vm.usageMode {
        case .off:
            EmptyView()
        case .bar:
            if !vm.usageLine.isEmpty {
                Text(vm.usageLine)
                    .font(small)
                    .foregroundColor(vm.card ? .secondary : .white.opacity(0.9))
                    .lineLimit(1)
                    .fixedSize()
                    .shadow(color: vm.card ? .clear : .black.opacity(0.8), radius: 1.5)
                    .padding(.top, 1)
            }
        case .ticker:
            if !vm.tickerText.isEmpty {
                Marquee(text: vm.tickerText, font: small, charWidth: smallCharWidth, width: contentWidth,
                        color: vm.card ? .secondary : .white.opacity(0.9))
                    .shadow(color: vm.card ? .clear : .black.opacity(0.8), radius: 1.5)
                    .padding(.top, 1)
            }
        }
    }

    func color(for state: PetState) -> Color {
        switch state {
        case .attention: return accent
        case .working: return Color(red: 0.25, green: 0.52, blue: 1.0)
        case .thinking: return Color(red: 0.55, green: 0.6, blue: 0.95)
        case .ready: return Color(red: 0.2, green: 0.78, blue: 0.45)
        case .idle: return Color.gray.opacity(0.8)
        case .sleeping: return Color.gray.opacity(0.4)
        }
    }
}
