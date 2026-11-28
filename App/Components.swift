import SwiftUI

// MARK: - Artwork & artist photo store (upgrades YouTube thumbnails to real album covers)

@MainActor
final class ArtworkStore: ObservableObject {
  static let shared = ArtworkStore()

  @Published private(set) var upgraded: [String: String] = [:]      // track id -> hi-res album cover
  @Published private(set) var artistPhotos: [String: String] = [:]  // lowercased artist -> photo
  private var pending: Set<String> = []
  private var pendingArtists: Set<String> = []
  private var missingArtists: Set<String> = []

  func url(for t: Track) -> String {
    if let u = upgraded[t.id] { return u }
    if let stored = LibraryStore.shared.tracksById[t.id]?.artworkURL, !ArtworkResolver.needsUpgrade(stored) { return stored }
    return t.artworkURL
  }

  func ensure(_ t: Track) async {
    guard upgraded[t.id] == nil, ArtworkResolver.needsUpgrade(url(for: t)), !pending.contains(t.id) else { return }
    pending.insert(t.id)
    defer { pending.remove(t.id) }
    if let cover = await ArtworkResolver.shared.albumCover(title: t.title, artist: LibraryStore.mainArtist(t.artist), album: t.album) {
      upgraded[t.id] = cover
      LibraryStore.shared.updateArtwork(cover, for: t.id)
    }
  }

  func photo(for artist: String) -> String? {
    artistPhotos[LibraryStore.mainArtist(artist).lowercased()]
  }

  func register(_ artists: [ArtistInfo]) {
    for a in artists where !a.pictureURL.isEmpty {
      artistPhotos[a.name.lowercased()] = a.pictureURL
    }
  }

  func ensurePhoto(_ artist: String) async {
    let name = LibraryStore.mainArtist(artist)
    let key = name.lowercased()
    guard !key.isEmpty, artistPhotos[key] == nil, !pendingArtists.contains(key), !missingArtists.contains(key) else { return }
    pendingArtists.insert(key)
    defer { pendingArtists.remove(key) }
    if let url = await ArtworkResolver.shared.artistPicture(name: name) {
      artistPhotos[key] = url
    } else {
      missingArtists.insert(key)
    }
  }
}

/// Track artwork that upgrades itself to the real album cover when the source only has a video thumbnail.
struct TrackArtwork: View {
  let track: Track
  var cornerRadius: CGFloat = 10
  var maxPixel: CGFloat = 500
  @ObservedObject private var store = ArtworkStore.shared

  var body: some View {
    ArtworkImage(url: store.url(for: track), cornerRadius: cornerRadius, maxPixel: maxPixel)
      .task(id: track.id) { await store.ensure(track) }
  }
}

struct ArtistAvatar: View {
  let name: String
  var size: CGFloat = 32
  @ObservedObject private var store = ArtworkStore.shared

