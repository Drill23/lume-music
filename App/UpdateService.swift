import SwiftUI

struct UpdateOffer: Equatable {
  var build: Int
  var versionName: String
  var url: String
  var notes: String
  var mandatory: Bool
}

/// Atualizações automáticas (contrato v2): GET /api/app/update ao abrir e a cada 6 h.
@MainActor
final class UpdateService: ObservableObject {
  static let shared = UpdateService()

  @Published private(set) var offer: UpdateOffer?

  private var loop: Task<Void, Never>?
  private let defaults = UserDefaults.standard
  private let debug = ProcessInfo.processInfo.arguments.contains("-LMDebugUpdate")

  /// Inicia a verificação (chamar uma vez ao abrir o app). Sem painel configurado, não faz nada.
  func start() {
    guard loop == nil else { return }
    loop = Task { [weak self] in
      try? await Task.sleep(for: .seconds(2))
      while !Task.isCancelled {
        await self?.check()
        try? await Task.sleep(for: .seconds(6 * 3600))
      }
    }
  }

  func check() async {
    if debug {
      offer = UpdateOffer(build: 999, versionName: "5.2.0", url: "https://example.com/Lume-Music-5.2.0.ipa",
                          notes: "• Player mais rápido\n• Correções de estabilidade\n• Novos temas de vidro", mandatory: false)
      return
    }
    let access = AccessService.shared
    await access.ensureConfig()
    guard access.panelAvailable else { return }
    do {
      let (status, json) = try await access.send("GET", "/api/app/update",
                                                 query: ["platform": AccessConfig.platform, "build": AccessConfig.buildNumber, "app": AccessConfig.appVersion], timeout: 10)
      guard status == 200, (json["ok"] as? Bool) == true, (json["available"] as? Bool) == true,
            let url = json["url"] as? String, !url.isEmpty else {
        if status == 200 { offer = nil }
        return
      }
      func num(_ v: Any?) -> Int { Int((v as? Double) ?? (v as? Int).map(Double.init) ?? (v as? NSNumber)?.doubleValue ?? 0) }
      let o = UpdateOffer(build: num(json["build"]), versionName: (json["versionName"] as? String) ?? "nova",
                          url: url, notes: ((json["notes"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                          mandatory: (json["mandatory"] as? Bool) ?? false)
      guard o.build > (Int(AccessConfig.buildNumber) ?? 0) else { offer = nil; return }
      if !o.mandatory, let until = defaults.object(forKey: deferKey(o.build)) as? Date, until > Date() { return }
      offer = o
    } catch {
      // sem rede: tenta no próximo ciclo
    }
  }

  private func deferKey(_ build: Int) -> String { "lume.update.deferred.\(build)" }

  /// "Depois": adia 24 h para aquela versão.
  func postpone() {
    guard let o = offer, !o.mandatory else { return }
    defaults.set(Date().addingTimeInterval(24 * 3600), forKey: deferKey(o.build))
    offer = nil
  }

  func openDownload() {
    guard let o = offer, let url = URL(string: o.url) else { return }
    UIApplication.shared.open(url)
    if !o.mandatory { offer = nil }
  }
}

struct UpdatePopupCard: View {
  let offer: UpdateOffer
  @ObservedObject private var update = UpdateService.shared

  var body: some View {
    GlassPopup {
      ZStack {
        Circle().fill(Color.clear).frame(width: 72, height: 72).glassCircle(tint: Theme.sky.opacity(0.35))
        Image(systemName: "arrow.down.circle.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.prismDiagonal)
      }
      VStack(spacing: 8) {
        Text("Nova versão \(offer.versionName) disponível")
          .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
        if !offer.notes.isEmpty {
          ScrollView {
            Text(offer.notes)
              .font(Theme.font(14)).foregroundStyle(Theme.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxHeight: 140)
          .padding(12)
          .glass(16)
        }
        Text("Depois de baixar, instale pelo LiveContainer.")
          .font(Theme.font(12.5)).foregroundStyle(Theme.tertiary).multilineTextAlignment(.center)
      }
      VStack(spacing: 10) {
        PrismButton(title: "Atualizar agora", systemImage: "arrow.down.to.line", height: 50) { update.openDownload() }
        if !offer.mandatory {
          GlassButton(title: "Depois", height: 48) { update.postpone() }
        }
      }
    }
  }
}
