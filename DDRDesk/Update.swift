import Foundation
import UIKit
import Combine

struct LatestBuild: Codable, Equatable {
    var version: String
    var build: Int
    var ipaURL: String
    var notes: String?
    var date: String?
    var installPageURL: String?
}

@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    static let feedURL = URL(string:
        "https://github.com/ddr-ai/ddrdesk-ios/releases/download/unsigned-ipa/latest.json"
    )!
    static let installPage = URL(string: "https://ddr-ai.github.io/ddrdesk-ios/")!

    @Published var latest: LatestBuild?
    @Published var checking = false
    @Published var lastError: String?
    @Published var installing = false

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

    /// No Mac / no Xcode: hand the new IPA to an on-device installer, or open
    /// the phone install page. iOS cannot overwrite this app by itself.
    func apply() {
        guard let latest else {
            UIApplication.shared.open(Self.installPage)
            return
        }
        guard let ipa = URL(string: latest.ipaURL) else { return }
        let encoded = ipa.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ipa.absoluteString
        let schemes = [
            "altstore://install?url=\(encoded)",
            "sidestore://install?url=\(encoded)",
            "feather://install?url=\(encoded)",
            "esign://install?url=\(encoded)",
            "gbox://import?url=\(encoded)",
            "apple-magnifier://install?url=\(encoded)",
            "trollstore://install?url=\(encoded)",
        ]
        for s in schemes {
            if let url = URL(string: s), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
        if let page = latest.installPageURL.flatMap(URL.init(string:)) {
            UIApplication.shared.open(page)
        } else {
            UIApplication.shared.open(Self.installPage)
        }
    }

    func shareIPA() {
        guard let latest, let ipa = URL(string: latest.ipaURL) else {
            apply()
            return
        }
        installing = true
        Task {
            defer { installing = false }
            do {
                let (tmp, _) = try await URLSession.shared.download(from: ipa)
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("DDRDesk-\(latest.build).ipa")
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
                let av = UIActivityViewController(activityItems: [dest], applicationActivities: nil)
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let root = scene.keyWindow?.rootViewController
                        ?? scene.windows.first?.rootViewController else {
                    apply()
                    return
                }
                var presenter = root
                while let p = presenter.presentedViewController { presenter = p }
                if let pop = av.popoverPresentationController {
                    pop.sourceView = presenter.view
                    pop.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                }
                presenter.present(av, animated: true)
            } catch {
                lastError = error.localizedDescription
                apply()
            }
        }
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first(where: \.isKeyWindow) ?? windows.first }
}
