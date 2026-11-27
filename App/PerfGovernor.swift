import Combine
import Foundation
import SwiftUI
import UIKit

/// Governador de desempenho/temperatura (5.0).
///
/// Junta em um só lugar o que deve frear animações contínuas:
///  • "Modo economia" dos Ajustes;
///  • Modo de Pouca Energia do iOS;
///  • aparelho esquentando (`thermalState` ≥ .serious);
///  • app inativo / em segundo plano / tela bloqueada (`isActive == false`).
///
/// Publica SÓ quando um desses estados muda (raramente), então observá-lo não custa re-render.
/// Uso em qualquer animação contínua:
///   TimelineView(.animation(minimumInterval: PerfGovernor.shared.frameInterval, paused: !gov.isActive || …))
@MainActor
final class PerfGovernor: ObservableObject {
  static let shared = PerfGovernor()

  /// Efeitos reduzidos (menos fps, sem brilhos extras).
  @Published private(set) var reduced = false
  /// App em primeiro plano e ativo. Falso com a tela bloqueada ou no fundo: pause tudo que é contínuo.
  @Published private(set) var isActive = true
  /// Aparelho quente (thermalState ≥ .serious) — além de reduzir, vale cortar o que for supérfluo.
  @Published private(set) var isHot = false

  private var bag = Set<AnyCancellable>()

  /// Intervalo mínimo entre quadros para visualizadores (60 fps normal, 30 fps reduzido).
  var frameInterval: Double { reduced ? 1.0 / 30.0 : 1.0 / 60.0 }
  /// Movimento contínuo permitido (Reduzir Movimento desliga).
  var allowsMotion: Bool { isActive && !UIAccessibility.isReduceMotionEnabled }

  private init() {
    let nc = NotificationCenter.default
    let app = UIApplication.shared
    isActive = app.applicationState == .active
    nc.publisher(for: UIApplication.didBecomeActiveNotification)
      .sink { [weak self] _ in MainActor.assumeIsolated { self?.setActive(true) } }
      .store(in: &bag)
    nc.publisher(for: UIApplication.willResignActiveNotification)
      .sink { [weak self] _ in MainActor.assumeIsolated { self?.setActive(false) } }
      .store(in: &bag)
    nc.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
      .merge(with: nc.publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange))
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in MainActor.assumeIsolated { self?.recompute() } }
      .store(in: &bag)
    LibraryStore.shared.$economyMode
      .removeDuplicates()
      .sink { [weak self] eco in MainActor.assumeIsolated { self?.recompute(economy: eco) } }
      .store(in: &bag)
    recompute()
  }

  private func setActive(_ v: Bool) {
    if isActive != v { isActive = v }
  }

  private func recompute(economy: Bool? = nil) {
    let eco = economy ?? LibraryStore.shared.economyMode
    let thermal = ProcessInfo.processInfo.thermalState
    let hot = thermal == .serious || thermal == .critical
    let r = eco || hot || ProcessInfo.processInfo.isLowPowerModeEnabled
    if isHot != hot { isHot = hot }
    if reduced != r { reduced = r }
  }
}
