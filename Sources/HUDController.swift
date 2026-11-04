import AppKit
import SwiftUI

final class HUDModel: ObservableObject {
    @Published var working = true
    @Published var title = ""
    @Published var onReveal: (() -> Void)? = nil
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 12) {
            if model.working {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color(red: 250 / 255, green: 75 / 255, blue: 0))
            }
            Text(model.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(2)
            Spacer(minLength: 4)
            if let reveal = model.onReveal {
                Button("Reveal in Finder", action: reveal)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 250 / 255, green: 75 / 255, blue: 0))
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: HUDPanel.size.width, height: HUDPanel.size.height)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.black.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .padding(14)   // room for the shadow
    }
}

private final class HUDPanel: NSPanel {
    static let size = CGSize(width: 360, height: 64)
    static let margin: CGFloat = 14

    init(contentView view: NSView) {
        let total = NSRect(x: 0, y: 0,
                           width: Self.size.width + Self.margin * 2,
                           height: Self.size.height + Self.margin * 2)
        super.init(contentRect: total,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = view
    }

    override var canBecomeKey: Bool { true }
}

/// Small "Converting… / Done, Reveal in Finder" card in the top-right corner.
final class HUDController {
    private let model = HUDModel()
    private lazy var panel = HUDPanel(contentView: NSHostingView(rootView: HUDView(model: model)))
    private var hideWork: DispatchWorkItem?

    func showWorking(count: Int, format: OutputFormat) {
        model.working = true
        model.title = "Converting \(count) file\(count == 1 ? "" : "s") to \(format.label)…"
        model.onReveal = nil
        present(autoHideAfter: nil)
    }

    func showDone(outputs: [URL]) {
        model.working = false
        model.title = "Done"
        model.onReveal = { [weak self] in
            NSWorkspace.shared.activateFileViewerSelecting(outputs)
            self?.hide()
        }
        present(autoHideAfter: 8)
    }

    func hide() {
        hideWork?.cancel()
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }

    private func present(autoHideAfter seconds: TimeInterval?) {
        hideWork?.cancel()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: area.maxX - size.width - 4, y: area.maxY - size.height - 4))
        }

        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }

        if let seconds {
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
    }
}
