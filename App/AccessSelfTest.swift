import Foundation

/// Autoteste das proteções do vitalício. Rodar com `-LMSelfTest` (imprime PASS/FAIL e encerra o app).
/// Usa servidor falso, UserDefaults descartável e cofre em memória: nunca toca no Keychain nem no painel reais.
@MainActor
enum AccessSelfTest {
  private typealias Handler = (URLRequest) throws -> (Int, [String: Any])

  private static func service(_ defaults: UserDefaults, _ secrets: SecretStore, base: String = "https://painel.test", _ handler: @escaping Handler) -> AccessService {
    let s = AccessService(defaults: defaults, secrets: secrets, transport: { req in
      let (status, obj) = try handler(req)
      let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
      return (data, HTTPURLResponse(url: req.url ?? URL(string: "https://painel.test")!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    })
    s.applyConfig(base: base, required: true)
    return s
  }

  private static func lifetimeJSON(_ code: String, token: String? = nil) -> [String: Any] {
    var j: [String: Any] = ["ok": true, "code": code, "lifetime": true, "plan": ["kind": "lifetime"], "message": "Acesso vitalício.", "purchase": "LM-7K3Q9X"]
    if let token { j["token"] = token }
    return j
  }

  private static func freshDefaults() -> (UserDefaults, String) {
    let name = "lume.selftest.\(UUID().uuidString)"
    return (UserDefaults(suiteName: name)!, name)
  }

  static func run() async {
    var fails = 0
    func expect(_ name: String, _ ok: Bool) {
      print(ok ? "PASS: \(name)" : "FAIL: \(name)")
      if !ok { fails += 1 }
    }
    let netError: Handler = { _ in throw URLError(.notConnectedToInternet) }

    // 1–2. Ativa vitalício; "atualização" (novo processo com os mesmos dados) preserva o vitalício.
    do {
      let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
      let vault = MemorySecretStore()
      let a = service(d, vault) { req in
        req.url?.path == "/api/access/activate" ? (200, lifetimeJSON("AB12CD", token: "tok1")) : (500, [:])
      }
      let info = try? await a.activate(code: "ab12cd")
      expect("ativar vitalício guarda código no Keychain", info?.lifetime == true && vault.get(AccessKeys.lifetimeCode) == "AB12CD")
      expect("ativar vitalício guarda nº do pedido no Keychain", vault.get(AccessKeys.lifetimeOrder) == "LM-7K3Q9X")

      let updated = service(d, vault, netError)
      expect("atualização preserva vitalício (mesmos dados)", updated.info?.lifetime == true && !updated.needsCode)
      await updated.check()
      expect("atualização + rede caída não bloqueia vitalício", !updated.needsCode && updated.lockedMessage == nil)

      let wiped = service(freshDefaults().0, vault, netError)
      expect("atualização preserva vitalício (UserDefaults zerado, só Keychain)", wiped.info?.lifetime == true && !wiped.needsCode)
    }

    // 3. Erros de rede / 5xx / resposta estranha / painel vazio nunca bloqueiam vitalício.
    do {
      let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
      let vault = MemorySecretStore()
      var mode = 0
      let s = service(d, vault) { req in
        if req.url?.path == "/api/access/activate" { return (200, lifetimeJSON("AB12CD", token: "tok1")) }
        switch mode {
        case 0: throw URLError(.timedOut)
        case 1: return (503, [:])
        case 2: return (200, [:])
        default: return (404, ["ok": false])
        }
      }
      _ = try? await s.activate(code: "AB12CD")
      for m in 0..<4 {
        mode = m
        await s.check()
        expect("vitalício não bloqueia (modo de falha \(m))", !s.needsCode && s.lockedMessage == nil && s.info?.lifetime == true)
      }
      s.applyConfig(base: "", required: true)
      expect("apiBase vazia nunca bloqueia", !s.needsCode)
    }

    // 4. 401 com código vitalício salvo → restaura sozinho, sem mostrar o portão.
    do {
      let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
      let vault = MemorySecretStore()
      var restoreCalls = 0
      var sawBody: [String: Any] = [:]
      let s = service(d, vault) { req in
        switch req.url?.path ?? "" {
        case "/api/access/activate": return (200, lifetimeJSON("AB12CD", token: "tok1"))
        case "/api/access/check": return (401, ["ok": false, "error": "invalid_token", "message": "Token inválido."])
        case "/api/purchase/restore":
          restoreCalls += 1
          sawBody = (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]) ?? [:]
          return (200, lifetimeJSON("AB12CD", token: "tok2"))
        default: return (500, [:])
        }
      }
      _ = try? await s.activate(code: "AB12CD")
      await s.check()
      expect("401 com código salvo chama /restore", restoreCalls == 1 && (sawBody["code"] as? String) == "AB12CD")
      expect("401 com código salvo restaura sozinho (sem portão)", !s.needsCode && s.lockedMessage == nil && s.token == "tok2")
    }

    // 5. Negativas explícitas do painel são respeitadas (transferido / revogado) e restore que falha leva ao portão.
    do {
      let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
      let vault = MemorySecretStore()
      var restoreCalls = 0
      let msg = "Sua conta Lume Vitalício foi transferida para outro aparelho. Se não foi você, fale com o suporte."
      let s = service(d, vault) { req in
        switch req.url?.path ?? "" {
        case "/api/access/activate": return (200, lifetimeJSON("AB12CD", token: "tok1"))
        case "/api/access/check": return (403, ["ok": false, "error": "transferred", "message": msg])
        case "/api/purchase/restore": restoreCalls += 1; return (200, lifetimeJSON("AB12CD", token: "tok2"))
        default: return (500, [:])
        }
      }
      _ = try? await s.activate(code: "AB12CD")
      await s.check()
      expect("403 transferred bloqueia com a mensagem do servidor, sem restore", s.needsCode && s.lockedMessage == msg && restoreCalls == 0)
      expect("portão vem com o código vitalício preenchido", s.prefillCode == "AB12CD")
    }
    do {
      let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
      let vault = MemorySecretStore()
      let need = "Este código vitalício já está em uso em outro aparelho."
      let s = service(d, vault) { req in
        switch req.url?.path ?? "" {
        case "/api/access/activate": return (200, lifetimeJSON("AB12CD", token: "tok1"))
        case "/api/access/check": return (401, ["ok": false, "error": "invalid_token"])
        case "/api/purchase/restore": return (403, ["ok": false, "error": "transfer_required", "message": need])
        default: return (500, [:])
        }
      }
      _ = try? await s.activate(code: "AB12CD")
      await s.check()
      expect("401 + restore negado (outro aparelho) leva ao portão com a mensagem", s.needsCode && s.lockedMessage == need)
    }
    do {
      let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
      let vault = MemorySecretStore()
      var phase = 0
      let s = service(d, vault) { req in
        switch req.url?.path ?? "" {
        case "/api/access/activate": return (200, lifetimeJSON("AB12CD", token: "tok1"))
        case "/api/access/check": return (401, ["ok": false])
        default: if phase == 0 { throw URLError(.notConnectedToInternet) }; return (500, [:])
        }
      }
      _ = try? await s.activate(code: "AB12CD")
      await s.check()
      expect("401 + restore sem rede não bloqueia vitalício", !s.needsCode)
    }

    // 6. Quem não é vitalício continua bloqueado normalmente no 401.
    do {
      let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
      let vault = MemorySecretStore()
      let s = service(d, vault) { req in
        switch req.url?.path ?? "" {
        case "/api/access/activate":
          return (200, ["ok": true, "token": "t", "code": "ZZ11YY", "lifetime": false, "expires": (Date().timeIntervalSince1970 + 30 * 86400) * 1000,
                        "plan": ["kind": "days", "value": 30]])
        default: return (401, ["ok": false, "message": "Acabou."])
        }
      }
      let i = try? await s.activate(code: "ZZ11YY")
      expect("código com prazo: 30 dias calculados de expires", i?.daysLeft == 30)
      await s.check()
      expect("código com prazo + 401 bloqueia", s.needsCode && s.lockedMessage == "Acabou.")
    }

    // 7. Migração aditiva: vitalício só em UserDefaults vai para o Keychain; vitalício não é trocado por outro código.
    do {
      let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
      let old = AccessInfo(code: "AB12CD", lifetime: true, expires: nil, planKind: "lifetime", planValue: nil, message: nil, note: nil, activatedAt: nil, purchase: "LM-7K3Q9X")
      d.set(try? JSONEncoder().encode(old), forKey: "lume.access.info")
      d.set("DEVICE-ABCDEFGH-1234", forKey: AccessKeys.device)
      let vault = MemorySecretStore()
      let s = service(d, vault, netError)
      expect("migração copia código vitalício para o Keychain", vault.get(AccessKeys.lifetimeCode) == "AB12CD" && vault.get(AccessKeys.lifetimeOrder) == "LM-7K3Q9X")
      expect("migração copia device id para o Keychain", vault.get(AccessKeys.device) == "DEVICE-ABCDEFGH-1234")
      expect("migração não apaga UserDefaults", d.data(forKey: "lume.access.info") != nil)
      do { _ = try await s.activate(code: "ZZ11YY"); expect("vitalício recusa trocar por outro código", false) }
      catch { expect("vitalício recusa trocar por outro código", (error as? AccessError)?.code == "already_lifetime") }
    }

    // 8. Transferência (v2.1).
    do {
      let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
      let vault = MemorySecretStore()
      var body: [String: Any] = [:]
      let s = service(d, vault) { req in
        body = (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]) ?? [:]
        if body["pin"] as? String == "000000" { return (429, ["ok": false, "error": "transfer_limit", "message": "Você já transferiu sua conta 3 vezes neste mês. Fale com o suporte."]) }
        return (200, lifetimeJSON("AB12CD", token: "tokNew"))
      }
      let i = try? await s.transfer(transferCode: "k7m2 qx4p")
      expect("transferência por código (8 caracteres) vira vitalício", i?.lifetime == true && (body["transferCode"] as? String) == "K7M2QX4P" && s.token == "tokNew")
      do { _ = try await s.transfer(code: "ab12cd", pin: "000000"); expect("transfer_limit devolve a mensagem do painel", false) }
      catch { expect("transfer_limit devolve a mensagem do painel", (error as? AccessError)?.message.contains("3 vezes") == true) }
    }

    // 8b. Recuperação do código perdido: "Esqueci meu código" (pedido + PIN) e restore só com o device.
    do {
      let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
      let vault = MemorySecretStore()
      var body: [String: Any] = [:]
      var path = ""
      let s = service(d, vault) { req in
        path = req.url?.path ?? ""
        body = (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]) ?? [:]
        if path == "/api/purchase/restore" { return (200, ["ok": true, "token": "tokR", "lifetime": true, "code": "QW34ER", "order": "LM-7K3Q9X"]) }
        if (body["pin"] as? String) == "111111" { return (403, ["ok": false, "error": "invalid_pin", "message": "PIN incorreto."]) }
        return (200, ["ok": true, "token": "tokF", "code": "QW34ER", "plan": ["kind": "lifetime"]])
      }
      let i = try? await s.transfer(order: "lm7k3q9x", pin: "123456")
      expect("esqueci meu código: pedido (sem hífen/minúsculas) + PIN", i?.lifetime == true && (body["order"] as? String) == "LM-7K3Q9X" && (body["pin"] as? String) == "123456" && path == "/api/purchase/transfer")
      expect("esqueci meu código salva o código no Keychain", vault.get(AccessKeys.lifetimeCode) == "QW34ER" && s.token == "tokF")
      do { _ = try await s.transfer(order: "LM-7K3Q9X", pin: "111111"); expect("PIN errado devolve a mensagem do painel", false) }
      catch { expect("PIN errado devolve a mensagem do painel", (error as? AccessError)?.message == "PIN incorreto.") }

      let (d2, n2) = freshDefaults(); defer { d2.removePersistentDomain(forName: n2) }
      let vault2 = MemorySecretStore()
      let s2 = service(d2, vault2) { req in
        path = req.url?.path ?? ""
        body = (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]) ?? [:]
        return (200, ["ok": true, "token": "tokR", "lifetime": true, "code": "QW34ER", "order": "LM-7K3Q9X"])
      }
      let p2 = PurchaseService(access: s2, defaults: d2, debug: false)
      _ = try? await p2.loadLifetimeCredentials()
      expect("restore só com o device devolve e salva code + order no Keychain", vault2.get(AccessKeys.lifetimeCode) == "QW34ER" && vault2.get(AccessKeys.lifetimeOrder) == "LM-7K3Q9X" && path == "/api/purchase/restore" && body["code"] == nil)
      // PIN: criado no aparelho → conferido localmente antes de mostrar o código
      s2.applyConfig(base: "https://painel.test", required: true)
      try? await p2.setPin("246810")
      expect("PIN criado neste aparelho é conferido localmente", p2.verifyPin("246810") && !p2.verifyPin("000000") && vault2.get(AccessKeys.pinHash) != "246810")
    }

    // 8c. Teste grátis automático (v2.3).
    do {
      let future = (Date().timeIntervalSince1970 + 7 * 86400) * 1000
      let trialJSON: [String: Any] = ["ok": true, "token": "tt", "code": "TT11AA", "lifetime": false, "expires": future, "plan": ["kind": "days", "value": 7], "trial": true]
      var d1 = freshDefaults(); defer { d1.0.removePersistentDomain(forName: d1.1) }
      var gotBody: [String: Any] = [:]
      let s1 = service(d1.0, MemorySecretStore()) { req in
        gotBody = (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]) ?? [:]
        return (200, trialJSON)
      }
      let r1 = await s1.startTrial()
      var ok1 = false
      if case .started(let i) = r1 { ok1 = i.daysLeft == 7 && !s1.needsCode && s1.pendingTrialWelcome }
      expect("teste grátis: start ok libera o acesso com 7 dias", ok1)
      expect("teste grátis: envia hw = device id", (gotBody["hw"] as? String) == s1.deviceId && (gotBody["device"] as? String) == s1.deviceId)

      let d2 = freshDefaults(); defer { d2.0.removePersistentDomain(forName: d2.1) }
      let s2 = service(d2.0, MemorySecretStore()) { _ in (200, ["ok": true, "enabled": false]) }
      var dis = false
      if case .disabled = await s2.startTrial() { dis = true }
      expect("teste desligado (enabled:false) → passo de código antigo", dis && s2.trialDisabled && s2.needsCode)

      let d3 = freshDefaults(); defer { d3.0.removePersistentDomain(forName: d3.1) }
      let msg = "Seu teste grátis já terminou neste aparelho. Garanta a Lume para sempre com o Vitalício."
      let s3 = service(d3.0, MemorySecretStore()) { _ in (403, ["ok": false, "error": "trial_used", "message": msg]) }
      var used = false
      if case .used(let m) = await s3.startTrial() { used = m == msg }
      expect("trial_used → portão com a mensagem do painel", used && s3.needsCode && s3.lockedMessage == msg)
      let s3b = service(d3.0, MemorySecretStore(), netError)
      expect("trial_used persiste entre aberturas", s3b.trialUsedMessage == msg && s3b.needsCode)

      let d4 = freshDefaults(); defer { d4.0.removePersistentDomain(forName: d4.1) }
      let s4 = service(d4.0, MemorySecretStore(), netError)
      var un = false
      if case .unreachable = await s4.startTrial() { un = true }
      expect("sem rede na 1ª abertura: tolerância (não bloqueia)", un && s4.inGrace && !s4.needsCode)
      d4.0.set(Date().addingTimeInterval(-25 * 3600), forKey: "lume.trial.graceStart")
      expect("tolerância acaba depois de 24 h", !s4.inGrace && s4.needsCode)
    }

    // 9. Utilidades.
    expect("normalizeOrder aceita lm7k3q9x", AccessService.normalizeOrder("lm7k3q9x") == "LM-7K3Q9X")
    expect("CRC16 do BR Code confere (123456789 = 29B1)", BRCode.crc16("123456789") == "29B1")
    let br = BRCode.make(key: "d0a9a4ea-96dd-4125-b161-1d7fc83ffd1d", name: "ADRIANO ALMEIDA", city: "BRASIL", amount: "10.00", txid: "LM7K3Q9X")
    expect("BR Code gerado tem CRC válido", br.hasSuffix(BRCode.crc16(String(br.dropLast(4)))))
    let po = PurchaseService.parseOrder(["orderId": "LM-7K3Q9X", "amountText": "R$ 10,00",
                                        "pix": ["key": NSNull(), "name": "Lume Music", "copiaECola": "000201", "automatic": true]])
    expect("pedido automático: sem chave e automatic=true", po?.automatic == true && po?.pixKey == nil && po?.shortPrice == "R$ 10")
    expect("QR Code é gerado", QRCodeImage.make(br) != nil)

    print(fails == 0 ? "SELFTEST: ALL PASS" : "SELFTEST: \(fails) FAIL")
    fflush(stdout)
    exit(fails == 0 ? 0 : 1)
  }
}
