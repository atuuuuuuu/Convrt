import SwiftUI
import AppKit

/// The wheels as a window: drop files, pick Convert / Tools / Actions, click what you want.
/// Works without the Accessibility and Input Monitoring permissions.
struct DropZoneView: View {
    @ObservedObject var model: DropZoneModel
    let onRun: (WheelItem, [URL]) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 14) {
            if model.urls.isEmpty { dropArea } else { content }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 400)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            FileDrop.urls(from: providers) { model.ingest($0) }
            return true
        }
    }

    private var dropArea: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(targeted ? Theme.primary : Theme.glow)
            Text("Drop files here").font(.system(size: 18, weight: .bold, design: .rounded))
            Text("Convert, edit or send them. Holding Shift while you drag anywhere does the same thing.")
                .font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(targeted ? Theme.primary : Theme.glow.opacity(0.6),
                              style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.ice.opacity(targeted ? 0.9 : 0.5)))
        )
    }

    private var content: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.urls.count) file\(model.urls.count == 1 ? "" : "s")")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(model.urls.prefix(3).map(\.lastPathComponent).joined(separator: ", ")
                         + (model.urls.count > 3 ? " …" : ""))
                        .font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Clear") { model.clear() }
            }

            Picker("", selection: Binding(get: { model.kind }, set: { model.select($0) })) {
                ForEach(model.availableKinds, id: \.rawValue) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                    ForEach(model.items) { item in
                        Button {
                            let urls = model.urls
                            model.clear()
                            onRun(item, urls)
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: model.kind == .convert ? "arrow.triangle.2.circlepath" : item.symbol)
                                    .font(.system(size: 20, weight: .semibold))
                                Text(item.label).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
                            }
                            .foregroundColor(Theme.navy)
                            .frame(maxWidth: .infinity, minHeight: 74)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.ice))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.primary.opacity(0.25)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

final class DropZoneController {
    private let model = DropZoneModel()
    private var window: NSWindow?
    var onRun: ((WheelItem, [URL]) -> Void)?

    func show() {
        if window == nil {
            let view = DropZoneView(model: model) { [weak self] item, urls in self?.onRun?(item, urls) }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Convrt Drop Zone"
            w.styleMask = [.titled, .closable, .resizable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 500, height: 440))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
