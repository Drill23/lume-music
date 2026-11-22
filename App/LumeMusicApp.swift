import SwiftUI

@main
struct LumeMusicApp: App {
  @State private var showIntro = true

  var body: some Scene {
    WindowGroup {
      ZStack {
        RootTabShell()
          .preferredColorScheme(.dark)

        if showIntro {
          IntroView {
            showIntro = false
          }
          .zIndex(100)
        }
      }
      .background(Theme.bg.ignoresSafeArea())
    }
  }
}
