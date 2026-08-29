import AppKit
import SwiftUI

/// Borderless, transparent, always-on-top, non-activating panel that hosts the pet.
final class PetPanel: NSPanel {
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onMoved: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        titleVisibility = .hidden
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Catches mouse events under the (hit-test-disabled) SwiftUI view: drag to move, click to pet, right-click for the menu.
final class DragCatcherView: NSView {
    weak var panel: PetPanel?
    private var dragStart: NSPoint?
    private var windowStart: NSPoint?
    private var moved = false
    private(set) var isDragging = false

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin
        moved = false
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let s = dragStart, let w = windowStart, let win = window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - s.x, dy = now.y - s.y
        if abs(dx) > 2 || abs(dy) > 2 { moved = true }
        win.setFrameOrigin(NSPoint(x: w.x + dx, y: w.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if moved { panel?.onMoved?() }
        else if event.clickCount == 2 { panel?.onDoubleClick?() }
        else { panel?.onClick?() }
        dragStart = nil; windowStart = nil; moved = false
        isDragging = false
    }

    override func rightMouseDown(with event: NSEvent) {
        panel?.onRightClick?(event)
    }
}
