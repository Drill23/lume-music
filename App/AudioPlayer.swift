import AVFoundation
import Combine
import MediaPlayer
import SwiftUI
import UIKit

/// Main playback controller: native AVPlayer (live HTTP .m4a + offline .m4a),
/// Lock Screen / AirPods controls, dynamic album color extraction, Apple Music animated artwork,
/// synced karaoke lyrics + 1-click PT-BR translation, autoplay radio, sleep timer, and visualizer telemetry.
@MainActor
final class AudioPlayer: ObservableObject {
  static let shared = AudioPlayer()

  @Published var currentTrack: Track?
  @Published var queue: [Track] = []
  @Published var currentIndex: Int = 0
  @Published var isPlaying: Bool = false
  @Published var isLoading: Bool = false
  @Published var currentTime: Double = 0
  @Published var duration: Double = 0
  @Published var shuffleEnabled: Bool = false
  @Published var repeatMode: RepeatMode = .off
  @Published var autoplayRadio: Bool = true
  @Published var playbackRate: Float = 1.0
  @Published var errorToast: String?

  // Rich visuals & lyrics state
  @Published var accentPrimary: Color = Theme.amber
  @Published var accentSecondary: Color = Theme.coral
  @Published var currentAnimatedArtURL: String?
  @Published var lyrics: LyricsBundle?
  @Published var isLoadingLyrics: Bool = false
  @Published var isTranslatingLyrics: Bool = false
  @Published var showTranslation: Bool = false
  @Published var currentBitrateLabel: String = "AAC"

  // Sleep timer
  @Published var sleepTimerOption: SleepTimerOption = .off
  @Published var sleepRemainingSeconds: Int = 0

  private var player: AVPlayer?
  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?
  private var statusObs: NSKeyValueObservation?
  private var sleepTimer: Timer?
  private var loadTask: Task<Void, Never>?
  private var lyricsTask: Task<Void, Never>?
  private var artTask: Task<Void, Never>?
  private var nowPlayingArtImage: UIImage?
  private var radioFetching = false

  private init() {
    configureAudioSession()
    configureRemoteCommands()
  }

  private func configureAudioSession() {
    do {
      let s = AVAudioSession.sharedInstance()
      try s.setCategory(.playback, mode: .default, options: [])
      try s.setActive(true)
    } catch {}
  }

  // MARK: - Playback Commands

  func play(_ track: Track, in list: [Track]? = nil) {
    let store = LibraryStore.shared
    store.register(track)
    if let list, !list.isEmpty {
      for t in list { store.register(t) }
      queue = list
      currentIndex = list.firstIndex(where: { $0.id == track.id }) ?? 0
    } else if let idx = queue.firstIndex(where: { $0.id == track.id }) {
      currentIndex = idx
    } else {
      queue = [track]
      currentIndex = 0
    }
    startCurrentTrack()
  }

  func playNextInQueue(_ track: Track) {
    LibraryStore.shared.register(track)
    if queue.isEmpty {
      play(track)
      return
    }
    let insertAt = min(queue.count, currentIndex + 1)
    queue.removeAll { $0.id == track.id && queue.firstIndex(of: $0) != currentIndex }
    let safeIdx = min(queue.count, insertAt)
    queue.insert(track, at: safeIdx)
    Haptics.light()
  }

  func addToQueue(_ track: Track) {
    LibraryStore.shared.register(track)
    if queue.isEmpty {
      play(track)
      return
    }
    if !queue.contains(where: { $0.id == track.id }) {
      queue.append(track)
    }
    Haptics.light()
  }

  func togglePlayPause() {
    guard let player else {
      if let tr = currentTrack { play(tr, in: queue) }
      return
    }
    Haptics.light()
    if isPlaying {
      player.pause()
      isPlaying = false
    } else {
      configureAudioSession()
      player.playImmediately(atRate: playbackRate)
      isPlaying = true
    }
    updateNowPlaying()
  }

