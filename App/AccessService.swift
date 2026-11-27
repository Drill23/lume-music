import SwiftUI
import Security

// MARK: - Configuração

/// Descoberta da URL do painel de códigos de acesso (contrato v1).
/// 1. `defaultAPIBase` compilada; 2. config remota (tem prioridade quando não vazia); 3. sem URL → portão DESLIGADO.
enum AccessConfig {
  /// Vazia até o painel existir. Quando existir, pode ser preenchida aqui ou (melhor) no arquivo remoto.
  static let defaultAPIBase = ""
  static let remoteConfigURL = "https://raw.githubusercontent.com/Drill23/lume-music/main/config/painel.json"
  static let appVersion: String = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "5.1.0"
  static let buildNumber: String = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "8"
  static let platform = "ios"
  static let codeAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
}

/// Nomes de chaves do Keychain. NUNCA renomear (a migração é só aditiva; o vitalício precisa sobreviver a atualizações).
enum AccessKeys {
  static let token = "lume.access.token"
  static let device = "lume.access.device"
  static let lifetimeCode = "lume.access.lifetimeCode"
  static let lifetimeOrder = "lume.access.order"
  static let paidCode = "lume.purchase.paidCode"
  static let pinHash = "lume.purchase.pinHash"
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
  /// "LM-XXXXXX" quando o código veio de uma compra.
  var purchase: String?

  var expiresDate: Date? { expires.map { Date(timeIntervalSince1970: $0 / 1000) } }
  var stillValid: Bool { lifetime || (expiresDate.map { $0 > Date() } ?? false) }

  /// Dias que faltam (arredonda para cima, com 5 min de tolerância). nil se vitalício/sem prazo.
  var daysLeft: Int? {
    guard !lifetime, let d = expiresDate else { return nil }
    return max(0, Int(ceil((d.timeIntervalSinceNow - 300) / 86400)))
  }

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

// MARK: - Armazenamento de segredos

protocol SecretStore {
  func get(_ key: String) -> String?
  func set(_ value: String, for key: String)
  func remove(_ key: String)
  /// Garante que um valor que só existe na cópia de reserva (UserDefaults) vá também para o Keychain.
  func ensureStored(_ key: String)
}

extension SecretStore { func ensureStored(_ key: String) {} }

struct KeychainSecretStore: SecretStore {
  func get(_ key: String) -> String? { Keychain.get(key) }
  func set(_ value: String, for key: String) { Keychain.set(value, for: key) }
  func remove(_ key: String) { Keychain.remove(key) }
  func ensureStored(_ key: String) {
    if Keychain.getStrict(key) == nil, let v = Keychain.get(key) { Keychain.set(v, for: key) }
  }
}

/// Usado nos autotestes (`-LMSelfTest`): nunca toca o Keychain real.
final class MemorySecretStore: SecretStore {
  private var box: [String: String] = [:]
  func get(_ key: String) -> String? { box[key] }
  func set(_ value: String, for key: String) { box[key] = value }
  func remove(_ key: String) { box[key] = nil }
}

/// Resultado do teste grátis automático (contrato v2.3).
enum TrialResult {
  case started(AccessInfo)
  /// Painel com o teste desligado (ou sem painel): usa o passo de código antigo.
  case disabled
  /// 403 trial_used: o teste deste aparelho já terminou.
  case used(String)
  /// 429 trial_rate_limited (limite de testes por IP).
  case limited(String)
  /// Rede/5xx/timeout.
  case unreachable
}

typealias AccessTransport = (URLRequest) async throws -> (Data, URLResponse)

// MARK: - Serviço

@MainActor
final class AccessService: ObservableObject {
  static let shared = AccessService(isShared: true)

  @Published private(set) var info: AccessInfo?
  /// Mensagem do servidor quando um usuário já ativado perdeu o acesso (revogado, expirado, aparelho removido).
  @Published var lockedMessage: String?
  @Published private(set) var apiBase: String = ""
  @Published private(set) var required: Bool = true
  @Published private(set) var configLoaded = false

  /// `-LMAccessMock`: simula um servidor (LUME26 = 3 meses, VITA01 = vitalício, outros = inválido).
  let mock: Bool
  /// `-LMDebugTrial <dias>` simula o teste grátis iniciado; `-LMDebugTrialUsed` simula "teste já usado".
  let debugTrialDays: Int?
  let debugTrialUsed: Bool

  /// Mensagem do servidor quando o teste grátis deste aparelho já terminou (guardada: não se repete a chamada).
  @Published private(set) var trialUsedMessage: String?
  @Published private(set) var trialDisabled = false
  @Published private(set) var trialBusy = false
  /// Boas-vindas "Você tem N dias grátis" aguardando o fim do onboarding.
  var pendingTrialWelcome = false
  private var trialTask: Task<TrialResult, Never>?
  private var trialRetry: Task<Void, Never>?

