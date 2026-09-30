import Foundation
import AppKit
@preconcurrency import InputMethodKit

@objc(NepaliIMEController)
public final class InputController: IMKInputController, @unchecked Sendable {
    // IMK guarantees calls on the main thread. We bridge via MainActor.assumeIsolated
    // because overrides of unannotated parent methods inherit non-isolation regardless
    // of any @MainActor decoration on this subclass.
    nonisolated(unsafe) private var _state: CompositionState = .idle
    nonisolated(unsafe) private var _panel: CandidateWindow?
    nonisolated(unsafe) private var _lookupToken: UInt64 = 0

    public override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        MainActor.assumeIsolated {
            self._panel = CandidateWindow()
            IMEServices.shared.bootstrap()
            Log.controller.debug("InputController init")
        }
    }

    // MARK: - IMK overrides

    public override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        let clientBox = ClientBox(client: sender)
        let eventBox = EventBox(event: event)
        return MainActor.assumeIsolated {
            self.handleOnMain(event: eventBox.event, client: clientBox.client)
        }
    }

    public override func deactivateServer(_ sender: Any!) {
        let box = ClientBox(client: sender)
        MainActor.assumeIsolated {
            Log.controller.debug("deactivateServer — committing buffer")
            self.commitSelectedAndReset(client: box.client)
        }
    }

    public override func cancelComposition() {
        let box = ClientBox(client: client())
        MainActor.assumeIsolated {
            self.clearMarkedText(client: box.client)
            self._state = .idle
            self._panel?.hide()
        }
    }

    public override func commitComposition(_ sender: Any!) {
        let box = ClientBox(client: sender)
        MainActor.assumeIsolated {
            self.commitSelectedAndReset(client: box.client)
        }
    }

    public override func menu() -> NSMenu! {
        let box: SendableBox<NSMenu> = MainActor.assumeIsolated { SendableBox(self.buildMenu()) }
        return box.value
    }

    public override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    // MARK: - Main-actor work

    @MainActor
    private func handleOnMain(event: NSEvent?, client sender: Any?) -> Bool {
        guard let event, event.type == .keyDown else { return false }

        // Idle-state period-to-danda auto-conversion. The decision is
        // entirely positional: we look at the document directly to see
        // whether the caret is sitting at the end of a Devanagari word
        // (or one space past it). No commit-history tracking required —
        // works for words pasted in or typed in earlier sessions, not
        // just freshly-committed ones.
        // Caps Lock (English mode) skips all of these: digits, `.`, `\` and
        // `*` go through untouched.
        if !_state.hasBuffer, !KeyEventRouter.isEnglishMode(event.modifierFlags) {
            let chars = event.characters ?? ""
            // Period-to-danda: `.` after a Devanagari word (or one space
            // past) becomes `।`.
            if chars == ".", cursorIsAtEndOfDevanagariWord(client: sender) {
                insertCommitted("।", client: sender)
                return true
            }
            // Direct-insert combining marks for already-committed words:
            // `\` adds halant, `*` adds anusvara to the previous akshara.
            // Only fire when the cursor is RIGHT AFTER a Devanagari char
            // (no space-past relaxation — combining marks attach
            // directly to the akshara, not across whitespace).
            if chars == "\\", charImmediatelyBeforeCursorIsDevanagari(client: sender) {
                insertCommitted("्", client: sender)
                return true
            }
            if chars == "*", charImmediatelyBeforeCursorIsDevanagari(client: sender) {
                insertCommitted("ं", client: sender)
                return true
            }
            // Devanagari digits: any ASCII 0-9 typed in idle becomes
            // its Devanagari counterpart ०-९. Always converts when the
            // Nepali IME is the active input source — to type ASCII
            // digits, switch to ABC momentarily.
            if chars.count == 1,
               let digit = chars.first?.wholeNumberValue, (0...9).contains(digit) {
                insertCommitted(Self.devanagariDigit(digit), client: sender)
                return true
            }
        }

        let action = KeyEventRouter.classify(event: event, hasComposition: _state.hasBuffer)
        return process(action: action, client: sender)
    }

    /// Returns the Devanagari digit glyph (०-९) for the given decimal value 0-9.
    private static func devanagariDigit(_ d: Int) -> String {
        let glyphs: [String] = ["०", "१", "२", "३", "४", "५", "६", "७", "८", "९"]
        return glyphs[d]
    }

    /// Reads the 1–2 characters immediately preceding the caret from the
    /// client document and returns true if `.` typed here should become
    /// the danda `।`. The rule:
    ///   - char[-1] is in the Devanagari block AND is not itself a danda → fire
    ///   - char[-1] is whitespace AND char[-2] is Devanagari (and not a danda) → fire
    ///   - otherwise → don't fire
    ///
    /// Excluding the danda from the "Devanagari" predicate prevents
    /// `..` from becoming `।।` (the second `.` sees the just-inserted
    /// danda before the caret and falls through as a literal period).
    /// Returns false if the client doesn't support `selectedRange`/
    /// `string(from:actualRange:)` (Electron, some Java apps), so periods
    /// pass through untouched in those clients.
    @MainActor
    private func cursorIsAtEndOfDevanagariWord(client: Any?) -> Bool {
        guard let textInput = client as? IMKTextInput else { return false }
        let sel = textInput.selectedRange()
        guard sel.location != NSNotFound, sel.location > 0 else { return false }

        let start = max(0, sel.location - 2)
        let len   = sel.location - start
        var actual = NSRange(location: 0, length: 0)
        guard let s = textInput.string(
            from: NSRange(location: start, length: len),
            actualRange: &actual
        ) else { return false }

        let chars = Array(s)
        guard let last = chars.last else { return false }

        if Self.isDevanagariNonDanda(last) { return true }
        if last.isWhitespace, chars.count >= 2,
           Self.isDevanagariNonDanda(chars[chars.count - 2]) {
            return true
        }
        return false
    }

    /// True for any character in the Devanagari block U+0900–U+097F
    /// EXCEPT the danda U+0964 itself (so `..` doesn't become `।।`).
    private static func isDevanagariNonDanda(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x0900...0x097F).contains(v) && v != 0x0964
    }

    /// Used by the idle `\`/`*` direct-insert paths: returns true when
    /// the character immediately before the caret is in the Devanagari
    /// block (any of it — combining marks can attach to anything we ever
    /// produce). Stricter than `cursorIsAtEndOfDevanagariWord` because
    /// halant/anusvara must touch the akshara directly, not across a
    /// space.
    @MainActor
    private func charImmediatelyBeforeCursorIsDevanagari(client: Any?) -> Bool {
        guard let textInput = client as? IMKTextInput else { return false }
        let sel = textInput.selectedRange()
        guard sel.location != NSNotFound, sel.location > 0 else { return false }

        var actual = NSRange(location: 0, length: 0)
        guard let s = textInput.string(
            from: NSRange(location: sel.location - 1, length: 1),
            actualRange: &actual
        ), let c = s.first, let scalar = c.unicodeScalars.first else {
            return false
        }
        return (0x0900...0x097F).contains(scalar.value)
    }

    @MainActor
    private func process(action: KeyAction, client: Any?) -> Bool {
        switch action {
        case .appendChar(let ch):
            appendCharacter(ch, client: client)
            return true
        case .backspace:
            backspace(client: client)
            return true
        case .commitSelected:
            commitSelectedAndReset(client: client)
            return false
        case .commitSelectedAndEat:
            commitSelectedAndReset(client: client)
            return true
        case .commitRaw:
            commitRawAndReset(client: client)
            return true
        case .cancel:
            clearMarkedText(client: client)
            _state = .idle
            _panel?.hide()
            return true
        case .selectIndex(let i):
            commitCandidate(at: i, client: client)
            return true
        case .moveSelection(let delta):
            moveSelection(by: delta)
            return true
        case .moveCaret(let delta):
            moveCaret(by: delta, client: client)
            return true
        case .commitSelectedThenInsert(let s):
            commitSelectedAndReset(client: client)
            // After committing, look at the document to decide what
            // punctuation/digit to insert. Works uniformly for the
            // candidate-commit path (caret after Devanagari → convert)
            // and the raw-fallback path (caret after Latin → literal).
            if s == "." && cursorIsAtEndOfDevanagariWord(client: client) {
                insertCommitted("।", client: client)
            } else if s.count == 1,
                      let digit = s.first?.wholeNumberValue, (0...9).contains(digit) {
                // Mid-composition digit (only `0` reaches this path —
                // 1-9 are candidate selectors). Always converts to
                // the Devanagari digit, matching the idle-state rule.
                insertCommitted(Self.devanagariDigit(digit), client: client)
            } else {
                insertCommitted(s, client: client)
            }
            return true
        case .passThrough:
            return false
        }
    }

    @MainActor
    private func appendCharacter(_ ch: Character, client: Any?) {
        var newBuffer = CompositionBuffer()
        if case .composing(let b, _, _) = _state {
            newBuffer = b
        }
        newBuffer.insert(ch)
        _state = .composing(buffer: newBuffer, candidates: [], selectedIndex: 0)
        showMarkedText(buffer: newBuffer, client: client)
        scheduleLookup(buffer: newBuffer.text, client: client)
    }

    @MainActor
    private func backspace(client: Any?) {
        guard case .composing(var buffer, _, _) = _state else { return }
        // Caret at the start: nothing before it to delete; keep composing.
        guard buffer.caret > 0 else { return }
        buffer.deleteBackward()
        if buffer.isEmpty {
            clearMarkedText(client: client)
            _state = .idle
            _panel?.hide()
            return
        }
        _state = .composing(buffer: buffer, candidates: [], selectedIndex: 0)
        showMarkedText(buffer: buffer, client: client)
        scheduleLookup(buffer: buffer.text, client: client)
    }

    @MainActor
    private func moveCaret(by delta: Int, client: Any?) {
        guard case .composing(var buffer, let candidates, let selected) = _state else { return }
        buffer.moveCaret(by: delta)
        // The buffer text is unchanged, so the candidates stay valid.
        _state = .composing(buffer: buffer, candidates: candidates, selectedIndex: selected)
        showMarkedText(buffer: buffer, client: client)
    }

    @MainActor
    private func commitCandidate(at index: Int, client: Any?) {
        guard case .composing(let buffer, let candidates, _) = _state else { return }
        guard index >= 0, index < candidates.count else {
            commitRawAndReset(client: client)
            return
        }
        let chosen = candidates[index]
        insertCommitted(chosen.output, client: client)
        if let engine = IMEServices.shared.engine {
            let input = buffer.text
            let output = chosen.output
            let source = chosen.source
            Task { await engine.recordSelection(input: input, output: output, source: source) }
        }
        _state = .idle
        _panel?.hide()
    }

    @MainActor
    private func commitSelectedAndReset(client: Any?) {
        guard case .composing(let buffer, let candidates, let selected) = _state else { return }
        if !candidates.isEmpty, selected < candidates.count {
            commitCandidate(at: selected, client: client)
        } else {
            insertCommitted(buffer.text, client: client)
            _state = .idle
            _panel?.hide()
        }
    }

    @MainActor
    private func commitRawAndReset(client: Any?) {
        guard case .composing(let buffer, _, _) = _state else { return }
        insertCommitted(buffer.text, client: client)
        _state = .idle
        _panel?.hide()
    }

    @MainActor
    private func moveSelection(by delta: Int) {
        guard case .composing(let buffer, let candidates, let selected) = _state else { return }
        guard !candidates.isEmpty else { return }
        let newIndex = max(0, min(candidates.count - 1, selected + delta))
        _state = .composing(buffer: buffer, candidates: candidates, selectedIndex: newIndex)
        _panel?.updateSelection(newIndex)
    }

    @MainActor
    private func scheduleLookup(buffer: String, client: Any?) {
        guard let engine = IMEServices.shared.engine else { return }
        _lookupToken &+= 1
        let token = _lookupToken
        let captured = ClientBox(client: client)
        Task { [weak self] in
            let results = await engine.candidates(for: buffer, limit: 9)
            await MainActor.run {
                guard let self else { return }
                guard self._lookupToken == token else { return }
                guard case .composing(let current, _, _) = self._state, current.text == buffer else { return }
                self._state = .composing(buffer: current, candidates: results, selectedIndex: 0)
                if results.isEmpty {
                    self._panel?.hide()
                } else {
                    let caret = self.caretRect(in: captured.client)
                    self._panel?.show(candidates: results, selectedIndex: 0, near: caret)
                }
            }
        }
    }

    @MainActor
    private func showMarkedText(buffer: CompositionBuffer, client: Any?) {
        guard let textInput = client as? IMKTextInput else { return }
        // Marked text stays as the raw Roman buffer while composing — the
        // user sees what they typed. Devanagari renderings live in the
        // candidate window (including the rule-transliterated fallback)
        // and only land in the document when a candidate is committed.
        let attributed = NSAttributedString(
            string: buffer.text,
            attributes: [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: NSColor.labelColor,
                .foregroundColor: NSColor.labelColor,
            ]
        )
        textInput.setMarkedText(
            attributed,
            selectionRange: NSRange(location: buffer.caretUTF16Offset, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    @MainActor
    private func clearMarkedText(client: Any?) {
        guard let textInput = client as? IMKTextInput else { return }
        textInput.setMarkedText(
            "",
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    @MainActor
    private func insertCommitted(_ text: String, client: Any?) {
        guard let textInput = client as? IMKTextInput else { return }
        textInput.insertText(
            text,
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    @MainActor
    private func caretRect(in client: Any?) -> NSRect {
        guard let textInput = client as? IMKTextInput else { return .zero }
        var lineRect = NSRect.zero
        _ = textInput.attributes(
            forCharacterIndex: 0,
            lineHeightRectangle: &lineRect
        )
        return lineRect
    }

    @MainActor
    private func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "Nepali IME")
        // Informational header (no action, so AppKit shows it disabled).
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let about = NSMenuItem(
            title: version.map { "Nepali IME \($0)" } ?? "Nepali IME",
            action: nil,
            keyEquivalent: ""
        )
        let openUserDict = NSMenuItem(
            title: "Open User Dictionary…",
            action: #selector(openUserDictionary(_:)),
            keyEquivalent: ""
        )
        openUserDict.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        menu.addItem(openUserDict)
        return menu
    }

    @objc private func openUserDictionary(_ sender: Any?) {
        let url = Paths.userDictionary
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
        }
        NSWorkspace.shared.open(url)
    }
}

/// Wrapper to carry the IMK client proxy across an actor boundary without Sendable warnings.
/// The client is only accessed back on the main actor where IMK guarantees we are.
private struct ClientBox: @unchecked Sendable {
    let client: Any?
}

private struct EventBox: @unchecked Sendable {
    let event: NSEvent?
}

/// Generic unchecked-Sendable wrapper for return values from MainActor.assumeIsolated
/// when the underlying type (e.g. NSMenu) isn't itself Sendable but the value is
/// constructed and consumed on the same main-actor invocation.
private struct SendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
