import AppKit
import SNotateCore
import SwiftUI

/// Settings > General (SN-506): snapping, the config files as a whole, and
/// the problems found in them. Export options stay in the config file.
struct GeneralSettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section("Drawing") {
                Toggle(
                    "Snap to image edges and other annotations",
                    isOn: Binding(
                        get: { model.settings.config.snap },
                        set: { model.setSnap($0) }
                    )
                )
            }
            Section {
                LabeledContent("Folder") {
                    Text(model.app.paths.directory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Import Config…") {
                        SettingsPanels.importConfig(model)
                    }
                    Button("Export Config…") {
                        SettingsPanels.exportConfig(model)
                    }
                    Spacer()
                    Button("Open Config Folder") {
                        NSWorkspace.shared.open(model.app.paths.directory)
                    }
                }
                if !model.status.isEmpty {
                    Text(model.status)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Config files")
            } footer: {
                Text("config, keymap and styles are plain text; export options, keys and anything else live there.")
                    .foregroundStyle(.secondary)
            }
            Section("Problems in the files") {
                if model.problems.isEmpty {
                    Text("No problems")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.problems, id: \.self) { problem in
                        Text(problem)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}