  private let defaults: UserDefaults
  private let secrets: SecretStore
  private let transport: AccessTransport?
  private let isShared: Bool
  private var configTask: Task<Void, Never>?
  private var monitorTask: Task<Void, Never>?
  private var checking = false
  private var lastCheck: Date? {
    get { defaults.object(forKey: "lume.access.lastCheck") as? Date }
    set { defaults.set(newValue, forKey: "lume.access.lastCheck") }
  }

  init(defaults: UserDefaults = .standard, secrets: SecretStore = KeychainSecretStore(), transport: AccessTransport? = nil, isShared: Bool = false) {
    self.defaults = defaults
    self.secrets = secrets
    self.transport = transport
    self.isShared = isShared
    let args = ProcessInfo.processInfo.arguments
    self.mock = isShared && args.contains("-LMAccessMock")
    self.debugTrialUsed = isShared && args.contains("-LMDebugTrialUsed")
    self.debugTrialDays = isShared ? Onboarding.debugValue("-LMDebugTrial").flatMap { Int($0) } : nil
    if let data = defaults.data(forKey: "lume.access.info"), let saved = try? JSONDecoder().decode(AccessInfo.self, from: data) {
      info = saved
    }
    migrateIntoSecrets()
    trialUsedMessage = defaults.string(forKey: "lume.trial.usedMessage")
    if info == nil, let m = trialUsedMessage { lockedMessage = m }
    applyConfig(base: isShared ? AccessConfig.defaultAPIBase : "", required: true)
    if isShared, let data = defaults.data(forKey: "lume.access.config"),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let base = obj["apiBase"] as? String, !base.isEmpty {
      applyConfig(base: base, required: (obj["required"] as? Bool) ?? true)
    }
  }

  /// Migração ADITIVA: copia para o Keychain o que hoje só existe em UserDefaults (sem apagar nada) e
  /// recompõe o vitalício se só o Keychain sobreviveu (ex.: reinstalação).
  private func migrateIntoSecrets() {
    secrets.ensureStored(AccessKeys.device)
    secrets.ensureStored(AccessKeys.token)
    if secrets.get(AccessKeys.device) == nil, let v = defaults.string(forKey: AccessKeys.device), v.count >= 8 {
      secrets.set(v, for: AccessKeys.device)
    }
    if let i = info, i.lifetime, !i.code.isEmpty {
      if secrets.get(AccessKeys.lifetimeCode) == nil { secrets.set(i.code, for: AccessKeys.lifetimeCode) }
      if let p = i.purchase, secrets.get(AccessKeys.lifetimeOrder) == nil { secrets.set(p, for: AccessKeys.lifetimeOrder) }
    }
    if info == nil, let code = secrets.get(AccessKeys.lifetimeCode), code.count == 6 {
      info = AccessInfo(code: code, lifetime: true, expires: nil, planKind: "lifetime", planValue: nil,
                        message: "Acesso vitalício.", note: nil, activatedAt: nil, purchase: secrets.get(AccessKeys.lifetimeOrder))
    }
  }

  func applyConfig(base: String, required: Bool) {
    var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
    while b.hasSuffix("/") { b.removeLast() }
    apiBase = b
    self.required = required
  }

  // MARK: Estado derivado

  /// O portão só liga com URL do painel (ou mock) e `required != false`.
  var gateEnabled: Bool { mock || debugTrialUsed || debugTrialDays != nil || (!apiBase.isEmpty && required) }
  var hasValidAccess: Bool { (info?.stillValid ?? false) && lockedMessage == nil }
  /// Precisa mostrar a tela de código agora.
  var needsCode: Bool { gateEnabled && (!(hasValidAccess || inGrace || trialBusy) || gateHold) }

  /// Tolerância da PRIMEIRA abertura: sem rede para iniciar o teste, deixa entrar por até 24 h (a partir da 1ª falha).
  var inGrace: Bool {
    guard info == nil, trialUsedMessage == nil, let g = defaults.object(forKey: "lume.trial.graceStart") as? Date else { return false }
    return Date() < g.addingTimeInterval(24 * 3600)
  }
  /// O portão fica na tela até a pessoa tocar em "Entrar" (assim o sucesso da ativação aparece inteiro).
  @Published var gateHold = false

  func releaseGate() {
    gateHold = false
    lockedMessage = nil
  }
  /// O painel (ou o mock) está disponível para compra/restauração/atualização.
  var panelAvailable: Bool { mock || debugTrialUsed || debugTrialDays != nil || !apiBase.isEmpty }
  var isLifetime: Bool { info?.lifetime == true }

  /// Código vitalício guardado no Keychain (ou o da ativação atual, se vitalício).
  var lifetimeCode: String? {
    if let c = secrets.get(AccessKeys.lifetimeCode), c.count == 6 { return c }
    if let i = info, i.lifetime, i.code.count == 6 { return i.code }
    return nil
  }
  var lifetimeOrder: String? { secrets.get(AccessKeys.lifetimeOrder) ?? info?.purchase }

  /// Código que a pessoa deve ver preenchido no portão (o vitalício, se houver).
  var prefillCode: String? { lifetimeCode }

