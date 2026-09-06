import SwiftUI

@main
struct DDRDeskApp: App {
    @StateObject private var updates = UpdateService.shared

    var body: some Scene {
        WindowGroup {
            ConnectView()
                .preferredColorScheme(.dark)
                .environmentObject(updates)
                .task { updates.start() }
        }
    }
}
