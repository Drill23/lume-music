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

    // 8d. Mesclagem da biblioteca (contrato 5.2 A) — pura, sem tocar a biblioteca real.
    do {
      func tr(_ v: String) -> BackupTrack { BackupTrack(videoId: v, title: "T\(v)", artist: "A") }
      func pl(_ id: String, _ name: String, updated: Int64, _ vids: [String]) -> BackupPlaylist {
        BackupPlaylist(id: id, name: name, created: 1000, updated: updated, tracks: vids.map(tr))
      }
      let local = LibraryV1(playlists: [pl("p1", "Local velha", updated: 100, ["a"]), pl("p2", "Só local", updated: 50, ["x"]), pl("p4", "Empate", updated: 300, ["l"])],
                            liked: [tr("c"), tr("a")], followed: ["Anitta", "pabllo vittar"])
      let remote = LibraryV1(playlists: [pl("p1", "Remota nova", updated: 200, ["a", "b"]), pl("p3", "Só remota", updated: 10, ["z"]), pl("p4", "Empate remota", updated: 300, ["r"])],
                             liked: [tr("a"), tr("b"), tr("c")], followed: ["ANITTA", "Pabllo Vittar", "Iza"])
      let m = LibraryMerge.merge(local: local, remote: remote)
      expect("mesclagem: playlists por id (união)", m.playlists.map(\.id) == ["p1", "p2", "p4", "p3"])
      expect("mesclagem: mesmo id fica a de updated maior (remota)", m.playlists.first { $0.id == "p1" }?.name == "Remota nova" && m.playlists.first { $0.id == "p1" }?.tracks.count == 2)
      expect("mesclagem: empate de updated fica a local", m.playlists.first { $0.id == "p4" }?.name == "Empate")
      let back = LibraryMerge.merge(local: remote, remote: local)
      expect("mesclagem: a de updated maior vence também no sentido inverso", back.playlists.first { $0.id == "p1" }?.name == "Remota nova")
      expect("mesclagem: curtidas por videoId, ordem local e as que faltam no fim", m.liked.map(\.videoId) == ["c", "a", "b"])
      expect("mesclagem: seguidos sem diferenciar maiúsculas", m.followed == ["Anitta", "pabllo vittar", "Iza"])

      // Playlist apagada (deletedPlaylists com `at` maior que `updated`) não volta; mais velha que o updated, não vale.
      let t1 = LibraryV1(deletedPlaylists: [BackupTombstone(id: "p1", at: 500), BackupTombstone(id: "p3", at: 5)])
      let m2 = LibraryMerge.merge(local: local, remote: LibraryV1(playlists: remote.playlists, deletedPlaylists: t1.deletedPlaylists))
      expect("mesclagem: tombstone mais nova que o updated tira a playlist", !m2.playlists.contains { $0.id == "p1" })
      expect("mesclagem: tombstone mais velha que o updated não apaga", m2.playlists.contains { $0.id == "p3" })
      expect("mesclagem: tombstone vencida some, a vigente fica", m2.deletedPlaylists.map(\.id) == ["p1"])
      let m3 = LibraryMerge.merge(local: LibraryV1(deletedPlaylists: [BackupTombstone(id: "p2", at: 900)]), remote: LibraryV1(playlists: [pl("p2", "Voltou?", updated: 800, ["q"])]))
      expect("mesclagem: apagada localmente depois do updated remoto não volta", !m3.playlists.contains { $0.id == "p2" })
      let none = LibraryMerge.merge(local: LibraryV1(), remote: LibraryV1())
      expect("mesclagem: vazio com vazio é vazio", none.isEmpty && none.deletedPlaylists.isEmpty)
      let now: Int64 = 400 * 86_400_000
      let old = LibraryMerge.merge(local: LibraryV1(deletedPlaylists: [BackupTombstone(id: "zz", at: 1)]), remote: LibraryV1(), now: now)
      expect("mesclagem: tombstone com mais de 120 dias é descartada", old.deletedPlaylists.isEmpty)

      // JSON do Android (números decimais, campos opcionais faltando) é lido sem perder o resto.
      let androidJSON = """
      {"v":1,"exportedAt":1.76427E12,"platform":"android","app":"5.2.0",
       "playlists":[{"id":"u1","name":"Treino","created":1764000000000,"updated":1764270000000.0,"tracks":[{"videoId":"dQw4w9WgXcQ","title":"X","artist":"Y","durationSec":213.0},{"title":"sem id"}]}],
       "liked":[{"videoId":"abc","title":"L","artist":"M","album":"N","artworkUrl":"https://i/x.jpg"}],
       "followed":["Anitta"]}
      """
      if let lib = try? JSONDecoder().decode(LibraryV1.self, from: Data(androidJSON.utf8)) {
        expect("LibraryV1 lê JSON do Android (decimais e item quebrado ignorado)", lib.v == 1 && lib.platform == "android" && lib.playlists.first?.tracks.count == 1
               && lib.playlists.first?.updated == 1764270000000 && lib.liked.first?.album == "N" && lib.deletedPlaylists.isEmpty)
      } else { expect("LibraryV1 lê JSON do Android (decimais e item quebrado ignorado)", false) }
      let fitted = local.fittedJSON().flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      expect("LibraryV1 serializa com v = 1 e as chaves do contrato", (fitted?["v"] as? Int) == 1 && fitted?["playlists"] != nil && fitted?["deletedPlaylists"] != nil && fitted?["followed"] != nil)
      var big = LibraryV1()
      big.liked = (0..<8000).map { BackupTrack(videoId: "v\($0)", title: String(repeating: "t", count: 40), artist: "artista", album: "álbum", artworkUrl: "https://i.ytimg.com/vi/v\($0)/hqdefault.jpg") }
      expect("biblioteca enorme perde capas e álbuns para caber em 1 MB", (big.fittedJSON()?.count ?? Int.max) <= LibraryV1.maxBytes)
      big.liked = (0..<60000).map { BackupTrack(videoId: "video\($0)", title: "titulo", artist: "artista") }
      expect("biblioteca gigante que não cabe devolve nil (413 evitado)", big.fittedJSON() == nil)
    }

    // 8e. ListenBrainz (contrato 5.2 B): regras e formato do envio.
    do {
      expect("scrobble: faixa de 200 s com 99 s não, com 100 s sim", !ListenBrainzRules.shouldScrobble(listened: 99, duration: 200) && ListenBrainzRules.shouldScrobble(listened: 100, duration: 200))
      expect("scrobble: faixa longa vale 4 minutos", !ListenBrainzRules.shouldScrobble(listened: 239, duration: 900) && ListenBrainzRules.shouldScrobble(listened: 240, duration: 900))
      expect("scrobble: faixa com menos de 30 s nunca", !ListenBrainzRules.shouldScrobble(listened: 29, duration: 29) && !ListenBrainzRules.shouldScrobble(listened: 20, duration: 20))
      expect("scrobble: 30 s exatos contam com 15 s", ListenBrainzRules.shouldScrobble(listened: 15, duration: 30))
      expect("scrobble: sem duração conhecida vale 4 minutos", !ListenBrainzRules.shouldScrobble(listened: 200, duration: 0) && ListenBrainzRules.shouldScrobble(listened: 240, duration: 0))
      let item = ScrobbleItem(listenedAt: 1_764_000_000, artist: "Anitta", track: "Envolver", release: "Versions of Me", videoId: "dQw4w9WgXcQ", durationMs: 193_000)
      let pn = ListenBrainzRules.body(type: "playing_now", items: [item], version: "5.2.0")
      let pnEntry = (pn["payload"] as? [[String: Any]])?.first
      expect("playing_now não leva listened_at", (pn["listen_type"] as? String) == "playing_now" && pnEntry?["listened_at"] == nil)
      let sg = ListenBrainzRules.body(type: "single", items: [item], version: "5.2.0")
      let e = (sg["payload"] as? [[String: Any]])?.first
      let md = e?["track_metadata"] as? [String: Any]
      let ai = md?["additional_info"] as? [String: Any]
      expect("single leva listened_at, artista, faixa e álbum", (e?["listened_at"] as? Int) == 1_764_000_000 && (md?["artist_name"] as? String) == "Anitta" && (md?["track_name"] as? String) == "Envolver" && (md?["release_name"] as? String) == "Versions of Me")
      expect("additional_info do contrato", (ai?["media_player"] as? String) == "Lume Music" && (ai?["submission_client"] as? String) == "Lume Music" && (ai?["submission_client_version"] as? String) == "5.2.0"
             && (ai?["music_service"] as? String) == "youtube.com" && (ai?["origin_url"] as? String) == "https://music.youtube.com/watch?v=dQw4w9WgXcQ" && (ai?["duration_ms"] as? Int) == 193_000)
      var q: [ScrobbleItem] = []
      for i in 0..<520 { q = ListenBrainzRules.enqueue(ScrobbleItem(listenedAt: i, artist: "a", track: "t"), to: q) }
      expect("fila offline guarda no máximo 500 (descarta as mais antigas)", q.count == 500 && q.first?.listenedAt == 20 && q.last?.listenedAt == 519)
    }

    // 8f. Texto do último backup.
    do {
      var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
      let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 22, minute: 5))!
      let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 21, minute: 40))!
      let yest = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 8, minute: 3))!
      let older = cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9, minute: 30))!
      expect("último backup: hoje às 21:40", LibraryBackupService.lastBackupText(today, now: now, calendar: cal) == "Último backup: hoje às 21:40")
      expect("último backup: ontem às 08:03", LibraryBackupService.lastBackupText(yest, now: now, calendar: cal) == "Último backup: ontem às 08:03")
      expect("último backup: dia 03/11 às 09:30", LibraryBackupService.lastBackupText(older, now: now, calendar: cal) == "Último backup: 03/11 às 09:30")
      expect("último backup: nenhum", LibraryBackupService.lastBackupText(nil) == "Nenhum backup ainda")
    }

    // 8e. Áudio 5.2: volume igual, limitador de pico, rampa e silêncio (matemática pura).
    for (name, ok) in LoudnessSelfTest.cases() { expect(name, ok) }

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
