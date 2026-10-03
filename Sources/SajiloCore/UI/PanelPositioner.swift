import Foundation
import AppKit

public enum PanelPositioner {
    public static func origin(
        forPanelSize panelSize: NSSize,
        below caret: NSRect,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSPoint {
        let preferred = NSPoint(x: caret.minX, y: caret.minY - panelSize.height - 4)
        let screen = screen(containing: caret, screens: screens) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return preferred }

        var x = preferred.x
        var y = preferred.y

        if x + panelSize.width > frame.maxX { x = frame.maxX - panelSize.width - 4 }
        if x < frame.minX { x = frame.minX + 4 }

        if y < frame.minY {
            y = caret.maxY + 4
            if y + panelSize.height > frame.maxY {
                y = frame.maxY - panelSize.height - 4
            }
        }

        return NSPoint(x: x, y: y)
    }

    private static func screen(containing rect: NSRect, screens: [NSScreen]) -> NSScreen? {
        screens.first(where: { $0.frame.intersects(rect) }) ?? screens.first
    }
}
