import SwiftUI

@main
struct SatPassApp: App {
    @StateObject private var store = PassStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
