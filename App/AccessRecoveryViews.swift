import SwiftUI

// MARK: - Campo de PIN (6 caixas de vidro, SecureField)

struct PinBoxes: View {
  @Binding var pin: String
  var shake: CGFloat = 0
  var failed = false
  var disabled = false
  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: 10) {
      ForEach(0..<6, id: \.self) { i in
        let filled = i < pin.count
        let current = focused && i == min(pin.count, 5)
        ZStack {
          RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.clear)
            .frame(width: 44, height: 56)
            .glass(14, tint: failed ? Theme.danger.opacity(0.4) : (filled ? Theme.lavender.opacity(0.35) : nil))
          Circle().fill(Theme.text).frame(width: 12, height: 12)
            .scaleEffect(filled ? 1 : 0.2).opacity(filled ? 1 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: filled)
        }
        .overlay(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(current ? AnyShapeStyle(Theme.prismDiagonal) : AnyShapeStyle(Color.clear), lineWidth: 2)
            .frame(width: 44, height: 56)
        )
        .scaleEffect(current ? 1.05 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: current)
      }
    }
    .modifier(ShakeEffect(shakes: shake))
    .contentShape(Rectangle())
    .onTapGesture { focused = true }
    .overlay {
      SecureField("", text: $pin)
        .focused($focused)
        .keyboardType(.numberPad)
        .textContentType(.oneTimeCode)
        .opacity(0.015)
        .disabled(disabled)
        .accessibilityLabel("PIN de 6 dígitos")
        .onChange(of: pin) { _, new in
          let n = String(new.filter(\.isNumber).prefix(6))
          if n != new { pin = n }
        }
    }
    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { focused = true } }
  }
}

// MARK: - Criar / trocar PIN de recuperação

struct PinSetupView: View {
  let mandatory: Bool
  let onDone: () -> Void

  private enum Stage { case enter, confirm, saving, done }

  @ObservedObject private var purchase = PurchaseService.shared
  @State private var stage: Stage = .enter
  @State private var pin = ""
  @State private var first = ""
  @State private var errorText: String?
  @State private var shakes: CGFloat = 0
  @State private var appear = false

  var body: some View {
    ZStack {
      Theme.canvas.ignoresSafeArea()
      OnboardingBackdrop(phase: 1, running: true).ignoresSafeArea()
      VStack(spacing: 24) {
        HStack {
          Spacer()
          if !mandatory && stage != .done {
            Button { onDone() } label: {
              Text("Cancelar").font(Theme.font(15, .semibold)).foregroundStyle(Theme.text)
                .padding(.horizontal, 16).frame(minHeight: 44).glassCapsule(interactive: true)
            }
            .buttonStyle(PressableStyle())
          }
        }
        .frame(height: 44)
        Spacer(minLength: 0)
        if stage == .done { doneView } else { formView }
        Spacer(minLength: 0)
        Text("Seu PIN fica guardado só no painel, de forma protegida.")
          .font(Theme.font(12.5)).foregroundStyle(Theme.tertiary)
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 12)
    }
  }

