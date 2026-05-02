import XCTest
import AppKit
@testable import NepaliIMECore

final class PanelPositionerTests: XCTestCase {
    private let screen = NSScreen.dummy(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))

    func testPlacesBelowCaretByDefault() {
        let caret = NSRect(x: 200, y: 500, width: 1, height: 18)
        let origin = PanelPositioner.origin(
            forPanelSize: NSSize(width: 200, height: 80),
            below: caret,
            screens: [screen]
        )
        XCTAssertEqual(origin.x, 200, accuracy: 0.5)
        XCTAssertEqual(origin.y, 500 - 80 - 4, accuracy: 0.5)
    }

    func testClampsRightEdge() {
        let caret = NSRect(x: 1400, y: 500, width: 1, height: 18)
        let origin = PanelPositioner.origin(
            forPanelSize: NSSize(width: 200, height: 80),
            below: caret,
            screens: [screen]
        )
        XCTAssertLessThanOrEqual(origin.x + 200, screen.frame.maxX)
    }

    func testClampsLeftEdge() {
        let caret = NSRect(x: -10, y: 500, width: 1, height: 18)
        let origin = PanelPositioner.origin(
            forPanelSize: NSSize(width: 200, height: 80),
            below: caret,
            screens: [screen]
        )
        XCTAssertGreaterThanOrEqual(origin.x, screen.frame.minX)
    }

    func testFlipsAboveCaretWhenBelowOffscreen() {
        let caret = NSRect(x: 200, y: 40, width: 1, height: 18)
        let origin = PanelPositioner.origin(
            forPanelSize: NSSize(width: 200, height: 80),
            below: caret,
            screens: [screen]
        )
        XCTAssertGreaterThanOrEqual(origin.y, 0)
    }
}

private extension NSScreen {
    static func dummy(frame: NSRect) -> NSScreen {
        if let main = NSScreen.screens.first { return main }
        return NSScreen()
    }
}
