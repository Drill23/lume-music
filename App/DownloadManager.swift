import AVFoundation
import Foundation
import SwiftUI

enum DownloadState: Equatable {
  case queued
  case resolving
  case downloading(Double)
  case failed(String)

  var fraction: Double {
    switch self {
    case .queued: return 0.02
    case .resolving: return 0.14
    case .downloading(let p): return p
    case .failed: return 0
    }
  }

  var isActive: Bool {
    switch self {
    case .queued, .resolving, .downloading: return true
    case .failed: return false
    }
  }
}

/// Gerenciador de downloads offline com fila de até 2 downloads simultâneos, pausa/retomada,
/// prefetch automático de capas e letras, e tratamento de falhas com tentativa rápida.
@MainActor
final class DownloadManager: ObservableObject {
  static let shared = DownloadManager()

  @Published var progressById: [String: Double] = [:]
  @Published var statesById: [String: DownloadState] = [:]
  @Published var activeCount: Int = 0
  @Published var paused: Bool = false
  @Published var lastMessage: String?

  private var queuedTracks: [Track] = []
  private var activeTasks: [String: Task<Void, Never>] = [:]
  private var failedTracks: [String: Track] = [:]
  private let maxConcurrent = 2

  var pendingCount: Int {
    activeTasks.count + queuedTracks.count
  }

  var failedItems: [(track: Track, reason: String)] {
    failedTracks.values.compactMap { tr in
      if case .failed(let msg) = statesById[tr.id] { return (tr, msg) }
      return nil
    }
    .sorted { $0.track.title.localizedCaseInsensitiveCompare($1.track.title) == .orderedAscending }
  }

  var overallProgress: Double {
    let activeAndQueued = Array(statesById.values.filter { $0.isActive })
    guard !activeAndQueued.isEmpty else { return 0 }
    let sum = activeAndQueued.reduce(0.0) { $0 + $1.fraction }
    return sum / Double(activeAndQueued.count)
  }

  func isDownloading(_ trackId: String) -> Bool {
    statesById[trackId]?.isActive == true
  }

  func download(_ track: Track) {
    if LibraryStore.shared.isDownloaded(track.id) || statesById[track.id]?.isActive == true { return }
    LibraryStore.shared.register(track)
    failedTracks.removeValue(forKey: track.id)
    statesById[track.id] = .queued
    progressById[track.id] = 0.02
    if !queuedTracks.contains(where: { $0.id == track.id }) {
      queuedTracks.append(track)
    }
    refreshCounts()
    pumpQueue()
  }

  func downloadBatch(_ tracks: [Track]) {
    let pending = tracks.filter { !LibraryStore.shared.isDownloaded($0.id) && statesById[$0.id]?.isActive != true }
    for t in pending {
      LibraryStore.shared.register(t)
      failedTracks.removeValue(forKey: t.id)
      statesById[t.id] = .queued
      progressById[t.id] = 0.02
      if !queuedTracks.contains(where: { $0.id == t.id }) {
        queuedTracks.append(t)
      }
    }
    refreshCounts()
    pumpQueue()
  }

  func downloadPlaylist(_ playlist: MusicPlaylist) {
    downloadBatch(LibraryStore.shared.tracks(in: playlist))
  }

  func retry(_ trackId: String) {
    guard let tr = failedTracks[trackId] ?? LibraryStore.shared.tracksById[trackId] else { return }
    failedTracks.removeValue(forKey: trackId)
    statesById.removeValue(forKey: trackId)
    download(tr)
  }

  func retryAllFailed() {
    let list = Array(failedTracks.values)
    for t in list { retry(t.id) }
  }

  func togglePauseAll() {
    paused.toggle()
    if paused {
      for (id, t) in activeTasks {
        t.cancel()
        if let tr = LibraryStore.shared.tracksById[id] {
          queuedTracks.insert(tr, at: 0)
          statesById[id] = .queued
          progressById[id] = 0.02
        }
      }
      activeTasks.removeAll()
      refreshCounts()
    } else {
      pumpQueue()
    }
  }