  private var formView: some View {
    VStack(spacing: 22) {
      ZStack {
        Circle().fill(Color.clear).frame(width: 76, height: 76).glassCircle(tint: Theme.lavender.opacity(0.35))
        Image(systemName: "lock.shield.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.prismDiagonal)
      }
      VStack(spacing: 8) {
        Text(stage == .enter ? "Crie seu PIN de recuperação" : "Confirme seu PIN")
          .font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
        Text(stage == .enter
             ? "São 6 números. Com ele você leva a sua conta Lume Vitalício para outro celular se perder este aparelho. Só você deve saber."
             : "Digite o mesmo PIN mais uma vez.")
          .font(Theme.font(14.5)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      PinBoxes(pin: $pin, shake: shakes, failed: errorText != nil, disabled: stage == .saving)
        .onChange(of: pin) { _, new in if new.count == 6 { Task { await advance() } } else if errorText != nil { errorText = nil } }
      Group {
        if let errorText {
          Label(errorText, systemImage: "exclamationmark.circle.fill")
            .font(Theme.font(14, .medium)).foregroundStyle(Theme.danger).multilineTextAlignment(.center)
        } else if stage == .saving {
          HStack(spacing: 8) { PrismSpinner(size: 18); Text("Guardando seu PIN…").font(Theme.font(14, .medium)).foregroundStyle(Theme.secondary) }
        } else {
          Text(" ").font(Theme.font(14))
        }
      }
      .frame(minHeight: 40)
      if stage == .confirm {
        GlassButton(title: "Voltar", systemImage: "chevron.left", height: 46) { pin = ""; first = ""; stage = .enter; errorText = nil }
      }
    }
  }

  private var doneView: some View {
    VStack(spacing: 20) {
      ZStack {
        SparkleBurst()
        Circle().fill(Color.clear).frame(width: 96, height: 96).glassCircle(tint: Theme.mint.opacity(0.4))
        Image(systemName: "checkmark").font(.system(size: 40, weight: .bold)).foregroundStyle(Theme.text)
          .scaleEffect(appear ? 1 : 0.3)
      }
      .frame(height: 120)
      Text("PIN criado!").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
      Text("Guarde-o em um lugar seguro. Você vai precisar dele para trazer sua conta a outro celular se perder este.")
        .font(Theme.font(14.5)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
      PrismButton(title: "Concluir", systemImage: "arrow.right", height: 52) { onDone() }
    }
    .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appear = true } }
  }

  private func advance() async {
    guard pin.count == 6 else { return }
    switch stage {
    case .enter:
      first = pin; pin = ""; stage = .confirm
      Haptics.light()
    case .confirm:
      if pin != first {
        withAnimation(.easeOut(duration: 0.5)) { shakes += 1 }
        withAnimation { errorText = "Os PINs não são iguais. Tente de novo." }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        pin = ""; first = ""; stage = .enter
        return
      }
      stage = .saving
      do {
        try await purchase.setPin(pin)
        Haptics.success()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { stage = .done }
      } catch {
        stage = .confirm
        withAnimation(.easeOut(duration: 0.5)) { shakes += 1 }
        withAnimation { errorText = (error as? AccessError)?.message ?? error.localizedDescription }
        pin = ""
      }
    default: break
    }
  }
}

// MARK: - Código de transferência (aparelho antigo)

struct TransferCodeView: View {
  var autoStart = false
  @ObservedObject private var purchase = PurchaseService.shared
  @State private var code: String?
  @State private var expires = Date()
  @State private var loading = false
  @State private var errorText: String?
  @State private var copied = false

  var body: some View {
    VStack(spacing: 18) {
      ZStack {
        Circle().fill(Color.clear).frame(width: 72, height: 72).glassCircle(tint: Theme.lavender.opacity(0.35))
        Image(systemName: "iphone.and.arrow.forward").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.prismDiagonal)
      }
      Text("Transferir para outro aparelho")
        .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Theme.text).multilineTextAlignment(.center)

      if let code {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
          let left = max(0, Int(expires.timeIntervalSince(ctx.date)))
          VStack(spacing: 12) {
            if left > 0 {
              Text("\(code.prefix(4)) \(code.suffix(4))")
                .font(.system(size: 36, weight: .bold, design: .monospaced)).foregroundStyle(Theme.text)
                .minimumScaleFactor(0.6).lineLimit(1)
                .padding(.horizontal, 18).padding(.vertical, 14)
                .glass(20, tint: Theme.lavender.opacity(0.3))
                .accessibilityLabel("Código de transferência \(code.map(String.init).joined(separator: " "))")
              Label(String(format: "Vale por mais %02d:%02d", left / 60, left % 60), systemImage: "timer")
                .font(Theme.font(14, .semibold)).foregroundStyle(left < 60 ? Theme.danger : Theme.secondary)
                .monospacedDigit()
              GlassButton(title: copied ? "Copiado" : "Copiar", systemImage: copied ? "checkmark" : "doc.on.doc", height: 50) {
                UIPasteboard.general.string = code
                Haptics.success(); copied = true
                Task { try? await Task.sleep(for: .seconds(1.6)); copied = false }
              }
            } else {
              Text("O código venceu.").font(Theme.font(15, .medium)).foregroundStyle(Theme.secondary)
              GlassButton(title: "Gerar novo código", systemImage: "arrow.clockwise", height: 50) { Task { await generate() } }
            }
          }
        }
        Text("No aparelho novo: abra a Lume › “Já sou vitalício” › “Tenho um código de transferência” e digite este código. Vale uma vez só. Depois, este aparelho perde o acesso.")
          .font(Theme.font(13)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text("Gere um código de uso único (vale 15 minutos) e digite no aparelho novo. Depois da transferência, este aparelho perde o acesso vitalício.")
          .font(Theme.font(14)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
        if loading {
          HStack(spacing: 8) { PrismSpinner(size: 18); Text("Gerando…").font(Theme.font(14, .medium)).foregroundStyle(Theme.secondary) }
            .frame(minHeight: 50)
        } else {
          PrismButton(title: "Gerar código de transferência", systemImage: "key.radiowaves.forward.fill", height: 52) { Task { await generate() } }
        }
      }
      if let errorText {
        Label(errorText, systemImage: "exclamationmark.circle.fill")
          .font(Theme.font(14, .medium)).foregroundStyle(Theme.danger).multilineTextAlignment(.center)
      }
    }
    .task { if autoStart, code == nil { await generate() } }
  }

  private func generate() async {
    loading = true; errorText = nil
    defer { loading = false }
    do {
      let r = try await purchase.transferCode()
      code = r.code; expires = r.expires
      Haptics.success()
    } catch {
      errorText = (error as? AccessError)?.message ?? error.localizedDescription
    }
  }
}

struct TransferDemoCard: View {
  @ObservedObject private var popups = Popups.shared
  var body: some View {
    GlassPopup {
      TransferCodeView(autoStart: true)
      GlassButton(title: "Fechar", height: 46) { popups.dismiss() }
    }
  }
}

struct TransferSheet: View {
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    ZStack {
      Theme.canvas.ignoresSafeArea()
      ScrollView {
        TransferCodeView()
          .padding(.horizontal, 24).padding(.top, 36).padding(.bottom, 30)
          .frame(maxWidth: 480).frame(maxWidth: .infinity)
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
  }
}

// MARK: - "Já sou vitalício" (aparelho novo)

/// Campo de texto de vidro (código de 6/8 caracteres).
private struct GlassCodeField: View {
  let title: String
  @Binding var text: String
  let length: Int
  var secure = false
  var numeric = false

