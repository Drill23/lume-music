import SwiftUI

@main
struct LumeMusicApp: App {
  @State private var showIntro = true
  @State private var revealed = false
  @AppStorage("lume.appearance") private var appearance = "system"

  var body: some Scene {
    WindowGroup {
      ZStack {
        RootView()
          .scaleEffect(revealed ? 1 : 0.94)
          .blur(radius: revealed ? 0 : 12)
          .opacity(revealed ? 1 : 0)

        if showIntro {
          IntroView {
            showIntro = false
          }
          .zIndex(100)
          .transition(.identity)
        }
      }
      .background(Theme.canvas.ignoresSafeArea())
      .preferredColorScheme(scheme)
      .onChange(of: showIntro) { _, now in
        if !now { withAnimation(.spring(response: 0.6, dampingFraction: 0.88)) { revealed = true } }
      }
      .task {
        // Start revealing slightly before the intro finishes, like an iOS app-launch zoom.
        try? await Task.sleep(for: .milliseconds(Theme.motion ? 1250 : 300))
        withAnimation(.spring(response: 0.7, dampingFraction: 0.88)) { revealed = true }
      }
    }
  }

  private var scheme: ColorScheme? {
    switch appearance {
    case "light": return .light
    case "dark": return .dark
    default: return nil
    }
  }
}
