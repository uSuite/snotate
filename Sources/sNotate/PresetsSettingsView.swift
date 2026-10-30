import AppKit
import SNotateCore
import SwiftUI

/// Settings > Presets (SN-506), Terminal's profile layout: the nine slots on
/// the left, the selected preset's name, colour and sizes on the right over
/// a preview drawn by the one renderer.
struct PresetsSettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                List(1...9, id: \.self, selection: $model.selectedSlot) { slot in
                    SlotRow(slot: slot, style: model.style(slot))
                }
                .listStyle(.bordered)
                HStack(spacing: 2) {
                    Button {
                        model.addPreset()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("New preset in the first free slot, a copy of the selected one")
                    Button {
                        SettingsPanels.confirmRemove(model, slot: model.selectedSlot)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help(model.isBuiltIn(model.selectedSlot) ? "Revert to the built-in preset" : "Remove the preset")
                    .disabled(!canRemove)
                    Menu {
                        Button("Duplicate") {
                            model.addPreset()
                        }
                        .disabled(model.style(model.selectedSlot) == nil)
                        Divider()
                        Button("Import Preset…") {
                            SettingsPanels.importPreset(model)
                        }
                        Button("Export Preset…") {
                            SettingsPanels.exportPreset(model, slot: model.selectedSlot)
                        }
                        .disabled(model.style(model.selectedSlot) == nil)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 200)
            Divider()
            Group {
                if model.style(model.selectedSlot) != nil {
                    // One editor per slot, so a name being typed is
                    // committed to its own preset when the selection moves.
                    PresetEditor(model: model, slot: model.selectedSlot)
                        .id(model.selectedSlot)
                } else {
                    VStack(spacing: 12) {
                        Text("Preset \(model.selectedSlot) is not set")
                            .font(.headline)
                        Text("Annotations that use it draw as preset 1.")
                            .foregroundStyle(.secondary)
                        Button("Create Preset \(model.selectedSlot)") {
                            var style = model.settings.styles.style(for: 1)
                            style.name = nil
                            model.save(style, to: model.selectedSlot)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 560)
        }
        .frame(height: 520)
    }

    /// Built-in presets can be reverted only once the file changes them.
    private var canRemove: Bool {
        let slot = model.selectedSlot
        guard let style = model.style(slot) else {
            return false
        }
        return !model.isBuiltIn(slot) || style != Styles.builtIn.presets[slot]
    }
}

private struct SlotRow: View {
    let slot: Int
    let style: Style?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(style.map { Color(cgColor: $0.color.cgColor) } ?? Color.clear)
                .overlay(Circle().strokeBorder(.secondary.opacity(0.4)))
                .frame(width: 14, height: 14)
            Text("\(slot)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(style.map { $0.name ?? "Unnamed" } ?? "Not set")
                .foregroundStyle(style == nil ? .secondary : .primary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

private struct PresetEditor: View {
    let model: SettingsModel
    let slot: Int
    /// The name as typed, written on return or when the field loses focus,
    /// so a space being typed is not trimmed away mid-word.
    @State private var name = ""
    @FocusState private var naming: Bool

    private var style: Style {
        model.style(slot) ?? Styles.builtIn.style(for: 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField(
                    "Name",
                    text: $name,
                    prompt: Text("Preset \(slot)")
                )
                .focused($naming)
                .onSubmit(commitName)
                .onChange(of: naming) {
                    if !naming {
                        commitName()
                    }
                }
                ColorPicker(
                    "Colour",
                    selection: Binding(
                        get: { Color(cgColor: style.color.cgColor) },
                        set: { color in
                            if let rgba = Self.rgba(color) {
                                model.update(slot) { $0.color = rgba }
                            }
                        }
                    ),
                    supportsOpacity: false
                )
                size("Stroke", key: "stroke", \.strokeWidth)
                size("Text size", key: "font", \.fontSize)
                size("Counter diameter", key: "counter", \.counterRadius, factor: 2)
                size("Blur radius", key: "blur", \.blurRadius)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 290)
            Image(decorative: PresetPreview.render(style), scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 20)
            if !model.status.isEmpty {
                Text(model.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
            Spacer(minLength: 8)
        }
        .onAppear {
            name = style.name ?? ""
        }
        .onDisappear {
            if name != (style.name ?? "") {
                commitName()
            }
        }
        .onChange(of: style.name) {
            if !naming {
                name = style.name ?? ""
            }
        }
    }

    private func commitName() {
        let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(StylesFile.nameLimit))
        name = trimmed
        model.update(slot) { $0.name = trimmed.isEmpty ? nil : trimmed }
    }

    /// A size in image pixels with the range the styles file accepts;
    /// `factor` shows the counter's diameter where the model keeps its
    /// radius, as the file does.
    private func size(
        _ label: String,
        key: String,
        _ path: WritableKeyPath<Style, CGFloat>,
        factor: CGFloat = 1
    ) -> some View {
        let range = StylesFile.ranges[key]!
        let value = Binding<Double>(
            get: { Double(style[keyPath: path] * factor) },
            set: { new in
                let clamped = min(max(CGFloat(new), range.lowerBound), range.upperBound)
                model.update(slot) { $0[keyPath: path] = clamped / factor }
            }
        )
        return LabeledContent(label) {
            HStack(spacing: 4) {
                TextField(label, value: value, format: .number.precision(.fractionLength(0...2)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                Stepper(label, value: value, in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                    .labelsHidden()
                Text("px")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static func rgba(_ color: Color) -> RGBA? {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else {
            return nil
        }
        return RGBA(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
    }
}