  var body: some View {
    Group {
      if secure {
        SecureField(title, text: $text).keyboardType(.numberPad).textContentType(.oneTimeCode)
      } else {
        TextField(title, text: $text)
          .keyboardType(.asciiCapable)
          .textInputAutocapitalization(.characters)
          .autocorrectionDisabled()
      }
    }
    .font(.system(size: 22, weight: .bold, design: .monospaced))
    .multilineTextAlignment(.center)
    .foregroundStyle(Theme.text)
    .frame(height: 56)
    .glass(18, tint: text.isEmpty ? nil : Theme.lavender.opacity(0.3))
    .onChange(of: text) { _, new in
      let f = numeric ? String(new.filter(\.isNumber).prefix(length)) : String(new.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(length))
      if f != new { text = f }
    }
  }
}

struct ClaimLifetimeSheet: View {
  var prefillCode: String?
  /// Chamado ao tocar em "Pronto" depois do sucesso (o portão se fecha aqui).
  var onFinished: () -> Void = {}

  private enum Mode { case transfer, codePin, forgot }

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var access = AccessService.shared
  @State private var mode: Mode = .transfer
  @State private var transferCode = ""
  @State private var code = ""
  @State private var pin = ""
  @State private var orderText = ""
  @State private var loading = false
  @State private var errorText: String?
  @State private var done: AccessInfo?

  private var orderReady: Bool { (orderText.count == 8 && orderText.hasPrefix("LM")) || orderText.count == 6 }
  private var ready: Bool {
    switch mode {
    case .transfer: return transferCode.count == 8
    case .codePin: return code.count == 6 && pin.count == 6
    case .forgot: return orderReady && pin.count == 6
    }
  }

