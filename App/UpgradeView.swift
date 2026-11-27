import SwiftUI

// MARK: - Fila de pop-ups de vidro (boas-vindas, pagamento confirmado, PIN, transferência)

@MainActor
final class Popups: ObservableObject {
  static let shared = Popups()

  enum Kind: Equatable {
    case welcome(days: Int, reminder: Bool)
    case paid(code: String, order: String?, debug: Bool)
    case pin(mandatory: Bool)
    case transferDemo
  }

  @Published private(set) var current: Kind?
  /// Sheet de upgrade (apresentada na raiz do app, serve para Ajustes, pop-up e portão).
  @Published var showUpgrade = false
  private var queue: [Kind] = []

  func present(_ kind: Kind) {
    if current == kind || queue.contains(kind) { return }
    if current == nil { current = kind } else { queue.append(kind) }
  }

  func dismiss() {
    current = nil
    guard !queue.isEmpty else { return }
    let next = queue.removeFirst()
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(380))
      if self.current == nil { self.current = next }
    }
  }

  func openUpgrade() {
    if current != nil { dismiss() }
    Haptics.light()
    showUpgrade = true
  }

  // MARK: Boas-vindas

  /// Logo após ativar um código com prazo (onboarding, portão e "Tenho um código").
  func welcomeAfterActivation(_ info: AccessInfo) {
    guard !info.lifetime, let days = info.daysLeft, days > 0 else { return }
    markReminders(info.code, days: days)
    present(.welcome(days: days, reminder: false))
  }

  private func reminderKey(_ code: String, _ tier: Int) -> String { "lume.welcome.shown.\(code).\(tier)" }

  private func markReminders(_ code: String, days: Int) {
    if days <= 3 { UserDefaults.standard.set(true, forKey: reminderKey(code, 3)) }
    if days <= 1 { UserDefaults.standard.set(true, forKey: reminderKey(code, 1)) }
  }

  /// Reaparece uma vez com 3 dias e uma vez com 1 dia restante.
  func checkReminders(_ access: AccessService) {
    guard access.panelAvailable, access.hasValidAccess, let info = access.info, !info.lifetime,
          let days = info.daysLeft, days >= 1, current == nil else { return }
    let d = UserDefaults.standard
    if days <= 1, !d.bool(forKey: reminderKey(info.code, 1)) {
      d.set(true, forKey: reminderKey(info.code, 1)); d.set(true, forKey: reminderKey(info.code, 3))
      present(.welcome(days: days, reminder: true))
    } else if days <= 3, !d.bool(forKey: reminderKey(info.code, 3)) {
      d.set(true, forKey: reminderKey(info.code, 3))
      present(.welcome(days: days, reminder: true))
    }
  }
}

// MARK: - Contêiner de vidro

struct GlassPopup<Content: View>: View {
  @ViewBuilder let content: () -> Content
  @State private var contentHeight: CGFloat = 0

  /// Rolável quando não cabe (iPhone SE, fonte grande, teclado): os botões do pop-up nunca ficam escondidos.
  var body: some View {
    ScrollView {
      VStack(spacing: 16) { content() }
        .padding(22)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
    }
    .scrollBounceBehavior(.basedOnSize)
    .scrollIndicators(.hidden)
    .scrollClipDisabled()
    .frame(maxWidth: 340)
    .frame(maxHeight: contentHeight > 0 ? contentHeight : .infinity)
    .glass(34)
    .shadow(color: .black.opacity(0.35), radius: 30, y: 14)
    .padding(.horizontal, 24)
    .padding(.vertical, 28)
  }
}

// MARK: - Hospedeiro dos pop-ups (fica por cima de tudo)

struct PopupHost: View {
  /// true enquanto o onboarding / portão / intro estão na tela (adia lembretes e avisos de atualização).
  let blocked: Bool

  @ObservedObject private var popups = Popups.shared
  @ObservedObject private var update = UpdateService.shared
  @ObservedObject private var access = AccessService.shared
  @ObservedObject private var purchase = PurchaseService.shared
  @Environment(\.scenePhase) private var scenePhase
  @State private var debugDone = false

  private var showUpdate: Bool { popups.current == nil && !blocked && update.offer != nil }

