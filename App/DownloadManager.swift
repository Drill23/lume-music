import Foundation
import SwiftUI

/// Fast native offline downloader (.mp4/.m4a + lyrics prefetch) using URLSessionDownloadDelegate.
@MainActor
final class DownloadManager: ObservableObject {
  static let shared = DownloadManager()

  @Published var progressById: [String: Double] = [:]
  @Published var activeCount: Int = 0
  @Published var lastMessage: String?

  private var tasks: [String: Task<Void, Never>] = [:]

  func isDownloading(_ trackId: String) -> Bool {
    progressById[trackId] != nil
  }

  func download(_ track: Track) {
    if LibraryStore.shared.isDownloaded(track.id) || tasks[track.id] != nil { return }
    LibraryStore.shared.register(track)
    progressById[track.id] = 0.06
    activeCount = progressById.count

    let t = Task {
      defer {
        Task { @MainActor in
          self.progressById.removeValue(forKey: track.id)
          self.tasks.removeValue(forKey: track.id)
          self.activeCount = self.progressById.count
        }
      }
      var working = track
      guard let vid = await MusicEngine.shared.resolveVideoId(for: working) else {
        await MainActor.run { self.lastMessage = "Não foi possível localizar o áudio de \(track.title)." }
        return
      }
      working.videoId = vid
      await MainActor.run {
        LibraryStore.shared.updateVideoId(vid, for: track.id)
        self.progressById[track.id] = 0.16
      }
      guard let resolved = await MusicEngine.shared.resolveStream(videoId: vid) else {
        await MainActor.run { self.lastMessage = "Falha ao obter o áudio para download." }
        return
      }
      await MainActor.run { self.progressById[track.id] = 0.24 }

      var req = URLRequest(url: resolved.url)
      req.timeoutInterval = 60
      for (k, v) in resolved.headers { req.setValue(v, forHTTPHeaderField: k) }

      do {
        let dest = LibraryStore.shared.localAudioURL(for: track.id)
        let bytesWritten = try await NativeFileDownloader.download(
          request: req,
          destination: dest,
          onProgress: { fraction in
            Task { @MainActor in
              self.progressById[track.id] = min(0.95, 0.24 + 0.71 * fraction)
            }
          }
        )

        guard bytesWritten > 32768 else {
          try? FileManager.default.removeItem(at: dest)
          await MainActor.run { self.lastMessage = "Download incompleto para \(track.title)." }
          return
        }

        // Prefetch synced lyrics silently for offline karaoke too
        _ = await LyricsService.shared.fetchLyrics(for: working)

        await MainActor.run {
          LibraryStore.shared.markDownloaded(working)
          Haptics.success()
          self.lastMessage = "Baixada offline: \(track.title)"
        }
      } catch {
        await MainActor.run { self.lastMessage = "Erro ao baixar \(track.title)." }
      }
    }
    tasks[track.id] = t
  }

  func downloadPlaylist(_ playlist: MusicPlaylist) {
    let tracks = LibraryStore.shared.tracks(in: playlist)
    for t in tracks where !LibraryStore.shared.isDownloaded(t.id) {
      download(t)
    }
  }

  func cancel(_ trackId: String) {
    tasks[trackId]?.cancel()
    tasks.removeValue(forKey: trackId)
    progressById.removeValue(forKey: trackId)
    activeCount = progressById.count
  }
}

/// Bridges URLSessionDownloadTask into Swift concurrency with native kernel-speed disk I/O.
private final class NativeFileDownloader: NSObject, URLSessionDownloadDelegate {
  private let destination: URL
  private let onProgress: (Double) -> Void
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
    if totalBytesExpectedToWrite > 0 {
      onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
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