  var body: some View {
    ZStack {
      Theme.canvas.ignoresSafeArea()
      ScrollView {
        VStack(spacing: 20) {
          if let done {
            AccessSuccessView(info: done, buttonTitle: "Pronto", showsWelcome: false) { onFinished(); dismiss() }
              .padding(.top, 40)
          } else { form }
        }
        .padding(.horizontal, 24).padding(.vertical, 30)
        .frame(maxWidth: 480).frame(maxWidth: .infinity)
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .onAppear { if let p = prefillCode, code.isEmpty { code = p } }
  }

  private var form: some View {
    VStack(spacing: 18) {
      VStack(spacing: 8) {
        Text("Já sou vitalício").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
        Text("Traga sua conta para este aparelho. O aparelho antigo deixa de ter o acesso.")
          .font(Theme.font(14.5)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      option(.transfer, "Tenho um código de transferência", "Gerado no aparelho antigo, em Ajustes", "iphone.and.arrow.forward")
      option(.codePin, "Código vitalício + PIN", "Se o aparelho antigo se perdeu", "lock.shield")
      option(.forgot, "Esqueci meu código", "Número do pedido + PIN", "questionmark.key.fill")

      Group {
        if mode == .transfer {
          GlassCodeField(title: "Código de 8 caracteres", text: $transferCode, length: 8)
        } else if mode == .forgot {
          VStack(spacing: 12) {
            GlassCodeField(title: "LM-______", text: $orderText, length: 8)
            GlassCodeField(title: "PIN de 6 dígitos", text: $pin, length: 6, secure: true, numeric: true)
            Text("O número do pedido aparece no comprovante do seu Pix. Isso desconecta a Lume do outro aparelho.")
              .font(Theme.font(12.5)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
          }
        } else {
          VStack(spacing: 12) {
            GlassCodeField(title: "Código vitalício", text: $code, length: 6)
            GlassCodeField(title: "PIN de 6 dígitos", text: $pin, length: 6, secure: true, numeric: true)
          }
        }
      }

      if let errorText {
        Label(errorText, systemImage: "exclamationmark.circle.fill")
          .font(Theme.font(14, .medium)).foregroundStyle(Theme.danger).multilineTextAlignment(.center)
      }

      Button {
        Task { await submit() }
      } label: {
        HStack(spacing: 8) {
          if loading { PrismSpinner(size: 18) }
          Text(loading ? "Conferindo…" : "Trazer minha conta").font(Theme.font(16, .semibold))
        }
        .foregroundStyle(Theme.onPrism)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(Capsule().fill(Theme.prismDiagonal))
        .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 0.8))
        .shadow(color: Theme.rose.opacity(0.3), radius: 12, y: 5)
      }
      .buttonStyle(PressableStyle())
      .disabled(!ready || loading)
      .opacity(ready ? 1 : 0.45)
    }
  }

  private func option(_ m: Mode, _ title: String, _ sub: String, _ icon: String) -> some View {
    Button {
      Haptics.selection()
      withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { mode = m; errorText = nil }
    } label: {
      HStack(spacing: 14) {
        Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.text)
          .frame(width: 40, height: 40).glassCircle()
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(Theme.font(15.5, .semibold)).foregroundStyle(Theme.text)
          Text(sub).font(Theme.font(12.5)).foregroundStyle(Theme.secondary)
        }
        Spacer(minLength: 0)
        Image(systemName: mode == m ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 20)).foregroundStyle(mode == m ? Theme.accent : Theme.tertiary)
      }
      .padding(.horizontal, 14).padding(.vertical, 10)
      .frame(maxWidth: .infinity, minHeight: 60)
      .glass(20, tint: mode == m ? Theme.lavender.opacity(0.3) : nil)
      .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
        .stroke(mode == m ? AnyShapeStyle(Theme.prismDiagonal) : AnyShapeStyle(Color.clear), lineWidth: 1.6))
    }
    .buttonStyle(PressableStyle())
    .accessibilityAddTraits(mode == m ? .isSelected : [])
  }

