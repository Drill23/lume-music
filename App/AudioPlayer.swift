import AVFoundation
import Combine
import MediaPlayer
import SwiftUI
import UIKit

/// Relógio isolado de reprodução: evita re-renderizar telas estáticas 7x/s quando o tempo avança.
@MainActor
final class PlaybackClock: ObservableObject {
  static let shared = PlaybackClock()
  @Published var currentTime: Double = 0
  @Published var duration: Double = 0
  private init() {}
}

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
  var currentTime: Double {
    get { PlaybackClock.shared.currentTime }
    set { PlaybackClock.shared.currentTime = newValue }
  }
  var duration: Double {
    get { PlaybackClock.shared.duration }
    set { PlaybackClock.shared.duration = newValue }
  }
  @Published var shuffleEnabled: Bool = false
  @Published var repeatMode: RepeatMode = .off
  @Published var autoplayRadio: Bool = true
  @Published var playbackRate: Float = 1.0
  @Published var errorToast: String?

  // Rich visuals & lyrics state
  @Published var accentPrimary: Color = Theme.rose
  @Published var accentSecondary: Color = Theme.lavender
  @Published var currentAnimatedArtURL: String?
  @Published var lyrics: LyricsBundle?
  @Published var isLoadingLyrics: Bool = false
  @Published var isTranslatingLyrics: Bool = false
  @Published var showTranslation: Bool = false
  @Published var currentBitrateLabel: String = "AAC"
  @Published var palette: ArtworkPalette = .fallback
  @Published var currentArtwork: String = ""
  @Published var contextTitle: String = ""
  private var varispeed: Float = 1.0

  // Sleep timer
  @Published var sleepTimerOption: SleepTimerOption = .off
  @Published var sleepRemainingSeconds: Int = 0
  @Published var sessionHistory: [Track] = []

  private var player: AVPlayer?
  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?
  private var failObserver: NSObjectProtocol?
  private var statusObs: NSKeyValueObservation?
  private var sleepTimer: Timer?
  private var loadTask: Task<Void, Never>?
  private var lyricsTask: Task<Void, Never>?
  private var artTask: Task<Void, Never>?
  private var prefetchTask: Task<Void, Never>?
  private var retriedTrackIds: Set<String> = []
  private var nowPlayingArtImage: UIImage?
  private var nowPlayingArtwork: MPMediaItemArtwork?
  /// Capa simples da faixa atual (base da arte composta da tela de bloqueio).
  private var lockCoverImage: UIImage?
  private var lockArtTask: Task<Void, Never>?
  /// MP4 progressivo (itag 18) guardado como reserva quando tocamos o áudio puro.
  private var pendingFallbackURL: URL?
  /// App em segundo plano / tela bloqueada: não publica o relógio (ninguém está vendo).
  private var inBackground = false
  private var lifecycleObservers: [NSObjectProtocol] = []
  private var radioFetching = false
  private var crossfadeTriggered = false
  private var shouldFadeInNext = false

  private init() {
    configureAudioSession()
    configureRemoteCommands()
    AudioSpectrum.shared.setEQGains(LibraryStore.shared.effectiveEQGains)
    let nc = NotificationCenter.default
    lifecycleObservers.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.inBackground = true }
    })
    lifecycleObservers.append(nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.inBackground = false
        // Sincroniza o relógio de uma vez ao voltar (no fundo ele não é publicado).
        if let p = self.player {
          let sec = p.currentTime().seconds
          if sec.isFinite && sec >= 0 { self.currentTime = sec }
          if let d = p.currentItem?.duration.seconds, d.isFinite, d > 1 { self.duration = d }
        }
      }
    })
  }

  /// Redesenha a arte da tela de bloqueio (ex.: o estilo mudou nos Ajustes).
  func refreshLockScreenArtwork() {
    guard let track = currentTrack else { return }
    scheduleLockArtwork(for: track)
  }

  /// Ganchos de depuração para o simulador: `-LMDebugPlay <videoId>` toca direto e
  /// `-LMDebugOpenPlayer` abre o player. Sem argumentos, não faz nada.
  func runDebugHooksIfNeeded() {
    let args = ProcessInfo.processInfo.arguments
    guard let i = args.firstIndex(of: "-LMDebugPlay"), i + 1 < args.count else { return }
    let vid = args[i + 1]
    let t = Track(id: vid, videoId: vid, title: "Teste de stream", artist: "Lume", artworkURL: "https://i.ytimg.com/vi/\(vid)/hqdefault.jpg", sourceService: "Debug")
    play(t)
    if args.contains("-LMDebugOpenPlayer") { AppModel.shared.openPlayer() }
  }

  private func configureAudioSession() {
    do {
      let s = AVAudioSession.sharedInstance()
      try s.setCategory(.playback, mode: .default, options: [])
      try s.setActive(true)
    } catch {}
  }

  // MARK: - Playback Commands

  func displayArtwork(for t: Track) -> String {
    ArtworkStore.shared.url(for: t)
  }

  func play(_ track: Track, in list: [Track]? = nil, context: String? = nil) {
    if let context { contextTitle = context } else if list == nil || list?.count == 1 { contextTitle = "" }
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

  /// Endless radio seeded by a track (YouTube Music "radio" mix).
  func startRadio(from track: Track) {
    autoplayRadio = true
    play(track, in: [track], context: "Rádio · \(LibraryStore.mainArtist(track.artist))")
    AppModel.shared.showToast("Rádio de \(track.title) ligada")
  }

  func moveQueue(from source: IndexSet, to destination: Int) {
    guard !queue.isEmpty else { return }
    let currentId = currentTrack?.id
    queue.move(fromOffsets: source, toOffset: destination)
    if let currentId, let idx = queue.firstIndex(where: { $0.id == currentId }) { currentIndex = idx }
  }

  func removeFromQueue(at offsets: IndexSet) {
    let currentId = currentTrack?.id
    let safe = IndexSet(offsets.filter { $0 != currentIndex && $0 < queue.count })
    queue.remove(atOffsets: safe)
    if let currentId, let idx = queue.firstIndex(where: { $0.id == currentId }) { currentIndex = idx }
  }

  /// Turntable pitch fader: real varispeed (tempo + pitch change together, like vinyl).
  func setVarispeed(_ rate: Float) {
    varispeed = rate
    player?.currentItem?.audioTimePitchAlgorithm = abs(rate - 1) < 0.001 ? .timeDomain : .varispeed
    playbackRate = rate
    if isPlaying { player?.rate = rate }
    updateNowPlaying()
  }

  func reloadLyrics() {
    guard let track = currentTrack else { return }
    lyricsTask?.cancel()
    lyricsTask = Task {
      self.isLoadingLyrics = true
      await LyricsService.shared.forgetMiss(for: track)
      let fetched = await LyricsService.shared.fetchLyrics(for: track)
      guard !Task.isCancelled, self.currentTrack?.id == track.id else { return }
      self.lyrics = fetched
      self.isLoadingLyrics = false
    }
  }

  func jumpToQueueIndex(_ idx: Int) {
    guard idx >= 0 && idx < queue.count else { return }
    currentIndex = idx
    startCurrentTrack()
  }

  func setRate(_ rate: Float) {
    varispeed = 1.0
    player?.currentItem?.audioTimePitchAlgorithm = .timeDomain
    playbackRate = rate
    if isPlaying { player?.rate = rate }
    updateNowPlaying()
  }

  func applySoundProfile(_ profile: SoundProfile) {
    LibraryStore.shared.soundProfile = profile
    AudioSpectrum.shared.setEQGains(LibraryStore.shared.effectiveEQGains)
    if let player {
      player.volume = profile == .night ? 0.72 : 1.0
    }
    Haptics.selection()
  }

  func applyCustomEQ(_ gains: [Float]) {
    LibraryStore.shared.customEQGains = gains
    LibraryStore.shared.soundProfile = .custom
    AudioSpectrum.shared.setEQGains(gains)
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
    crossfadeTriggered = false
    LibraryStore.shared.recordPlay(track)
    sessionHistory.removeAll { $0.id == track.id }
    sessionHistory.insert(track, at: 0)
    if sessionHistory.count > 40 { sessionHistory = Array(sessionHistory.prefix(40)) }

    loadTask?.cancel()
    lyricsTask?.cancel()
    artTask?.cancel()
    prefetchTask?.cancel()
    retriedTrackIds.remove(track.id)

    currentArtwork = ArtworkStore.shared.url(for: track)
    nowPlayingArtImage = nil
    nowPlayingArtwork = nil
    lockCoverImage = nil
    lockArtTask?.cancel()
    pendingFallbackURL = nil

    // 1. Real album cover (upgrade YouTube thumbnails) + ambient palette + lock-screen art + animated cover
    artTask = Task {
      await ArtworkStore.shared.ensure(track)
      guard !Task.isCancelled, self.currentTrack?.id == track.id else { return }
      let art = ArtworkStore.shared.url(for: track)
      if art != self.currentArtwork { self.currentArtwork = art }
      if !art.isEmpty {
        let pal = await ArtworkColorExtractor.shared.palette(for: art)
        guard !Task.isCancelled, self.currentTrack?.id == track.id else { return }
        withAnimation(.easeInOut(duration: 0.8)) {
          self.palette = pal
          self.accentPrimary = pal.vibrant
          self.accentSecondary = pal.vibrant2
        }
        if let img = await ImagePipeline.shared.image(art, maxPixel: 800), self.currentTrack?.id == track.id {
          // 1º a capa simples (instantâneo); depois a arte composta (vinil/K7) desenhada em segundo plano.
          self.lockCoverImage = img
          self.setNowPlayingImage(img)
          self.scheduleLockArtwork(for: track)
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
      var fetched = await LyricsService.shared.fetchLyrics(for: track)
      // Second chance: YouTube Music lyrics need the videoId, which resolves in parallel.
      if fetched == nil, track.videoId == nil {
        for _ in 0..<16 {
          guard !Task.isCancelled, self.currentTrack?.id == track.id else { return }
          if let vid = self.currentTrack?.videoId {
            var withVid = track
            withVid.videoId = vid
            await LyricsService.shared.forgetMiss(for: withVid)
            fetched = await LyricsService.shared.fetchLyrics(for: withVid)
            break
          }
          try? await Task.sleep(for: .milliseconds(500))
        }
      }
      guard !Task.isCancelled, self.currentTrack?.id == track.id else { return }
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

      if store.offlineMode {
        self.isLoading = false
        self.isPlaying = false
        self.errorToast = "Modo offline ativo. Baixe “\(track.title)” para ouvir sem internet."
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
      self.currentBitrateLabel = resolved.audioOnly ? "AAC · \(max(96, resolved.bitrate / 1000)) kbps" : "AAC · Estéreo"
      self.pendingFallbackURL = resolved.audioOnly ? resolved.fallbackURL : nil
      let asset = resolved.headers.isEmpty
        ? AVURLAsset(url: resolved.url)
        : AVURLAsset(url: resolved.url, options: ["AVURLAssetHTTPHeaderFieldsKey": resolved.headers])
      self.beginAVPlayback(asset: asset, track: working)

      // Pre-populate autoplay radio silently if queue is short
      if self.autoplayRadio && self.queue.count - self.currentIndex <= 2 {
        Task { await self.appendRadio(for: working) }
      }
      self.scheduleNextTrackPrefetch()
    }
  }

  private func scheduleNextTrackPrefetch() {
    prefetchTask?.cancel()
    let nextIdx = currentIndex + 1
    guard nextIdx < queue.count, !LibraryStore.shared.offlineMode else { return }
    let nextTrack = queue[nextIdx]
    prefetchTask = Task {
      try? await Task.sleep(for: .milliseconds(1500))
      guard !Task.isCancelled else { return }
      await ArtworkStore.shared.ensure(nextTrack)
      let art = await MainActor.run { ArtworkStore.shared.url(for: nextTrack) }
      if !art.isEmpty { _ = await ImagePipeline.shared.image(art, maxPixel: 700) }
      if !LibraryStore.shared.isDownloaded(nextTrack.id) {
        if let vid = await MusicEngine.shared.resolveVideoId(for: nextTrack) {
          await MainActor.run { LibraryStore.shared.updateVideoId(vid, for: nextTrack.id) }
          _ = await MusicEngine.shared.resolveStream(videoId: vid)
        }
      }
      _ = await LyricsService.shared.fetchLyrics(for: nextTrack)
    }
  }

  private func beginAVPlayback(asset: AVURLAsset, track: Track) {
    cleanupPlayerObservers()
    configureAudioSession()

    let item = AVPlayerItem(asset: asset)
    item.preferredForwardBufferDuration = 12
    item.audioTimePitchAlgorithm = abs(varispeed - 1) < 0.001 ? .timeDomain : .varispeed
    AudioSpectrum.shared.attach(to: item)
    let p = AVPlayer(playerItem: item)
    p.automaticallyWaitsToMinimizeStalling = true
    let targetVol: Float = LibraryStore.shared.soundProfile == .night ? 0.72 : 1.0
    p.volume = shouldFadeInNext ? 0.08 : targetVol
    self.player = p
    if shouldFadeInNext {
      shouldFadeInNext = false
      Task { @MainActor [weak self, weak p] in
        for step in 1...10 {
          try? await Task.sleep(for: .milliseconds(90))
          guard let self, let p, self.player === p else { return }
          p.volume = targetVol * (Float(step) / 10.0)
        }
      }
    }

    statusObs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
      if it.status == .readyToPlay {
        // O stream progressivo (MP4 itag 18) traz vídeo 360p: desligamos a faixa de vídeo para o
        // iPhone não decodificar imagem que ninguém vê (menos CPU/GPU, menos calor e bateria).
        for t in it.tracks where t.assetTrack?.mediaType == .video && t.isEnabled { t.isEnabled = false }
      }
      if it.status == .failed {
        let msg = it.error?.localizedDescription ?? "Falha ao reproduzir esta faixa."
        Task { @MainActor [weak self] in
          guard let self else { return }
          if self.tryProgressiveFallback(track: track) { return }
          if let vid = track.videoId,
             !LibraryStore.shared.isDownloaded(track.id),
             !self.retriedTrackIds.contains(track.id),
             self.currentTrack?.id == track.id {
            self.retriedTrackIds.insert(track.id)
            await MusicEngine.shared.invalidateStream(videoId: vid)
            if let fresh = await MusicEngine.shared.resolveStream(videoId: vid),
               self.currentTrack?.id == track.id {
              let asset = fresh.headers.isEmpty
                ? AVURLAsset(url: fresh.url)
                : AVURLAsset(url: fresh.url, options: ["AVURLAssetHTTPHeaderFieldsKey": fresh.headers])
              self.beginAVPlayback(asset: asset, track: track)
              return
            }
          }
          self.isLoading = false
          self.isPlaying = false
          self.errorToast = "Erro no áudio: \(msg)"
        }
      }
    }

    failObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { _ = self?.tryProgressiveFallback(track: track) }
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

    // Antes: a cada 0,15 s este bloco reatribuía isPlaying/isLoading/duration mesmo sem mudança —
    // e todo @Published dispara objectWillChange, re-renderizando ~7x/s TODAS as telas que observam o
    // player (as 4 abas ficam vivas no RootView). Agora só publica quando o valor muda de verdade,
    // não cria Task por tick e, em segundo plano/tela bloqueada, não publica o relógio.
    timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.15, preferredTimescale: 600), queue: .main) { [weak self] cm in
      MainActor.assumeIsolated { self?.handleTick(cm) }
    }

    p.playImmediately(atRate: playbackRate)
    isPlaying = true
    isLoading = false
    updateNowPlaying()
  }

  private func handleTick(_ cm: CMTime) {
    guard let pl = player else { return }
    let clock = PlaybackClock.shared
    let sec = cm.seconds
    var now = clock.currentTime
    var dur = clock.duration
    if sec.isFinite && sec >= 0 { now = sec }
    if let d = pl.currentItem?.duration.seconds, d.isFinite && d > 1 { dur = d }
    if !inBackground {
      if clock.currentTime != now { clock.currentTime = now }
      if clock.duration != dur { clock.duration = dur }
    }
    switch pl.timeControlStatus {
    case .playing:
      if isLoading { isLoading = false }
      if !isPlaying { isPlaying = true }
    case .waitingToPlayAtSpecifiedRate:
      if !isLoading { isLoading = true }
    default:
      break
    }
    if sleepTimerOption == .endOfTrack {
      let rem = max(0, Int(dur - now))
      if sleepRemainingSeconds != rem { sleepRemainingSeconds = rem }
    }
    let xf = LibraryStore.shared.crossfadeSeconds
    if xf > 0, repeatMode != .one, sleepTimerOption != .endOfTrack, dur > xf + 2, isPlaying {
      let rem = dur - now
      let baseVol: Float = LibraryStore.shared.soundProfile == .night ? 0.72 : 1.0
      if rem <= xf && rem > 0 {
        let ratio = max(0.05, min(1.0, Float(rem / xf)))
        pl.volume = baseVol * ratio
        if rem <= 0.65 && !crossfadeTriggered && (currentIndex + 1 < queue.count || repeatMode == .all || autoplayRadio) {
          crossfadeTriggered = true
          shouldFadeInNext = true
          // O relógio pode estar congelado em segundo plano: sincroniza antes de trocar.
          clock.currentTime = now
          nextTrack()
        }
      } else if !crossfadeTriggered && sleepRemainingSeconds == 0 && pl.volume != baseVol {
        pl.volume = baseVol
      }
    }
  }

  /// Se o áudio puro (itag 140) falhar, troca para o MP4 progressivo já resolvido, do mesmo ponto.
  private func tryProgressiveFallback(track: Track) -> Bool {
    guard let fb = pendingFallbackURL, currentTrack?.id == track.id else { return false }
    pendingFallbackURL = nil
    let resumeAt = player.map { $0.currentTime().seconds } ?? 0
    currentBitrateLabel = "AAC · Estéreo"
    beginAVPlayback(asset: AVURLAsset(url: fb), track: track)
    if resumeAt.isFinite && resumeAt > 1 {
      player?.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    return true
  }

  private func setNowPlayingImage(_ img: UIImage) {
    nowPlayingArtImage = img
    nowPlayingArtwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
    updateNowPlaying()
  }

  /// Arte composta (vinil / fita K7) da tela de bloqueio: desenhada uma vez por faixa+estilo, fora da main.
  private func scheduleLockArtwork(for track: Track) {
    lockArtTask?.cancel()
    guard let cover = lockCoverImage else { return }
    let style = LibraryStore.shared.resolvedLockArtStyle
    guard style != .cover else {
      setNowPlayingImage(cover)
      return
    }
    let palette = self.palette
    lockArtTask = Task { [weak self] in
      let img = await LockScreenArtwork.shared.image(for: track, cover: cover, style: style, palette: palette)
      guard let self, !Task.isCancelled, self.currentTrack?.id == track.id, let img else { return }
      self.setNowPlayingImage(img)
      // Depuração: `-LMDebugLockArt` salva as duas artes compostas em tmp/ para inspeção.
      if ProcessInfo.processInfo.arguments.contains("-LMDebugLockArt") {
        for st in [LockArtStyle.vinyl, .cassette] {
          if let out = await LockScreenArtwork.shared.image(for: track, cover: cover, style: st, palette: palette) {
            try? out.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("lockart-\(st.rawValue).png"))
          }
        }
      }
    }
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
    if let fo = failObserver {
      NotificationCenter.default.removeObserver(fo)
    }
    failObserver = nil
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
    if let art = nowPlayingArtwork {
      info[MPMediaItemPropertyArtwork] = art
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
}
