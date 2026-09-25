import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var prefs: Preferences
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            themeSection
            dividerLine
            backgroundSection
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    // MARK: - Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THEME").sectionLabel()
            Picker("", selection: $prefs.theme) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - Background

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BACKGROUND").sectionLabel()
            Picker("", selection: $prefs.background) {
                ForEach(BackgroundMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch prefs.background {
            case .translucent:
                Text("Blends with the desktop behind the popover.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .solid:
                colorSwatches

            case .image:
                imageControls
            }
        }
    }

    private let presets: [String] = [
        "#1C1C1E", "#2C2C2E", "#0A2540", "#12343B", "#1B2A4A", "#3A2352",
        "#4A1F2B", "#0E3B2E", "#3B3222", "#2B2B2B",
        "#F2F2F7", "#E5E7EB", "#DCE3F0", "#E8F0EE", "#F0E8F5", "#FBEAE7"
    ]

    private var colorSwatches: some View {
        VStack(alignment: .leading, spacing: 8) {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(presets, id: \.self) { hex in
                    let color = Color(hex: hex) ?? .gray
                    let selected = prefs.solidColor.hexString.caseInsensitiveCompare(hex) == .orderedSame
                    Button {
                        prefs.solidColor = color
                        prefs.background = .solid
                    } label: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color)
                            .frame(height: 30)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selected ? Color.accentColor : Color.primary.opacity(0.15),
                                            lineWidth: selected ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Tap a color. Text auto-adjusts for contrast.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var imageControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let img = prefs.backgroundImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 64, height: 40)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        )
                }
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        prefs.pickImage()
                    } label: {
                        Text(prefs.backgroundImage == nil ? "Choose Image…" : "Change…")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if prefs.backgroundImage != nil {
                        Button {
                            prefs.clearImage()
                        } label: {
                            Text("Remove")
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
            }

            if prefs.backgroundImage != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Dim overlay")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(prefs.imageDim * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $prefs.imageDim, in: 0...0.8)
                        .controlSize(.small)
                }
            }
        }
    }

    private var dividerLine: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
    }
}
