import SwiftUI
import Security

// MARK: - Configuração

/// Descoberta da URL do painel de códigos de acesso (contrato v1).
/// 1. `defaultAPIBase` compilada; 2. config remota (tem prioridade quando não vazia); 3. sem URL → portão DESLIGADO.
enum AccessConfig {
  /// Vazia até o painel existir. Quando existir, pode ser preenchida aqui ou (melhor) no arquivo remoto.
  static let defaultAPIBase = ""
  static let remoteConfigURL = "https://raw.githubusercontent.com/Drill23/lume-music/main/config/painel.json"
  static let appVersion = "5.0.0"
  static let platform = "ios"
  static let codeAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
}

struct AccessInfo: Codable, Equatable {
  var code: String
  var lifetime: Bool
  /// Milissegundos desde 1970; nil se vitalício.
  var expires: Double?
  var planKind: String?      // months | days | lifetime
  var planValue: Int?
  var message: String?
  var note: String?
  var activatedAt: Double?

  var expiresDate: Date? { expires.map { Date(timeIntervalSince1970: $0 / 1000) } }
  var stillValid: Bool { lifetime || (expiresDate.map { $0 > Date() } ?? false) }

  /// AB••CD
  var maskedCode: String {
    guard code.count == 6 else { return code }
    return String(code.prefix(2)) + "••" + String(code.suffix(2))
  }
}

struct AccessError: LocalizedError {
  let code: String
  let message: String
  /// true quando é recusa do servidor (401/403) — bloqueia; false = rede/5xx.
  let isDenial: Bool
  var errorDescription: String? { message }
}

// MARK: - Serviço

@MainActor
final class AccessService: ObservableObject {
  static let shared = AccessService()

  @Published private(set) var info: AccessInfo?
  /// Mensagem do servidor quando um usuário já ativado perdeu o acesso (revogado, expirado, aparelho removido).
  @Published var lockedMessage: String?
  @Published private(set) var apiBase: String = ""
  @Published private(set) var required: Bool = true
  @Published private(set) var configLoaded = false

  /// `-LMAccessMock`: simula um servidor (LUME26 = 3 meses, VITA01 = vitalício, outros = inválido).
  let mock = ProcessInfo.processInfo.arguments.contains("-LMAccessMock")

  private let defaults = UserDefaults.standard
  private var configTask: Task<Void, Never>?
  private var monitorTask: Task<Void, Never>?
  private var lastCheck: Date? {
    get { defaults.object(forKey: "lume.access.lastCheck") as? Date }
    set { defaults.set(newValue, forKey: "lume.access.lastCheck") }
  }

  private init() {
    if let data = defaults.data(forKey: "lume.access.info"), let saved = try? JSONDecoder().decode(AccessInfo.self, from: data) {
      info = saved
    }
    applyConfig(base: AccessConfig.defaultAPIBase, required: true)
    if let data = defaults.data(forKey: "lume.access.config"),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let base = obj["apiBase"] as? String, !base.isEmpty {
      applyConfig(base: base, required: (obj["required"] as? Bool) ?? true)
    }
  }

  private func applyConfig(base: String, required: Bool) {
    var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
    while b.hasSuffix("/") { b.removeLast() }
    apiBase = b
    self.required = required
  }

  // MARK: Estado derivado

  /// O portão só liga com URL do painel (ou mock) e `required != false`.
  var gateEnabled: Bool { mock || (!apiBase.isEmpty && required) }
  var hasValidAccess: Bool { (info?.stillValid ?? false) && lockedMessage == nil }
  /// Precisa mostrar a tela de código agora.
  var needsCode: Bool { gateEnabled && !hasValidAccess }

  // MARK: Identidade do aparelho

  /// UUID único, guardado no Keychain (sobrevive a reinstalações) com cópia em UserDefaults como reserva.
  var deviceId: String {
    if let v = Keychain.get("lume.access.device") { return v }
    if let v = defaults.string(forKey: "lume.access.device"), v.count >= 8 { Keychain.set(v, for: "lume.access.device"); return v }
    let v = UUID().uuidString
    Keychain.set(v, for: "lume.access.device")
    defaults.set(v, forKey: "lume.access.device")
    return v
  }