  var body: some View {
    ZStack {
      if case .pin(let mandatory) = popups.current {
        PinSetupView(mandatory: mandatory) { popups.dismiss() }
          .transition(.opacity)
          .zIndex(2)
      } else if popups.current != nil || showUpdate {
        Color.black.opacity(0.5).ignoresSafeArea()
          .transition(.opacity)
          .onTapGesture {}
        Group {
          switch popups.current {
          case .welcome(let days, let reminder): WelcomePopupCard(days: days, reminder: reminder)
          case .paid(let code, let order, let debug): PaidPopupCard(code: code, order: order, debug: debug)
          case .transferDemo: TransferDemoCard()
          default:
            if let offer = update.offer { UpdatePopupCard(offer: offer) }
          }
        }
        .transition(.scale(scale: 0.86).combined(with: .opacity))
        // O pop-up fica por cima de tudo: fecha o teclado que estava aberto atrás dele.
        .onAppear { LumeKeyboard.dismiss() }
      }
    }
    .animation(.spring(response: 0.42, dampingFraction: 0.78), value: popups.current)
    .animation(.spring(response: 0.42, dampingFraction: 0.78), value: update.offer?.build)
    .allowsHitTesting(popups.current != nil || showUpdate)
    .task { await launchTasks() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await resumeChecks() } }
    }
    .onChange(of: blocked) { _, nowBlocked in
      if !nowBlocked { Task { await resumeChecks() } }
    }
  }

  private func launchTasks() async {
    try? await Task.sleep(for: .milliseconds(900))
    if !debugDone {
      debugDone = true
      if let d = Onboarding.debugValue("-LMDebugWelcome"), let n = Int(d) { popups.present(.welcome(days: n, reminder: false)) }
      if let c = Onboarding.debugValue("-LMDebugPaid") { popups.present(.paid(code: AccessService.normalize(c), order: nil, debug: true)) }
      if ProcessInfo.processInfo.arguments.contains("-LMDebugTransfer") { popups.present(.transferDemo) }
      if ProcessInfo.processInfo.arguments.contains("-LMDebugPin") { popups.present(.pin(mandatory: true)) }
      if purchase.debugUpgrade { popups.showUpgrade = true }
    }
    await resumeChecks()
  }

  private func resumeChecks() async {
    // Pagamento confirmado que ainda não foi ativado (app fechado no meio): reabre o pop-up.
    if let code = access.vault.get(AccessKeys.paidCode), code.count == 6, !(access.isLifetime && access.lifetimeCode == code) {
      popups.present(.paid(code: code, order: nil, debug: false))
    } else if purchase.pinPending, access.isLifetime {
      popups.present(.pin(mandatory: true))
    }
    guard !blocked else { return }
    await purchase.resumeIfPending()
    popups.checkReminders(access)
  }
}

// MARK: - Caixas de código (somente leitura)

struct CodeBoxesRow: View {
  let code: String
  var width: CGFloat = 40
  var height: CGFloat = 52
  var tint: Color? = Theme.lavender.opacity(0.35)

