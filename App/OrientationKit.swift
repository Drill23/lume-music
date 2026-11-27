import SwiftUI
import UIKit
import CoreMotion

// MARK: - Orientation lock (app level)
//
// O app inteiro é só retrato no iPhone. O Cover Flow é a única tela que pede paisagem:
// ele muda `OrientationLock.shared.mask` e pede uma atualização de geometria à cena.
// Ao sair, volta a travar em retrato. O `OrientationAppDelegate` devolve essa máscara ao UIKit.

final class OrientationLock {
  static let shared = OrientationLock()

  /// Máscara que o `AppDelegate` devolve ao UIKit. iPhone: só retrato por padrão; iPad: tudo.
  private(set) var mask: UIInterfaceOrientationMask = OrientationLock.defaultMask

  static var defaultMask: UIInterfaceOrientationMask {
    UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .all
  }

  private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

  /// Libera paisagem e gira a interface para o lado pedido (`.landscapeLeft`/`.landscapeRight` em termos de INTERFACE).
  @MainActor
  func forceLandscape(_ interface: UIInterfaceOrientationMask) {
    guard isPhone else { return }
    mask = .landscape
    refresh(rotateTo: interface)
  }

  /// Volta a travar em retrato e gira a interface de volta.
  @MainActor
  func lockPortrait() {
    guard isPhone else { return }
    mask = .portrait
    refresh(rotateTo: .portrait)
  }

  @MainActor
  private func refresh(rotateTo target: UIInterfaceOrientationMask) {
    guard let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first(where: { $0.activationState == .foregroundActive }) ??
      UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
    else { return }

    // Avisa a raiz e toda a cadeia de apresentadas (o Cover Flow é um fullScreenCover).
    var vc = scene.keyWindow?.rootViewController
    while let current = vc {
      current.setNeedsUpdateOfSupportedInterfaceOrientations()
      vc = current.presentedViewController
    }
    scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { error in
      #if DEBUG
      print("[OrientationLock] requestGeometryUpdate falhou: \(error)")
      #endif
    }
  }
}

/// Entregue ao SwiftUI com `@UIApplicationDelegateAdaptor` em `LumeMusicApp`.
final class OrientationAppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    CoverFlowDebug.launchIfRequested()
    return true
  }

  func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
    OrientationLock.shared.mask
  }
}

// MARK: - Orientação física (acelerômetro)

/// Orientação FÍSICA do aparelho, em termos de aparelho (não de interface).
enum PhysicalOrientation: Equatable {
  case portrait
  /// Lado esquerdo do aparelho para baixo (UIDeviceOrientation.landscapeLeft). A interface correspondente é `.landscapeRight`.
  case landscapeLeft
  /// Lado direito do aparelho para baixo (UIDeviceOrientation.landscapeRight). A interface correspondente é `.landscapeLeft`.
  case landscapeRight

  var interfaceMask: UIInterfaceOrientationMask? {
    switch self {
    case .portrait: return nil
    case .landscapeLeft: return .landscapeRight
    case .landscapeRight: return .landscapeLeft
    }
  }
}

/// Lê a gravidade (CoreMotion, ~10 Hz) para saber como o aparelho está segurado, mesmo com a trava de rotação ativada.
/// Também escuta `UIDevice.orientation` (principal quando não há sensor, como no Simulator).
/// Só roda entre `start()` e `stop()`.
@MainActor
final class MotionOrientationMonitor: ObservableObject {
  @Published private(set) var current: PhysicalOrientation?

  private let manager = CMMotionManager()
  private var observer: NSObjectProtocol?
  private var pending: PhysicalOrientation?
  private var pendingCount = 0
  private var running = false

  func start() {
    guard !running else { return }
    running = true
    pending = nil
    pendingCount = 0

    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    observer = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.ingestDeviceOrientation() }
    }

    if manager.isDeviceMotionAvailable {
      manager.deviceMotionUpdateInterval = 0.1
      manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
        guard let g = motion?.gravity else { return }
        MainActor.assumeIsolated { self?.ingest(x: g.x, y: g.y) }
      }
    }
    ingestDeviceOrientation()
  }

  func stop() {
    guard running else { return }
    running = false
    manager.stopDeviceMotionUpdates()
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
    UIDevice.current.endGeneratingDeviceOrientationNotifications()
    pending = nil
    pendingCount = 0
  }

  /// Simula uma leitura do sensor (usado pelos argumentos de depuração).
  func inject(_ orientation: PhysicalOrientation) {
    current = orientation
  }

  private func ingestDeviceOrientation() {
    switch UIDevice.current.orientation {
    case .portrait: commit(.portrait, immediately: !manager.isDeviceMotionAvailable)
    case .landscapeLeft: commit(.landscapeLeft, immediately: !manager.isDeviceMotionAvailable)
    case .landscapeRight: commit(.landscapeRight, immediately: !manager.isDeviceMotionAvailable)
    default: break // faceUp / faceDown / upsideDown / unknown: ignora
    }
  }

  /// Gravidade no referencial do aparelho: retrato em pé => y ≈ -1; lado esquerdo para baixo => x ≈ -1.
  private func ingest(x: Double, y: Double) {
    var candidate: PhysicalOrientation?
    if abs(x) > 0.72, abs(x) > abs(y) + 0.25 {
      candidate = x < 0 ? .landscapeLeft : .landscapeRight
    } else if y < -0.72, abs(y) > abs(x) + 0.25 {
      candidate = .portrait
    }
    guard let candidate else { pending = nil; pendingCount = 0; return }
    commit(candidate, immediately: false)
  }

  /// Histerese: exige ~0,3 s (3 leituras) estáveis antes de trocar, para não tremer na transição.
  private func commit(_ candidate: PhysicalOrientation, immediately: Bool) {
    if immediately {
      if candidate != current { current = candidate }
      return
    }
    if candidate == pending { pendingCount += 1 } else { pending = candidate; pendingCount = 1 }
    if pendingCount >= 3, candidate != current { current = candidate }
  }
}
