import Foundation

struct Pairing: Codable, Equatable {
    var id: String
    var name: String
    var fingerprint: String
    var endpoints: [String]
    var lastSeen: Date
}

final class PairingStore {
    static let shared = PairingStore()
    private let key = "ddrdesk.pairings"
    private init() {}

    func load() -> [Pairing] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Pairing].self, from: data)) ?? []
    }

    func save(_ items: [Pairing]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func upsert(_ p: Pairing) {
        var all = load().filter { $0.id != p.id }
        all.insert(p, at: 0)
        save(all)
    }

    func pairing(for id: String) -> Pairing? {
        load().first { $0.id == id }
    }

    func rememberEndpoints(id: String, name: String, fp: String, endpoints: [String]) {
        upsert(Pairing(id: id, name: name, fingerprint: fp, endpoints: endpoints, lastSeen: Date()))
    }
}
