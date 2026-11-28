import Combine
import SwiftUI
import UIKit
import WidgetKit

/// Executa no app os comandos dos botões do widget (ver Shared/LumeWidgetShared.swift).
@MainActor
enum LumeRemoteControl {
  enum Command { case toggle, next, previous }

  static func run(_ command: Command) {
    let player = AudioPlayer.shared
    switch command {
    case .toggle:
      if player.currentTrack == nil { playLast() } else { player.togglePlayPause() }
    case .next:
      if player.currentTrack == nil { playLast() } else { player.nextTrack() }
    case .previous:
      if player.currentTrack == nil { playLast() } else { player.previousTrack() }
    }
  }

  /// App recém-aberto pelo widget, sem faixa na fila: toca a última que o widget mostra.
  private static func playLast() {
    if let t = LibraryStore.shared.recentTracks.first {
      AudioPlayer.shared.play(t)
    } else if let d = WidgetStore.read(), let vid = d.videoId, !vid.isEmpty {
      AudioPlayer.shared.play(Track(id: d.trackId ?? vid, videoId: vid, title: d.title, artist: d.artist, artworkURL: d.artworkURL ?? ""))
    }
  }
}

/// Publica a música atual para o widget (JSON + capa reduzida no App Group) e pede a atualização da linha do tempo.
/// Sem App Group (LiveContainer) não faz nada.
@MainActor
final class WidgetBridge {
  static let shared = WidgetBridge()

  private var cancellables = Set<AnyCancellable>()
  private var pushTask: Task<Void, Never>?
  private var lastCoverKey: String?
  private var lastWritten: WidgetNowPlaying?
  private var started = false

  func start() {
    guard !started, LumeGroup.containerURL != nil else { return }
    started = true
    lastWritten = WidgetStore.read()
    lastCoverKey = lastWritten?.coverKey
    let p = AudioPlayer.shared
    Publishers.CombineLatest3(p.$currentTrack, p.$isPlaying, p.$currentArtwork)
      .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
      .sink { [weak self] track, playing, art in
        MainActor.assumeIsolated { self?.push(track: track, playing: playing, artwork: art) }
      }
      .store(in: &cancellables)
    // Primeira vez (nada gravado ainda): mostra a última música ouvida, pausada.
    if lastWritten == nil, p.currentTrack == nil, let t = LibraryStore.shared.recentTracks.first {
      push(track: t, playing: false, artwork: "")
    }
  }

  private func push(track: Track?, playing: Bool, artwork: String) {
    // Sem faixa: mantém a última que foi gravada ("ou a última tocada").
    guard let t = track else { return }
    let art = artwork.isEmpty ? ArtworkStore.shared.url(for: t) : artwork
    let key = t.id + "|" + art
    pushTask?.cancel()
    pushTask = Task { [weak self] in
      guard let self else { return }
      if key != self.lastCoverKey {
        let jpeg = await Self.coverData(art)
        if Task.isCancelled { return }
        WidgetStore.writeCover(jpeg)
        self.lastCoverKey = key
      }
      let value = WidgetNowPlaying(title: t.title, artist: t.artist, isPlaying: playing,
                                   videoId: t.videoId, trackId: t.id, artworkURL: art.isEmpty ? nil : art, coverKey: key)
      guard value != self.lastWritten else { return }
      WidgetStore.write(value)
      self.lastWritten = value
      WidgetCenter.shared.reloadAllTimelines()
    }
  }

  /// Capa em ~300 px, JPEG (nil se não deu para baixar: o widget mostra o fundo padrão).
  private static func coverData(_ url: String) async -> Data? {
    guard !url.isEmpty, let img = await ImagePipeline.shared.image(url, maxPixel: 300) else { return nil }
    return await Task.detached(priority: .utility) {
      let side: CGFloat = 300
      let longest = max(img.size.width, img.size.height)
      guard longest > side else { return img.jpegData(compressionQuality: 0.82) }
      let k = side / longest
      let size = CGSize(width: img.size.width * k, height: img.size.height * k)
      let fmt = UIGraphicsImageRendererFormat.default()
      fmt.scale = 1
      let out = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
      return out.jpegData(compressionQuality: 0.82)
    }.value
  }
}

/// Liga as extras 5.2 (backup da biblioteca, ListenBrainz, widget) a partir de um único ponto no LumeMusicApp.
@MainActor
enum LumeExtras {
  static func start() {
    LibraryBackupService.shared.start()
    ListenBrainzService.shared.start()
    WidgetBridge.shared.start()
  }

  /// Depois que o painel foi consultado e o teste/acesso foi resolvido na abertura.
  static func accessReady() {
    LibraryBackupService.shared.accessReady()
  }
}
