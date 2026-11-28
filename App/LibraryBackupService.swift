import SwiftUI
import UIKit

/// Cliente do backup da biblioteca (contrato 5.2 A): POST /api/library/backup e /api/library/restore.
/// Tudo em silêncio quando o painel não responde (404, rede, 5xx): tenta de novo depois, sem avisar a pessoa.
@MainActor
final class LibraryBackupService: ObservableObject {
  static let shared = LibraryBackupService()

  @Published private(set) var lastBackupAt: Date?
  @Published private(set) var busy = false
  /// Resultado da última ação MANUAL (só aparece quando a pessoa toca nos botões).
  @Published var message: String?

  enum BackupOutcome: Equatable { case saved(Date), tooLarge(String), unavailable, failed }
  enum RestoreOutcome: Equatable { case merged(LibraryStore.BackupApplySummary), nothingSaved, unavailable, failed }

  private let defaults = UserDefaults.standard
  private var started = false
  private var debounce: Task<Void, Never>?
  private var observers: [NSObjectProtocol] = []
  private var running = false

  private enum Key {
    static let last = "lume.backup.lastAt"
    static let dirty = "lume.backup.dirty"
    static let restoredFor = "lume.backup.restoredFor"
    static let nextAuto = "lume.backup.nextAutoRestore"
  }

  private init() {
    let t = defaults.double(forKey: Key.last)
    if t > 0 { lastBackupAt = Date(timeIntervalSince1970: t) }
  }

  // MARK: Disparos

