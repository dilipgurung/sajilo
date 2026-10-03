import XCTest
@testable import SajiloCore

final class CompositionBufferTests: XCTestCase {
    func testTypingAppendsAtEnd() {
        var b = CompositionBuffer()
        for ch in "nmste" { b.insert(ch) }
        XCTAssertEqual(b.text, "nmste")
        XCTAssertEqual(b.caret, 5)
    }

    func testLeftThenTypeInsertsMidWord() {
        // Fix the typo `nmste` → `namaste` without retyping.
        var b = CompositionBuffer(text: "nmste")
        b.moveCaret(by: -4)
        b.insert("a")
        XCTAssertEqual(b.text, "namste")
        b.moveCaret(by: +1)
        b.insert("a")
        XCTAssertEqual(b.text, "namaste")
        XCTAssertEqual(b.caret, 4)
    }

    func testBackspaceDeletesBeforeCaret() {
        var b = CompositionBuffer(text: "namxaste")
        b.moveCaret(by: -4)
        b.deleteBackward()
        XCTAssertEqual(b.text, "namaste")
        XCTAssertEqual(b.caret, 3)
    }

    func testBackspaceAtStartIsNoOp() {
        var b = CompositionBuffer(text: "ab", caret: 0)
        b.deleteBackward()
        XCTAssertEqual(b.text, "ab")
        XCTAssertEqual(b.caret, 0)
    }

    func testCaretClampsToBuffer() {
        var b = CompositionBuffer(text: "abc")
        b.moveCaret(by: +1)
        XCTAssertEqual(b.caret, 3)
        b.moveCaret(by: -10)
        XCTAssertEqual(b.caret, 0)
        XCTAssertEqual(CompositionBuffer(text: "abc", caret: 99).caret, 3)
    }

    func testCaretUTF16Offset() {
        let b = CompositionBuffer(text: "gai*DaakoT", caret: 4)
        XCTAssertEqual(b.caretUTF16Offset, 4)
    }
}