  // MARK: Identidade do aparelho

  /// UUID único, guardado no Keychain (sobrevive a reinstalações) com cópia em UserDefaults como reserva.
  var deviceId: String {
    if let v = secrets.get(AccessKeys.device) { return v }
    if let v = defaults.string(forKey: AccessKeys.device), v.count >= 8 { secrets.set(v, for: AccessKeys.device); return v }
    let v = UUID().uuidString
    secrets.set(v, for: AccessKeys.device)
    defaults.set(v, forKey: AccessKeys.device)
    return v
  }

  var token: String? {
    get { secrets.get(AccessKeys.token) }
    set { if let newValue { secrets.set(newValue, for: AccessKeys.token) } else { secrets.remove(AccessKeys.token) } }
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
    guard isShared, let url = URL(string: AccessConfig.remoteConfigURL) else { return }
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

  /// "lm-ab12cd", "LMAB12CD" ou "LM-AB12CD" → "LM-AB12CD"; nil se não parecer um pedido.
  static func normalizeOrder(_ raw: String) -> String? {
    let s = raw.uppercased().filter { $0.isLetter || $0.isNumber }
    guard s.hasPrefix("LM"), s.count == 8 else { return nil }
    return "LM-" + s.dropFirst(2)
  }

  func activate(code raw: String) async throws -> AccessInfo {
    let code = Self.normalize(raw)
    guard code.count == 6 else {
      throw AccessError(code: "bad_request", message: "O código tem 6 caracteres.", isDenial: true)
    }
    // Quem já é vitalício e está com acesso válido não troca por outro código (o vitalício nunca é rebaixado).
    if let i = info, i.lifetime, hasValidAccess, i.code != code, gateEnabled {
      throw AccessError(code: "already_lifetime", message: "Este aparelho já tem o acesso vitalício. Não precisa de outro código.", isDenial: true)
    }
    if mock { return try await mockActivate(code) }
    guard gateEnabled else { throw AccessError(code: "no_panel", message: "O painel de códigos ainda não está disponível.", isDenial: false) }

    let body: [String: Any] = [
      "code": code, "device": deviceId, "platform": AccessConfig.platform,
      "app": AccessConfig.appVersion, "name": UIDevice.current.name,
    ]
    let (status, json) = try await send("POST", "/api/access/activate", body: body)
    guard status == 200, (json["ok"] as? Bool) == true, let tok = json["token"] as? String else {
      let msg = (json["message"] as? String) ?? Self.defaultMessage(status)
      throw AccessError(code: (json["error"] as? String) ?? "error", message: msg, isDenial: status >= 400 && status < 500)
    }
    return adopt(json, token: tok, fallbackCode: code)
  }

  /// Restaura a compra pelo código vitalício OU pelo número do pedido (contrato: POST /api/purchase/restore).
  @discardableResult
  func restoreLifetime(code rawCode: String?, order rawOrder: String?, deviceOnly: Bool = false) async throws -> AccessInfo {
    let code = rawCode.map(Self.normalize).flatMap { $0.count == 6 ? $0 : nil }
    let order = rawOrder.flatMap(Self.normalizeOrder)
    guard code != nil || order != nil || deviceOnly else {
      throw AccessError(code: "bad_request", message: "Digite o código de 6 caracteres ou o número do pedido (LM-XXXXXX).", isDenial: true)
    }
    if mock, let code { return try await activate(code: code) }
    guard panelAvailable else { throw AccessError(code: "no_panel", message: "O painel ainda não está disponível.", isDenial: false) }
    var body: [String: Any] = ["device": deviceId, "platform": AccessConfig.platform, "app": AccessConfig.appVersion, "name": UIDevice.current.name]
    if let code { body["code"] = code }
    if let order { body["order"] = order }
    let (status, json) = try await send("POST", "/api/purchase/restore", body: body)
    if status == 200, (json["ok"] as? Bool) == true, let tok = json["token"] as? String {
      return adopt(json, token: tok, fallbackCode: code ?? lifetimeCode ?? "")
    }
    if status == 404 || status == 405, let code { return try await activateForRestore(code) }
    let msg = (json["message"] as? String) ?? Self.defaultMessage(status)
    throw AccessError(code: (json["error"] as? String) ?? "error", message: msg, isDenial: status >= 400 && status < 500)
  }

  /// v2.1 — traz a conta para ESTE aparelho: código de transferência (8 caracteres) OU código vitalício + PIN.
  @discardableResult
  func transfer(transferCode rawTransfer: String? = nil, code rawCode: String? = nil, order rawOrder: String? = nil, pin: String? = nil) async throws -> AccessInfo {
    var body: [String: Any] = ["device": deviceId, "platform": AccessConfig.platform, "app": AccessConfig.appVersion, "name": UIDevice.current.name]
    var code = ""
    if let rawTransfer {
      let t = Self.normalizeTransfer(rawTransfer)
      guard t.count == 8 else { throw AccessError(code: "bad_request", message: "O código de transferência tem 8 caracteres.", isDenial: true) }
      body["transferCode"] = t
    } else if let rawOrder {
      // "Esqueci meu código": número do pedido + PIN (aceita sem hífen e em minúsculas).
      let raw = rawOrder.uppercased().filter { $0.isLetter || $0.isNumber }
      guard let o = Self.normalizeOrder(raw.count == 6 ? "LM" + raw : raw) else {
        throw AccessError(code: "bad_request", message: "O número do pedido parece LM-XXXXXX.", isDenial: true)
      }
      let p = (pin ?? "").filter(\.isNumber)
      guard p.count == 6 else { throw AccessError(code: "bad_request", message: "O PIN tem 6 dígitos.", isDenial: true) }
      body["order"] = o; body["pin"] = p
    } else {
      code = Self.normalize(rawCode ?? "")
      let p = (pin ?? "").filter(\.isNumber)
      guard code.count == 6 else { throw AccessError(code: "bad_request", message: "O código vitalício tem 6 caracteres.", isDenial: true) }
      guard p.count == 6 else { throw AccessError(code: "bad_request", message: "O PIN tem 6 dígitos.", isDenial: true) }
      body["code"] = code; body["pin"] = p
    }
    guard panelAvailable else { throw AccessError(code: "no_panel", message: "O painel ainda não está disponível.", isDenial: false) }
    let (status, json) = try await send("POST", "/api/purchase/transfer", body: body)
    guard status == 200, (json["ok"] as? Bool) == true, let tok = json["token"] as? String else {
      let msg = (json["message"] as? String) ?? Self.defaultMessage(status)
      throw AccessError(code: (json["error"] as? String) ?? "error", message: msg, isDenial: status >= 400 && status < 500)
    }
    var j = json
    if (j["lifetime"] as? Bool) == nil { j["lifetime"] = true }
    return adopt(j, token: tok, fallbackCode: code)
  }

  static func normalizeTransfer(_ raw: String) -> String {
    String(raw.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(8))
  }

  /// Plano B de restauração: activate normal com o código salvo (painel sem /restore).
  private func activateForRestore(_ code: String) async throws -> AccessInfo {
    let body: [String: Any] = ["code": code, "device": deviceId, "platform": AccessConfig.platform,
                               "app": AccessConfig.appVersion, "name": UIDevice.current.name]
    let (status, json) = try await send("POST", "/api/access/activate", body: body)
    guard status == 200, (json["ok"] as? Bool) == true, let tok = json["token"] as? String else {
      let msg = (json["message"] as? String) ?? Self.defaultMessage(status)
      throw AccessError(code: (json["error"] as? String) ?? "error", message: msg, isDenial: status >= 400 && status < 500)
    }
    return adopt(json, token: tok, fallbackCode: code)
  }

  /// Guarda uma ativação/restauração bem-sucedida (token, info, Keychain do vitalício).
  private func adopt(_ json: [String: Any], token tok: String, fallbackCode: String) -> AccessInfo {
    var parsed = Self.parseInfo(json, fallbackCode: fallbackCode)
    if parsed.code.isEmpty { parsed.code = fallbackCode }
    token = tok
    rememberLifetime(parsed)
    store(parsed)
    if trialUsedMessage != nil { trialUsedMessage = nil; defaults.removeObject(forKey: "lume.trial.usedMessage") }
    lastCheck = Date()
    startMonitoring()
    return parsed
  }

  /// Vitalício: código e número do pedido ficam no Keychain (sobrevivem a atualização e reinstalação).
  private func rememberLifetime(_ i: AccessInfo) {
    if i.lifetime {
      secrets.set(i.code, for: AccessKeys.lifetimeCode)
      if let p = i.purchase { secrets.set(p, for: AccessKeys.lifetimeOrder) }
    } else if secrets.get(AccessKeys.lifetimeCode) != nil, lockedMessage != nil {
      // Só chega aqui se o vitalício foi explicitamente revogado e a pessoa entrou com outro código.
      secrets.remove(AccessKeys.lifetimeCode)
    }
  }

  /// Anota o número do pedido que gerou o vitalício (o painel nem sempre devolve `purchase`).
  func noteLifetimeOrder(_ order: String) {
    secrets.set(order, for: AccessKeys.lifetimeOrder)
    if var i = info, i.lifetime, i.purchase == nil { i.purchase = order; store(i) }
  }

  /// Segredos extras (código pago aguardando ativação) usam o mesmo cofre.
  var vault: SecretStore { secrets }

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
      rememberLifetime(i); store(i); return i
    default:
      throw AccessError(code: "invalid_code", message: "Código inválido. Confira e tente de novo.", isDenial: true)
    }
  }

