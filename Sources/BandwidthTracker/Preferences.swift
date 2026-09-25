import SwiftUI
import AppKit
import Combine

enum ThemeMode: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum BackgroundMode: String, CaseIterable, Identifiable {
    case translucent, solid, image
    var id: String { rawValue }
    var label: String {
        switch self {
        case .translucent: return "Translucent"
        case .solid: return "Solid"
        case .image: return "Image"
        }
    }
}

final class Preferences: ObservableObject {
    private let d = UserDefaults.standard

    @Published var theme: ThemeMode {
        didSet { d.set(theme.rawValue, forKey: "pref.theme") }
    }
    @Published var background: BackgroundMode {
        didSet { d.set(background.rawValue, forKey: "pref.background") }
    }
    @Published var solidColor: Color {
        didSet { d.set(solidColor.hexString, forKey: "pref.solidColor") }
    }
    @Published var imagePath: String {
        didSet {
            d.set(imagePath, forKey: "pref.imagePath")
            reloadImage()
        }
    }
    @Published var imageDim: Double {
        didSet { d.set(imageDim, forKey: "pref.imageDim") }
    }
    @Published private(set) var backgroundImage: NSImage?
    @Published private(set) var imageLuminance: Double = 0.5

    init() {
        let d = UserDefaults.standard
        theme = ThemeMode(rawValue: d.string(forKey: "pref.theme") ?? "") ?? .auto
        background = BackgroundMode(rawValue: d.string(forKey: "pref.background") ?? "") ?? .translucent
        solidColor = Color(hex: d.string(forKey: "pref.solidColor") ?? "") ?? Color(nsColor: .windowBackgroundColor)
        imagePath = d.string(forKey: "pref.imagePath") ?? ""
        imageDim = d.object(forKey: "pref.imageDim") as? Double ?? 0.35
        let path = d.string(forKey: "pref.imagePath") ?? ""
        let img = path.isEmpty ? nil : NSImage(contentsOfFile: path)
        backgroundImage = img
        imageLuminance = img.map { Self.averageLuminance($0) } ?? 0.5
    }

    func reloadImage() {
        let img = imagePath.isEmpty ? nil : NSImage(contentsOfFile: imagePath)
        backgroundImage = img
        imageLuminance = img.map { Self.averageLuminance($0) } ?? 0.5
    }

    // User's manual theme choice (drives translucent mode + AppKit chrome)
    var colorScheme: ColorScheme? {
        switch theme {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    // Effective scheme actually applied to text — for solid/image it auto-contrasts
    // against the background luminance so text is never invisible.
    var effectiveScheme: ColorScheme? {
        switch background {
        case .translucent:
            return colorScheme
        case .solid:
            return Self.luminance(of: solidColor) < 0.5 ? .dark : .light
        case .image:
            return backgroundImage == nil ? colorScheme : (imageLuminance < 0.5 ? .dark : .light)
        }
    }

    // True when the effective scheme wants light text (background is dark)
    var backgroundIsDark: Bool {
        switch effectiveScheme {
        case .some(.dark): return true
        default: return false
        }
    }

    var effectiveNSAppearance: NSAppearance? {
        switch effectiveScheme {
        case .some(.dark): return NSAppearance(named: .darkAqua)
        case .some(.light): return NSAppearance(named: .aqua)
        default: return nil
        }
    }

    static func luminance(of color: Color) -> Double {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return 0.299 * ns.redComponent + 0.587 * ns.greenComponent + 0.114 * ns.blueComponent
    }

    static func averageLuminance(_ image: NSImage) -> Double {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return 0.5 }
        let w = bitmap.pixelsWide, h = bitmap.pixelsHigh
        guard w > 0, h > 0 else { return 0.5 }
        var total = 0.0, count = 0.0
        let stepX = max(1, w / 16), stepY = max(1, h / 16)
        for x in stride(from: 0, to: w, by: stepX) {
            for y in stride(from: 0, to: h, by: stepY) {
                if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    total += 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
                    count += 1
                }
            }
        }
        return count > 0 ? total / count : 0.5
    }

    // MARK: - Image handling

    func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .bmp, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose Background Image"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url,
           let dest = Self.copyToAppSupport(url) {
            imagePath = dest.path
            background = .image
        }
    }

    func clearImage() {
        if !imagePath.isEmpty {
            try? FileManager.default.removeItem(atPath: imagePath)
        }
        imagePath = ""
        if background == .image { background = .translucent }
    }

    private static func copyToAppSupport(_ src: URL) -> URL? {
        let fm = FileManager.default
        guard let appSup = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSup.appendingPathComponent("BandwidthTracker", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = src.pathExtension.isEmpty ? "img" : src.pathExtension
        let dest = dir.appendingPathComponent("background-\(Int(Date().timeIntervalSince1970)).\(ext)")
        // Remove any prior background files
        if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in files where f.lastPathComponent.hasPrefix("background-") {
                try? fm.removeItem(at: f)
            }
        }
        do {
            try fm.copyItem(at: src, to: dest)
            return dest
        } catch {
            return nil
        }
    }
}

extension Color {
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self = Color(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}