  private var token: String? {
    get { Keychain.get("lume.access.token") }
    set { if let newValue { Keychain.set(newValue, for: "lume.access.token") } else { Keychain.remove("lume.access.token") } }
  }

  // MARK: Config remota

  /// Baixa `painel.json` (timeout 6 s). Chamadas simultâneas aguardam a mesma tarefa.
  func ensureConfig() async {
    if let t = configTask { await t.value; return }
    let task = Task { await self.fetchConfig() }
    configTask = task
    await task.value
  }

  private func fetchConfig() async {
    defer { configLoaded = true }
    guard let url = URL(string: AccessConfig.remoteConfigURL) else { return }
    var req = URLRequest(url: url)
    req.timeoutInterval = 6
    req.cachePolicy = .reloadIgnoringLocalCacheData
    guard let (data, resp) = try? await URLSession.shared.data(for: req),
          (resp as? HTTPURLResponse)?.statusCode == 200,
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
    let base = (obj["apiBase"] as? String) ?? ""
    if !base.isEmpty {
      defaults.set(data, forKey: "lume.access.config")
      applyConfig(base: base, required: (obj["required"] as? Bool) ?? true)
    } else if obj.keys.contains("apiBase") {
      // O painel foi removido da config: volta ao modo pré-painel.
      defaults.removeObject(forKey: "lume.access.config")
      applyConfig(base: AccessConfig.defaultAPIBase, required: true)
    }
  }

  // MARK: Ativar

