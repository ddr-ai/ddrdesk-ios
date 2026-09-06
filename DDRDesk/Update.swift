import Foundation
import UIKit
import Combine

struct LatestBuild: Codable, Equatable {
    var version: String
    var build: Int
    var ipaURL: String
    var notes: String?
    var date: String?
}

@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    static let feedURL = URL(string:
        "https://github.com/ddr-ai/ddrdesk-ios/releases/download/unsigned-ipa/latest.json"
    )!

    @Published var latest: LatestBuild?
    @Published var checking = false
    @Published var lastError: String?

    var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var updateAvailable: Bool {
        guard let latest else { return false }
        return latest.build > currentBuild
    }

    private var autoOpenedFor: Int = 0
    private var timer: Timer?

    private init() {}

    func start() {
        Task { await check(autoInstall: true) }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.check(autoInstall: true)
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.check(autoInstall: true)
            }
        }
    }

    func check(autoInstall: Bool) async {
        checking = true
        lastError = nil
        defer { checking = false }
        var req = URLRequest(url: Self.feedURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                lastError = "update feed HTTP \(http.statusCode)"
                return
            }
            let decoded = try JSONDecoder().decode(LatestBuild.self, from: data)
            latest = decoded
            if autoInstall, decoded.build > currentBuild, autoOpenedFor != decoded.build {
                autoOpenedFor = decoded.build
                apply()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func apply() {
        guard let latest else { return }
        guard let ipa = URL(string: latest.ipaURL) else { return }
        let encoded = ipa.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ipa.absoluteString
        let candidates = [
            URL(string: "altstore://install?url=\(encoded)"),
            URL(string: "sidestore://install?url=\(encoded)"),
            URL(string: "apple-magnifier://install?url=\(encoded)"),
        ].compactMap { $0 }

        for url in candidates {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
        UIApplication.shared.open(ipa)
    }
}
