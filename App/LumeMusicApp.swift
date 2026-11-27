import SwiftUI

@main
struct LumeMusicApp: App {
  @State private var showOnboarding = !Onboarding.isDone || Onboarding.debugForced
  @State private var showIntro = LibraryStore.shared.introEnabled && Onboarding.isDone && !Onboarding.debugForced
  @StateObject private var access = AccessService.shared
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("lume.appearance") private var appearance = "system"

  var body: some Scene {
    WindowGroup {
      ZStack {
        RootView()

        // Código de acesso: usuário que perdeu o acesso (ou sem código) vê a tela de código; a biblioteca fica intacta.
        if !showOnboarding && access.needsCode {
          AccessGateView()
            .zIndex(90)
            .transition(.opacity)
        }

        if showOnboarding {
          OnboardingView {
            withAnimation(.easeOut(duration: 0.2)) { showOnboarding = false }
          }
          .zIndex(110)
          .transition(.opacity)
        } else if showIntro {
          IntroView {
            withAnimation(.easeOut(duration: 0.25)) { showIntro = false }
          }
          .zIndex(100)
          .transition(.opacity)
        }
      }
      .background(Theme.canvas.ignoresSafeArea())
      .preferredColorScheme(scheme)
      .animation(.easeInOut(duration: 0.3), value: access.needsCode)
      .task {
        LumeTextures.shared.prewarmInBackground()
        access.startMonitoring()
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { Task { await access.checkIfDue() } }
      }
      .onReceive(NotificationCenter.default.publisher(for: Onboarding.reopenNotification)) { _ in
        showIntro = false
        withAnimation(.easeInOut(duration: 0.3)) { showOnboarding = true }
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