  func cancel(_ trackId: String) {
    activeTasks[trackId]?.cancel()
    activeTasks.removeValue(forKey: trackId)
    queuedTracks.removeAll { $0.id == trackId }
    failedTracks.removeValue(forKey: trackId)
    statesById.removeValue(forKey: trackId)
    progressById.removeValue(forKey: trackId)
    refreshCounts()
    pumpQueue()
  }

  func cancelAll() {
    for t in activeTasks.values { t.cancel() }
    activeTasks.removeAll()
    queuedTracks.removeAll()
    failedTracks.removeAll()
    statesById.removeAll()
    progressById.removeAll()
    paused = false
    refreshCounts()
  }

  private func refreshCounts() {
    activeCount = activeTasks.count + queuedTracks.count
  }

  private func pumpQueue() {
    guard !paused else { return }
    while activeTasks.count < maxConcurrent, !queuedTracks.isEmpty {
      let next = queuedTracks.removeFirst()
      if LibraryStore.shared.isDownloaded(next.id) {
        statesById.removeValue(forKey: next.id)
        progressById.removeValue(forKey: next.id)
        continue
      }
      startTask(for: next)
    }
    refreshCounts()
  }

  private func startTask(for track: Track) {
    statesById[track.id] = .resolving
    progressById[track.id] = 0.08

    let t = Task.detached(priority: .utility) { [weak self] in
      defer {
        Task { @MainActor [weak self] in
          guard let self else { return }
          self.activeTasks.removeValue(forKey: track.id)
          self.refreshCounts()
          self.pumpQueue()
        }
      }

      var working = track
      guard let vid = await MusicEngine.shared.resolveVideoId(for: working) else {
        await MainActor.run {
          self?.markFailed(working, reason: "Áudio não localizado")
        }
        return
      }
      if Task.isCancelled { return }
      working.videoId = vid
      await MainActor.run {
        LibraryStore.shared.updateVideoId(vid, for: track.id)
        self?.statesById[track.id] = .resolving
        self?.progressById[track.id] = 0.16
      }

      guard let resolved = await MusicEngine.shared.resolveStream(videoId: vid) else {
        await MainActor.run {
          self?.markFailed(working, reason: "Stream indisponível")
        }
        return
      }
      if Task.isCancelled { return }

      await MainActor.run {
        self?.statesById[track.id] = .downloading(0.20)
        self?.progressById[track.id] = 0.20
      }

      var req = URLRequest(url: resolved.url)
      req.timeoutInterval = 60
      for (k, v) in resolved.headers { req.setValue(v, forHTTPHeaderField: k) }

      let destBase = await MainActor.run { LibraryStore.shared.localAudioURL(for: track.id).deletingPathExtension() }
      let dlURL = destBase.deletingLastPathComponent().appendingPathComponent(destBase.lastPathComponent + ".dl.mp4")
      let m4aURL = destBase.appendingPathExtension("m4a")
      let mp4URL = destBase.appendingPathExtension("mp4")

      do {
        let bytesWritten = try await NativeFileDownloader.download(
          request: req,
          destination: dlURL,
          onProgress: { fraction in
            let p = min(0.96, 0.20 + 0.76 * fraction)
            Task { @MainActor [weak self] in
              guard let self, self.statesById[track.id]?.isActive == true else { return }
              self.statesById[track.id] = .downloading(p)
              self.progressById[track.id] = p
            }
          }
        )

        if Task.isCancelled {
          try? FileManager.default.removeItem(at: dlURL)
          return
        }

        guard bytesWritten > 32768 else {
          try? FileManager.default.removeItem(at: dlURL)
          let failedTrack = working
          await MainActor.run {
            self?.markFailed(failedTrack, reason: "Arquivo incompleto")
          }
          return
        }

        await MainActor.run {
          guard let self, self.statesById[track.id]?.isActive == true else { return }
          self.statesById[track.id] = .downloading(0.98)
          self.progressById[track.id] = 0.98
        }

        // Player só de áudio: extrai a faixa AAC por passthrough (~100ms, zero recodificação, fora da MainActor).
        let finalURL = await Self.stripVideoTrackPassthrough(from: dlURL, toM4A: m4aURL, fallbackMP4: mp4URL)
        if Task.isCancelled {
          try? FileManager.default.removeItem(at: dlURL)
          return
        }

        let finalSize = (try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? Int64) ?? bytesWritten
        let savedTrack = working

        await MainActor.run {
          guard let self else { return }
          LibraryStore.shared.markDownloaded(savedTrack, fileSize: finalSize)
          // Sonoridade guardada de forma permanente: o "volume igual" também vale offline.
          LoudnessStore.shared.pin(db: resolved.loudnessDb ?? LoudnessStore.shared.db(for: vid, track.id), keys: [vid, track.id])
          self.statesById.removeValue(forKey: track.id)
          self.progressById.removeValue(forKey: track.id)
          self.failedTracks.removeValue(forKey: track.id)
          Haptics.success()
          self.lastMessage = "Baixada offline: \(track.title)"
        }

        // Prefetch de capa e letra em segundo plano para nunca travar a conclusão em 95–99%.
        Task.detached(priority: .background) {
          let artURL = await MainActor.run { ArtworkStore.shared.url(for: savedTrack) }
          if !artURL.isEmpty {
            _ = await ImagePipeline.shared.image(artURL, maxPixel: 700)
          }
          _ = await LyricsService.shared.fetchLyrics(for: savedTrack)
        }
      } catch is CancellationError {
        try? FileManager.default.removeItem(at: dlURL)
      } catch {
        try? FileManager.default.removeItem(at: dlURL)
        let failedTrack = working
        await MainActor.run {
          self?.markFailed(failedTrack, reason: "Falha de rede")
        }
      }
    }
    activeTasks[track.id] = t
    refreshCounts()
  }