  var body: some View {
    HStack(spacing: 8) {
      ForEach(Array(code.enumerated()), id: \.offset) { _, ch in
        Text(String(ch))
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundStyle(Theme.text)
          .frame(width: width, height: height)
          .glass(13, tint: tint)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Código \(code.map(String.init).joined(separator: " "))")
  }
}

/// Indicador de espera: arco prisma girando.
struct PrismSpinner: View {
  var size: CGFloat = 22
  @State private var spin = false
  var body: some View {
    Circle()
      .trim(from: 0, to: 0.72)
      .stroke(Theme.prismAngular, style: StrokeStyle(lineWidth: size / 7, lineCap: .round))
      .frame(width: size, height: size)
      .rotationEffect(.degrees(spin ? 360 : 0))
      .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
      .onAppear { spin = true }
  }
}

/// Explosão leve de brilhos (confete discreto).
struct SparkleBurst: View {
  @State private var go = false
  var body: some View {
    ZStack {
      ForEach(0..<12, id: \.self) { i in
        let a = Double(i) / 12 * 2 * .pi
        Image(systemName: i % 2 == 0 ? "sparkle" : "star.fill")
          .font(.system(size: i % 2 == 0 ? 15 : 8, weight: .bold))
          .foregroundStyle(Theme.prismColors[i % 4])
          .offset(x: go ? CGFloat(cos(a)) * 84 : 0, y: go ? CGFloat(sin(a)) * 84 : 0)
          .scaleEffect(go ? 1 : 0.2)
          .opacity(go ? 0 : 1)
          .animation(.easeOut(duration: 1.0).delay(0.1), value: go)
      }
    }
    .allowsHitTesting(false)
    .onAppear { go = true }
  }
}

// MARK: - Pop-up de boas-vindas

struct WelcomePopupCard: View {
  let days: Int
  let reminder: Bool
  @ObservedObject private var purchase = PurchaseService.shared
  @ObservedObject private var popups = Popups.shared

  private var daysText: String { days == 1 ? "1 dia" : "\(days) dias" }

  var body: some View {
    GlassPopup {
      ZStack {
        Circle().fill(Color.clear).frame(width: 76, height: 76).glassCircle(tint: Theme.lavender.opacity(0.35))
        Image(systemName: reminder ? "hourglass" : "sparkles")
          .font(.system(size: 30, weight: .bold))
          .foregroundStyle(Theme.prismDiagonal)
      }
      VStack(spacing: 8) {
        Text(reminder ? (days == 1 ? "Seu período grátis acaba amanhã" : "Seu período grátis está acabando") : "Bem-vindo à Lume ✨")
          .font(.system(size: 23, weight: .bold, design: .rounded))
          .foregroundStyle(Theme.text)
          .multilineTextAlignment(.center)
        Group {
          if reminder {
            Text(days == 1 ? "Falta **1 dia** para o fim do período grátis." : "Faltam **\(days) dias** para o fim do período grátis.")
          } else {
            Text("Você tem **\(daysText) grátis** para curtir tudo.")
          }
        }
        .font(Theme.font(16.5, .medium))
        .foregroundStyle(Theme.text)
        .multilineTextAlignment(.center)
        Text(reminder ? "Garanta a Lume para sempre com um pagamento único, sem mensalidade."
                      : "Música sem limites. Quando quiser, leve a Lume para sempre com um pagamento único.")
          .font(Theme.font(14))
          .foregroundStyle(Theme.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      VStack(spacing: 10) {
        PrismButton(title: "Começar a ouvir", systemImage: "play.fill", height: 50) { popups.dismiss() }
        if purchase.available || Onboarding.debugValue("-LMDebugWelcome") != nil {
          GlassButton(title: purchase.priceText.map { "Quero o vitalício · \($0)" } ?? "Quero o vitalício", systemImage: "infinity", height: 50) {
            popups.openUpgrade()
          }
        }
      }
    }
  }
}

// MARK: - Pop-up "Pagamento confirmado!"

struct PaidPopupCard: View {
  let code: String
  let order: String?
  let debug: Bool

  private enum Phase { case activating, done, failed(String) }

  @ObservedObject private var purchase = PurchaseService.shared
  @ObservedObject private var popups = Popups.shared
  @State private var phase: Phase = .activating
  @State private var copied = false
  @State private var appear = false
  @State private var shownOrder: String?

  var body: some View {
    GlassPopup {
      ZStack {
        SparkleBurst()
        Circle().fill(Color.clear).frame(width: 84, height: 84).glassCircle(tint: Theme.mint.opacity(0.4))
        Image(systemName: "checkmark")
          .font(.system(size: 36, weight: .bold))
          .foregroundStyle(Theme.text)
          .scaleEffect(appear ? 1 : 0.3)
          .opacity(appear ? 1 : 0)
      }
      .frame(height: 96)

      VStack(spacing: 6) {
        Text("Pagamento confirmado!")
          .font(.system(size: 24, weight: .bold, design: .rounded))
          .foregroundStyle(Theme.text)
          .multilineTextAlignment(.center)
        switch phase {
        case .activating:
          HStack(spacing: 8) {
            PrismSpinner(size: 18)
            Text("Ativando seu acesso vitalício…").font(Theme.font(15, .medium)).foregroundStyle(Theme.secondary)
          }
        case .done:
          Text("Acesso vitalício ✨ Obrigado por comprar!")
            .font(Theme.font(16, .medium)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
        case .failed(let msg):
          Label(msg, systemImage: "exclamationmark.circle.fill")
            .font(Theme.font(14, .medium)).foregroundStyle(Theme.danger).multilineTextAlignment(.center)
        }
      }

      VStack(spacing: 8) {
        Text("Seu código vitalício").font(Theme.font(13)).foregroundStyle(Theme.secondary)
        CodeBoxesRow(code: code)
        if let o = shownOrder ?? order {
          Text("Pedido \(o)")
            .font(.system(size: 16, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
        }
        Text("Guarde o número do pedido e o seu PIN: com eles você recupera a conta em outro celular. O número também aparece no comprovante do seu Pix.")
          .font(Theme.font(12.5)).foregroundStyle(Theme.tertiary).multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
        Button {
          UIPasteboard.general.string = code
          Haptics.light()
          copied = true
          Task { try? await Task.sleep(for: .seconds(1.6)); copied = false }
        } label: {
          Label(copied ? "Copiado" : "Copiar código", systemImage: copied ? "checkmark" : "doc.on.doc")
            .font(Theme.font(14, .semibold)).foregroundStyle(Theme.text)
            .frame(minWidth: 140, minHeight: 44)
            .glassCapsule(interactive: true)
        }
        .buttonStyle(PressableStyle())
      }

      switch phase {
      case .activating: EmptyView()
      case .done:
        PrismButton(title: "Continuar", systemImage: "arrow.right", height: 50) {
          popups.dismiss()
          if !debug, purchase.pinPending { popups.present(.pin(mandatory: true)) }
        }
      case .failed:
        PrismButton(title: "Tentar de novo", systemImage: "arrow.clockwise", height: 50) { Task { await activate() } }
      }
    }
    .task {
      withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.15)) { appear = true }
      Haptics.success()
      await activate()
    }
  }

  private func activate() async {
    phase = .activating
    if debug {
      try? await Task.sleep(for: .milliseconds(900))
      shownOrder = order ?? "LM-7K3Q9X"
      phase = .done
      return
    }
    do {
      let info = try await purchase.activatePaid(code: code, order: order)
      shownOrder = info.purchase ?? order ?? AccessService.shared.lifetimeOrder
      SoundFX.shared.play(.success)
      phase = .done
    } catch {
      phase = .failed((error as? AccessError)?.message ?? error.localizedDescription)
    }
  }
}

// MARK: - Sheet de upgrade

struct UpgradeView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject private var purchase = PurchaseService.shared
  @State private var copiedPix = false
  @State private var copiedKey = false
  @State private var qr: UIImage?
  @State private var qrFor = ""

  var body: some View {
    ZStack {
      Theme.canvas.ignoresSafeArea()
      ScrollView {
        VStack(spacing: 22) {
          header
          benefits
          content
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 36)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .lumeSheetScroll()
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .task { await purchase.prepare() }
    .onAppear { purchase.startPolling() }
    .onDisappear { purchase.stopPolling() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { purchase.startPolling(); Task { await purchase.refreshStatus() } } else { purchase.stopPolling() }
    }
    .onChange(of: purchase.order) { _, o in
      if o != nil { purchase.startPolling() }
      refreshQR()
    }
    .onAppear { refreshQR() }
  }

  private func refreshQR() {
    guard let c = purchase.order?.copiaECola, !c.isEmpty, c != qrFor else { return }
    qrFor = c
    qr = QRCodeImage.make(c)
  }

  // MARK: Partes

  private var header: some View {
    ZStack(alignment: .top) {
      VStack(spacing: 10) {
        ZStack {
          Circle().fill(Color.clear).frame(width: 78, height: 78).glassCircle(tint: Theme.lavender.opacity(0.35))
          Image(systemName: "infinity").font(.system(size: 32, weight: .bold)).foregroundStyle(Theme.prismDiagonal)
        }
        Text("Lume Vitalício")
          .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
        if let p = purchase.order?.amountText ?? purchase.priceText {
          Text(p)
            .font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(Theme.prismDiagonal)
          Text("pagamento único").font(Theme.font(13.5)).foregroundStyle(Theme.secondary)
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.top, 14)
      HStack {
        Color.clear.frame(width: 44, height: 44)
        Spacer()
        Button { Haptics.light(); dismiss() } label: {
          Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
            .frame(width: 44, height: 44).glassCircle(interactive: true)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Fechar")
      }
    }
  }

  private var benefits: some View {
    VStack(alignment: .leading, spacing: 14) {
      benefit("infinity", "Para sempre no seu aparelho")
      benefit("arrow.triangle.2.circlepath", "Todas as atualizações")
      benefit("calendar.badge.minus", "Sem mensalidade")
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glass(24)
  }

  private func benefit(_ icon: String, _ text: String) -> some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.onPrism)
        .frame(width: 38, height: 38).background(Circle().fill(Theme.prismDiagonal))
      Text(text).font(Theme.font(16, .medium)).foregroundStyle(Theme.text)
      Spacer(minLength: 0)
    }
    .frame(minHeight: 44)
  }

  @ViewBuilder private var content: some View {
    if let o = purchase.order {
      VStack(spacing: 16) {
        if let url = o.checkoutUrl.flatMap(URL.init(string:)) {
          PrismButton(title: "Pagar com Pix ou cartão", systemImage: "creditcard.fill", height: 54) {
            UIApplication.shared.open(url)
          }
        }
        pixSection(o)
        if let e = purchase.errorText { errorLine(e) }
      }
    } else if purchase.loading {
      HStack(spacing: 10) {
        PrismSpinner()
        Text("Preparando seu pagamento…").font(Theme.font(15, .medium)).foregroundStyle(Theme.secondary)
      }
      .frame(maxWidth: .infinity, minHeight: 80)
    } else {
      VStack(spacing: 14) {
        errorLine(purchase.errorText ?? "Não foi possível preparar o pagamento.")
        GlassButton(title: "Tentar de novo", systemImage: "arrow.clockwise", height: 50) { Task { await purchase.prepare() } }
      }
    }
  }

  private func errorLine(_ text: String) -> some View {
    Label(text, systemImage: "exclamationmark.circle.fill")
      .font(Theme.font(14, .medium)).foregroundStyle(Theme.danger).multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
  }

  private func pixSection(_ o: PurchaseOrder) -> some View {
    VStack(spacing: 16) {
      Text(o.checkoutUrl == nil ? "Pague com Pix" : "Ou pague com Pix")
        .font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)

      if !o.copiaECola.isEmpty {
        Group {
          if let qr {
            Image(uiImage: qr).resizable().interpolation(.none).scaledToFit()
          } else {
            PrismSpinner(size: 28)
          }
        }
        .frame(width: 200, height: 200)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.6), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .accessibilityLabel("QR Code do Pix")

        VStack(spacing: 10) {
          GlassButton(title: copiedPix ? "Copiado" : "Copiar Pix copia e cola", systemImage: copiedPix ? "checkmark" : "doc.on.doc", height: 52) {
            UIPasteboard.general.string = o.copiaECola
            Haptics.success()
            copiedPix = true
            Task { try? await Task.sleep(for: .seconds(1.6)); copiedPix = false }
          }
          if !o.automatic, let key = o.pixKey {
            GlassButton(title: copiedKey ? "Chave copiada" : "Copiar chave", systemImage: copiedKey ? "checkmark" : "key.fill", height: 52) {
              UIPasteboard.general.string = key
              Haptics.success()
              copiedKey = true
              Task { try? await Task.sleep(for: .seconds(1.6)); copiedKey = false }
            }
          }
        }
      }

      if o.automatic {
        HStack(spacing: 12) {
          PrismSpinner(size: 22)
          Text("Assim que o Pix cair, seu acesso vitalício é liberado sozinho — pode deixar esta tela aberta")
            .font(Theme.font(14.5, .medium)).foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glass(20)
      } else {
        manualFooter
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity)
    .glass(28)
  }

  @ViewBuilder private var manualFooter: some View {
    if purchase.status == .review {
      HStack(spacing: 12) {
        PrismSpinner(size: 22)
        VStack(alignment: .leading, spacing: 2) {
          Text("Aguardando confirmação").font(Theme.font(15, .semibold)).foregroundStyle(Theme.text)
          Text(purchase.message ?? "Assim que o pagamento for confirmado, seu código aparece aqui.")
            .font(Theme.font(13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      .padding(16)
      .frame(maxWidth: .infinity)
      .glass(20)
    } else {
      VStack(spacing: 8) {
        PrismButton(title: purchase.claiming ? "Enviando…" : "Já paguei", systemImage: "checkmark.circle.fill", height: 54) {
          Task { await purchase.claim() }
        }
        .disabled(purchase.claiming)
        .opacity(purchase.claiming ? 0.6 : 1)
        Text("Depois de pagar, toque aqui para avisar. A liberação acontece assim que o pagamento for confirmado.")
          .font(Theme.font(12.5)).foregroundStyle(Theme.tertiary).multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}
