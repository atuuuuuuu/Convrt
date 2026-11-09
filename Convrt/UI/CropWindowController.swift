import AppKit
import SwiftUI

/// Opens the cropper for each dragged image in turn and collects the results.
/// Main thread only.
final class CropWindowController: NSObject, NSWindowDelegate {
    static let shared = CropWindowController()

    private var window: NSWindow?
    private var queue: [URL] = []
    private var total = 0
    private var summary = ConversionSummary()
    private var completion: ((ConversionSummary) -> Void)?
    private var closingByCode = false

    func run(urls: [URL], completion: @escaping (ConversionSummary) -> Void) {
        if window != nil { closeWindow(); finish() }      // an unfinished earlier session just ends
        queue = urls
        total = urls.count
        summary = ConversionSummary()
        self.completion = completion
        showNext()
    }

    private func showNext() {
        guard !queue.isEmpty else { finish(); return }
        let url = queue.removeFirst()
        do {
            let image = try ImageTools.loadForDisplay(url)
            let position = total > 1 ? "\(total - queue.count) of \(total)" : ""
            let model = CropModel(url: url, image: image, position: position)
            let view = CropEditorView(model: model, hasMore: !queue.isEmpty,
                                      onCrop: { [weak self] in self?.crop(model) },
                                      onSkip: { [weak self] in self?.skip() },
                                      onCancel: { [weak self] in self?.cancel() })
            present(view, title: "Crop — \(url.lastPathComponent)")
        } catch {
            summary.failures.append(ConversionFailure(name: url.lastPathComponent, message: error.localizedDescription))
            showNext()
        }
    }

    private func crop(_ model: CropModel) {
        let rect = model.geometry.pixelRect
        let url = model.url
        closeWindow()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try ImageTools.crop(url, to: rect) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let out): self.summary.outputs.append(out)
                case .failure(let error):
                    self.summary.failures.append(ConversionFailure(name: url.lastPathComponent, message: error.localizedDescription))
                }
                self.showNext()
            }
        }
    }

    private func skip() {
        closeWindow()
        showNext()
    }

    private func cancel() {
        closeWindow()
        queue.removeAll()
        finish()
    }

    private func finish() {
        let done = completion
        completion = nil
        if summary.outputs.isEmpty && summary.failures.isEmpty { summary.message = "Crop cancelled" }
        done?(summary)
    }

    // MARK: - Window

    private func present(_ view: CropEditorView, title: String) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 660),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.contentView = NSHostingView(rootView: view)
        w.contentMinSize = NSSize(width: 640, height: 480)
        w.title = title
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.level = .floating
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func closeWindow() {
        closingByCode = true
        window?.close()
        window = nil
        closingByCode = false
    }

    /// The user clicked the red close button: treat it as Cancel.
    func windowWillClose(_ notification: Notification) {
        guard !closingByCode else { return }
        window = nil
        queue.removeAll()
        finish()
    }
}
