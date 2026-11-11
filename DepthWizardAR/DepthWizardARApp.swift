import SwiftUI

@main
struct DepthWizardARApp: App {
    @StateObject private var library = ProjectLibrary()

    var body: some Scene {
        WindowGroup {
            ProjectLibraryView()
                .environmentObject(library)
                .preferredColorScheme(.light)
        }
    }
}
