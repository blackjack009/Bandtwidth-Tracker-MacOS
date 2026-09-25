import Foundation
import Combine

@MainActor
final class SpeedTester: ObservableObject {
    nonisolated init() {}

    enum Phase: Equatable {
        case idle, downloading, uploading, done, failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var downloadMbps: Double = 0
    @Published var uploadMbps: Double = 0
    @Published var pingMs: Double = 0
    @Published var progress: Double = 0

    private let downloadBytes = 25_000_000
    private let uploadBytes = 10_000_000

    func run() {
        Task { await runAsync() }
    }

    private func runAsync() async {
        phase = .downloading
        progress = 0
        downloadMbps = 0
        uploadMbps = 0
        pingMs = 0

        do {
            pingMs = try await measurePing()
            downloadMbps = try await measureDownload()
            uploadMbps = try await measureUpload()
            phase = .done
            progress = 1
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func measurePing() async throws -> Double {
        let url = URL(string: "https://speed.cloudflare.com/__down?bytes=0")!
        var samples: [Double] = []
        for i in 0..<5 {
            let start = Date()
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            _ = try await URLSession.shared.data(for: req)
            // Drop the first sample — it includes DNS + TLS cold-start setup.
            if i > 0 { samples.append(Date().timeIntervalSince(start) * 1000) }
        }
        samples.sort()
        return samples.isEmpty ? 0 : samples[samples.count / 2]
    }

    private func measureDownload() async throws -> Double {
        phase = .downloading
        let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(downloadBytes)")!
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let start = Date()
        let (data, _) = try await URLSession.shared.data(for: req)
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return 0 }
        return (Double(data.count) * 8) / (elapsed * 1_000_000)
    }

    private func measureUpload() async throws -> Double {
        phase = .uploading
        let url = URL(string: "https://speed.cloudflare.com/__up")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let payload = Data(count: uploadBytes)

        let start = Date()
        _ = try await URLSession.shared.upload(for: req, from: payload)
        let elapsed = Date().timeIntervalSince(start)
        await MainActor.run { self.progress = 1.0 }
        return (Double(uploadBytes) * 8) / (elapsed * 1_000_000)
    }
}
