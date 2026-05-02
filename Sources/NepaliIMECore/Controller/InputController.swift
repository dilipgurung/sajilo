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
    /// Set whenever a Devanagari candidate is committed; consulted by the
    /// `.` → `।` (danda) auto-conversion. `nil` means "no recent Nepali
    /// commit" — keeps period-as-period behavior when typing English.
    nonisolated(unsafe) private var _lastNepaliCommitTime: Date? = nil
    private static let dandaConversionWindow: TimeInterval = 1.5

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
        MainActor.assumeIsolated {
            self.clearMarkedText(client: nil)
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

        // Idle-state danda auto-conversion: if a `.` arrives soon after a
        // Devanagari commit (Tab/Space/digit/etc finished a candidate),
        // swap it for `।` (the Nepali full stop). After the window expires
        // the period passes through unchanged so users can type English
        // sentences while leaving the input source active.
        if !_state.hasBuffer, event.charactersIgnoringModifiers == "." {
            let mapped = mappedPunctuation(".")
            if mapped != "." {
                insertCommitted(mapped, client: sender)
                return true
            }
        }

        let action = KeyEventRouter.classify(event: event, hasComposition: _state.hasBuffer)
        return process(action: action, client: sender)
    }

    /// Returns `।` if `s` is `.` and a Devanagari candidate was committed
    /// within `dandaConversionWindow`. Clears the timestamp on a successful
    /// swap so a second `.` immediately after passes through unchanged
    /// (avoids `..` → `।।`).
    @MainActor
    private func mappedPunctuation(_ s: String) -> String {
        guard s == ".",
              let last = _lastNepaliCommitTime,
              Date().timeIntervalSince(last) <= Self.dandaConversionWindow
        else { return s }
        _lastNepaliCommitTime = nil
        return "।"
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
        case .commitSelectedThenInsert(let s):
            commitSelectedAndReset(client: client)
            insertCommitted(mappedPunctuation(s), client: client)
            return true
        case .passThrough:
            return false
        }
    }

    @MainActor
    private func appendCharacter(_ ch: Character, client: Any?) {
        var newBuffer: String
        if case .composing(let b, _, _) = _state {
            newBuffer = b + String(ch)
        } else {
            newBuffer = String(ch)
        }
        _state = .composing(buffer: newBuffer, candidates: [], selectedIndex: 0)
        showMarkedText(buffer: newBuffer, client: client)
        scheduleLookup(buffer: newBuffer, client: client)
    }

    @MainActor
    private func backspace(client: Any?) {
        guard case .composing(let buffer, _, _) = _state else { return }
        let trimmed = String(buffer.dropLast())
        if trimmed.isEmpty {
            clearMarkedText(client: client)
            _state = .idle
            _panel?.hide()
            return
        }
        _state = .composing(buffer: trimmed, candidates: [], selectedIndex: 0)
        showMarkedText(buffer: trimmed, client: client)
        scheduleLookup(buffer: trimmed, client: client)
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
            let input = buffer
            let output = chosen.output
            let source = chosen.source
            Task { await engine.recordSelection(input: input, output: output, source: source) }
        }
        _lastNepaliCommitTime = Date()
        _state = .idle
        _panel?.hide()
    }

    @MainActor
    private func commitSelectedAndReset(client: Any?) {
        guard case .composing(let buffer, let candidates, let selected) = _state else { return }
        if !candidates.isEmpty, selected < candidates.count {
            commitCandidate(at: selected, client: client)
        } else {
            insertCommitted(buffer, client: client)
            _state = .idle
            _panel?.hide()
        }
    }

    @MainActor
    private func commitRawAndReset(client: Any?) {
        guard case .composing(let buffer, _, _) = _state else { return }
        insertCommitted(buffer, client: client)
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
                guard case .composing(let currentBuffer, _, _) = self._state, currentBuffer == buffer else { return }
                self._state = .composing(buffer: buffer, candidates: results, selectedIndex: 0)
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
    private func showMarkedText(buffer: String, client: Any?) {
        guard let textInput = client as? IMKTextInput else { return }
        // Marked text stays as the raw Roman buffer while composing — the
        // user sees what they typed. Devanagari renderings live in the
        // candidate window (including the rule-transliterated fallback)
        // and only land in the document when a candidate is committed.
        let attributed = NSAttributedString(
            string: buffer,
            attributes: [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: NSColor.labelColor,
                .foregroundColor: NSColor.labelColor,
            ]
        )
        textInput.setMarkedText(
            attributed,
            selectionRange: NSRange(location: (buffer as NSString).length, length: 0),
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
        let about = NSMenuItem(title: "About Nepali IME", action: nil, keyEquivalent: "")
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
