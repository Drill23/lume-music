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

    let t = Task {
      defer {
        Task { @MainActor in
          self.activeTasks.removeValue(forKey: track.id)
          self.refreshCounts()
          self.pumpQueue()
        }
      }

      var working = track
      guard let vid = await MusicEngine.shared.resolveVideoId(for: working) else {
        await MainActor.run {
          self.markFailed(working, reason: "Áudio não localizado")
        }
        return
      }
      if Task.isCancelled { return }
      working.videoId = vid
      await MainActor.run {
        LibraryStore.shared.updateVideoId(vid, for: track.id)
        self.statesById[track.id] = .resolving
        self.progressById[track.id] = 0.16
      }

      guard let resolved = await MusicEngine.shared.resolveStream(videoId: vid) else {
        await MainActor.run {
          self.markFailed(working, reason: "Stream indisponível")
        }
        return
      }
      if Task.isCancelled { return }

      await MainActor.run {
        self.statesById[track.id] = .downloading(0.24)
        self.progressById[track.id] = 0.24
      }

      var req = URLRequest(url: resolved.url)
      req.timeoutInterval = 60
      for (k, v) in resolved.headers { req.setValue(v, forHTTPHeaderField: k) }

      do {
        let dest = LibraryStore.shared.localAudioURL(for: track.id)
        let bytesWritten = try await NativeFileDownloader.download(
          request: req,
          destination: dest,
          onProgress: { fraction in
            let p = min(0.95, 0.24 + 0.71 * fraction)
            Task { @MainActor in
              guard self.statesById[track.id]?.isActive == true else { return }
              self.statesById[track.id] = .downloading(p)
              self.progressById[track.id] = p
            }
          }
        )

        guard bytesWritten > 32768 else {
          try? FileManager.default.removeItem(at: dest)
          await MainActor.run {
            self.markFailed(working, reason: "Arquivo incompleto")
          }
          return
        }
        // Player de música: o arquivo salvo fica só com o áudio (sem a faixa de vídeo do MP4 de origem).
        await Self.stripVideoTrack(at: dest)

        // Prefetch capa e letra para uso 100% offline
        let artURL = await MainActor.run { ArtworkStore.shared.url(for: working) }
        if !artURL.isEmpty {
          _ = await ImagePipeline.shared.image(artURL, maxPixel: 700)
        }
        _ = await LyricsService.shared.fetchLyrics(for: working)

        await MainActor.run {
          LibraryStore.shared.markDownloaded(working)
          // Sonoridade guardada de forma permanente: o "volume igual" também vale offline.
          LoudnessStore.shared.pin(db: resolved.loudnessDb ?? LoudnessStore.shared.db(for: vid, track.id), keys: [vid, track.id])
          self.statesById.removeValue(forKey: track.id)
          self.progressById.removeValue(forKey: track.id)
          self.failedTracks.removeValue(forKey: track.id)
          Haptics.success()
          self.lastMessage = "Baixada offline: \(track.title)"
        }
      } catch is CancellationError {
        // Ignorado no cancelamento/pausa
      } catch {
        await MainActor.run {
          self.markFailed(working, reason: "Falha de rede")
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

/// Bridges URLSessionDownloadTask into Swift concurrency with native kernel-speed disk I/O.
private final class NativeFileDownloader: NSObject, URLSessionDownloadDelegate {
  private let destination: URL
  private let onProgress: (Double) -> Void
  private var lastReported: Double = -1
  private var continuation: CheckedContinuation<Int64, Error>?
  private var finished = false

  private init(destination: URL, onProgress: @escaping (Double) -> Void) {
    self.destination = destination
    self.onProgress = onProgress
  }

  static func download(
    request: URLRequest,
    destination: URL,
    onProgress: @escaping (Double) -> Void
  ) async throws -> Int64 {
    try await withCheckedThrowingContinuation { cont in
      let delegate = NativeFileDownloader(destination: destination, onProgress: onProgress)
      delegate.continuation = cont
      let cfg = URLSessionConfiguration.default
      cfg.timeoutIntervalForRequest = 30
      cfg.timeoutIntervalForResource = 180
      let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
      let task = session.downloadTask(with: request)
      task.resume()
      session.finishTasksAndInvalidate()
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    // Antes: um salto para a main + 2 @Published por pedaço de ~16 KB (centenas por faixa),
    // re-renderizando toda lista que observa o DownloadManager. Agora: no máximo a cada 2%.
    guard totalBytesExpectedToWrite > 0 else { return }
    let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    if fraction - lastReported >= 0.02 || fraction >= 1 {
      lastReported = fraction
      onProgress(fraction)
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard !finished else { return }
    finished = true
    do {
      if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
        continuation?.resume(throwing: URLError(.badServerResponse))
        continuation = nil
        return
      }
      let attrs = try FileManager.default.attributesOfItem(atPath: location.path)
      let size = (attrs[.size] as? Int64) ?? 0
      try? FileManager.default.removeItem(at: destination)
      try FileManager.default.moveItem(at: location, to: destination)
      continuation?.resume(returning: size)
      continuation = nil
    } catch {
      continuation?.resume(throwing: error)
      continuation = nil
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard !finished, let error else { return }
    finished = true
    continuation?.resume(throwing: error)
    continuation = nil
  }
}

// MARK: - Só áudio
extension DownloadManager {
  /// Regrava o arquivo baixado só com a faixa de áudio (AAC em .m4a), sem a faixa de vídeo.
  /// Se algo falhar, mantém o original (que continua tocando normalmente).
  static func stripVideoTrack(at url: URL) async {
    let asset = AVURLAsset(url: url)
    guard let videoTracks = try? await asset.loadTracks(withMediaType: .video), !videoTracks.isEmpty,
          let audioTracks = try? await asset.loadTracks(withMediaType: .audio), !audioTracks.isEmpty,
          let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return }
    let tmp = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".m4a")
    export.outputURL = tmp
    export.outputFileType = .m4a
    await export.export()
    guard export.status == .completed,
          let size = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int64) ?? nil,
          size > 32768 else {
      try? FileManager.default.removeItem(at: tmp)
      return
    }
    _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
  }
}