  static func normalize(_ raw: String) -> String {
    String(raw.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
  }

  func activate(code raw: String) async throws -> AccessInfo {
    let code = Self.normalize(raw)
    guard code.count == 6 else {
      throw AccessError(code: "bad_request", message: "O código tem 6 caracteres.", isDenial: true)
    }
    if mock { return try await mockActivate(code) }
    guard gateEnabled else { throw AccessError(code: "no_panel", message: "O painel de códigos ainda não está disponível.", isDenial: false) }

    let body: [String: Any] = [
      "code": code, "device": deviceId, "platform": AccessConfig.platform,
      "app": AccessConfig.appVersion, "name": UIDevice.current.name,
    ]
    let (status, json) = try await post("/api/access/activate", body: body, bearer: nil)
    guard status == 200, (json["ok"] as? Bool) == true, let tok = json["token"] as? String else {
      let msg = (json["message"] as? String) ?? Self.defaultMessage(status)
      throw AccessError(code: (json["error"] as? String) ?? "error", message: msg, isDenial: status >= 400 && status < 500)
    }
    var parsed = Self.parseInfo(json, fallbackCode: code)
    parsed.code = code
    token = tok
    store(parsed)
    lastCheck = Date()
    startMonitoring()
    return parsed
  }

  private func mockActivate(_ code: String) async throws -> AccessInfo {
    try? await Task.sleep(for: .milliseconds(1100))
    switch code {
    case "LUME26":
      var c = DateComponents(); c.year = 2027; c.month = 2; c.day = 26; c.hour = 12
      let exp = Calendar(identifier: .gregorian).date(from: c) ?? Date().addingTimeInterval(90 * 86400)
      let i = AccessInfo(code: code, lifetime: false, expires: exp.timeIntervalSince1970 * 1000, planKind: "months", planValue: 3,
                         message: "Código válido por 3 meses.", note: nil, activatedAt: Date().timeIntervalSince1970 * 1000)
      store(i); return i
    case "VITA01":
      let i = AccessInfo(code: code, lifetime: true, expires: nil, planKind: "lifetime", planValue: nil,
                         message: "Acesso vitalício.", note: "Obrigado por comprar!", activatedAt: Date().timeIntervalSince1970 * 1000)
      store(i); return i
    default:
      throw AccessError(code: "invalid_code", message: "Código inválido. Confira e tente de novo.", isDenial: true)
    }
  }

  // MARK: Checar

  /// Chama `/check`. Só 401/403 bloqueia; rede/5xx mantém o acesso enquanto `lifetime`/`expires` valerem.
  func check() async {
    guard gateEnabled, let current = info else { return }
    if mock { lastCheck = Date(); return }
    guard let tok = token else {
      // Sem token guardado (ex.: Keychain apagado): pede o código de novo, sem tocar na biblioteca.
      lockedMessage = "Digite seu código de acesso novamente para continuar."
      return
    }
    let body: [String: Any] = ["device": deviceId, "app": AccessConfig.appVersion, "platform": AccessConfig.platform]
    do {
      let (status, json) = try await post("/api/access/check", body: body, bearer: tok)
      if status == 200, (json["ok"] as? Bool) != false {
        var updated = Self.parseInfo(json, fallbackCode: current.code)
        if updated.code.isEmpty { updated.code = current.code }
        store(updated)
        lockedMessage = nil
        lastCheck = Date()
      } else if status == 401 || status == 403 {
        let msg = (json["message"] as? String) ?? "Seu acesso não está mais ativo. Digite um código válido."
        revokeLocally(message: msg)
      }
      // outros status (429, 5xx): tolerância
    } catch {
      // rede: tolerância offline
    }
  }

  /// Checa se passaram 6 h desde a última checagem.
  func checkIfDue() async {
    guard gateEnabled, info != nil else { return }
    if let last = lastCheck, Date().timeIntervalSince(last) < 6 * 3600 { return }
    await check()
  }

  /// Verifica ao iniciar e a cada 6 h em primeiro plano.
  func startMonitoring() {
    monitorTask?.cancel()
    monitorTask = Task { [weak self] in
      await self?.ensureConfig()
      await self?.check()
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(6 * 3600))
        await self?.check()
      }
    }
  }

  private func revokeLocally(message: String) {
    token = nil
    lockedMessage = message
    // `info` fica guardado só para mascarar o código na tela; o acesso é negado por `lockedMessage`.
  }

  /// Remove a ativação deste aparelho (botão "Trocar código" libera a tela para novo código).
  func signOutForCodeChange() {
    token = nil
    info = nil
    defaults.removeObject(forKey: "lume.access.info")
    lockedMessage = nil
  }

  // MARK: Textos

  func successTitle(_ i: AccessInfo) -> String {
    i.lifetime ? "Acesso vitalício ✨" : "Código válido por \(Self.planText(i))"
  }

  func successSubtitle(_ i: AccessInfo) -> String {
    if i.lifetime { return "Obrigado por comprar!" }
    if let d = i.expiresDate { return "até \(Self.longDate(d))" }
    return i.message ?? ""
  }

  static func planText(_ i: AccessInfo) -> String {
    let v = i.planValue ?? 0
    switch i.planKind {
    case "months": return v == 1 ? "1 mês" : "\(v) meses"
    case "days": return v == 1 ? "1 dia" : "\(v) dias"
    default:
      if let d = i.expiresDate {
        let days = max(1, Int(d.timeIntervalSinceNow / 86400))
        return days >= 60 ? "\(days / 30) meses" : "\(days) dias"
      }
      return "tempo limitado"
    }
  }

  static func longDate(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "pt_BR")
    f.dateFormat = "d 'de' MMMM 'de' yyyy"
    return f.string(from: d)
  }

  static func shortDate(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "pt_BR")
    f.dateFormat = "dd/MM/yyyy"
    return f.string(from: d)
  }

  // MARK: Rede / persistência

  private func store(_ i: AccessInfo) {
    info = i
    if let data = try? JSONEncoder().encode(i) { defaults.set(data, forKey: "lume.access.info") }
  }

  private static func parseInfo(_ j: [String: Any], fallbackCode: String) -> AccessInfo {
    let plan = j["plan"] as? [String: Any]
    func num(_ v: Any?) -> Double? { (v as? Double) ?? (v as? Int).map(Double.init) ?? (v as? NSNumber)?.doubleValue }
    let note = (j["note"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    return AccessInfo(
      code: (j["code"] as? String) ?? fallbackCode,
      lifetime: (j["lifetime"] as? Bool) ?? ((plan?["kind"] as? String) == "lifetime"),
      expires: num(j["expires"]),
      planKind: plan?["kind"] as? String,
      planValue: num(plan?["value"]).map { Int($0) },
      message: j["message"] as? String,
      note: note,
      activatedAt: num(j["activatedAt"])
    )
  }

  private static func defaultMessage(_ status: Int) -> String {
    switch status {
    case 429: return "Muitas tentativas. Aguarde alguns minutos e tente de novo."
    case 500...: return "O servidor está indisponível agora. Tente de novo em instantes."
    default: return "Não foi possível validar o código."
    }
  }

  private func post(_ path: String, body: [String: Any], bearer: String?) async throws -> (Int, [String: Any]) {
    guard let url = URL(string: apiBase + path) else {
      throw AccessError(code: "bad_url", message: "Endereço do painel inválido.", isDenial: false)
    }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.timeoutInterval = 12
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
      let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
      return (status, json)
    } catch {
      throw AccessError(code: "network", message: "Sem conexão com o servidor. Verifique a internet e tente de novo.", isDenial: false)
    }
  }
}