  /// Chamado uma vez na abertura: liga os observadores (mudança na biblioteca, vitalício ativado, fundo/primeiro plano).
  func start() {
    guard !started else { return }
    started = true
    let nc = NotificationCenter.default
    observers.append(nc.addObserver(forName: .lumeLibraryChanged, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.libraryChanged() }
    })
    observers.append(nc.addObserver(forName: .lumeLifetimeAdopted, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.lifetimeAdopted() }
    })
    observers.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.enteredBackground() }
    })
    observers.append(nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.accessReady() }
    })
  }

  /// Sessão de acesso ativa (teste ou vitalício) e painel disponível.
  var sessionReady: Bool {
    let a = AccessService.shared
    return a.panelAvailable && !a.mock && a.hasValidAccess && a.token != nil
  }

  /// Abertura / volta ao app com o painel já conhecido: restaura (uma vez por dia) se ainda não há a marca
  /// "restaurado neste aparelho" e garante o primeiro backup / backups pendentes.
  func accessReady() {
    guard started, sessionReady else { return }
    if !hasRestoredHere, Date() >= nextAutoAttempt {
      Task { await autoRestoreThenBackup() }
      return
    }
    if isDirty || (lastBackupAt == nil && !LibraryStore.shared.exportBackup().isEmpty) {
      markDirty()
      scheduleBackup(after: 20)
    }
  }

  private func libraryChanged() {
    markDirty()
    guard sessionReady else { return }
    scheduleBackup(after: 20)
  }

  private func lifetimeAdopted() {
    // Vitalício novo neste aparelho (ativação, transferência ou restauração): traz tudo que estava guardado.
    Task { await autoRestoreThenBackup(force: true) }
  }

  private func enteredBackground() {
    guard sessionReady, isDirty || lastBackupAt == nil else { return }
    debounce?.cancel()
    endBackgroundTask()
    bgTask = UIApplication.shared.beginBackgroundTask(withName: "lume.backup") { [weak self] in
      MainActor.assumeIsolated { self?.endBackgroundTask() }
    }
    Task {
      _ = await backupNow(manual: false)
      endBackgroundTask()
    }
  }

  private var bgTask: UIBackgroundTaskIdentifier = .invalid
  private func endBackgroundTask() {
    guard bgTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(bgTask)
    bgTask = .invalid
  }

  private func scheduleBackup(after seconds: Double) {
    debounce?.cancel()
    debounce = Task { [weak self] in
      try? await Task.sleep(for: .seconds(seconds))
      if Task.isCancelled { return }
      guard let self else { return }
      _ = await self.backupNow(manual: false)
    }
  }

  private func autoRestoreThenBackup(force: Bool = false) async {
    guard sessionReady else { return }
    let outcome = await restoreNow(manual: false)
    switch outcome {
    case .failed, .unavailable:
      defaults.set(Date().addingTimeInterval(30 * 60).timeIntervalSince1970, forKey: Key.nextAuto)
    default:
      defaults.set(Date().addingTimeInterval(24 * 3600).timeIntervalSince1970, forKey: Key.nextAuto)
      // O que veio mesclado (e o que só existe aqui) volta ao painel.
      if !LibraryStore.shared.exportBackup().isEmpty { markDirty(); scheduleBackup(after: force ? 3 : 20) }
    }
  }

  // MARK: Backup

  @discardableResult
  func backupNow(manual: Bool) async -> BackupOutcome {
    guard sessionReady, !running else { return .unavailable }
    running = true
    busy = manual
    defer { running = false; busy = false }

    // Antes do primeiro backup deste acesso, traz e mescla o que já existe no painel: assim uma biblioteca
    // vazia (celular novo) nunca sobrescreve o backup de quem já tinha tudo guardado.
    if !hasRestoredHere {
      let r = await restoreNow(manual: false)
      if r == .failed || r == .unavailable {
        if manual { message = "Não foi possível falar com o servidor agora. Tente de novo em instantes." }
        retryLater()
        return .failed
      }
    }

    let access = AccessService.shared
    guard let token = access.token else { return .unavailable }
    let lib = LibraryStore.shared.exportBackup()
    guard let data = lib.fittedJSON(), let libObj = try? JSONSerialization.jsonObject(with: data) else {
      let m = "Sua biblioteca ficou grande demais para o backup."
      if manual { message = m }
      return .tooLarge(m)
    }
    let body: [String: Any] = ["device": access.deviceId, "platform": AccessConfig.platform, "app": AccessConfig.appVersion, "library": libObj]
    do {
      let (status, json) = try await access.send("POST", "/api/library/backup", body: body, bearer: token, timeout: 20)
      if status == 200, (json["ok"] as? Bool) == true {
        let ms = (json["savedAt"] as? Double) ?? (json["savedAt"] as? Int).map(Double.init)
        let when = ms.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        lastBackupAt = when
        defaults.set(when.timeIntervalSince1970, forKey: Key.last)
        defaults.set(false, forKey: Key.dirty)
        if manual { message = "Backup feito." }
        return .saved(when)
      }
      if status == 413 {
        let m = (json["message"] as? String) ?? "Sua biblioteca ficou grande demais para o backup."
        if manual { message = m }
        return .tooLarge(m)
      }
      if manual { message = status == 429 ? "Muitos backups seguidos. Tente de novo daqui a pouco." : "O backup ainda não está disponível. Tentaremos de novo mais tarde." }
      retryLater()
      return .failed
    } catch {
      if manual { message = "Sem conexão. O backup será feito quando a internet voltar." }
      retryLater()
      return .failed
    }
  }

  // MARK: Restauração

  @discardableResult
  func restoreNow(manual: Bool) async -> RestoreOutcome {
    guard sessionReady else { return .unavailable }
    if manual { busy = true }
    defer { if manual { busy = false } }
    let access = AccessService.shared
    guard let token = access.token else { return .unavailable }
    let body: [String: Any] = ["device": access.deviceId, "platform": AccessConfig.platform, "app": AccessConfig.appVersion]
    do {
      let (status, json) = try await access.send("POST", "/api/library/restore", body: body, bearer: token, timeout: 20)
      guard status == 200, (json["ok"] as? Bool) == true else {
        if manual { message = "O backup ainda não está disponível. Tente de novo mais tarde." }
        return .failed
      }
      markRestoredHere()
      guard let libObj = json["library"], !(libObj is NSNull), JSONSerialization.isValidJSONObject(libObj),
            let data = try? JSONSerialization.data(withJSONObject: libObj),
            let remote = try? JSONDecoder().decode(LibraryV1.self, from: data), remote.v == 1 else {
        if manual { message = "Ainda não há backup guardado para o seu acesso." }
        return .nothingSaved
      }
      let summary = LibraryStore.shared.applyBackupMerge(remote)
      if manual { message = Self.summaryText(summary) }
      return .merged(summary)
    } catch {
      if manual { message = "Sem conexão. Tente de novo quando a internet voltar." }
      return .failed
    }
  }

  static func summaryText(_ s: LibraryStore.BackupApplySummary) -> String {
    guard s.changed else { return "Tudo certo: sua biblioteca já estava igual ao backup." }
    var parts: [String] = []
    let pl = s.addedPlaylists + s.updatedPlaylists
    if pl > 0 { parts.append(pl == 1 ? "1 playlist" : "\(pl) playlists") }
    if s.addedLiked > 0 { parts.append(s.addedLiked == 1 ? "1 curtida" : "\(s.addedLiked) curtidas") }
    if s.addedFollowed > 0 { parts.append(s.addedFollowed == 1 ? "1 artista" : "\(s.addedFollowed) artistas") }
    if s.removedPlaylists > 0 { parts.append(s.removedPlaylists == 1 ? "1 playlist apagada em outro aparelho saiu daqui" : "\(s.removedPlaylists) playlists apagadas em outro aparelho saíram daqui") }
    return "Restaurado: " + parts.joined(separator: ", ") + "."
  }

  // MARK: Estado

  private var isDirty: Bool { defaults.bool(forKey: Key.dirty) }
  private func markDirty() { defaults.set(true, forKey: Key.dirty) }
  private var nextAutoAttempt: Date {
    let t = defaults.double(forKey: Key.nextAuto)
    return t > 0 ? Date(timeIntervalSince1970: t) : .distantPast
  }

  /// Marca de "restaurado neste aparelho", por identidade (teste/código manual vs. cada pedido vitalício).
  private var identity: String {
    let a = AccessService.shared
    guard a.isLifetime else { return "d" }
    return "p:" + (a.lifetimeOrder ?? a.lifetimeCode ?? "")
  }
  private var hasRestoredHere: Bool { defaults.string(forKey: Key.restoredFor) == identity }
  private func markRestoredHere() { defaults.set(identity, forKey: Key.restoredFor) }

  private func retryLater() {
    markDirty()
    scheduleBackup(after: 5 * 60)
  }

  // MARK: Texto

  static func lastBackupText(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
    guard let date else { return "Nenhum backup ainda" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "pt_BR")
    f.calendar = calendar
    f.timeZone = calendar.timeZone
    f.dateFormat = "HH:mm"
    let hm = f.string(from: date)
    if calendar.isDate(date, inSameDayAs: now) { return "Último backup: hoje às \(hm)" }
    if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { return "Último backup: ontem às \(hm)" }
    f.dateFormat = "dd/MM"
    return "Último backup: \(f.string(from: date)) às \(hm)"
  }
}
