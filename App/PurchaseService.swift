import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import CryptoKit

// MARK: - Modelos (contrato v2 / v2.1 / v2.2)

struct PurchaseOrder: Codable, Equatable {
  var orderId: String
  var amountText: String
  var plan: String
  /// Só aparece se algum dia o painel mandar um checkout externo (v2.2: normalmente nulo).
  var checkoutUrl: String?
  var pixKey: String?
  var pixName: String?
  var copiaECola: String
  /// true = Pix dinâmico confirmado sozinho pelo painel (sem "Já paguei").
  var automatic: Bool
  var pollSeconds: Int
  var expiresAt: Double?

  /// "R$ 10,00" → "R$ 10"
  var shortPrice: String { PurchaseService.shortPrice(amountText) }
}

enum PurchaseStatus: String { case pending, review, paid, canceled }

// MARK: - Serviço de compra

@MainActor
final class PurchaseService: ObservableObject {
  static let shared = PurchaseService(access: AccessService.shared)

  @Published private(set) var order: PurchaseOrder?
  @Published private(set) var status: PurchaseStatus = .pending
  @Published private(set) var message: String?
  @Published private(set) var loading = false
  @Published private(set) var claiming = false
  @Published var errorText: String?
  /// Último preço conhecido do painel ("R$ 10"). Antes de saber, os botões ficam sem preço.
  @Published private(set) var priceText: String?

  private let access: AccessService
  private let defaults: UserDefaults
  private var pollTask: Task<Void, Never>?

  /// `-LMDebugUpgrade`: dados falsos locais (sem rede). `-LMDebugManual` simula o modo Pix manual.
  let debugUpgrade: Bool
  let debugManual: Bool

  init(access: AccessService, defaults: UserDefaults = .standard, debug: Bool? = nil) {
    self.access = access
    self.defaults = defaults
    let args = ProcessInfo.processInfo.arguments
    let onDevice = debug ?? true
    debugUpgrade = onDevice && args.contains("-LMDebugUpgrade")
    debugManual = onDevice && args.contains("-LMDebugManual")
    priceText = defaults.string(forKey: "lume.purchase.priceText")
    if let data = defaults.data(forKey: "lume.purchase.pending"), let o = try? JSONDecoder().decode(PurchaseOrder.self, from: data) {
      order = o
    }
  }

  nonisolated static func shortPrice(_ text: String) -> String {
    text.replacingOccurrences(of: ",00", with: "")
  }

  /// Compra disponível: painel configurado (ou mock/debug).
  var available: Bool { access.panelAvailable || debugUpgrade }

  // MARK: Chaves de estado local

  var pinPending: Bool {
    get { defaults.bool(forKey: "lume.purchase.pinPending") }
    set { defaults.set(newValue, forKey: "lume.purchase.pinPending") }
  }
  var pinSet: Bool {
    get { defaults.bool(forKey: "lume.purchase.pinSet") }
    set { defaults.set(newValue, forKey: "lume.purchase.pinSet") }
  }

  private func savePending(_ o: PurchaseOrder?) {
    if let o, let data = try? JSONEncoder().encode(o) { defaults.set(data, forKey: "lume.purchase.pending") }
    else { defaults.removeObject(forKey: "lume.purchase.pending") }
  }

  // MARK: Criar pedido

  /// Mostra o pedido pendente guardado na hora e (re)cria/reaproveita o pedido no painel.
  func prepare() async {
    errorText = nil
    if debugUpgrade { loadDebugOrder(); return }
    guard available else { errorText = "O painel ainda não está disponível. Tente de novo mais tarde."; return }
    if order != nil { Task { await refreshStatus() } }
    await create()
  }

