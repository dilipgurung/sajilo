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

    func testReturnCommitsSelectedAndEatsKeyWhenComposing() {
        XCTAssertEqual(classify("\r", composing: true), .commitSelectedAndEat)
    }

    func testShiftReturnCommitsRawWhenComposing() {
        XCTAssertEqual(
            KeyEventRouter.classify(characters: "\r", modifierFlags: .shift, hasComposition: true),
            .commitRaw
        )
        XCTAssertEqual(
            KeyEventRouter.classify(characters: "\r", modifierFlags: .shift, hasComposition: false),
            .passThrough
        )
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

    func testLeftRightMoveCaretInsteadOfCommitting() {
        XCTAssertEqual(classify("\u{F702}", composing: true), .moveCaret(-1))
        XCTAssertEqual(classify("\u{F703}", composing: true), .moveCaret(+1))
    }

    func testLeftRightPassThroughWhenIdle() {
        XCTAssertEqual(classify("\u{F702}", composing: false), .passThrough)
        XCTAssertEqual(classify("\u{F703}", composing: false), .passThrough)
    }

    func testPunctuationCommitsAndInsertsWhenComposing() {
        XCTAssertEqual(classify(",", composing: true), .commitSelectedThenInsert(","))
        XCTAssertEqual(classify(".", composing: true), .commitSelectedThenInsert("."))
    }

    func testBackslashAndAsteriskAppendInsteadOfCommitMidComposition() {
        // `\` and `*` are halant / anusvara sigils — they must enter the
        // buffer so the rule transliterator can fold them, not trigger
        // the punctuation commit-then-insert rule.
        XCTAssertEqual(classify("\\", composing: true), .appendChar("\\"))
        XCTAssertEqual(classify("*",  composing: true), .appendChar("*"))
        // In idle they pass through normally — the InputController
        // handles direct-insert for already-committed words.
        XCTAssertEqual(classify("\\", composing: false), .passThrough)
        XCTAssertEqual(classify("*",  composing: false), .passThrough)
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

    // MARK: - Caps Lock = English pass-through

    func testCapsLockLetterPassesThroughWhenIdle() {
        XCTAssertEqual(capsLock("N", composing: false), .passThrough)
        XCTAssertEqual(capsLock("N", composing: false, shift: true), .passThrough)
    }

    func testCapsLockLetterCommitsWordInProgressThenInserts() {
        XCTAssertEqual(capsLock("U", composing: true), .commitSelectedThenInsert("U"))
    }

    func testCapsLockKeepsCompositionControlKeys() {
        // A word started before Caps Lock went on can still be finished.
        XCTAssertEqual(capsLock(" ", composing: true), .commitSelected)
        XCTAssertEqual(capsLock("\u{8}", composing: true), .backspace)
        XCTAssertEqual(capsLock("1", composing: true), .selectIndex(0))
    }

    func testEnglishModeFollowsCapsLockOnly() {
        XCTAssertTrue(KeyEventRouter.isEnglishMode([.capsLock]))
        XCTAssertTrue(KeyEventRouter.isEnglishMode([.capsLock, .shift]))
        XCTAssertFalse(KeyEventRouter.isEnglishMode([.shift]))
        XCTAssertFalse(KeyEventRouter.isEnglishMode([]))
    }

    private func capsLock(_ chars: String, composing: Bool, shift: Bool = false) -> KeyAction {
        KeyEventRouter.classify(
            characters: chars,
            modifierFlags: shift ? [.capsLock, .shift] : [.capsLock],
            hasComposition: composing
        )
    }

    private func classify(_ chars: String, composing: Bool) -> KeyAction {
        KeyEventRouter.classify(
            characters: chars,
            modifierFlags: [],
            hasComposition: composing
        )
    }
}