  var body: some View {
    ZStack {
      if let url = store.photo(for: name) {
        ArtworkImage(url: url, cornerRadius: size / 2, maxPixel: max(120, size * 3), placeholderIcon: "person.fill")
      } else {
        Circle().fill(Theme.prismDiagonal.opacity(0.85))
        Text(String(LibraryStore.mainArtist(name).prefix(1)).uppercased())
          .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
          .foregroundStyle(Theme.onPrism)
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .task(id: name) { await store.ensurePhoto(name) }
  }
}

// MARK: - Track context menu

struct TrackMenuItems: View {
  let track: Track
  var queue: [Track]? = nil
  private var store: LibraryStore { LibraryStore.shared }
  private var downloads: DownloadManager { DownloadManager.shared }
  private var player: AudioPlayer { AudioPlayer.shared }
  private var app: AppModel { AppModel.shared }

  var body: some View {
    Button { player.play(track, in: queue) } label: { Label("Tocar agora", systemImage: "play.fill") }
    Button { player.playNextInQueue(track); app.showToast("Toca a seguir: \(track.title)") } label: { Label("Tocar a seguir", systemImage: "text.line.first.and.arrowtriangle.forward") }
    Button { player.addToQueue(track); app.showToast("Adicionada à fila") } label: { Label("Adicionar à fila", systemImage: "text.line.last.and.arrowtriangle.forward") }
    Button { player.startRadio(from: track) } label: { Label("Iniciar rádio", systemImage: "dot.radiowaves.left.and.right") }
    Divider()
    Button { store.toggleFavorite(track) } label: {
      Label(store.isFavorite(track.id) ? "Remover das curtidas" : "Curtir", systemImage: store.isFavorite(track.id) ? "heart.slash" : "heart")
    }
    Button { app.playlistPickerTrack = track } label: { Label("Adicionar a uma playlist", systemImage: "text.badge.plus") }
    if store.isDownloaded(track.id) {
      Button(role: .destructive) { store.removeDownload(track.id) } label: { Label("Remover download", systemImage: "trash") }
    } else if downloads.isDownloading(track.id) {
      Button { downloads.cancel(track.id) } label: { Label("Cancelar download", systemImage: "xmark.circle") }
    } else {
      Button { downloads.download(track) } label: { Label("Baixar", systemImage: "arrow.down.circle") }
    }
    Divider()
    Button { app.openArtist(track.artist) } label: { Label("Ver artista", systemImage: "music.mic") }
  }
}

// MARK: - Track row (Apple Music style)

struct TrackRow: View {
  let track: Track
  var rank: Int? = nil
  var queue: [Track]? = nil
  var showArtwork: Bool = true
  var onPlay: (() -> Void)? = nil

  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var store = LibraryStore.shared

  var body: some View {
    let active = player.currentTrack?.id == track.id
    HStack(spacing: 12) {
      if let rank {
        Text("\(rank)")
          .font(Theme.font(14.5, .bold))
          .foregroundStyle(rankColor(rank))
          .monospacedDigit()
          .frame(width: 26)
      }
      if showArtwork {
        TrackArtwork(track: track, cornerRadius: 8, maxPixel: 200)
          .frame(width: 50, height: 50)
          .overlay {
            if active {
              RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.35))
              Image(systemName: "waveform")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
            }
          }
      }
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 5) {
          Text(track.title)
            .font(Theme.font(16, .regular))
            .foregroundStyle(active ? Theme.accent : Theme.text)
            .lineLimit(1)
          if track.isExplicit {
            Image(systemName: "e.square.fill").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
          }
        }
        HStack(spacing: 5) {
          if store.isDownloaded(track.id) {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.secondary)
          }
          Text(track.artist)
            .font(Theme.font(13.5))
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 6)
      TrackDownloadIndicator(trackId: track.id)
      Menu {
        TrackMenuItems(track: track, queue: queue)
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Theme.secondary)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("Mais opções")
    }
    .padding(.vertical, 5)
    .contentShape(Rectangle())
    .onTapGesture {
      Haptics.light()
      if let onPlay { onPlay() } else { player.play(track, in: queue) }
    }
    .contextMenu { TrackMenuItems(track: track, queue: queue) }
  }

  private func rankColor(_ rank: Int) -> Color {
    switch rank {
    case 1: return Theme.hex(0xF59E0B)
    case 2: return Theme.hex(0x94A3B8)
    case 3: return Theme.hex(0xD97706)
    default: return Theme.secondary
    }
  }
}

/// Isola a assinatura do DownloadManager para não re-renderizar todas as linhas de música a cada tick.
private struct TrackDownloadIndicator: View {
  let trackId: String
  @ObservedObject private var downloads = DownloadManager.shared

  var body: some View {
    if let p = downloads.progressById[trackId] {
      Circle()
        .trim(from: 0, to: CGFloat(p))
        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .frame(width: 18, height: 18)
    }
  }
}

// MARK: - Tiles

struct AlbumTile: View {
  let album: AlbumShowcase
  var width: CGFloat = 150
  var showDate: Bool = false

  var body: some View {
    Button {
      Haptics.light()
      AppModel.shared.push(.album(album))
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        ArtworkImage(url: album.artworkURL, cornerRadius: 12, maxPixel: 420)
          .frame(width: width, height: width)
          .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
          .lumeShadow(10, y: 6, opacity: 0.5)
        VStack(alignment: .leading, spacing: 1) {
          Text(album.title)
            .font(Theme.font(14, .medium))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
          Text(showDate ? subtitleWithDate : album.artist)
            .font(Theme.font(13))
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
      }
    }
    .buttonStyle(PressableStyle())
  }

  private var subtitleWithDate: String {
    let d = Theme.shortDate(album.releaseDate)
    return d.isEmpty ? album.artist : "\(album.artist) · \(d)"
  }
}

struct ArtistBubble: View {
  let name: String
  var pictureURL: String? = nil
  var deezerId: Int? = nil
  var size: CGFloat = 86
  var rank: Int? = nil

  var body: some View {
    Button {
      Haptics.light()
      AppModel.shared.push(.artist(name, deezerId))
    } label: {
      VStack(spacing: 8) {
        Group {
          if let pictureURL, !pictureURL.isEmpty {
            ArtworkImage(url: pictureURL, cornerRadius: size / 2, maxPixel: size * 3, placeholderIcon: "person.fill")
          } else {
            ArtistAvatar(name: name, size: size)
          }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.hairline, lineWidth: 0.5))
        .lumeShadow(10, y: 5, opacity: 0.45)
        .overlay(alignment: .topLeading) {
          if let rank {
            Text("#\(rank)")
              .font(Theme.font(10.5, .bold))
              .foregroundStyle(.white)
              .monospacedDigit()
              .padding(.horizontal, 6)
              .frame(height: 20)
              .background(Capsule().fill(badgeColor(rank)))
              .overlay(Capsule().stroke(.white.opacity(0.45), lineWidth: 0.6))
              .offset(x: -2, y: -2)
          }
        }
        Text(name)
          .font(Theme.font(13, .medium))
          .foregroundStyle(Theme.text)
          .lineLimit(1)
          .frame(width: size + 8)
      }
    }
    .buttonStyle(PressableStyle())
  }

  private func badgeColor(_ rank: Int) -> Color {
    switch rank {
    case 1: return Theme.hex(0xD97706)
    case 2: return Theme.hex(0x64748B)
    case 3: return Theme.hex(0xB45309)
    default: return Color.black.opacity(0.65)
    }
  }
}