  func create() async {
    guard !debugUpgrade else { loadDebugOrder(); return }
    guard !loading else { return }
    loading = true
    errorText = nil
    defer { loading = false }
    await access.ensureConfig()
    let body: [String: Any] = ["device": access.deviceId, "platform": AccessConfig.platform, "app": AccessConfig.appVersion, "method": "pix"]
    do {
      let (status, json) = try await access.send("POST", "/api/purchase/create", body: body)
      guard status == 200, (json["ok"] as? Bool) == true, let o = Self.parseOrder(json) else {
        let m = (json["message"] as? String) ?? (status == 503 ? "A compra ainda não está disponível. Tente de novo mais tarde." : AccessService.defaultMessage(status))
        errorText = m
        return
      }
      apply(order: o, statusText: json["status"] as? String)
    } catch {
      errorText = (error as? AccessError)?.message ?? error.localizedDescription
    }
  }

  private func apply(order o: PurchaseOrder, statusText: String?) {
    order = o
    status = statusText.flatMap(PurchaseStatus.init(rawValue:)) ?? .pending
    priceText = o.shortPrice
    defaults.set(o.shortPrice, forKey: "lume.purchase.priceText")
    savePending(o)
  }

  static func parseOrder(_ j: [String: Any]) -> PurchaseOrder? {
    guard let id = j["orderId"] as? String, !id.isEmpty else { return nil }
    let pix = j["pix"] as? [String: Any]
    let copia = (pix?["copiaECola"] as? String) ?? ""
    let url = (j["checkoutUrl"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    func num(_ v: Any?) -> Double? { (v as? Double) ?? (v as? Int).map(Double.init) ?? (v as? NSNumber)?.doubleValue }
    guard !copia.isEmpty || url != nil else { return nil }
    return PurchaseOrder(
      orderId: id,
      amountText: (j["amountText"] as? String) ?? "R$ 10,00",
      plan: (j["plan"] as? String) ?? "Vitalício",
      checkoutUrl: url,
      pixKey: (pix?["key"] as? String).flatMap { $0.isEmpty ? nil : $0 },
      pixName: pix?["name"] as? String,
      copiaECola: copia,
      automatic: (pix?["automatic"] as? Bool) ?? false,
      pollSeconds: max(2, Int(num(j["pollSeconds"]) ?? 5)),
      expiresAt: num(j["expiresAt"])
    )
  }

  // MARK: Status / claim

  func refreshStatus() async {
    guard !debugUpgrade, let o = order else { return }
    do {
      let (code, json) = try await access.send("GET", "/api/purchase/status", query: ["order": o.orderId, "device": access.deviceId], timeout: 10)
      guard code == 200, (json["ok"] as? Bool) == true else { return }
      let st = (json["status"] as? String).flatMap(PurchaseStatus.init(rawValue:)) ?? .pending
      status = st
      message = json["message"] as? String
      switch st {
      case .paid:
        if let c = json["code"] as? String, AccessService.normalize(c).count == 6 {
          paid(code: AccessService.normalize(c), order: o.orderId)
        }
      case .canceled:
        stopPolling()
        order = nil
        savePending(nil)
      default: break
      }
    } catch {
      // rede: tenta de novo no próximo ciclo
    }
  }

  func claim() async {
    guard let o = order, !claiming else { return }
    if debugUpgrade { status = .review; message = "Recebemos seu aviso. Assim que o pagamento for confirmado, seu código aparece aqui."; return }
    claiming = true
    errorText = nil
    defer { claiming = false }
    do {
      let (code, json) = try await access.send("POST", "/api/purchase/claim", body: ["order": o.orderId, "device": access.deviceId])
      if code == 200, (json["ok"] as? Bool) == true {
        status = PurchaseStatus(rawValue: (json["status"] as? String) ?? "review") ?? .review
        message = "Recebemos seu aviso. Assim que o pagamento for confirmado, seu código aparece aqui."
        Haptics.success()
      } else {
        errorText = (json["message"] as? String) ?? AccessService.defaultMessage(code)
      }
    } catch {
      errorText = (error as? AccessError)?.message ?? error.localizedDescription
    }
  }

  /// Pagamento confirmado: guarda o código no Keychain (não se perde se o app fechar) e abre o pop-up.
  private func paid(code: String, order id: String) {
    stopPolling()
    access.vault.set(code, for: AccessKeys.paidCode)
    order = nil
    savePending(nil)
    if access.isLifetime && access.lifetimeCode == code { access.vault.remove(AccessKeys.paidCode); return }
    Popups.shared.showUpgrade = false
    Popups.shared.present(.paid(code: code, order: id, debug: false))
  }

  /// O painel já ativou o aparelho que comprou: restore (mesmo aparelho, sem PIN) devolve o token.
  func activatePaid(code: String, order id: String?) async throws -> AccessInfo {
    let info = try await access.restoreLifetime(code: code, order: id)
    access.vault.remove(AccessKeys.paidCode)
    if let id { access.noteLifetimeOrder(id) }
    if !pinSet { pinPending = true }
    return info
  }

  // MARK: Polling (só com a tela aberta / ao voltar para o app)

  func startPolling() {
    guard !debugUpgrade, pollTask == nil, order != nil else { return }
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        await self?.refreshStatus()
        let s = self?.order?.pollSeconds ?? 5
        try? await Task.sleep(for: .seconds(s))
      }
    }
  }

