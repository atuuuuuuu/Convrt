import SwiftUI
import AppKit

struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "tray.full.fill").foregroundColor(Theme.primary)
                Text("Shelf").font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                if !model.urls.isEmpty { Button("Clear") { model.clear() }.buttonStyle(.borderless).font(.caption) }
                Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                    .help("Hide the shelf")
            }

            if model.urls.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 26)).foregroundColor(Theme.glow)
                    Text("Drop files here to keep them handy, then drag them out into any app.")
                        .font(.caption).multilineTextAlignment(.center).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.urls, id: \.self) { url in row(url) }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 230, height: 320)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.primary.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .padding(12)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            FileDrop.urls(from: providers) { model.add($0) }
            return true
        }
    }

    private func row(_ url: URL) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24)
            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle).font(.system(size: 12))
            Spacer(minLength: 2)
            Button { model.remove(url) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).foregroundColor(.secondary)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.ice.opacity(0.7)))
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL) }
    }
}

/// A small always-on-top panel at the screen edge. Non-activating, so it never steals focus from the app you drag into.
final class ShelfController {
    static let shared = ShelfController()

    private let model = ShelfModel()
    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 254, height: 344),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.contentView = NSHostingView(rootView: ShelfView(model: model, onClose: { [weak self] in self?.hide() }))
        return p
    }()

    var isVisible: Bool { panel.isVisible }

    func add(_ urls: [URL]) {
        model.pruneMissing()
        model.add(urls)
        show()
    }

    func show() {
        if !panel.isVisible, let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: area.maxX - panel.frame.width - 6, y: area.midY - panel.frame.height / 2))
        }
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }

    func toggle() { isVisible ? hide() : show() }
}
