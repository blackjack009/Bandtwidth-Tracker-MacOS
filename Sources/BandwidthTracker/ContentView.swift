import SwiftUI
import AppKit

enum ContentTab: String, CaseIterable {
    case now = "Now"
    case recap = "Recap"
}

struct ContentView: View {
    @EnvironmentObject var monitor: BandwidthMonitor
    @EnvironmentObject var tester: SpeedTester
    @EnvironmentObject var prefs: Preferences
    @Environment(\.colorScheme) private var scheme
    @State private var tab: ContentTab = .now
    @State private var showSettings = false

    private let popWidth: CGFloat = 400
    private let popHeight: CGFloat = 620

    var body: some View {
        VStack(spacing: 0) {
            header
            if showSettings {
                ScrollView { SettingsView(onDone: { showSettings = false }) }
            } else {
                tabPicker
                ScrollView {
                    switch tab {
                    case .now:
                        nowContent
                    case .recap:
                        RecapView()
                    }
                }
            }
            footer
        }
        .frame(width: popWidth, height: popHeight)
        .background(backgroundLayer)
        .clipped()
        .preferredColorScheme(prefs.effectiveScheme)
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        switch prefs.background {
        case .translucent:
            Color.clear
        case .solid:
            prefs.solidColor
        case .image:
            if let img = prefs.backgroundImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: popWidth, height: popHeight)
                    .clipped()
                    .overlay((prefs.backgroundIsDark ? Color.black : Color.white).opacity(prefs.imageDim))
            } else {
                Color.clear
            }
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(ContentTab.allCases, id: \.self) { t in
                Button {
                    tab = t
                } label: {
                    Text(t.rawValue)
                        .font(.system(size: 11, weight: tab == t ? .semibold : .medium))
                        .foregroundStyle(tab == t ? .primary : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(tab == t ? Color.primary.opacity(0.10) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { dividerLine }
    }

    private var nowContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            liveHero
            sparkline
            dividerLine
            todaySection
            dividerLine
            interfacesSection
            dividerLine
            speedTestSection
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Bandwidth")
                .font(.headline)
            Spacer()
            if !showSettings {
                Button {
                    monitor.resetToday()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reset now (auto reset 00:00 WIB)")
            }
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: showSettings ? "chevron.left" : "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(showSettings ? .primary : .secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showSettings ? "Back" : "Preferences")
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { dividerLine }
    }

    // MARK: - Live hero

    private var liveHero: some View {
        HStack(alignment: .top, spacing: 0) {
            liveColumn(
                label: "DOWNLOAD",
                icon: "arrow.down",
                value: ByteFormat.speed(monitor.downloadSpeed)
            )
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 1, height: 46)
                .padding(.horizontal, 6)
            liveColumn(
                label: "UPLOAD",
                icon: "arrow.up",
                value: ByteFormat.speed(monitor.uploadSpeed)
            )
        }
    }

    private func liveColumn(label: String, icon: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
            }
            .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sparkline

    private var sparkline: some View {
        ZStack {
            Sparkline(data: monitor.downloadHistory,
                      color: .primary.opacity(scheme == .dark ? 0.85 : 0.75))
            Sparkline(data: monitor.uploadHistory,
                      color: .primary.opacity(scheme == .dark ? 0.35 : 0.30))
        }
        .frame(height: 42)
    }

    // MARK: - Today

    private var todaySection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("TODAY").sectionLabel()
                Spacer()
                Text(ByteFormat.bytes(monitor.todayDown &+ monitor.todayUp))
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            row(icon: "arrow.down", title: "Downloaded",
                value: ByteFormat.bytes(monitor.todayDown))
            row(icon: "arrow.up", title: "Uploaded",
                value: ByteFormat.bytes(monitor.todayUp))
        }
    }

    // MARK: - Interfaces

    private var interfacesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("INTERFACES").sectionLabel()
            if monitor.interfaces.isEmpty {
                Text("No active interfaces")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(monitor.interfaces.prefix(4).enumerated()),
                            id: \.element.name) { _, i in
                        HStack(spacing: 10) {
                            Text(i.name)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            metric(icon: "arrow.down",
                                   text: ByteFormat.bytes(i.received))
                                .frame(width: 96, alignment: .trailing)
                            metric(icon: "arrow.up",
                                   text: ByteFormat.bytes(i.sent))
                                .frame(width: 96, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Speed test

    private var speedTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SPEED TEST").sectionLabel()
                Spacer()
                Button {
                    tester.run()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.needle")
                            .font(.system(size: 11, weight: .semibold))
                        Text(runButtonTitle)
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.borderless)
                .disabled(tester.phase == .downloading || tester.phase == .uploading)
            }
            if tester.phase == .downloading || tester.phase == .uploading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(tester.phase == .downloading ? "Testing download…" : "Testing upload…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 24) {
                testStat(label: "PING",
                         value: String(format: "%.0f", tester.pingMs),
                         unit: "ms")
                testStat(label: "DOWN",
                         value: String(format: "%.1f", tester.downloadMbps),
                         unit: "Mbps")
                testStat(label: "UP",
                         value: String(format: "%.1f", tester.uploadMbps),
                         unit: "Mbps")
            }
            if case .failed(let msg) = tester.phase {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private func testStat(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).sectionLabel()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var runButtonTitle: String {
        switch tester.phase {
        case .idle: return "Run"
        case .downloading: return "Downloading…"
        case .uploading: return "Uploading…"
        case .done: return "Run Again"
        case .failed: return "Retry"
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("Auto-reset · 00:00 WIB")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { dividerLine }
    }

    // MARK: - Helpers

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    private func row(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    private func metric(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(.callout, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }
}

extension View {
    func sectionLabel() -> some View {
        self.font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

struct Sparkline: View {
    let data: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let maxV = max(data.max() ?? 1, 1)
            Path { path in
                guard data.count > 1 else { return }
                let step = geo.size.width / CGFloat(data.count - 1)
                for (i, v) in data.enumerated() {
                    let x = CGFloat(i) * step
                    let y = geo.size.height - CGFloat(v / maxV) * geo.size.height
                    if i == 0 { path.move(to: .init(x: x, y: y)) }
                    else { path.addLine(to: .init(x: x, y: y)) }
                }
            }
            .stroke(color, style: .init(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}
