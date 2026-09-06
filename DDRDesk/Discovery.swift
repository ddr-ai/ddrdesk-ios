import Foundation
import Network

/// Browse `_ddrdesk._tcp` and match the 9-digit connection ID. LAN only.
final class Discovery {
    private var browser: NWBrowser?
    private(set) var hits: [String: [NWEndpoint]] = [:]
    var onChange: (() -> Void)?

    func start() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjour(type: "_ddrdesk._tcp", domain: "local."), using: params)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            var map: [String: [NWEndpoint]] = [:]
            for r in results {
                let id = txtID(r) ?? "_unknown"
                map[id, default: []].append(r.endpoint)
            }
            self?.hits = map
            self?.onChange?()
        }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    func endpoints(for id: String) -> [NWEndpoint] {
        hits[id] ?? []
    }
}

private func txtID(_ r: NWBrowser.Result) -> String? {
    switch r.metadata {
    case .bonjour(let txt):
        return txt.dictionary["id"]
    default:
        return nil
    }
}
