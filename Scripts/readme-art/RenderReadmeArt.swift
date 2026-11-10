import XCTest
import SwiftUI
@testable import Convrt

/// Temporary: renders README art from the real RadialWheelView. Not part of the app's tests.
final class RenderReadmeArt: XCTestCase {
    let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ART_OUT"] ?? "/tmp/convrt-art")
    let logo = ProcessInfo.processInfo.environment["ART_LOGO"] ?? ""

    func model(_ kind: WheelKind, highlight: Int) -> WheelModel {
        let m = WheelModel()
        let urls = [URL(fileURLWithPath: "/tmp/photo.png")]
        m.kind = kind
        m.availableKinds = [.convert, .tools, .actions]
        m.items = WheelCatalog.items(for: kind, urls: urls)
        m.highlighted = highlight
        m.visible = true
        return m
    }

    @MainActor func save<V: View>(_ view: V, _ name: String, scale: CGFloat = 2) throws {
        let r = ImageRenderer(content: view)
        r.scale = scale
        r.isOpaque = false
        guard let cg = r.cgImage else { return XCTFail("render \(name)") }
        let rep = NSBitmapImageRep(cgImage: cg)
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    }

    @MainActor func testRender() throws {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let convert = model(.convert, highlight: 1)
        let tools = model(.tools, highlight: 4)
        let actions = model(.actions, highlight: 0)

        // One strip with all three wheels, transparent background: never wraps on GitHub.
        let card = LinearGradient(colors: [Color(red: 0.07, green: 0.16, blue: 0.36), Theme.navy],
                                  startPoint: .top, endPoint: .bottom)
        func caption(_ title: String, _ sub: String) -> some View {
            VStack(spacing: 2) {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                Text(sub).font(.system(size: 13)).foregroundColor(.white.opacity(0.65))
            }
        }
        try save(HStack(spacing: 0) {
            VStack(spacing: -14) { RadialWheelView(model: convert); caption("Convert", "Hold Shift") }
            VStack(spacing: -14) { RadialWheelView(model: tools); caption("Tools", "Tap Option, or Command") }
            VStack(spacing: -14) { RadialWheelView(model: actions); caption("Actions", "Tap Option again, or Control") }
        }
        .padding(.horizontal, 10).padding(.bottom, 26)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(card)), "wheels.png")

        // Banner 1600x600 (rendered at 800x300 @2x).
        let blue = Theme.primary, navy = Theme.navy
        let banner = ZStack {
            LinearGradient(colors: [Color(red: 0.12, green: 0.36, blue: 0.95), navy],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    if let img = NSImage(contentsOfFile: logo) {
                        Image(nsImage: img).resizable().scaledToFit().frame(height: 44)
                    }
                    Text("Convrt").font(.system(size: 58, weight: .bold, design: .rounded)).foregroundColor(.white)
                    Text("Drag a file. Hold Shift. Drop it on a slice.").fixedSize()
                        .font(.system(size: 20, weight: .semibold)).foregroundColor(.white)
                    Text("Convert, edit and share files from the menu bar.").fixedSize()
                        .font(.system(size: 15)).foregroundColor(.white.opacity(0.75))
                    HStack(spacing: 8) {
                        ForEach(["100% offline", "No accounts", "Native macOS"], id: \.self) { t in
                            Text(t).font(.system(size: 12, weight: .medium)).foregroundColor(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(.white.opacity(0.14)))
                                .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
                        }
                    }.padding(.top, 6)
                }
                .padding(.leading, 56)
                Spacer()
                RadialWheelView(model: model(.convert, highlight: 1))
                    .scaleEffect(0.82)
                    .frame(width: 300)
                    .padding(.trailing, 30)
            }
        }
        .frame(width: 800, height: 300)
        _ = blue
        try save(banner, "banner.png")

        // Social preview 1280x640 (640x320 @2x).
        let social = ZStack {
            LinearGradient(colors: [Color(red: 0.12, green: 0.36, blue: 0.95), navy],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    if let img = NSImage(contentsOfFile: logo) {
                        Image(nsImage: img).resizable().scaledToFit().frame(height: 36)
                    }
                    Text("Convrt").font(.system(size: 50, weight: .bold, design: .rounded)).foregroundColor(.white)
                    Text("Offline file converter\nfor the Mac menu bar")
                        .font(.system(size: 18, weight: .medium)).foregroundColor(.white.opacity(0.85))
                }.padding(.leading, 44)
                Spacer()
                RadialWheelView(model: model(.tools, highlight: 4)).scaleEffect(0.78).padding(.trailing, 4)
            }
        }
        .frame(width: 640, height: 320)
        try save(social, "social-preview.png")
    }
}
