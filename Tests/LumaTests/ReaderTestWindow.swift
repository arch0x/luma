import AppKit

/// Preserve the requested geometry even on GitHub's smaller virtual displays.
@MainActor final class ReaderTestWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