  func seek(to seconds: Double) {
    guard let player else { return }
    let clamped = max(0, min(duration > 0 ? duration : seconds, seconds))
    currentTime = clamped
    let cm = CMTime(seconds: clamped, preferredTimescale: 600)
    player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
    updateNowPlaying()
  }

  func nextTrack() {
    guard !queue.isEmpty else { return }
    Haptics.light()
    if shuffleEnabled && queue.count > 1 {
      var nextIdx = Int.random(in: 0..<queue.count)
      if nextIdx == currentIndex { nextIdx = (currentIndex + 1) % queue.count }
      currentIndex = nextIdx
      startCurrentTrack()
      return
    }
    if currentIndex + 1 < queue.count {
      currentIndex += 1
      startCurrentTrack()
    } else if repeatMode == .all {
      currentIndex = 0
      startCurrentTrack()
    } else if autoplayRadio, let cur = currentTrack {
      Task {
        await appendRadio(for: cur)
        if self.currentIndex + 1 < self.queue.count {
          self.currentIndex += 1
          self.startCurrentTrack()
        }
      }
    } else {
      player?.pause()
      isPlaying = false
    }
  }

  func previousTrack() {
    Haptics.light()
    if currentTime > 3.5 {
      seek(to: 0)
      return
    }
    guard !queue.isEmpty else { return }
    if currentIndex > 0 {
      currentIndex -= 1
      startCurrentTrack()
    } else if repeatMode == .all {
      currentIndex = queue.count - 1
      startCurrentTrack()
    } else {
      seek(to: 0)
    }
  }

  func jumpToQueueIndex(_ idx: Int) {
    guard idx >= 0 && idx < queue.count else { return }
    currentIndex = idx
    startCurrentTrack()
  }

  func setRate(_ rate: Float) {
    playbackRate = rate
    if isPlaying { player?.rate = rate }
    updateNowPlaying()
  }

  func applySoundProfile(_ profile: SoundProfile) {
    LibraryStore.shared.soundProfile = profile
    if let player {
      player.volume = profile == .night ? 0.72 : 1.0
    }
    Haptics.selection()
  }

  // MARK: - Sleep Timer

