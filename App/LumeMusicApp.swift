import SwiftUI

@main
struct LumeMusicApp: App {
  /// Controla a orientação do app (só retrato; o Cover Flow libera paisagem). Ver OrientationKit.swift.
  @UIApplicationDelegateAdaptor(OrientationAppDelegate.self) private var orientationDelegate
  @State private var showOnboarding = !Onboarding.isDone || Onboarding.debugForced
  @State private var showIntro = LibraryStore.shared.introEnabled && Onboarding.isDone && !Onboarding.debugForced
  @StateObject private var access = AccessService.shared
  @StateObject private var popups = Popups.shared
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
            access.onboardingFinished()
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

        // Pop-ups de vidro: boas-vindas, pagamento confirmado, PIN, transferência e nova versão.
        PopupHost(blocked: showOnboarding || showIntro || access.needsCode)
          .zIndex(200)
      }
      .sheet(isPresented: $popups.showUpgrade) { UpgradeView() }
      .background(Theme.canvas.ignoresSafeArea())
      .preferredColorScheme(scheme)
      .animation(.easeInOut(duration: 0.3), value: access.needsCode)
      .task {
        LumeExtras.start()
        LumeTextures.shared.prewarmInBackground()
        access.startMonitoring()
        UpdateService.shared.start()
        if Onboarding.isDone && !Onboarding.debugForced { await access.ensureConfig(); await access.ensureTrialIfNeeded() }
        LumeExtras.accessReady()
        if ProcessInfo.processInfo.arguments.contains("-LMSelfTest") { await AccessSelfTest.run() }
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active {
          Task {
            await access.checkIfDue()
            if Onboarding.isDone { await access.ensureTrialIfNeeded() }
          }
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: Onboarding.reopenNotification)) { _ in
        showIntro = false
        withAnimation(.easeInOut(duration: 0.3)) { showOnboarding = true }
      }
      .onOpenURL { url in
        guard url.scheme == "lumemusic" else { return }
        if AudioPlayer.shared.currentTrack != nil {
          AppModel.shared.showPlayer = true
        }
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