// MARK: - Keychain

enum Keychain {
  private static let service = "com.adriano.lumemusic.access"

  static func get(_ key: String) -> String? {
    let q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key,
      kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var out: AnyObject?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else {
      // Reserva em UserDefaults (ex.: ambiente sem Keychain).
      return UserDefaults.standard.string(forKey: "kc.\(key)")
    }
    return String(data: d, encoding: .utf8)
  }

  static func set(_ value: String, for key: String) {
    remove(key, alsoFallback: false)
    let q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key,
      kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    if SecItemAdd(q as CFDictionary, nil) != errSecSuccess {
      UserDefaults.standard.set(value, forKey: "kc.\(key)")
    }
  }

  static func remove(_ key: String, alsoFallback: Bool = true) {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    SecItemDelete(q as CFDictionary)
    if alsoFallback { UserDefaults.standard.removeObject(forKey: "kc.\(key)") }
  }
}

// MARK: - Campo de código (6 caixinhas de vidro)

struct ShakeEffect: GeometryEffect {
  var travel: CGFloat = 10
  var shakes: CGFloat
  var animatableData: CGFloat {
    get { shakes }
    set { shakes = newValue }
  }
  func effectValue(size: CGSize) -> ProjectionTransform {
    ProjectionTransform(CGAffineTransform(translationX: travel * sin(shakes * .pi * 4), y: 0))
  }
}

/// Entrada do código: 6 caixinhas de vidro, teclado ASCII maiúsculo, colar funciona, "tremer" no erro e brilho prisma carregando.
struct AccessCodeView: View {
  var title: String = "Digite seu código de acesso"
  var subtitle: String = "O código tem 6 letras e números. Ele chegou junto com a sua compra."
  /// Mensagem exibida logo ao abrir (ex.: quando o servidor tirou o acesso).
  var initialMessage: String?
  var autoFocus = true
  let onActivated: (AccessInfo) -> Void

  @ObservedObject private var access = AccessService.shared
  @State private var code = ""
  @State private var loading = false
  @State private var errorText: String?
  @State private var shakes: CGFloat = 0
  @State private var shimmer: CGFloat = -1
  @FocusState private var focused: Bool