  private func markFailed(_ track: Track, reason: String) {
    progressById.removeValue(forKey: track.id)
    statesById[track.id] = .failed(reason)
    failedTracks[track.id] = track
    lastMessage = "Erro ao baixar \(track.title): \(reason)"
  }
}

/// Bridges URLSessionDownloadTask into Swift concurrency with native kernel-speed disk I/O
/// and immediate task cancellation.
private final class NativeFileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  private let destination: URL
  private let onProgress: (Double) -> Void
  private let lock = NSLock()
  private var lastReported: Double = -1
  private var lastReportTime: CFTimeInterval = 0
  private var continuation: CheckedContinuation<Int64, Error>?
  private var downloadTask: URLSessionDownloadTask?
  private var session: URLSession?
  private var finished = false

  private init(destination: URL, onProgress: @escaping (Double) -> Void) {
    self.destination = destination
    self.onProgress = onProgress
  }

  private func cancelActive() {
    lock.lock()
    let alreadyFinished = finished
    finished = true
    let cont = continuation
    continuation = nil
    let task = downloadTask
    let sess = session
    downloadTask = nil
    session = nil
    lock.unlock()

    task?.cancel()
    sess?.invalidateAndCancel()
    if !alreadyFinished {
      cont?.resume(throwing: CancellationError())
    }
  }

  static func download(
    request: URLRequest,
    destination: URL,
    onProgress: @escaping (Double) -> Void
  ) async throws -> Int64 {
    let delegate = NativeFileDownloader(destination: destination, onProgress: onProgress)
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { cont in
        delegate.lock.lock()
        if Task.isCancelled || delegate.finished {
          delegate.finished = true
          delegate.lock.unlock()
          cont.resume(throwing: CancellationError())
          return
        }
        delegate.continuation = cont
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 180
        let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: request)
        delegate.session = session
        delegate.downloadTask = task
        delegate.lock.unlock()

        task.resume()
        session.finishTasksAndInvalidate()
      }
    } onCancel: {
      delegate.cancelActive()
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0 else { return }
    let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    let now = CFAbsoluteTimeGetCurrent()
    // Limita a ~8 atualizações/segundo para não enfileirar dezenas de Tasks na MainActor em Wi-Fi rápido.
    if (now - lastReportTime >= 0.12 && fraction - lastReported >= 0.03) || fraction >= 1 {
      lastReported = fraction
      lastReportTime = now
      onProgress(fraction)
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    lock.lock()
    if finished {
      lock.unlock()
      return
    }
    finished = true
    let cont = continuation
    continuation = nil
    self.downloadTask = nil
    self.session = nil
    lock.unlock()

    do {
      if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
        cont?.resume(throwing: URLError(.badServerResponse))
        return
      }
      let attrs = try FileManager.default.attributesOfItem(atPath: location.path)
      let size = (attrs[.size] as? Int64) ?? 0
      try? FileManager.default.removeItem(at: destination)
      try FileManager.default.moveItem(at: location, to: destination)
      cont?.resume(returning: size)
    } catch {
      cont?.resume(throwing: error)
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error else { return }
    lock.lock()
    if finished {
      lock.unlock()
      return
    }
    finished = true
    let cont = continuation
    continuation = nil
    self.downloadTask = nil
    self.session = nil
    lock.unlock()

    if (error as NSError).code == NSURLErrorCancelled {
      cont?.resume(throwing: CancellationError())
    } else {
      cont?.resume(throwing: error)
    }
  }
}

