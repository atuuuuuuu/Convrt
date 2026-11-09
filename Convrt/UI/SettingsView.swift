import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @AppStorage(AppSettings.Key.convertTrigger) private var trigger = TriggerKey.shift.rawValue
    @AppStorage(AppSettings.Key.outputMode) private var outputMode = OutputMode.sameFolder.rawValue
    @AppStorage(AppSettings.Key.customOutputPath) private var customPath = ""
    @AppStorage(AppSettings.Key.deleteOriginal) private var deleteOriginal = false
    @AppStorage(AppSettings.Key.imageQuality) private var quality = 0.85
    @AppStorage(AppSettings.Key.playSound) private var playSound = true
    @AppStorage(AppSettings.Key.optionCycles) private var optionCycles = true
    @AppStorage(AppSettings.Key.directJumpKeys) private var directJumpKeys = true
    @AppStorage(AppSettings.Key.toolMaxDimension) private var maxDimension = 1920
    @AppStorage(AppSettings.Key.compressQuality) private var compressQuality = 0.6

    @State private var rules = WatchRuleStore.load()

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

                Section("Wheels") {
                    Toggle("Option ⌥ cycles Convert · Tools · Actions", isOn: $optionCycles)
                    Toggle("Command ⌘ opens Tools, Control ⌃ opens Actions", isOn: $directJumpKeys)
                    Text("Scroll, Tab or the arrow keys move around the open wheel. Esc closes it.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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

                Section("Tools") {
                    Picker("Resize: longest side", selection: $maxDimension) {
                        ForEach([1024, 1280, 1920, 2560, 3840], id: \.self) { Text("\($0) px").tag($0) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Compress quality")
                            Spacer()
                            Text("\(Int((compressQuality * 100).rounded()))%")
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $compressQuality, in: 0.1...1.0, step: 0.05)
                    }
                }

                Section("Watch Folders") {
                    if rules.isEmpty {
                        Text("New files that land in a folder you add here are converted automatically, once they have finished downloading or copying. Files already there are left alone, and originals are never deleted.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ForEach($rules) { $rule in
                        HStack(spacing: 8) {
                            Toggle("", isOn: $rule.enabled).labelsHidden()
                            Text(URL(fileURLWithPath: rule.folder).lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(rule.folder)
                            Spacer()
                            Text("→").foregroundColor(.secondary)
                            Picker("", selection: $rule.format) {
                                ForEach(watchFormats, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                            }
                            .labelsHidden()
                            .frame(width: 84)
                            Button {
                                rules.removeAll { $0.id == rule.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Stop watching this folder")
                        }
                    }
                    Button("Add Folder…", action: addWatchFolder)
                }

                Section("Permissions") {
                    permissionRow("Accessibility", ok: accessibilityOK)
                    permissionRow("Input Monitoring", ok: inputMonitoringOK)
                    Button("Check Permissions…") { PermissionManager.check(showWhenGranted: true) }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 480, height: 720)
        .onChange(of: rules) { newValue in
            WatchRuleStore.save(newValue)
            NotificationCenter.default.post(name: .watchRulesChanged, object: nil)
        }
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
                .foregroundColor(Theme.primary)
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

    /// What a watched folder can turn files into (MP3 only when an encoder is installed).
    private var watchFormats: [OutputFormat] {
        [.jpg, .png, .heic, .pdf, .wav, .mp3, .m4a, .mp4].filter { $0.canEncode }
    }

    private func addWatchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Watch"
        panel.message = "Choose a folder. New files that appear in it will be converted."
        if panel.runModal() == .OK, let url = panel.url, !rules.contains(where: { $0.folder == url.path }) {
            rules.append(WatchRule(folder: url.path, format: OutputFormat.jpg.rawValue, enabled: true))
        }
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