  func stopPolling() {
    pollTask?.cancel()
    pollTask = nil
  }

  /// Ao voltar para o app: uma consulta se houver pedido pendente.
  func resumeIfPending() async {
    guard order != nil, status != .paid else { return }
    await refreshStatus()
  }

  // MARK: Restaurar / transferir / PIN

  /// "Restaurar compra" no MESMO aparelho: código vitalício ou número do pedido.
  func restore(input raw: String) async throws -> AccessInfo {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if let o = AccessService.normalizeOrder(text) { return try await access.restoreLifetime(code: nil, order: o) }
    return try await access.restoreLifetime(code: text, order: nil)
  }

  func setPin(_ pin: String) async throws {
    if debugPin { try? await Task.sleep(for: .milliseconds(700)); pinSet = true; pinPending = false; storePinHash(pin); return }
    guard let tok = access.token else { throw AccessError(code: "no_token", message: "Entre com seu código antes de criar o PIN.", isDenial: true) }
    let (code, json) = try await access.send("POST", "/api/purchase/pin", body: ["device": access.deviceId, "token": tok, "pin": pin], bearer: tok)
    guard code == 200, (json["ok"] as? Bool) != false else {
      throw AccessError(code: (json["error"] as? String) ?? "error", message: (json["message"] as? String) ?? AccessService.defaultMessage(code), isDenial: code >= 400 && code < 500)
    }
    pinSet = true
    pinPending = false
    storePinHash(pin)
  }

  // MARK: Ver meu código (protegido pelo PIN)

  private func pinDigest(_ pin: String) -> String {
    let d = SHA256.hash(data: Data("lume|\(access.deviceId)|\(pin)".utf8))
    return d.map { String(format: "%02x", $0) }.joined()
  }

  private func storePinHash(_ pin: String) { access.vault.set(pinDigest(pin), for: AccessKeys.pinHash) }

  /// Este aparelho sabe conferir o PIN (foi criado/trocado aqui).
  var canVerifyPinLocally: Bool { access.vault.get(AccessKeys.pinHash) != nil }

  func verifyPin(_ pin: String) -> Bool {
    guard let h = access.vault.get(AccessKeys.pinHash) else { return false }
    return h == pinDigest(pin)
  }

  /// Código e nº do pedido guardados; se faltar o código, pede ao painel (mesmo aparelho) e salva no Keychain.
  func loadLifetimeCredentials() async throws -> (code: String, order: String?) {
    if let c = access.lifetimeCode { return (c, access.lifetimeOrder) }
    let info = try await access.restoreLifetime(code: nil, order: access.lifetimeOrder, deviceOnly: true)
    return (info.code, info.purchase ?? access.lifetimeOrder)
  }