  private func submit() async {
    guard ready, !loading else { return }
    loading = true; errorText = nil
    defer { loading = false }
    Haptics.medium()
    do {
      let info: AccessInfo
      switch mode {
      case .transfer: info = try await access.transfer(transferCode: transferCode)
      case .codePin: info = try await access.transfer(code: code, pin: pin)
      case .forgot: info = try await access.transfer(order: orderText, pin: pin)
      }
      SoundFX.shared.play(.success); Haptics.success()
      withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { done = info }
    } catch {
      SoundFX.shared.play(.error)
      UINotificationFeedbackGenerator().notificationOccurred(.error)
      withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { errorText = (error as? AccessError)?.message ?? error.localizedDescription }
    }
  }
}

// MARK: - Restaurar compra (mesmo aparelho)

struct RestorePurchaseSheet: View {
  var prefillCode: String?
  var onFinished: () -> Void = {}

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var purchase = PurchaseService.shared
  @State private var input = ""
  @State private var loading = false
  @State private var errorText: String?
  @State private var done: AccessInfo?

  var body: some View {
    ZStack {
      Theme.canvas.ignoresSafeArea()
      ScrollView {
        VStack(spacing: 18) {
          if let done {
            AccessSuccessView(info: done, buttonTitle: "Pronto", showsWelcome: false) { onFinished(); dismiss() }.padding(.top, 40)
          } else {
            Text("Restaurar compra").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
            Text("Digite o código vitalício (6 caracteres) ou o número do pedido (LM-XXXXXX). Serve para este mesmo aparelho. Para trazer a conta de outro celular, use “Já sou vitalício”.")
              .font(Theme.font(14.5)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
            TextField("Código ou LM-XXXXXX", text: $input)
              .keyboardType(.asciiCapable).textInputAutocapitalization(.characters).autocorrectionDisabled()
              .font(.system(size: 20, weight: .bold, design: .monospaced)).multilineTextAlignment(.center)
              .foregroundStyle(Theme.text).frame(height: 56).glass(18, tint: input.isEmpty ? nil : Theme.lavender.opacity(0.3))
              .submitLabel(.go).onSubmit { Task { await submit() } }
            if let errorText {
              Label(errorText, systemImage: "exclamationmark.circle.fill")
                .font(Theme.font(14, .medium)).foregroundStyle(Theme.danger).multilineTextAlignment(.center)
            }
            Button { Task { await submit() } } label: {
              HStack(spacing: 8) {
                if loading { PrismSpinner(size: 18) }
                Text(loading ? "Conferindo…" : "Restaurar").font(Theme.font(16, .semibold))
              }
              .foregroundStyle(Theme.onPrism).frame(maxWidth: .infinity, minHeight: 52)
              .background(Capsule().fill(Theme.prismDiagonal))
              .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 0.8))
            }
            .buttonStyle(PressableStyle())
            .disabled(input.trimmingCharacters(in: .whitespaces).count < 6 || loading)
            .opacity(input.trimmingCharacters(in: .whitespaces).count < 6 ? 0.45 : 1)
          }
        }
        .padding(.horizontal, 24).padding(.vertical, 30)
        .frame(maxWidth: 480).frame(maxWidth: .infinity)
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .onAppear { if let p = prefillCode, input.isEmpty { input = p } }
  }

  private func submit() async {
    guard !loading else { return }
    loading = true; errorText = nil
    defer { loading = false }
    do {
      let info = try await purchase.restore(input: input)
      SoundFX.shared.play(.success); Haptics.success()
      withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { done = info }
    } catch {
      SoundFX.shared.play(.error)
      UINotificationFeedbackGenerator().notificationOccurred(.error)
      withAnimation { errorText = (error as? AccessError)?.message ?? error.localizedDescription }
    }
  }
}

// MARK: - Ver meu código (protegido pelo PIN)

struct RevealCodeSheet: View {
  private enum Stage { case pin, loading, shown(code: String, order: String?) }

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var purchase = PurchaseService.shared
  @State private var stage: Stage = .pin
  @State private var canVerify = PurchaseService.shared.canVerifyPinLocally
  @State private var creatingPin = false
  @State private var pin = ""
  @State private var errorText: String?
  @State private var shakes: CGFloat = 0
  @State private var attempts = 0
  @State private var lockedUntil = Date.distantPast
  @State private var copiedCode = false
  @State private var copiedOrder = false