  // MARK: Teste grátis automático (v2.3)

  /// Pede o teste grátis ao painel (hw = device id do Keychain; timeout 8 s). Chamadas simultâneas compartilham a mesma tarefa.
  @discardableResult
  func startTrial() async -> TrialResult {
    if let t = trialTask { return await t.value }
    let t = Task { await self.performTrial() }
    trialTask = t
    trialBusy = true
    let r = await t.value
    trialTask = nil
    trialBusy = false
    return r
  }

  private func performTrial() async -> TrialResult {
    if debugTrialUsed {
      let m = "Seu teste grátis já terminou neste aparelho. Garanta a Lume para sempre com o Vitalício."
      trialUsedMessage = m; lockedMessage = m
      return .used(m)
    }
    if let days = debugTrialDays {
      try? await Task.sleep(for: .milliseconds(500))
      let exp = Date().addingTimeInterval(Double(days) * 86400 + 60)
      let i = AccessInfo(code: "TESTE0", lifetime: false, expires: exp.timeIntervalSince1970 * 1000, planKind: "days", planValue: days,
                         message: "Você tem \(days) dias grátis.", note: nil, activatedAt: Date().timeIntervalSince1970 * 1000)
      info = i   // só em memória (depuração)
      pendingTrialWelcome = true
      return .started(i)
    }
    await ensureConfig()
    guard gateEnabled, !mock else { return .disabled }
    let body: [String: Any] = ["device": deviceId, "hw": deviceId, "platform": AccessConfig.platform, "app": AccessConfig.appVersion]
    do {
      let (status, json) = try await send("POST", "/api/trial/start", body: body, timeout: 8)
      let err = (json["error"] as? String) ?? ""
      if status == 200, (json["ok"] as? Bool) == true {
        if (json["enabled"] as? Bool) == false { trialDisabled = true; return .disabled }
        if let tok = json["token"] as? String {
          var j = json
          if (j["lifetime"] as? Bool) == nil { j["lifetime"] = false }
          let i = adopt(j, token: tok, fallbackCode: "")
          defaults.removeObject(forKey: "lume.trial.graceStart")
          lockedMessage = nil
          pendingTrialWelcome = true
          return .started(i)
        }
      }
      if status == 403, err == "trial_used" {
        let m = (json["message"] as? String) ?? "Seu teste grátis já terminou neste aparelho. Garanta a Lume para sempre com o Vitalício."
        trialUsedMessage = m
        defaults.set(m, forKey: "lume.trial.usedMessage")
        lockedMessage = m
        return .used(m)
      }
      if status == 429 {
        let m = (json["message"] as? String) ?? AccessService.defaultMessage(429)
        lockedMessage = m
        return .limited(m)
      }
      return noteUnreachable()
    } catch {
      return noteUnreachable()
    }
  }