  var debugPin: Bool { ProcessInfo.processInfo.arguments.contains("-LMDebugPin") && !access.panelAvailable }

  /// Gera o código de transferência (8 caracteres, 15 min, uso único) no aparelho antigo.
  func transferCode() async throws -> (code: String, expires: Date) {
    if ProcessInfo.processInfo.arguments.contains("-LMDebugTransfer") && !access.panelAvailable {
      try? await Task.sleep(for: .milliseconds(600))
      return ("K7M2QX4P", Date().addingTimeInterval(15 * 60))
    }
    guard let tok = access.token else { throw AccessError(code: "no_token", message: "Entre com seu código antes de transferir.", isDenial: true) }
    let (code, json) = try await access.send("POST", "/api/purchase/transfer-code", body: ["device": access.deviceId, "token": tok], bearer: tok)
    func num(_ v: Any?) -> Double? { (v as? Double) ?? (v as? Int).map(Double.init) ?? (v as? NSNumber)?.doubleValue }
    guard code == 200, (json["ok"] as? Bool) != false,
          let t = (json["transferCode"] as? String) ?? (json["code"] as? String) else {
      throw AccessError(code: (json["error"] as? String) ?? "error", message: (json["message"] as? String) ?? AccessService.defaultMessage(code), isDenial: code >= 400 && code < 500)
    }
    var exp = Date().addingTimeInterval(15 * 60)
    if let ms = num(json["expiresAt"]), ms > 1_000_000_000_000 { exp = Date(timeIntervalSince1970: ms / 1000) }
    else if let s = num(json["expiresIn"]) { exp = Date().addingTimeInterval(s) }
    return (AccessService.normalizeTransfer(t), exp)
  }

  // MARK: Debug

  private func loadDebugOrder() {
    let id = "LM-7K3Q9X"
    let key = "d0a9a4ea-96dd-4125-b161-1d7fc83ffd1d"
    let copia = BRCode.make(key: key, name: "ADRIANO ALMEIDA", city: "BRASIL", amount: "10.00", txid: "LM7K3Q9X")
    let manual = debugManual
    var o = PurchaseOrder(orderId: id, amountText: "R$ 10,00", plan: "Vitalício",
                          checkoutUrl: manual ? "https://example.com/checkout" : nil,
                          pixKey: manual ? key : nil, pixName: manual ? "ADRIANO ALMEIDA" : "Lume Music",
                          copiaECola: copia, automatic: !manual, pollSeconds: 5, expiresAt: nil)
    if !manual { o.checkoutUrl = nil }
    order = o
    status = .pending
    priceText = o.shortPrice
  }
}

// MARK: - QR Code nítido (CoreImage)

enum QRCodeImage {
  static func make(_ text: String, scale: CGFloat = 12) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let out = filter.outputImage else { return nil }
    let scaled = out.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let ctx = CIContext(options: [.useSoftwareRenderer: false])
    guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
    return UIImage(cgImage: cg)
  }
}

// MARK: - BR Code Pix (só para o modo de depuração)

enum BRCode {
  static func tlv(_ id: String, _ value: String) -> String { id + String(format: "%02d", value.count) + value }

  static func crc16(_ s: String) -> String {
    var crc: UInt16 = 0xFFFF
    for b in s.utf8 {
      crc ^= UInt16(b) << 8
      for _ in 0..<8 { crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1 }
    }
    return String(format: "%04X", crc)
  }

  static func make(key: String, name: String, city: String, amount: String, txid: String) -> String {
    let account = tlv("00", "br.gov.bcb.pix") + tlv("01", key)
    var p = tlv("00", "01") + tlv("01", "12") + tlv("26", account) + tlv("52", "0000") + tlv("53", "986")
    p += tlv("54", amount) + tlv("58", "BR") + tlv("59", String(name.prefix(25))) + tlv("60", String(city.prefix(15)))
    p += tlv("62", tlv("05", String(txid.prefix(25))))
    p += "6304"
    return p + crc16(p)
  }
}