  var body: some View {
    VStack(spacing: 22) {
      VStack(spacing: 8) {
        Text(title)
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundStyle(Theme.text)
          .multilineTextAlignment(.center)
        Text(subtitle)
          .font(Theme.font(14.5))
          .foregroundStyle(Theme.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }

      boxes
        .modifier(ShakeEffect(shakes: shakes))
        .onTapGesture { focused = true }
        .overlay {
          TextField("", text: $code)
            .focused($focused)
            .keyboardType(.asciiCapable)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .textContentType(.oneTimeCode)
            .submitLabel(.go)
            .onSubmit { Task { await submit() } }
            .opacity(0.015)
            .disabled(loading)
            .accessibilityLabel("Código de acesso")
        }
        .onChange(of: code) { _, new in
          let n = AccessService.normalize(new)
          if n != new { code = n }
          if errorText != nil { withAnimation(.easeOut(duration: 0.2)) { errorText = nil } }
          if n.count == 6, !loading { Task { await submit() } }
          if !n.isEmpty, n.count > 0 { SoundFX.shared.play(.tap) }
        }

      Group {
        if let errorText {
          Label(errorText, systemImage: "exclamationmark.circle.fill")
            .font(Theme.font(14, .medium))
            .foregroundStyle(Theme.danger)
            .multilineTextAlignment(.center)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else if loading {
          Text("Conferindo seu código…")
            .font(Theme.font(14, .medium))
            .foregroundStyle(Theme.secondary)
            .transition(.opacity)
        } else {
          Text(" ").font(Theme.font(14))
        }
      }
      .frame(minHeight: 40)

      HStack(spacing: 12) {
        PasteButton(payloadType: String.self) { strings in
          guard let s = strings.first else { return }
          Task { @MainActor in
            code = AccessService.normalize(s)
            Haptics.light()
          }
        }
        .labelStyle(.titleAndIcon)
        .buttonBorderShape(.capsule)
        .tint(Theme.lavender)
        .frame(minHeight: 44)
        .disabled(loading)

        Button {
          Task { await submit() }
        } label: {
          HStack(spacing: 8) {
            Text("Ativar").font(Theme.font(16, .semibold))
            Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
          }
          .foregroundStyle(Theme.onPrism)
          .frame(maxWidth: .infinity, minHeight: 48)
          .background(Capsule().fill(Theme.prismDiagonal))
          .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 0.8))
          .shadow(color: Theme.rose.opacity(0.3), radius: 12, y: 5)
        }
        .buttonStyle(PressableStyle())
        .disabled(loading || code.count < 6)
        .opacity(code.count < 6 ? 0.45 : 1)
      }
    }
    .onAppear {
      if let initialMessage { errorText = initialMessage }
      if autoFocus { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { focused = true } }
    }
  }

  private var boxes: some View {
    HStack(spacing: 10) {
      ForEach(0..<6, id: \.self) { i in
        let chars = Array(code)
        let ch: String = i < chars.count ? String(chars[i]) : ""
        let isCurrent = focused && i == min(chars.count, 5) && !loading
        ZStack {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.clear)
            .frame(width: 46, height: 58)
            .glass(14, tint: errorText != nil ? Theme.danger.opacity(0.4) : (ch.isEmpty ? nil : Theme.lavender.opacity(0.35)))
          Text(ch)
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.text)
            .scaleEffect(ch.isEmpty ? 0.6 : 1)
            .opacity(ch.isEmpty ? 0 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: ch)
          if isCurrent && ch.isEmpty {
            Capsule().fill(Theme.accent).frame(width: 2, height: 26)
              .opacity(0.8)
          }
          if loading {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .fill(LinearGradient(colors: [.clear, Theme.peach.opacity(0.55), Theme.rose.opacity(0.55), Theme.lavender.opacity(0.5), .clear],
                                   startPoint: .leading, endPoint: .trailing))
              .frame(width: 46, height: 58)
              .mask(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                  .frame(width: 46, height: 58)
              )
              .opacity(shimmerOpacity(i))
          }
        }
        .overlay(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(isCurrent ? AnyShapeStyle(Theme.prismDiagonal) : AnyShapeStyle(Color.clear), lineWidth: 2)
            .frame(width: 46, height: 58)
        )
        .scaleEffect(isCurrent ? 1.05 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isCurrent)
      }
    }
    .contentShape(Rectangle())
  }

  private func shimmerOpacity(_ i: Int) -> Double {
    // Onda de brilho que atravessa as caixinhas da esquerda para a direita.
    let pos = Double(i) / 5.0
    let d = abs(pos - Double((shimmer + 1) / 2))
    return max(0, 1 - d * 3.2)
  }

  private func submit() async {
    guard !loading, code.count == 6 else { return }
    focused = false
    loading = true
    shimmer = -1
    withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { shimmer = 1 }
    Haptics.medium()
    defer { loading = false }
    do {
      let info = try await access.activate(code: code)
      SoundFX.shared.play(.success)
      Haptics.success()
      onActivated(info)
    } catch {
      let msg = (error as? AccessError)?.message ?? error.localizedDescription
      SoundFX.shared.play(.error)
      UINotificationFeedbackGenerator().notificationOccurred(.error)
      withAnimation(.easeOut(duration: 0.5)) { shakes += 1 }
      withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { errorText = msg }
      focused = true
    }
  }
}

