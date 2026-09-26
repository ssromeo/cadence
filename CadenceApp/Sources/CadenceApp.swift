import SwiftUI

@main
struct CadenceApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light) // le thème clair est un choix, pas un oubli du sombre
        }
    }
}