  var body: some View {
    ZStack {
      Theme.canvas.ignoresSafeArea()
      if creatingPin {
        PinSetupView(mandatory: false) { creatingPin = false; canVerify = purchase.canVerifyPinLocally }
      } else {
        ScrollView {
          VStack(spacing: 22) { content }
            .padding(.horizontal, 24).padding(.vertical, 36)
            .frame(maxWidth: 480).frame(maxWidth: .infinity)
        }
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
  }

  @ViewBuilder private var content: some View {
    ZStack {
      Circle().fill(Color.clear).frame(width: 72, height: 72).glassCircle(tint: Theme.lavender.opacity(0.35))
      Image(systemName: "eye.fill").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.prismDiagonal)
    }
    switch stage {
    case .pin where !canVerify:
      Text("Crie um PIN neste aparelho").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
      Text("Para proteger o seu código, ele só aparece depois do PIN. Este aparelho ainda não conhece o seu PIN: crie (ou troque) o PIN agora.")
        .font(Theme.font(14.5)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      PrismButton(title: "Criar PIN", systemImage: "lock.shield.fill", height: 52) { creatingPin = true }
    case .pin:
      Text("Digite seu PIN").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
      Text("Para ver o código e o número do pedido.").font(Theme.font(14.5)).foregroundStyle(Theme.secondary)
      PinBoxes(pin: $pin, shake: shakes, failed: errorText != nil)
        .onChange(of: pin) { _, new in
          if new.count == 6 { Task { await verify() } } else if errorText != nil { errorText = nil }
        }
      Group {
        if let errorText {
          Label(errorText, systemImage: "exclamationmark.circle.fill")
            .font(Theme.font(14, .medium)).foregroundStyle(Theme.danger).multilineTextAlignment(.center)
        } else { Text(" ").font(Theme.font(14)) }
      }
      .frame(minHeight: 40)
    case .loading:
      HStack(spacing: 8) { PrismSpinner(size: 18); Text("Buscando seu código…").font(Theme.font(14, .medium)).foregroundStyle(Theme.secondary) }
        .frame(minHeight: 60)
    case .shown(let code, let order):
      Text("Seu acesso vitalício").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
      CodeBoxesRow(code: code)
      if let order {
        Text("Pedido \(order)").font(.system(size: 17, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
      }
      VStack(spacing: 10) {
        GlassButton(title: copiedCode ? "Código copiado" : "Copiar código", systemImage: copiedCode ? "checkmark" : "doc.on.doc", height: 48) {
          UIPasteboard.general.string = code; Haptics.success(); copiedCode = true
          Task { try? await Task.sleep(for: .seconds(1.6)); copiedCode = false }
        }
        if let order {
          GlassButton(title: copiedOrder ? "Pedido copiado" : "Copiar nº do pedido", systemImage: copiedOrder ? "checkmark" : "doc.on.doc", height: 48) {
            UIPasteboard.general.string = order; Haptics.success(); copiedOrder = true
            Task { try? await Task.sleep(for: .seconds(1.6)); copiedOrder = false }
          }
        }
      }
      Text("Guarde o número do pedido e o seu PIN: com eles você recupera a conta em outro celular. O número também aparece no comprovante do seu Pix.")
        .font(Theme.font(12.5)).foregroundStyle(Theme.tertiary).multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      PrismButton(title: "Fechar", height: 50) { dismiss() }
    }
  }

  private func verify() async {
    guard pin.count == 6 else { return }
    if lockedUntil > Date() {
      let s = Int(lockedUntil.timeIntervalSinceNow.rounded(.up))
      withAnimation { errorText = "Muitas tentativas. Tente de novo em \(s) s." }
      pin = ""; return
    }
    guard purchase.verifyPin(pin) else {
      attempts += 1
      if attempts >= 5 { attempts = 0; lockedUntil = Date().addingTimeInterval(60) }
      withAnimation(.easeOut(duration: 0.5)) { shakes += 1 }
      withAnimation { errorText = "PIN incorreto." }
      UINotificationFeedbackGenerator().notificationOccurred(.error)
      pin = ""; return
    }
    stage = .loading
    do {
      let r = try await purchase.loadLifetimeCredentials()
      Haptics.success()
      withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { stage = .shown(code: r.code, order: r.order) }
    } catch {
      stage = .pin
      pin = ""
      errorText = (error as? AccessError)?.message ?? error.localizedDescription
    }
  }
}
