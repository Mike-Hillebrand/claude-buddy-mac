// Tiny synthetic-input helper for demos: uiclick move|click|rclick|dclick X Y | key CODE [cmd] | drag X1 Y1 X2 Y2
// Coordinates are global CG coordinates (origin top-left of the main display, y down).
import Foundation
import CoreGraphics

let a = CommandLine.arguments
func pt(_ i: Int) -> CGPoint { CGPoint(x: Double(a[i]) ?? 0, y: Double(a[i + 1]) ?? 0) }
let tapName = ProcessInfo.processInfo.environment["UITAP"] ?? "hid"
let src: CGEventSource? = ProcessInfo.processInfo.environment["UISRC"] == "session" ? CGEventSource(stateID: .combinedSessionState) : nil
func post(_ e: CGEvent?) { e?.post(tap: tapName == "session" ? .cgSessionEventTap : (tapName == "annotated" ? .cgAnnotatedSessionEventTap : .cghidEventTap)); usleep(40_000) }
func move(_ p: CGPoint) { post(CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)) }
func click(_ p: CGPoint, button: CGMouseButton, count: Int = 1) {
    let down: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
    let up: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
    move(p)
    usleep(150_000)   // let hover-based hit testing (ignoresMouseEvents polling) catch up
    for n in 1...count {
        let d = CGEvent(mouseEventSource: src, mouseType: down, mouseCursorPosition: p, mouseButton: button)
        d?.setIntegerValueField(.mouseEventClickState, value: Int64(n))
        post(d)
        let u = CGEvent(mouseEventSource: src, mouseType: up, mouseCursorPosition: p, mouseButton: button)
        u?.setIntegerValueField(.mouseEventClickState, value: Int64(n))
        post(u)
        usleep(60_000)
    }
}
guard a.count >= 2 else { print("usage"); exit(1) }
switch a[1] {
case "move": move(pt(2))
case "click": click(pt(2), button: .left)
case "dclick": click(pt(2), button: .left, count: 2)
case "rclick": click(pt(2), button: .right)
case "drag":
    let p1 = pt(2), p2 = pt(4)
    move(p1)
    post(CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p1, mouseButton: .left))
    let steps = 25
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        let p = CGPoint(x: p1.x + (p2.x - p1.x) * t, y: p1.y + (p2.y - p1.y) * t)
        post(CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left))
        usleep(16_000)
    }
    post(CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p2, mouseButton: .left))
case "key":
    let code = CGKeyCode(UInt16(a[2]) ?? 0)
    let d = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
    let u = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
    if a.count > 3 && a[3] == "cmd" { d?.flags = .maskCommand; u?.flags = .maskCommand }
    post(d); post(u)
default: print("unknown"); exit(1)
}