/// Tall editorial card (Serene-inspired): full-bleed art, glass artist pill on top, bold title at the bottom.
struct TallTrackCard: View {
  let track: Track
  let rank: Int
  var caption: String = "no Brasil"
  let onPlay: () -> Void

  var body: some View {
    Button {
      Haptics.medium()
      onPlay()
    } label: {
      ZStack(alignment: .bottomLeading) {
        TrackArtwork(track: track, cornerRadius: 0, maxPixel: 700)
          .frame(width: 206, height: 276)
        LinearGradient(
          stops: [
            .init(color: .black.opacity(0.28), location: 0),
            .init(color: .clear, location: 0.26),
            .init(color: .clear, location: 0.52),
            .init(color: .black.opacity(0.82), location: 1),
          ],
          startPoint: .top, endPoint: .bottom
        )
        VStack(alignment: .leading, spacing: 0) {
          HStack(spacing: 8) {
            ArtistAvatar(name: track.artist, size: 30)
            VStack(alignment: .leading, spacing: 0) {
              Text(LibraryStore.mainArtist(track.artist))
                .font(Theme.font(12.5, .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
              Text("Top \(rank) \(caption)")
                .font(Theme.font(10.5, .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "play.fill")
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(.white)
          }
          .padding(.leading, 5)
          .padding(.trailing, 12)
          .frame(height: 40)
          .glassCapsule(clear: true)
          .environment(\.colorScheme, .dark)

          Spacer()

          HStack(spacing: 5) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 11, weight: .bold))
            Text("#\(rank)").font(Theme.font(12, .semibold)).monospacedDigit()
          }
          .foregroundStyle(.white.opacity(0.85))
          .padding(.bottom, 4)
          Text(track.title.uppercased())
            .font(.system(size: 18, weight: .heavy))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .minimumScaleFactor(0.8)
        }
        .padding(12)
      }
      .frame(width: 206, height: 276)
      .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 0.8))
      .lumeShadow(16, y: 10, opacity: 0.6)
    }
    .buttonStyle(PressableStyle())
    .contextMenu { TrackMenuItems(track: track) }
  }
}

/// Serene "Recently played" card with a glass ▶ pill.
struct PlayCard: View {
  let track: Track
  let queue: [Track]
  var size: CGFloat = 132

  var body: some View {
    Button {
      Haptics.light()
      AudioPlayer.shared.play(track, in: queue)
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        ZStack(alignment: .bottomLeading) {
          TrackArtwork(track: track, cornerRadius: 0, maxPixel: 400)
            .frame(width: size, height: size * 1.12)
          HStack(spacing: 4) {
            Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
            Text("Tocar").font(Theme.font(11, .semibold))
          }
          .foregroundStyle(.white)
          .padding(.horizontal, 10)
          .frame(height: 26)
          .glassCapsule(clear: true)
          .environment(\.colorScheme, .dark)
          .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
        .lumeShadow(10, y: 6, opacity: 0.45)
        Text(track.title).font(Theme.font(13.5, .medium)).foregroundStyle(Theme.text).lineLimit(1)
          .frame(width: size, alignment: .leading)
        Text(track.artist).font(Theme.font(12.5)).foregroundStyle(Theme.secondary).lineLimit(1)
          .frame(width: size, alignment: .leading)
      }
    }
    .buttonStyle(PressableStyle())
    .contextMenu { TrackMenuItems(track: track, queue: queue) }
  }
}

// MARK: - Skeletons

/// Esqueleto "respirando". 5.0: antes era um gradiente com máscara deslizando para sempre (mask +
/// overlay redesenhados a cada quadro, mesmo nas abas ocultas). Agora só a opacidade pulsa — barato —
/// e fica parado com Reduzir Movimento, modo economia ou aparelho quente.
struct Shimmer: ViewModifier {
  @State private var dim = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func body(content: Content) -> some View {
    content
      .opacity(dim ? 0.55 : 1)
      .onAppear {
        guard !reduceMotion, !PerfGovernor.shared.reduced else { return }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
      }
      .onDisappear { dim = false }
  }
}

struct SkeletonBlock: View {
  var width: CGFloat? = nil
  var height: CGFloat
  var radius: CGFloat = 16
  var body: some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
      .fill(Theme.fillStrong)
      .frame(width: width, height: height)
      .modifier(Shimmer())
  }
}

/// Horizontally scrolling row with standard margins.
struct HRow<Content: View>: View {
  var spacing: CGFloat = 14
  @ViewBuilder var content: () -> Content
  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      LazyHStack(alignment: .top, spacing: spacing) { content() }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
    .scrollClipDisabled()
  }
}