  func setSleepTimer(_ option: SleepTimerOption) {
    sleepTimer?.invalidate()
    sleepTimer = nil
    sleepTimerOption = option
    switch option {
    case .off:
      sleepRemainingSeconds = 0
    case .endOfTrack:
      sleepRemainingSeconds = max(1, Int(max(0, duration - currentTime)))
    default:
      sleepRemainingSeconds = option.rawValue * 60
      sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
        Task { @MainActor [weak self] in
          guard let self else { return }
          if self.sleepRemainingSeconds <= 1 {
            self.sleepTimer?.invalidate()
            self.sleepTimer = nil
            self.sleepTimerOption = .off
            self.sleepRemainingSeconds = 0
            self.player?.pause()
            self.isPlaying = false
            self.player?.volume = 1.0
          } else {
            self.sleepRemainingSeconds -= 1
            if self.sleepRemainingSeconds <= 5 {
              self.player?.volume = Float(self.sleepRemainingSeconds) / 5.0
            }
          }
        }
      }
    }
    Haptics.selection()
  }

  // MARK: - Core Track Startup Pipeline

  private func startCurrentTrack() {
    guard currentIndex >= 0 && currentIndex < queue.count else { return }
    let track = queue[currentIndex]
    currentTrack = track
    isLoading = true
    isPlaying = false
    currentTime = 0
    duration = track.duration
    errorToast = nil
    lyrics = nil
    showTranslation = LibraryStore.shared.autoTranslateLyrics
    currentAnimatedArtURL = track.animatedArtworkURL
    LibraryStore.shared.recordPlay(track)

    loadTask?.cancel()
    lyricsTask?.cancel()
    artTask?.cancel()

    // 1. Dynamic Liquid Glass colors + Apple Music Animated Artwork in parallel
    artTask = Task {
      if !track.artworkURL.isEmpty {
        let (c1, c2) = await ArtworkColorExtractor.shared.colors(for: track.artworkURL)
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.7)) {
          self.accentPrimary = c1
          self.accentSecondary = c2
        }
        // Load UIImage for Lock Screen artwork
        if let u = URL(string: track.artworkURL), let (d, _) = try? await URLSession.shared.data(from: u) {
          self.nowPlayingArtImage = UIImage(data: d)
          self.updateNowPlaying()
        }
      }
      if LibraryStore.shared.animatedArtEnabled && track.animatedArtworkURL == nil {
        if let anim = await MusicEngine.shared.fetchAnimatedArtwork(title: track.title, artist: track.artist, album: track.album) {
          guard !Task.isCancelled else { return }
          LibraryStore.shared.updateAnimatedArt(anim, for: track.id)
          if self.currentTrack?.id == track.id {
            self.currentAnimatedArtURL = anim
          }
        }
      }
    }

    // 2. Synced Karaoke Lyrics (LRCLIB) + optional auto-translation
    lyricsTask = Task {
      self.isLoadingLyrics = true
      let fetched = await LyricsService.shared.fetchLyrics(for: track)
      guard !Task.isCancelled else { return }
      self.lyrics = fetched
      self.isLoadingLyrics = false
      if LibraryStore.shared.autoTranslateLyrics, let fetched {
        await self.translateCurrentLyrics(bundle: fetched)
      }
    }

    // 3. Resolve playable audio (offline local .m4a first -> live IOS AAC .m4a stream)
    loadTask = Task {
      let store = LibraryStore.shared
      if store.isDownloaded(track.id) {
        let localURL = store.localAudioURL(for: track.id)
        let asset = AVURLAsset(url: localURL)
        self.currentBitrateLabel = "Offline · AAC"
        self.beginAVPlayback(asset: asset, track: track)
        return
      }

      var working = track
      guard let vid = await MusicEngine.shared.resolveVideoId(for: working) else {
        guard !Task.isCancelled else { return }
        self.isLoading = false
        self.errorToast = "Áudio não encontrado para \(track.title)."
        return
      }
      working.videoId = vid
      store.updateVideoId(vid, for: track.id)
      if self.currentIndex < self.queue.count && self.queue[self.currentIndex].id == track.id {
        self.queue[self.currentIndex].videoId = vid
      }
      if self.currentTrack?.id == track.id { self.currentTrack?.videoId = vid }

      guard let resolved = await MusicEngine.shared.resolveStream(videoId: vid) else {
        guard !Task.isCancelled else { return }
        self.isLoading = false
        self.errorToast = "Não foi possível conectar ao stream de áudio."
        return
      }
      guard !Task.isCancelled else { return }
      self.currentBitrateLabel = "AAC · Estéreo"
      let asset = resolved.headers.isEmpty
        ? AVURLAsset(url: resolved.url)
        : AVURLAsset(url: resolved.url, options: ["AVURLAssetHTTPHeaderFieldsKey": resolved.headers])
      self.beginAVPlayback(asset: asset, track: working)

      // Pre-populate autoplay radio silently if queue is short
      if self.autoplayRadio && self.queue.count - self.currentIndex <= 2 {
        Task { await self.appendRadio(for: working) }
      }
    }
  }

  private func beginAVPlayback(asset: AVURLAsset, track: Track) {
    cleanupPlayerObservers()
    configureAudioSession()

    let item = AVPlayerItem(asset: asset)
    item.preferredForwardBufferDuration = 12
    let p = AVPlayer(playerItem: item)
    p.automaticallyWaitsToMinimizeStalling = true
    p.volume = LibraryStore.shared.soundProfile == .night ? 0.72 : 1.0
    self.player = p

    statusObs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
      if it.status == .failed {
        let msg = it.error?.localizedDescription ?? "Falha ao reproduzir esta faixa."
        Task { @MainActor [weak self] in
          self?.isLoading = false
          self?.isPlaying = false
          self?.errorToast = "Erro no áudio: \(msg)"
        }
      }
    }

    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if self.sleepTimerOption == .endOfTrack {
          self.sleepTimerOption = .off
          self.sleepRemainingSeconds = 0
          self.isPlaying = false
          return
        }
        if self.repeatMode == .one {
          self.seek(to: 0)
          self.player?.playImmediately(atRate: self.playbackRate)
          self.isPlaying = true
        } else {
          self.nextTrack()
        }
      }
    }

    timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.15, preferredTimescale: 600), queue: .main) { [weak self] cm in
      Task { @MainActor [weak self] in
        guard let self, let pl = self.player else { return }
        let sec = cm.seconds
        if sec.isFinite && sec >= 0 { self.currentTime = sec }
        if let d = pl.currentItem?.duration.seconds, d.isFinite && d > 1 {
          self.duration = d
        }
        if pl.timeControlStatus == .playing {
          self.isLoading = false
          self.isPlaying = true
        } else if pl.timeControlStatus == .waitingToPlayAtSpecifiedRate {
          self.isLoading = true
        }
        if self.sleepTimerOption == .endOfTrack {
          self.sleepRemainingSeconds = max(0, Int(self.duration - self.currentTime))
        }
      }
    }

    p.playImmediately(atRate: playbackRate)
    isPlaying = true
    isLoading = false
    updateNowPlaying()
  }

  private func cleanupPlayerObservers() {
    statusObs?.invalidate()
    statusObs = nil
    if let obs = timeObserver, let p = player {
      p.removeTimeObserver(obs)
    }
    timeObserver = nil
    if let eo = endObserver {
      NotificationCenter.default.removeObserver(eo)
    }
    endObserver = nil
    player?.pause()
  }

  // MARK: - Lyrics Translation (1-click PT-BR)

  func toggleTranslation() {
    Haptics.selection()
    if showTranslation {
      showTranslation = false
      return
    }
    showTranslation = true
    guard let cur = lyrics else { return }
    if cur.translatedToPT { return }
    Task { await translateCurrentLyrics(bundle: cur) }
  }

  private func translateCurrentLyrics(bundle: LyricsBundle) async {
    guard !isTranslatingLyrics else { return }
    isTranslatingLyrics = true
    let translated = await LyricsService.shared.translateToPortuguese(bundle)
    if self.lyrics?.trackKey == translated.trackKey {
      self.lyrics = translated
    }
    isTranslatingLyrics = false
  }

  // MARK: - Autoplay Radio

  private func appendRadio(for track: Track) async {
    guard !radioFetching, let vid = track.videoId else { return }
    radioFetching = true
    defer { radioFetching = false }
    let more = await MusicEngine.shared.fetchRadioQueue(for: vid, limit: 18)
    let existing = Set(queue.map(\.id))
    let fresh = more.filter { !existing.contains($0.id) }
    for t in fresh { LibraryStore.shared.register(t) }
    if !fresh.isEmpty { queue.append(contentsOf: fresh) }
  }

  // MARK: - Lock Screen & Control Center

  private func configureRemoteCommands() {
    let cc = MPRemoteCommandCenter.shared()
    cc.playCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        if !self.isPlaying { self.togglePlayPause() }
      }
      return .success
    }
    cc.pauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        if self.isPlaying { self.togglePlayPause() }
      }
      return .success
    }
    cc.togglePlayPauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.togglePlayPause() }
      return .success
    }
    cc.nextTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.nextTrack() }
      return .success
    }
    cc.previousTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.previousTrack() }
      return .success
    }
    cc.changePlaybackPositionCommand.addTarget { [weak self] ev in
      if let e = ev as? MPChangePlaybackPositionCommandEvent {
        Task { @MainActor in self?.seek(to: e.positionTime) }
      }
      return .success
    }
  }

  private func updateNowPlaying() {
    guard let tr = currentTrack else { return }
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: tr.title,
      MPMediaItemPropertyArtist: tr.artist,
      MPMediaItemPropertyAlbumTitle: tr.album,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
      MPMediaItemPropertyPlaybackDuration: duration > 0 ? duration : tr.duration,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0.0,
    ]
    if let img = nowPlayingArtImage {
      info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
}
