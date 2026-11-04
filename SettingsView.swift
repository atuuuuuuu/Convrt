import SwiftUI
import AppKit
import ServiceManagement

private let brandOrange = Color(red: 250 / 255, green: 75 / 255, blue: 0)

struct SettingsView: View {
    @AppStorage(AppSettings.Key.convertTrigger) private var trigger = TriggerKey.shift.rawValue
    @AppStorage(AppSettings.Key.outputMode) private var outputMode = OutputMode.sameFolder.rawValue
    @AppStorage(AppSettings.Key.customOutputPath) private var customPath = ""
    @AppStorage(AppSettings.Key.deleteOriginal) private var deleteOriginal = false
    @AppStorage(AppSettings.Key.imageQuality) private var quality = 0.85
    @AppStorage(AppSettings.Key.playSound) private var playSound = true

    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var accessibilityOK = PermissionManager.accessibilityGranted
    @State private var inputMonitoringOK = PermissionManager.inputMonitoringGranted

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section("General") {
                    Picker("Hold to show the Convert wheel", selection: $trigger) {
                        ForEach(TriggerKey.allCases) { key in
                            Text(key.title).tag(key.rawValue)
                        }
                    }
                    Toggle("Launch at login", isOn: launchBinding)
                    Toggle("Play a sound when done", isOn: $playSound)
                }

                Section("Output") {
                    Picker("Save converted files", selection: $outputMode) {
                        Text("Next to the original").tag(OutputMode.sameFolder.rawValue)
                        Text("In a chosen folder").tag(OutputMode.customFolder.rawValue)
                    }
                    if outputMode == OutputMode.customFolder.rawValue {
                        HStack {
                            Text(customPath.isEmpty ? "No folder chosen" : customPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Choose…", action: chooseFolder)
                        }
                    }
                    Toggle("Move the original to the Trash after converting", isOn: $deleteOriginal)
                }

                Section("Quality") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Lossy formats (JPG, HEIC)")
                            Spacer()
                            Text("\(Int((quality * 100).rounded()))%")
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $quality, in: 0.1...1.0, step: 0.05)
                    }
                }

                Section("Permissions") {
                    permissionRow("Accessibility", ok: accessibilityOK)
                    permissionRow("Input Monitoring", ok: inputMonitoringOK)
                    Button("Check Permissions…") { PermissionManager.check(showWhenGranted: true) }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 460, height: 640)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in refresh() }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 14) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 36)
                .foregroundColor(brandOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Convrt")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Version \(version) · everything stays on your Mac")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    private func permissionRow(_ name: String, ok: Bool) -> some View {
        HStack {
            Text(name)
            Spacer()
            Label(ok ? "Granted" : "Not granted",
                  systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(ok ? .green : .orange)
        }
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                do {
                    if newValue { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Couldn’t change Launch at Login"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
                launchAtLogin = (SMAppService.mainApp.status == .enabled)
            }
        )
    }

    // MARK: - Actions

    private func refresh() {
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
        accessibilityOK = PermissionManager.accessibilityGranted
        inputMonitoringOK = PermissionManager.inputMonitoringGranted
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            customPath = url.path
            outputMode = OutputMode.customFolder.rawValue
        }
    }
}
