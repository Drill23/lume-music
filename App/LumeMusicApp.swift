import SwiftUI

@main
struct LumeMusicApp: App {
  @State private var showIntro = LibraryStore.shared.introEnabled
  @AppStorage("lume.appearance") private var appearance = "system"

  var body: some Scene {
    WindowGroup {
      ZStack {
        RootView()

        if showIntro {
          IntroView {
            withAnimation(.easeOut(duration: 0.25)) {
              showIntro = false
            }
          }
          .zIndex(100)
          .transition(.opacity)
        }
      }
      .background(Theme.canvas.ignoresSafeArea())
      .preferredColorScheme(scheme)
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
