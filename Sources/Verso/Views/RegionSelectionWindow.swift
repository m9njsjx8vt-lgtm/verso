import AppKit

/// Fullscreen transparent overlay that lets the user drag a selection rect.
/// On mouse-up, calls `onSelect` with the rect in **screen coordinates**
/// (top-left origin, ready for `CGWindowListCreateImage`).
final class RegionSelectionWindow: NSWindow {
    private let onSelect: (CGRect) -> Void
    private let onCancel: () -> Void
    private let selectionView: SelectionView

    init(
        screen: NSScreen,
        onSelect: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.selectionView = SelectionView()

        // Avoid NSWindow's screen-specific convenience initializer here.
        // On macOS 26 it can dispatch back into the Swift subclass initializer
        // before RegionSelectionWindow's stored properties are valid, causing
        // an EXC_BREAKPOINT when starting region OCR.
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)

        backgroundColor = NSColor.black.withAlphaComponent(0.30)
        isOpaque = false
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        contentView = selectionView
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }

    override func mouseDown(with event: NSEvent) {
        selectionView.startDrag(at: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        selectionView.updateDrag(to: event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        let rect = selectionView.endDrag()
        guard rect.width >= 5, rect.height >= 5, let screen = self.screen else {
            cancel()
            return
        }
        // Convert NSWindow rect (bottom-left origin) → CG screen rect (top-left origin)
        let screenFrame = screen.frame
        let cgRect = CGRect(
            x: rect.origin.x + screenFrame.origin.x,
            y: screenFrame.origin.y + screenFrame.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        orderOut(nil)
        // Tiny delay so the overlay is fully gone before the screenshot
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.onSelect(cgRect)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            cancel()
        } else {
            super.keyDown(with: event)
        }
    }

    private func cancel() {
        orderOut(nil)
        onCancel()
    }
}

private final class SelectionView: NSView {
    private var startPoint: NSPoint = .zero
    private var currentRect: NSRect = .zero
    private var isDragging = false

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    func startDrag(at point: NSPoint) {
        startPoint = point
        currentRect = NSRect(origin: point, size: .zero)
        isDragging = true
        needsDisplay = true
    }

    func updateDrag(to point: NSPoint) {
        currentRect = NSRect(
            x: min(startPoint.x, point.x),
            y: min(startPoint.y, point.y),
            width: abs(point.x - startPoint.x),
            height: abs(point.y - startPoint.y)
        )
        needsDisplay = true
    }

    @discardableResult
    func endDrag() -> NSRect {
        isDragging = false
        let r = currentRect
        currentRect = .zero
        needsDisplay = true
        return r
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isDragging, currentRect.width > 0, currentRect.height > 0 else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Punch out the selection (clear the dimmed bg)
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.fill(currentRect)
        ctx.restoreGState()
        // Draw border
        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(rect: currentRect)
        border.lineWidth = 2
        border.stroke()
    }
}