  private func noteUnreachable() -> TrialResult {
    if defaults.object(forKey: "lume.trial.graceStart") == nil { defaults.set(Date(), forKey: "lume.trial.graceStart") }
    objectWillChange.send()
    startTrialRetry()
    return .unreachable
  }

  /// Sem rede na primeira abertura: tenta de novo em segundo plano.
  private func startTrialRetry() {
    guard isShared, trialRetry == nil else { return }
    trialRetry = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(45))
        guard let self, self.info == nil, self.trialUsedMessage == nil else { break }
        let r = await self.startTrial()
        if case .unreachable = r { continue }
        if case .started = r { self.presentTrialWelcomeIfReady() }
        break
      }
      self?.trialRetry = nil
    }
  }

  /// Ao abrir o app (e ao voltar): se ainda não há acesso nem teste usado, pede o teste.
  func ensureTrialIfNeeded() async {
    guard !mock, info == nil, trialUsedMessage == nil, !trialDisabled, !debugTrialUsed || lockedMessage == nil else { return }
    if case .started = await startTrial() { presentTrialWelcomeIfReady() }
  }

  /// Pop-up "Você tem N dias grátis" (depois do onboarding).
  func presentTrialWelcomeIfReady() {
    guard pendingTrialWelcome, Onboarding.isDone, let i = info else { return }
    pendingTrialWelcome = false
    Popups.shared.welcomeAfterActivation(i)
  }

  /// Chamado quando o onboarding termina.
  func onboardingFinished() {
    guard pendingTrialWelcome, let i = info else { return }
    pendingTrialWelcome = false
    Popups.shared.welcomeAfterActivation(i)
  }

  // MARK: Checar

  /// Erros que o painel decide de propósito: o app respeita (não tenta restaurar sozinho).
  static let finalDenials: Set<String> = ["transferred", "revoked", "transfer_required"]

  private enum RecoverResult { case restored, unreachable, denied(String) }

  /// Chama `/check`. Só 401/403 explícito bloqueia; rede/5xx/timeout/resposta estranha mantêm o acesso.
  /// Com código vitalício salvo, um 401/403 dispara a restauração silenciosa ANTES de qualquer tela.
  func check() async {
    guard gateEnabled, let current = info, !checking else { return }
    if mock { lastCheck = Date(); return }
    checking = true
    defer { checking = false }
    guard let tok = token else {
      await recoverOrLock(message: "Digite seu código de acesso novamente para continuar.", current: current)
      return
    }
    let body: [String: Any] = ["device": deviceId, "app": AccessConfig.appVersion, "platform": AccessConfig.platform]
    do {
      let (status, json) = try await send("POST", "/api/access/check", body: body, bearer: tok)
      if status == 200, (json["ok"] as? Bool) == true {
        var updated = Self.parseInfo(json, fallbackCode: current.code)
        if updated.code.isEmpty { updated.code = current.code }
        // Vitalício é pegajoso: o painel nunca rebaixa quem já pagou.
        if current.lifetime, !updated.lifetime, updated.code == current.code || lifetimeCode == updated.code {
          updated.lifetime = true; updated.expires = nil; updated.planKind = "lifetime"; updated.planValue = nil
        }
        if updated.purchase == nil { updated.purchase = current.purchase }
        rememberLifetime(updated)
        store(updated)
        lockedMessage = nil
        lastCheck = Date()
      } else if status == 401 || status == 403 {
        let msg = (json["message"] as? String) ?? "Seu acesso não está mais ativo. Digite um código válido."
        let err = (json["error"] as? String) ?? ""
        if Self.finalDenials.contains(err) {
          // v2.1: transferido para outro aparelho / revogado é decisão do painel — nunca "restaurar" por cima.
          revokeLocally(message: msg)
        } else {
          await recoverOrLock(message: msg, current: current)
        }
      }
      // outros status (404, 429, 5xx, corpo estranho): tolerância
    } catch {
      // rede/timeout: tolerância offline
    }
  }

  private func recoverOrLock(message: String, current: AccessInfo) async {
    guard lifetimeCode != nil || current.lifetime else {
      revokeLocally(message: message)
      return
    }
    switch await autoRestore() {
    case .restored, .unreachable: break
    case .denied(let m): revokeLocally(message: m.isEmpty ? message : m)
    }
  }

  /// Restauração automática e silenciosa com o código (ou pedido) vitalício guardados.
  private func autoRestore() async -> RecoverResult {
    let code = lifetimeCode
    let order = lifetimeOrder
    guard code != nil || order != nil else { return .denied("") }
    do {
      try await restoreLifetime(code: code, order: order)
      lockedMessage = nil
      return .restored
    } catch let e as AccessError {
      return e.isDenial ? .denied(e.message) : .unreachable
    } catch {
      return .unreachable
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
    guard isShared else { return }
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

  /// Remove a ativação deste aparelho (libera a tela para novo código). Não apaga o código vitalício do Keychain.
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
      activatedAt: num(j["activatedAt"]),
      purchase: ((j["purchase"] as? String) ?? (j["order"] as? String)).flatMap { $0.isEmpty ? nil : $0 }
    )
  }

  static func defaultMessage(_ status: Int) -> String {
    switch status {
    case 429: return "Muitas tentativas. Aguarde alguns minutos e tente de novo."
    case 500...: return "O servidor está indisponível agora. Tente de novo em instantes."
    default: return "Não foi possível validar o código."
    }
  }

  /// Requisição JSON ao painel (usada pelo acesso, compra e atualização). Lança `AccessError` (isDenial=false) em falha de rede.
  func send(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil, bearer: String? = nil, timeout: TimeInterval = 12) async throws -> (Int, [String: Any]) {
    guard var comps = URLComponents(string: apiBase + path), !apiBase.isEmpty else {
      throw AccessError(code: "bad_url", message: "Endereço do painel inválido.", isDenial: false)
    }
    if !query.isEmpty { comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
    guard let url = comps.url else {
      throw AccessError(code: "bad_url", message: "Endereço do painel inválido.", isDenial: false)
    }
    var req = URLRequest(url: url)
    req.httpMethod = method
    req.timeoutInterval = timeout
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
    if let body {
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    }
    do {
      let (data, resp): (Data, URLResponse)
      if let transport { (data, resp) = try await transport(req) } else { (data, resp) = try await URLSession.shared.data(for: req) }
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

  /// Só o Keychain de verdade (sem reserva em UserDefaults).
  static func getStrict(_ key: String) -> String? {
    let q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key,
      kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var out: AnyObject?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
    return String(data: d, encoding: .utf8)
  }

  static func get(_ key: String) -> String? {
    if let v = getStrict(key) { return v }
    // Reserva em UserDefaults (ex.: ambiente sem Keychain).
    return UserDefaults.standard.string(forKey: "kc.\(key)")
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
  /// Código já preenchido (ex.: o vitalício guardado). Não envia sozinho.
  var prefill: String?
  let onActivated: (AccessInfo) -> Void

  @ObservedObject private var access = AccessService.shared
  @State private var code = ""
  @State private var loading = false
  @State private var errorText: String?
  @State private var shakes: CGFloat = 0
  @State private var shimmer: CGFloat = -1
  @State private var suppressAuto = false
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
          if n.count == 6, !loading {
            if suppressAuto { suppressAuto = false } else { Task { await submit() } }
          }
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
        } else if focused {
          // Teclado aberto: botão visível para fechá-lo (o campo de código é invisível, sem barra própria).
          Button { focused = false } label: {
            Label("Fechar teclado", systemImage: "keyboard.chevron.compact.down")
              .font(Theme.font(14, .semibold))
              .foregroundStyle(Theme.secondary)
              .padding(.horizontal, 16)
              .frame(minHeight: 44)
              .contentShape(Rectangle())
          }
          .buttonStyle(PressableStyle())
        } else {
          Text(" ").font(Theme.font(14))
        }
      }
      .frame(minHeight: 44)

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
      if let prefill, code.isEmpty { suppressAuto = true; code = AccessService.normalize(prefill) }
      // Teste grátis vencido: não abre o teclado por cima do "Comprar vitalício" (relê o estado na hora).
      if autoFocus { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { if access.trialUsedMessage == nil { focused = true } } }
    }
    .onChange(of: access.trialUsedMessage) { _, msg in if msg != nil { focused = false } }
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
  /// Com prazo: depois de continuar, abre o pop-up de boas-vindas com os dias grátis.
  var showsWelcome = true
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

      PrismButton(title: buttonTitle, systemImage: "arrow.right", height: 52) {
        onContinue()
        if showsWelcome { Popups.shared.welcomeAfterActivation(info) }
      }
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
  private enum GateSheet: String, Identifiable { case claim, restore; var id: String { rawValue } }

  @ObservedObject private var access = AccessService.shared
  @ObservedObject private var purchase = PurchaseService.shared
  @State private var activated: AccessInfo?
  @State private var sheet: GateSheet?

  var body: some View {
    ZStack {
      Theme.canvas.ignoresSafeArea()
      OnboardingBackdrop(phase: 1, running: true).ignoresSafeArea()
      ScrollView {
        VStack(spacing: 24) {
          Spacer(minLength: 24)
          PrismMark(size: 64)
          if let info = activated {
            AccessSuccessView(info: info, buttonTitle: "Entrar na Lume") {
              withAnimation(.easeInOut(duration: 0.3)) { access.releaseGate() }
            }
            .transition(.scale(scale: 0.95).combined(with: .opacity))
          } else {
            AccessCodeView(
              title: access.trialUsedMessage != nil ? "Seu teste grátis terminou"
                : (access.lockedMessage == nil ? "Digite seu código de acesso" : "Precisamos do seu código"),
              subtitle: access.trialUsedMessage != nil
                ? "Garanta a Lume para sempre com o Vitalício. Se você recebeu um código, digite-o abaixo."
                : "O código tem 6 letras e números. Ele chegou junto com a sua compra.",
              initialMessage: access.lockedMessage,
              autoFocus: access.trialUsedMessage == nil,
              prefill: access.prefillCode
            ) { info in
              withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { activated = info }
            }
            .transition(.opacity)
            actions
          }
          Spacer(minLength: 16)
          Text("Sua biblioteca continua guardada neste iPhone.")
            .font(Theme.font(12.5))
            .foregroundStyle(Theme.tertiary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
      }
      .lumeSheetScroll()
    }
    .onAppear {
      access.gateHold = true
      Task { await access.ensureTrialIfNeeded() }
    }
    .onChange(of: access.hasValidAccess) { _, ok in
      if ok, activated == nil, sheet == nil { access.releaseGate() }
    }
    .sheet(item: $sheet) { s in
      switch s {
      case .claim: ClaimLifetimeSheet(prefillCode: access.prefillCode) { access.releaseGate() }
      case .restore: RestorePurchaseSheet(prefillCode: access.prefillCode) { access.releaseGate() }
      }
    }
  }

  @ViewBuilder private var actions: some View {
    VStack(spacing: 10) {
      if access.panelAvailable {
        PrismButton(title: purchase.priceText.map { "Comprar vitalício · \($0)" } ?? "Comprar vitalício", systemImage: "infinity", height: 50) {
          Popups.shared.openUpgrade()
        }
      }
      GlassButton(title: "Já sou vitalício", systemImage: "person.badge.key.fill", height: 48) { sheet = .claim }
      Button { Haptics.light(); sheet = .restore } label: {
        Text("Restaurar compra").font(Theme.font(15, .semibold)).foregroundStyle(Theme.secondary)
          .frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(PressableStyle())
    }
  }
}

// MARK: - Cartão para Ajustes

/// Cartão "Seu acesso": status, código (toque para mostrar/copiar) e ações de upgrade, código, transferência e restauração.
struct AccessStatusCard: View {
  private enum CardSheet: String, Identifiable { case code, claim, restore, transfer, pin, reveal; var id: String { rawValue } }

  @ObservedObject private var access = AccessService.shared
  @ObservedObject private var purchase = PurchaseService.shared
  @State private var sheet: CardSheet?
  @State private var revealed = false
  @State private var copied = false

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
        if info.lifetime { lifetimeCodeRow(info) } else { codeRow(info) }
        if info.lifetime {
          Text("Guarde este código: com ele você recupera a Lume em outro celular ou se reinstalar")
            .font(Theme.font(12.5)).foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let note = info.note, !(info.lifetime && note.caseInsensitiveCompare("Obrigado por comprar!") == .orderedSame) {
          Text(note).font(Theme.font(13)).foregroundStyle(Theme.secondary)
        }
      }
      if access.gateEnabled {
        VStack(spacing: 10) {
          if access.isLifetime {
            GlassButton(title: "Ver meu código", systemImage: "eye.fill", height: 46) { sheet = .reveal }
            GlassButton(title: "Transferir para outro aparelho", systemImage: "iphone.and.arrow.forward", height: 46) { sheet = .transfer }
            GlassButton(title: purchase.pinSet ? "Trocar PIN" : "Criar PIN de recuperação", systemImage: "lock.shield.fill", height: 46) { sheet = .pin }
          } else {
            if purchase.available {
              PrismButton(title: "Fazer upgrade para o Vitalício", systemImage: "infinity", height: 48) { Popups.shared.openUpgrade() }
            }
            GlassButton(title: "Tenho um código", systemImage: "key.fill", height: 46) { sheet = .code }
            GlassButton(title: "Já sou vitalício", systemImage: "person.badge.key.fill", height: 46) { sheet = .claim }
          }
          if access.isLifetime {
            GlassButton(title: "Tenho um código", systemImage: "key.fill", height: 46) { sheet = .code }
          }
          GlassButton(title: "Restaurar compra", systemImage: "arrow.counterclockwise", height: 46) { sheet = .restore }
        }
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glass(24)
    .sheet(item: $sheet) { s in
      switch s {
      case .code: ChangeCodeSheet()
      case .claim: ClaimLifetimeSheet(prefillCode: nil)
      case .restore: RestorePurchaseSheet(prefillCode: access.prefillCode)
      case .transfer: TransferSheet()
      case .pin: PinSetupView(mandatory: false) { sheet = nil }
      case .reveal: RevealCodeSheet()
      }
    }
  }

  /// Vitalício: o código só aparece depois do PIN ("Ver meu código"); aqui só a máscara e o nº do pedido.
  private func lifetimeCodeRow(_ info: AccessInfo) -> some View {
    VStack(spacing: 4) {
      HStack {
        Text("Código").font(Theme.font(14)).foregroundStyle(Theme.secondary)
        Spacer()
        Text(info.maskedCode).font(.system(size: 17, weight: .bold, design: .monospaced)).foregroundStyle(Theme.text)
      }
      if let order = access.lifetimeOrder {
        HStack {
          Text("Pedido").font(Theme.font(14)).foregroundStyle(Theme.secondary)
          Spacer()
          Text(order).font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
        }
      }
    }
    .frame(minHeight: 44)
  }

  /// Código: toque mostra; com ele visível, toque copia.
  private func codeRow(_ info: AccessInfo) -> some View {
    Button {
      if revealed {
        UIPasteboard.general.string = info.code
        Haptics.success()
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.6)); copied = false }
      } else {
        Haptics.light()
        withAnimation(.easeOut(duration: 0.2)) { revealed = true }
        Task { try? await Task.sleep(for: .seconds(10)); withAnimation { revealed = false } }
      }
    } label: {
      HStack(spacing: 8) {
        Text("Código").font(Theme.font(14)).foregroundStyle(Theme.secondary)
        Spacer()
        Text(copied ? "Copiado" : (revealed ? info.code : info.maskedCode))
          .font(.system(size: 17, weight: .bold, design: .monospaced))
          .foregroundStyle(copied ? Theme.ok : Theme.text)
        Image(systemName: copied ? "checkmark" : (revealed ? "doc.on.doc" : "eye"))
          .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.secondary)
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(revealed ? "Código \(info.code). Toque para copiar" : "Código oculto. Toque para mostrar")
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
    if let d = i.expiresDate {
      guard d > Date() else { return "Venceu em \(AccessService.shortDate(d))" }
      let n = i.daysLeft ?? 0
      return "Grátis · \(n == 1 ? "falta 1 dia" : "faltam \(n) dias")"
    }
    return "Ativo"
  }

  private var statusColor: Color {
    guard access.gateEnabled, let i = access.info, access.lockedMessage == nil, i.stillValid else { return access.gateEnabled ? Theme.danger : Theme.secondary }
    return Theme.ok
  }
}

struct ChangeCodeSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var done: AccessInfo?

  var body: some View {
    ZStack {
      Theme.canvas.ignoresSafeArea()
      ScrollView {
        VStack {
          if let done {
            AccessSuccessView(info: done, buttonTitle: "Pronto") { dismiss() }
          } else {
            AccessCodeView(title: "Trocar código", subtitle: "Digite o novo código. O código atual só é substituído se o novo for válido.") { info in
              withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { done = info }
            }
          }
        }
        .padding(.horizontal, 24)
        .padding(.top, 56)
        .padding(.bottom, 24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
      }
      .lumeSheetScroll()
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
  }
}
