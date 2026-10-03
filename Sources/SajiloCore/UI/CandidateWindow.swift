import Foundation
import AppKit
import SwiftUI

@MainActor
public final class CandidateWindow {
    private let panel: NSPanel
    private let model = CandidateModel()
    private let hostingView: NSHostingView<CandidateView>

    public init() {
        let view = CandidateView(model: model)
        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = false

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.contentView = host
        panel.ignoresMouseEvents = true

        self.panel = panel
        self.hostingView = host
    }

    public var isVisible: Bool { panel.isVisible }

    public func show(candidates: [Candidate], selectedIndex: Int, near caret: NSRect) {
        model.candidates = candidates
        model.selectedIndex = selectedIndex
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let size = NSSize(
            width: max(160, fitting.width),
            height: max(28, fitting.height)
        )
        panel.setContentSize(size)
        let origin = PanelPositioner.origin(forPanelSize: size, below: caret)
        panel.setFrameOrigin(origin)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    public func hide() {
        if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    public func updateSelection(_ index: Int) {
        model.selectedIndex = index
    }
}