// MARK: - Sucesso do código

struct AccessSuccessView: View {
  let info: AccessInfo
  var buttonTitle = "Continuar"
  let onContinue: () -> Void

  @State private var appear = false
  @State private var sparkle = false

  var body: some View {
    VStack(spacing: 22) {
      ZStack {
        ForEach(0..<10, id: \.self) { i in
          let angle = Double(i) / 10 * 2 * .pi
          Image(systemName: i % 2 == 0 ? "sparkle" : "star.fill")
            .font(.system(size: i % 2 == 0 ? 16 : 9, weight: .bold))
            .foregroundStyle(Theme.prismColors[i % 4])
            .offset(x: sparkle ? CGFloat(cos(angle)) * 92 : 0, y: sparkle ? CGFloat(sin(angle)) * 92 : 0)
            .scaleEffect(sparkle ? 1 : 0.2)
            .opacity(sparkle ? 0 : 1)
            .animation(.easeOut(duration: 0.9).delay(0.12), value: sparkle)
        }
        Circle()
          .fill(Color.clear)
          .frame(width: 112, height: 112)
          .glassCircle(tint: Theme.mint.opacity(0.35))
        Circle()
          .trim(from: 0, to: appear ? 1 : 0)
          .stroke(Theme.prismAngular, style: StrokeStyle(lineWidth: 4, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .frame(width: 112, height: 112)
        Image(systemName: info.lifetime ? "infinity" : "checkmark")
          .font(.system(size: 44, weight: .bold))
          .foregroundStyle(Theme.text)
          .scaleEffect(appear ? 1 : 0.3)
          .opacity(appear ? 1 : 0)
      }
      .frame(height: 140)

      VStack(spacing: 8) {
        Text(AccessService.shared.successTitle(info))
          .font(.system(size: 28, weight: .bold, design: .rounded))
          .foregroundStyle(Theme.text)
          .multilineTextAlignment(.center)
        Text(AccessService.shared.successSubtitle(info))
          .font(Theme.font(17, .medium))
          .foregroundStyle(Theme.secondary)
          .multilineTextAlignment(.center)
        if let note = info.note, !(info.lifetime && note.caseInsensitiveCompare("Obrigado por comprar!") == .orderedSame) {
          Text(note)
            .font(Theme.font(15))
            .foregroundStyle(Theme.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .glass(16)
            .padding(.top, 6)
        }
      }
      .opacity(appear ? 1 : 0)
      .offset(y: appear ? 0 : 12)

      PrismButton(title: buttonTitle, systemImage: "arrow.right", height: 52, action: onContinue)
        .opacity(appear ? 1 : 0)
    }
    .onAppear {
      withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) { appear = true }
      sparkle = true
    }
  }
}

// MARK: - Tela de bloqueio (usuário já ativado que perdeu o acesso, ou sem código)

/// Tela cheia pedindo o código. NÃO mexe na biblioteca do usuário.
struct AccessGateView: View {
  @ObservedObject private var access = AccessService.shared
  @State private var activated: AccessInfo?

  var body: some View {
    ZStack {
      Theme.canvas.ignoresSafeArea()
      OnboardingBackdrop(phase: 1, running: true).ignoresSafeArea()
      VStack(spacing: 28) {
        Spacer(minLength: 20)
        PrismMark(size: 64)
        if let info = activated {
          AccessSuccessView(info: info, buttonTitle: "Entrar na Lume") {
            withAnimation(.easeInOut(duration: 0.3)) { access.lockedMessage = nil }
          }
          .transition(.scale(scale: 0.95).combined(with: .opacity))
        } else {
          AccessCodeView(
            title: access.lockedMessage == nil ? "Digite seu código de acesso" : "Precisamos do seu código",
            initialMessage: access.lockedMessage
          ) { info in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { activated = info }
          }
          .transition(.opacity)
        }
        Spacer(minLength: 20)
        Text("Sua biblioteca continua guardada neste iPhone.")
          .font(Theme.font(12.5))
          .foregroundStyle(Theme.tertiary)
      }
      .padding(.horizontal, 24)
    }
  }
}

// MARK: - Cartão para Ajustes

/// Cartão "Seu acesso": código mascarado, status, validade e botão "Trocar código". Para a frente de Ajustes incluir.
struct AccessStatusCard: View {
  @ObservedObject private var access = AccessService.shared
  @State private var changing = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(Theme.onPrism)
          .frame(width: 44, height: 44)
          .background(Circle().fill(Theme.prismDiagonal))
        VStack(alignment: .leading, spacing: 2) {
          Text("Seu acesso")
            .font(Theme.font(17, .semibold))
            .foregroundStyle(Theme.text)
          Text(statusLine)
            .font(Theme.font(13.5))
            .foregroundStyle(statusColor)
        }
        Spacer(minLength: 0)
      }
      if let info = access.info {
        HStack {
          Text("Código")
            .font(Theme.font(14)).foregroundStyle(Theme.secondary)
          Spacer()
          Text(info.maskedCode)
            .font(.system(size: 17, weight: .bold, design: .monospaced))
            .foregroundStyle(Theme.text)
        }
        if let note = info.note {
          Text(note).font(Theme.font(13)).foregroundStyle(Theme.secondary)
        }
      }
      if access.gateEnabled {
        GlassButton(title: "Trocar código", systemImage: "key.fill", height: 46) { changing = true }
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glass(24)
    .sheet(isPresented: $changing) { ChangeCodeSheet() }
  }

  private var icon: String {
    if !access.gateEnabled { return "lock.open.fill" }
    return access.info?.lifetime == true ? "infinity" : "key.fill"
  }

  private var statusLine: String {
    guard access.gateEnabled else { return "Acesso livre" }
    guard let i = access.info else { return "Sem código ativado" }
    if access.lockedMessage != nil { return "Acesso interrompido" }
    if i.lifetime { return "Vitalício" }
    if let d = i.expiresDate { return d > Date() ? "Válido até \(AccessService.shortDate(d))" : "Venceu em \(AccessService.shortDate(d))" }
    return "Ativo"
  }

  private var statusColor: Color {
    guard access.gateEnabled, let i = access.info, access.lockedMessage == nil, i.stillValid else { return access.gateEnabled ? Theme.danger : Theme.secondary }
    return Theme.ok
  }
}

private struct ChangeCodeSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var done: AccessInfo?

  var body: some View {
    ZStack {
      Theme.canvas.ignoresSafeArea()
      VStack {
        Spacer()
        if let done {
          AccessSuccessView(info: done, buttonTitle: "Pronto") { dismiss() }
        } else {
          AccessCodeView(title: "Trocar código", subtitle: "Digite o novo código. O código atual só é substituído se o novo for válido.") { info in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { done = info }
          }
        }
        Spacer()
      }
      .padding(.horizontal, 24)
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
  }
}
