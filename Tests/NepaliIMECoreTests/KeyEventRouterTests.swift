import XCTest
import AppKit
@testable import NepaliIMECore

final class KeyEventRouterTests: XCTestCase {
    func testLatinLetterAppends() {
        XCTAssertEqual(classify("a", composing: false), .appendChar("a"))
        XCTAssertEqual(classify("Z", composing: true), .appendChar("Z"))
    }

    func testNonLatinPassesWhenIdle() {
        XCTAssertEqual(classify(" ", composing: false), .passThrough)
        XCTAssertEqual(classify("\r", composing: false), .passThrough)
        XCTAssertEqual(classify("5", composing: false), .passThrough)
        XCTAssertEqual(classify(",", composing: false), .passThrough)
    }

    func testSpaceCommitsWhenComposing() {
        XCTAssertEqual(classify(" ", composing: true), .commitSelected)
    }

    func testReturnCommitsSelectedWhenComposing() {
        XCTAssertEqual(classify("\r", composing: true), .commitSelected)
    }

    func testEscapeCancelsWhenComposing() {
        XCTAssertEqual(classify("\u{1B}", composing: true), .cancel)
    }

    func testBackspaceWhenComposing() {
        XCTAssertEqual(classify("\u{8}", composing: true), .backspace)
        XCTAssertEqual(classify("\u{7F}", composing: true), .backspace)
    }

    func testTabSelectsFirstCandidate() {
        XCTAssertEqual(classify("\t", composing: true), .selectIndex(0))
    }

    func testDigitsSelectCandidatesWhenComposing() {
        XCTAssertEqual(classify("1", composing: true), .selectIndex(0))
        XCTAssertEqual(classify("5", composing: true), .selectIndex(4))
        XCTAssertEqual(classify("9", composing: true), .selectIndex(8))
    }

    func testZeroDoesNotSelectCandidate() {
        XCTAssertNotEqual(classify("0", composing: true), .selectIndex(-1))
    }

    func testArrowsMoveSelection() {
        XCTAssertEqual(classify("\u{F700}", composing: true), .moveSelection(-1))
        XCTAssertEqual(classify("\u{F701}", composing: true), .moveSelection(+1))
    }

    func testPunctuationCommitsAndInsertsWhenComposing() {
        XCTAssertEqual(classify(",", composing: true), .commitSelectedThenInsert(","))
        XCTAssertEqual(classify(".", composing: true), .commitSelectedThenInsert("."))
    }

    func testBacktickAppendsAsSigilNotCommit() {
        // Backtick is the retroflex sigil prefix; it must enter the
        // buffer (so the rule transliterator can fold `` `t `` → ट
        // etc.) instead of triggering commit-then-insert like other
        // ASCII punctuation.
        XCTAssertEqual(classify("`", composing: false), .appendChar("`"))
        XCTAssertEqual(classify("`", composing: true),  .appendChar("`"))
    }

    func testCommandKeyChordPassesThrough() {
        let action = KeyEventRouter.classify(
            characters: "s",
            modifierFlags: [.command],
            hasComposition: true
        )
        XCTAssertEqual(action, .passThrough)
    }

    func testControlKeyChordPassesThrough() {
        let action = KeyEventRouter.classify(
            characters: "a",
            modifierFlags: [.control],
            hasComposition: true
        )
        XCTAssertEqual(action, .passThrough)
    }

    func testShiftedLetterStillAppends() {
        let action = KeyEventRouter.classify(
            characters: "A",
            modifierFlags: [.shift],
            hasComposition: false
        )
        XCTAssertEqual(action, .appendChar("A"))
    }

    private func classify(_ chars: String, composing: Bool) -> KeyAction {
        KeyEventRouter.classify(
            characters: chars,
            modifierFlags: [],
            hasComposition: composing
        )
    }
}