// MARK: - Só áudio (passthrough instantâneo, sem recodificação)
extension DownloadManager {
  /// Remuxa o arquivo baixado (`.part`) só com a faixa de áudio usando `AVAssetExportPresetPassthrough`
  /// (sem recodificar AAC, sem disputar o encoder de áudio com o AVPlayer).
  /// Executa fora da MainActor. Em caso de falha, move o arquivo original para `.mp4`.
  nonisolated static func stripVideoTrackPassthrough(from dlURL: URL, toM4A m4aURL: URL, fallbackMP4 mp4URL: URL) async -> URL {
    let fm = FileManager.default
    let asset = AVURLAsset(url: dlURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
    let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
    let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []

    // Se já veio só áudio (stream audioOnly), apenas move para .m4a sem reprocessar.
    if videoTracks.isEmpty {
      try? fm.removeItem(at: mp4URL)
      try? fm.removeItem(at: m4aURL)
      if (try? fm.moveItem(at: dlURL, to: m4aURL)) != nil {
        return m4aURL
      }
      try? fm.moveItem(at: dlURL, to: mp4URL)
      return mp4URL
    }

    if let audioTrack = audioTracks.first {
      let comp = AVMutableComposition()
      if let timeRange = try? await audioTrack.load(.timeRange),
         timeRange.duration.seconds > 0,
         let compTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
        do {
          try compTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
          if let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) {
            let compatible = await export.compatibleFileTypes
            let targetType: AVFileType? = compatible.contains(.m4a) ? .m4a : (compatible.contains(.mp4) ? .mp4 : nil)
            if let targetType {
              let ext = targetType == .m4a ? "m4a" : "mp4"
              let tmpURL = dlURL.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + "." + ext)
              export.outputURL = tmpURL
              export.outputFileType = targetType
              export.shouldOptimizeForNetworkUse = false

              await withTaskCancellationHandler {
                await export.export()
              } onCancel: {
                export.cancelExport()
              }

              if !Task.isCancelled,
                 export.status == .completed,
                 let size = (try? fm.attributesOfItem(atPath: tmpURL.path)[.size] as? Int64) ?? nil,
                 size > 32768 {
                let finalDest = targetType == .m4a ? m4aURL : mp4URL
                let staleDest = targetType == .m4a ? mp4URL : m4aURL
                try? fm.removeItem(at: staleDest)
                try? fm.removeItem(at: finalDest)
                try? fm.moveItem(at: tmpURL, to: finalDest)
                try? fm.removeItem(at: dlURL)
                return finalDest
              }
              try? fm.removeItem(at: tmpURL)
            }
          }
        } catch {
          // Cai no fallback abaixo sem interromper o download.
        }
      }
    }

    // Fallback seguro: mantém o MP4 original (o AudioPlayer já desativa a faixa de vídeo ao tocar).
    try? fm.removeItem(at: m4aURL)
    try? fm.removeItem(at: mp4URL)
    try? fm.moveItem(at: dlURL, to: mp4URL)
    return mp4URL
  }
}
