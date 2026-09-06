import SwiftUI

@main
struct DDRDeskApp: App {
    var body: some Scene {
        WindowGroup {
            ConnectView()
                .preferredColorScheme(.dark)
        }
    }
}
