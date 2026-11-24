import SwiftUI

// MARK: - Cartões Reutilizáveis (Países, Gêneros, Playlists, Mixes)

struct CountryFlagCard: View {
  let country: ChartCountry
  var width: CGFloat = 152

  var body: some View {
    Button {
      Haptics.light()
      AppModel.shared.push(.country(country))
    } label: {
      ZStack(alignment: .bottomLeading) {
        LinearGradient(colors: [Theme.hex(country.hexA), Theme.hex(country.hexB)], startPoint: .topLeading, endPoint: .bottomTrailing)
        LinearGradient(colors: [.white.opacity(0.20), .clear], startPoint: .top, endPoint: .center)
        Text(country.flag)
          .font(.system(size: 54))
          .opacity(0.28)
          .rotationEffect(.degrees(12))
          .offset(x: 12, y: -4)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
          .padding(6)

        VStack(alignment: .leading, spacing: 2) {
          Text(country.flag)
            .font(.system(size: 26))
          Text(country.name)
            .font(Theme.font(15.5, .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
          Text("Top 50")
            .font(Theme.font(11.5, .semibold))
            .foregroundStyle(.white.opacity(0.82))
        }
        .padding(14)
      }
      .frame(width: width, height: 112)
      .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.22), lineWidth: 0.8))
      .lumeShadow(10, y: 6, opacity: 0.45)
    }
    .buttonStyle(PressableStyle(scale: 0.97))
  }
}

struct GenreCard: View {
  let genre: MusicGenre

  var body: some View {
    Button {
      Haptics.light()
      AppModel.shared.push(.genre(genre))
    } label: {
      ZStack(alignment: .bottomLeading) {
        LinearGradient(colors: [Theme.hex(genre.hexA), Theme.hex(genre.hexB)], startPoint: .topLeading, endPoint: .bottomTrailing)
        LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
        Image(systemName: genre.icon)
          .font(.system(size: 56, weight: .bold))
          .foregroundStyle(.white.opacity(0.25))
          .rotationEffect(.degrees(14))
          .offset(x: 18, y: 4)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
          .padding(6)

        VStack(alignment: .leading, spacing: 2) {
          Text(genre.title)
            .font(Theme.font(16, .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
          Text(genre.subtitle)
            .font(Theme.font(11, .medium))
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
      }
      .frame(height: 98)
      .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 0.8))
      .lumeShadow(10, y: 6, opacity: 0.45)
    }
    .buttonStyle(PressableStyle(scale: 0.97))
  }
}

struct RemotePlaylistCard: View {
  let playlist: RemotePlaylist
  var width: CGFloat = 152

  var body: some View {
    Button {
      Haptics.light()
      AppModel.shared.push(.remotePlaylist(playlist))
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        ArtworkImage(url: playlist.artworkURL, cornerRadius: 14, maxPixel: 420, placeholderIcon: "music.note.list")
          .frame(width: width, height: width)
          .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
          .lumeShadow(10, y: 6, opacity: 0.45)
        Text(playlist.title)
          .font(Theme.font(14, .medium))
          .foregroundStyle(Theme.text)
          .lineLimit(1)
          .frame(width: width, alignment: .leading)
        Text(playlist.subtitle)
          .font(Theme.font(12))
          .foregroundStyle(Theme.secondary)
          .lineLimit(1)
          .frame(width: width, alignment: .leading)
      }
    }
    .buttonStyle(PressableStyle())
  }
}

struct PersonalizedMixCard: View {
  let mix: PersonalizedMix

  var body: some View {
    Button {
      Haptics.light()
      AppModel.shared.push(.mix(mix))
    } label: {
      VStack(alignment: .leading, spacing: 10) {
        ZStack(alignment: .topLeading) {
          LinearGradient(colors: [Theme.hex(mix.hexA), Theme.hex(mix.hexB)], startPoint: .topLeading, endPoint: .bottomTrailing)
          if let art = mix.tracks.first(where: { !$0.artworkURL.isEmpty })?.artworkURL {
            ArtworkImage(url: art, cornerRadius: 0, maxPixel: 320)
              .opacity(0.32)
              .blendMode(.overlay)
          }
          LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)

          VStack(alignment: .leading, spacing: 0) {
            HStack {
              Text(mix.tag)
                .font(Theme.font(10.5, .bold))
                .tracking(0.8)
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .glassCapsule(clear: true)
              Spacer()
              Image(systemName: mix.icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
            Text(mix.title)
              .font(.system(size: 20, weight: .heavy, design: .rounded))
              .foregroundStyle(.white)
              .lineLimit(2)
            Text(mix.subtitle)
              .font(Theme.font(12, .medium))
              .foregroundStyle(.white.opacity(0.84))
              .lineLimit(2)
          }
          .padding(14)
        }
        .frame(width: 178, height: 192)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.22), lineWidth: 0.8))
        .lumeShadow(12, y: 8, opacity: 0.5)
        .environment(\.colorScheme, .dark)
      }
    }
    .buttonStyle(PressableStyle(scale: 0.97))
  }
}

// MARK: - Parada de País (CountryChartView)

struct CountryChartView: View {
  @State private var selectedCountry: ChartCountry
  @State private var bundle: CountryChartBundle?
  @State private var loading = true
  @State private var scope: CountryScope = .songs

  enum CountryScope: String, CaseIterable, Identifiable {
    case songs = "Top 50"
    case albums = "Álbuns"
    case artists = "Artistas"
    case trending = "Em Alta"
    var id: String { rawValue }
  }

  init(country: ChartCountry) {
    _selectedCountry = State(initialValue: country)
  }

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 20) {
        hero
        countryPickerStrip
        scopePicker

        if loading && bundle == nil {
          VStack(spacing: 12) {
            ForEach(0..<8, id: \.self) { _ in
              HStack(spacing: 12) {
                SkeletonBlock(width: 50, height: 50, radius: 8)
                VStack(alignment: .leading, spacing: 6) {
                  SkeletonBlock(width: 190, height: 14, radius: 6)
                  SkeletonBlock(width: 120, height: 12, radius: 6)
                }
                Spacer()
              }
            }
          }
          .padding(.horizontal, 20)
        } else if let bundle {
          scopeContent(bundle)
        } else {
          EmptyStateView(icon: "wifi.exclamationmark", title: "Parada indisponível", message: "Não foi possível carregar os rankings deste país agora.")
        }
      }
      .padding(.bottom, 20)
    }
    .ignoresSafeArea(edges: .top)
    .background(Theme.canvas.ignoresSafeArea())
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .task(id: selectedCountry.code) {
      loading = true
      bundle = await CatalogExplorerService.shared.countryChart(for: selectedCountry)
      if let arts = bundle?.topArtists { ArtworkStore.shared.register(arts) }
      loading = false
    }
  }

  private var hero: some View {
    ZStack(alignment: .bottomLeading) {
      LinearGradient(colors: [Theme.hex(selectedCountry.hexA), Theme.hex(selectedCountry.hexB)], startPoint: .topLeading, endPoint: .bottomTrailing)
      LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)

      Text(selectedCountry.flag)
        .font(.system(size: 130))
        .opacity(0.25)
        .offset(x: 20, y: 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

      VStack(alignment: .leading, spacing: 6) {
        Text(selectedCountry.region.uppercased())
          .font(Theme.font(11, .bold))
          .tracking(1.1)
          .foregroundStyle(.white.opacity(0.85))
        HStack(spacing: 10) {
          Text(selectedCountry.flag).font(.system(size: 36))
          Text("Top 50 \(selectedCountry.name)")
            .font(.system(size: 30, weight: .heavy))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
        }
        Text("As músicas, álbuns e cantores mais ouvidos no país")
          .font(Theme.font(13.5, .medium))
          .foregroundStyle(.white.opacity(0.86))
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 22)
    }
    .frame(height: 230)
    .clipped()
  }

  private var countryPickerStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(ChartCountry.all) { c in
          PrismChip(title: "\(c.flag) \(c.name)", active: c.code == selectedCountry.code) {
            selectedCountry = c
          }
        }
      }
      .padding(.horizontal, 20)
    }
    .scrollClipDisabled()
  }

  private var scopePicker: some View {
    HStack(spacing: 8) {
      ForEach(CountryScope.allCases) { s in
        PrismChip(title: s.rawValue, active: scope == s) { scope = s }
      }
    }
    .padding(.horizontal, 20)
  }

  @ViewBuilder
  private func scopeContent(_ b: CountryChartBundle) -> some View {
    switch scope {
    case .songs:
      VStack(spacing: 14) {
        HStack(spacing: 10) {
          PlayShuffleBar(tracks: b.topSongs, context: "Top 50 \(b.country.name)")
          GlassIconButton(systemName: "arrow.down.circle", size: 50) {
            let top10 = Array(b.topSongs.prefix(10))
            DownloadManager.shared.downloadBatch(top10)
            AppModel.shared.showToast("Baixando Top 10 de \(b.country.name)")
          }
          .accessibilityLabel("Baixar Top 10")
        }
        .padding(.horizontal, 20)

        LazyVStack(spacing: 0) {
          ForEach(Array(b.topSongs.enumerated()), id: \.element.id) { idx, tr in
            TrackRow(track: tr, rank: idx + 1, queue: b.topSongs)
          }
        }
        .padding(.horizontal, 20)
      }
    case .albums:
      if b.topAlbums.isEmpty {
        EmptyStateView(icon: "square.stack", title: "Sem álbuns", message: "Nenhum álbum ranqueado disponível agora.")
      } else {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 20) {
          ForEach(b.topAlbums) { a in
            GeometryReader { g in
              AlbumTile(album: a, width: g.size.width, showDate: true)
            }
            .aspectRatio(0.78, contentMode: .fit)
          }
        }
        .padding(.horizontal, 20)
      }
    case .artists:
      if b.topArtists.isEmpty {
        EmptyStateView(icon: "music.mic", title: "Sem artistas", message: "Nenhum artista ranqueado disponível agora.")
      } else {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 22) {
          ForEach(Array(b.topArtists.enumerated()), id: \.element.id) { idx, a in
            ArtistBubble(name: a.name, pictureURL: a.pictureURL, deezerId: a.deezerId, size: 96, rank: a.rank ?? (idx + 1))
          }
        }
        .padding(.horizontal, 16)
      }
    case .trending:
      let list = b.trending.isEmpty ? Array(b.topSongs.prefix(20)) : b.trending
      VStack(spacing: 14) {
        PlayShuffleBar(tracks: list, context: "Em alta · \(b.country.name)")
          .padding(.horizontal, 20)
        LazyVStack(spacing: 0) {
          ForEach(Array(list.enumerated()), id: \.element.id) { idx, tr in
            TrackRow(track: tr, rank: idx + 1, queue: list)
          }
        }
        .padding(.horizontal, 20)
      }
    }
  }
}

// MARK: - Hub de Gênero Musical (GenreHubView)

struct GenreHubView: View {
  let genre: MusicGenre
  @State private var bundle: GenreHubBundle?
  @State private var loading = true

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 26) {
        hero
        if loading && bundle == nil {
          VStack(spacing: 12) {
            ForEach(0..<6, id: \.self) { _ in
              HStack(spacing: 12) {
                SkeletonBlock(width: 50, height: 50, radius: 8)
                VStack(alignment: .leading, spacing: 6) {
                  SkeletonBlock(width: 180, height: 14, radius: 6)
                  SkeletonBlock(width: 110, height: 12, radius: 6)
                }
                Spacer()
              }
            }
          }
          .padding(.horizontal, 20)
        } else if let b = bundle {
          content(b)
        }
      }
      .padding(.bottom, 20)
    }
    .ignoresSafeArea(edges: .top)
    .background(Theme.canvas.ignoresSafeArea())
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .task(id: genre.id) {
      loading = true
      bundle = await CatalogExplorerService.shared.genreHub(for: genre)
      if let arts = bundle?.topArtists { ArtworkStore.shared.register(arts) }
      loading = false
    }
  }

  private var hero: some View {
    ZStack(alignment: .bottomLeading) {
      LinearGradient(colors: [Theme.hex(genre.hexA), Theme.hex(genre.hexB)], startPoint: .topLeading, endPoint: .bottomTrailing)
      LinearGradient(colors: [.black.opacity(0.22), .black.opacity(0.42)], startPoint: .top, endPoint: .bottom)
      Image(systemName: genre.icon)
        .font(.system(size: 130, weight: .bold))
        .foregroundStyle(.white.opacity(0.22))
        .rotationEffect(.degrees(14))
        .offset(x: 34, y: -6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

      VStack(alignment: .leading, spacing: 4) {
        Text(genre.group.rawValue.uppercased())
          .font(Theme.font(11, .bold))
          .tracking(1.1)
          .foregroundStyle(.white.opacity(0.84))
        Text(genre.title)
          .font(.system(size: 34, weight: .heavy))
          .foregroundStyle(.white)
          .lineLimit(2)
        Text(genre.subtitle)
          .font(Theme.font(14, .medium))
          .foregroundStyle(.white.opacity(0.85))
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 22)
    }
    .frame(height: 226)
    .clipped()
  }

  @ViewBuilder
  private func content(_ b: GenreHubBundle) -> some View {
    if !b.topSongs.isEmpty {
      HStack(spacing: 10) {
        PlayShuffleBar(tracks: b.topSongs, context: genre.title)
        GlassIconButton(systemName: "dot.radiowaves.left.and.right", size: 50) {
          if let first = b.topSongs.first {
            AudioPlayer.shared.startRadio(from: first)
          }
        }
        .accessibilityLabel("Rádio do estilo")
      }
      .padding(.horizontal, 20)
    }

    if !b.topArtists.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Principais artistas", actionLabel: "Ver todos") {
          AppModel.shared.push(.artists("Artistas · \(genre.title)", b.topArtists))
        }
        HRow(spacing: 16) {
          ForEach(Array(b.topArtists.prefix(16).enumerated()), id: \.element.id) { idx, a in
            ArtistBubble(name: a.name, pictureURL: a.pictureURL, deezerId: a.deezerId, rank: idx + 1)
          }
        }
      }
    }

    if !b.topSongs.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        SectionHeader(title: "Mais tocadas em \(genre.title)", actionLabel: b.topSongs.count > 10 ? "Ver tudo" : nil, action: b.topSongs.count > 10 ? {
          AppModel.shared.push(.tracks("Top \(genre.title)", b.topSongs))
        } : nil)
        VStack(spacing: 0) {
          ForEach(Array(b.topSongs.prefix(12).enumerated()), id: \.element.id) { idx, tr in
            TrackRow(track: tr, rank: idx + 1, queue: b.topSongs)
          }
        }
        .padding(.horizontal, 20)
      }
    }

    if !b.topAlbums.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Álbuns em destaque", actionLabel: "Ver tudo") {
          AppModel.shared.push(.albums("Álbuns · \(genre.title)", b.topAlbums))
        }
        HRow {
          ForEach(b.topAlbums.prefix(16)) { a in AlbumTile(album: a, width: 150, showDate: true) }
        }
      }
    }

    if !b.playlists.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Playlists selecionadas")
        HRow {
          ForEach(b.playlists) { pl in RemotePlaylistCard(playlist: pl) }
        }
      }
    }
  }
}

// MARK: - Playlist Editorial Remota (RemotePlaylistView)

struct RemotePlaylistView: View {
  let playlist: RemotePlaylist
  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var app = AppModel.shared
  @State private var tracks: [Track] = []
  @State private var loading = true

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(spacing: 0) {
        VStack(spacing: 6) {
          ArtworkImage(url: playlist.artworkURL, cornerRadius: 18, maxPixel: 700, placeholderIcon: "music.note.list")
            .frame(width: 220, height: 220)
            .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
            .padding(.top, 8)
            .padding(.bottom, 14)
          Text(playlist.title)
            .font(Theme.font(24, .bold))
            .foregroundStyle(Theme.text)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 28)
          Text(playlist.subtitle)
            .font(Theme.font(13.5))
            .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)

        VStack(spacing: 16) {
          PlayShuffleBar(tracks: tracks, context: playlist.title)
          HStack(spacing: 14) {
            GlassIconButton(systemName: "arrow.down.circle", size: 46) {
              DownloadManager.shared.downloadBatch(tracks)
              app.showToast("Baixando \(tracks.count) músicas")
            }
            .accessibilityLabel("Baixar todas")
            GlassIconButton(systemName: "text.badge.plus", size: 46) {
              if store.playlists.contains(where: { $0.name == playlist.title }) {
                app.showToast("Esta playlist já está na sua biblioteca")
              } else {
                store.createPlaylist(name: playlist.title, subtitle: playlist.creator, sourceBadge: "Curadoria", artworkURL: playlist.artworkURL, tracks: tracks)
                Haptics.success()
                app.showToast("Playlist salva na biblioteca")
              }
            }
            .accessibilityLabel("Salvar na biblioteca")
          }
          .glassGroup()
          .disabled(tracks.isEmpty)
          .opacity(tracks.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)

        VStack(spacing: 0) {
          if loading {
            VStack(spacing: 12) {
              ForEach(0..<8, id: \.self) { _ in
                HStack(spacing: 12) {
                  SkeletonBlock(width: 50, height: 50, radius: 8)
                  VStack(alignment: .leading, spacing: 6) {
                    SkeletonBlock(width: 170, height: 14, radius: 6)
                    SkeletonBlock(width: 110, height: 12, radius: 6)
                  }
                  Spacer()
                }
              }
            }
            .padding(.top, 14)
          } else if tracks.isEmpty {
            EmptyStateView(icon: "music.note.list", title: "Faixas indisponíveis", message: "Não foi possível carregar as músicas desta playlist agora.")
          } else {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, tr in
              TrackRow(track: tr, rank: idx + 1, queue: tracks)
              if idx < tracks.count - 1 {
                Divider().overlay(Theme.hairline).padding(.leading, 62)
              }
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
      }
    }
    .background(Theme.canvas.ignoresSafeArea())
    .navigationTitle(playlist.title)
    .navigationBarTitleDisplayMode(.inline)
    .task {
      tracks = await CatalogExplorerService.shared.playlistTracks(deezerId: playlist.deezerId)
      loading = false
    }
  }
}

// MARK: - Mix Personalizado (MixDetailView)

struct MixDetailView: View {
  let mix: PersonalizedMix
  @ObservedObject private var app = AppModel.shared
  @ObservedObject private var store = LibraryStore.shared

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 20) {
        ZStack(alignment: .bottomLeading) {
          LinearGradient(colors: [Theme.hex(mix.hexA), Theme.hex(mix.hexB)], startPoint: .topLeading, endPoint: .bottomTrailing)
          LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
          Image(systemName: mix.icon)
            .font(.system(size: 120, weight: .bold))
            .foregroundStyle(.white.opacity(0.22))
            .offset(x: 24, y: 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
          VStack(alignment: .leading, spacing: 4) {
            Text(mix.tag)
              .font(Theme.font(11, .bold))
              .tracking(1.1)
              .foregroundStyle(.white.opacity(0.85))
            Text(mix.title)
              .font(.system(size: 32, weight: .heavy))
              .foregroundStyle(.white)
            Text(mix.subtitle)
              .font(Theme.font(14, .medium))
              .foregroundStyle(.white.opacity(0.85))
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 22)
        }
        .frame(height: 220)
        .clipped()

        HStack(spacing: 10) {
          PlayShuffleBar(tracks: mix.tracks, context: mix.title)
          GlassIconButton(systemName: "arrow.down.circle", size: 50) {
            DownloadManager.shared.downloadBatch(mix.tracks)
            app.showToast("Baixando \(mix.title)")
          }
          .accessibilityLabel("Baixar mix")
          GlassIconButton(systemName: "text.badge.plus", size: 50) {
            store.createPlaylist(name: mix.title, subtitle: mix.subtitle, sourceBadge: "Lume Mix", tracks: mix.tracks)
            Haptics.success()
            app.showToast("Mix salvo nas suas playlists")
          }
          .accessibilityLabel("Salvar mix")
        }
        .padding(.horizontal, 20)

        LazyVStack(spacing: 0) {
          ForEach(Array(mix.tracks.enumerated()), id: \.element.id) { idx, tr in
            TrackRow(track: tr, rank: idx + 1, queue: mix.tracks)
          }
        }
        .padding(.horizontal, 20)
      }
      .padding(.bottom, 20)
    }
    .ignoresSafeArea(edges: .top)
    .background(Theme.canvas.ignoresSafeArea())
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
  }
}

// MARK: - Central de Downloads Offline (DownloadsCenterView)

struct DownloadsCenterView: View {
  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var downloads = DownloadManager.shared
  @ObservedObject private var app = AppModel.shared
  @State private var confirmClear = false

  var body: some View {
    List {
      Section {
        Toggle(isOn: $store.offlineMode) {
          Label("Modo Offline", systemImage: "airplane.circle.fill")
        }
        Toggle(isOn: $store.autoDownloadFavorites) {
          Label("Baixar curtidas automaticamente", systemImage: "heart.circle.fill")
        }
      } header: {
        Text("Comportamento offline")
      } footer: {
        Text("Com o Modo Offline ativo, o Lume toca apenas músicas já salvas no aparelho e evita consumo de dados móveis.")
      }
      .listRowBackground(Theme.canvasRaised)

      if downloads.pendingCount > 0 {
        Section("Na fila agora (\(downloads.pendingCount))") {
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Text(downloads.paused ? "Pausado" : "Baixando faixas…")
                .font(Theme.font(14, .semibold))
              Spacer()
              Text("\(Int((downloads.overallProgress * 100).rounded()))%")
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.secondary)
                .monospacedDigit()
            }
            ProgressView(value: downloads.overallProgress)
              .tint(Theme.accent)
            HStack(spacing: 10) {
              Button(downloads.paused ? "Retomar" : "Pausar") {
                downloads.togglePauseAll()
              }
              .buttonStyle(.bordered)
              Button("Cancelar tudo", role: .destructive) {
                downloads.cancelAll()
              }
              .buttonStyle(.bordered)
            }
          }
          .padding(.vertical, 4)

          ForEach(Array(downloads.statesById.keys.sorted()), id: \.self) { id in
            if let st = downloads.statesById[id], st.isActive, let tr = store.tracksById[id] {
              HStack(spacing: 12) {
                TrackArtwork(track: tr, cornerRadius: 8, maxPixel: 140)
                  .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                  Text(tr.title).font(Theme.font(15, .medium)).lineLimit(1)
                  Text(statusLabel(st)).font(Theme.font(12.5)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button { downloads.cancel(id) } label: {
                  Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
        .listRowBackground(Theme.canvasRaised)
      }

      if !downloads.failedItems.isEmpty {
        Section {
          ForEach(downloads.failedItems, id: \.track.id) { item in
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 2) {
                Text(item.track.title).font(Theme.font(15, .medium)).lineLimit(1)
                Text("\(item.track.artist) · \(item.reason)")
                  .font(Theme.font(12.5))
                  .foregroundStyle(Theme.danger)
                  .lineLimit(1)
              }
              Spacer()
              Button("Tentar") { downloads.retry(item.track.id) }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
          }
          Button("Tentar todos novamente") { downloads.retryAllFailed() }
        } header: {
          Text("Falhas (\(downloads.failedItems.count))")
        }
        .listRowBackground(Theme.canvasRaised)
      }

      Section {
        LabeledContent("Espaço ocupado", value: store.offlineStorageFormatted)
        LabeledContent("Faixas salvas", value: "\(store.downloadedTracks.count)")
        if !store.downloadedTracks.isEmpty {
          Button {
            if let first = store.downloadedTracks.first {
              AudioPlayer.shared.play(first, in: store.downloadedTracks, context: "Baixadas")
            }
          } label: {
            Label("Tocar todas offline", systemImage: "play.fill")
          }
          Button(role: .destructive) { confirmClear = true } label: {
            Label("Remover todos os downloads", systemImage: "trash")
          }
        }
      } header: {
        Text("Armazenamento no iPhone")
      }
      .listRowBackground(Theme.canvasRaised)

      if !store.downloadedTracks.isEmpty {
        Section("Músicas baixadas") {
          ForEach(store.downloadedTracks) { tr in
            HStack(spacing: 12) {
              TrackRow(track: tr, queue: store.downloadedTracks)
              let sz = store.fileSizeFormatted(for: tr.id)
              if !sz.isEmpty {
                Text(sz)
                  .font(Theme.font(11.5))
                  .foregroundStyle(Theme.tertiary)
                  .monospacedDigit()
              }
            }
            .swipeActions(edge: .trailing) {
              Button(role: .destructive) {
                store.removeDownload(tr.id)
                app.showToast("Download removido")
              } label: { Label("Apagar", systemImage: "trash") }
            }
          }
        }
        .listRowBackground(Theme.canvasRaised)
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(Theme.canvas.ignoresSafeArea())
    .tint(Theme.accent)
    .navigationTitle("Downloads")
    .navigationBarTitleDisplayMode(.large)
    .confirmationDialog("Remover todas as músicas baixadas?", isPresented: $confirmClear, titleVisibility: .visible) {
      Button("Remover tudo", role: .destructive) {
        store.removeAllDownloads()
        Haptics.success()
        app.showToast("Downloads removidos")
      }
      Button("Cancelar", role: .cancel) {}
    }
  }

  private func statusLabel(_ st: DownloadState) -> String {
    switch st {
    case .queued: return "Na fila…"
    case .resolving: return "Localizando áudio…"
    case .downloading(let p): return "Baixando \(Int((p * 100).rounded()))%"
    case .failed(let r): return "Erro: \(r)"
    }
  }
}

// MARK: - Lume Replay · Seu Resumo (ReplayView)

struct ReplayView: View {
  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var app = AppModel.shared

  var body: some View {
    let summary = store.replaySummary
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 24) {
        heroCard(summary)

        if summary.totalPlays == 0 {
          EmptyStateView(
            icon: "sparkles",
            title: "Seu Replay está nascendo",
            message: "Ouça suas músicas favoritas para ver aqui seus cantores mais ouvidos, faixas campeãs e tempo total de música."
          )
        } else {
          HStack(spacing: 12) {
            PrismButton(title: "Tocar meu Replay", systemImage: "play.fill") {
              let tracks = summary.topTracks.map(\.track)
              if let f = tracks.first {
                AudioPlayer.shared.play(f, in: tracks, context: "Lume Replay")
              }
            }
            GlassButton(title: "Salvar playlist", systemImage: "text.badge.plus") {
              let tracks = summary.topTracks.map(\.track)
              store.createPlaylist(name: "Meu Lume Replay", subtitle: "Suas mais ouvidas", sourceBadge: "Replay", tracks: tracks)
              Haptics.success()
              app.showToast("Playlist Replay salva")
            }
          }
          .padding(.horizontal, 20)

          if !summary.topArtists.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
              SectionHeader(title: "Seus artistas #1")
              VStack(spacing: 0) {
                ForEach(Array(summary.topArtists.prefix(5).enumerated()), id: \.offset) { idx, item in
                  Button {
                    app.openArtist(item.name)
                  } label: {
                    HStack(spacing: 12) {
                      Text("#\(idx + 1)")
                        .font(Theme.font(15, .bold))
                        .foregroundStyle(idx < 3 ? Theme.accent : Theme.secondary)
                        .frame(width: 30)
                      ArtistAvatar(name: item.name, size: 42)
                      Text(item.name)
                        .font(Theme.font(16, .medium))
                        .foregroundStyle(Theme.text)
                      Spacer()
                      Text("\(item.count) \(item.count == 1 ? "play" : "plays")")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.secondary)
                        .monospacedDigit()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                  }
                  .buttonStyle(.plain)
                  if idx < min(4, summary.topArtists.count - 1) {
                    Divider().overlay(Theme.hairline).padding(.leading, 56)
                  }
                }
              }
              .glass(22)
              .padding(.horizontal, 20)
            }
          }

          if !summary.topTracks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              SectionHeader(title: "Suas músicas mais ouvidas")
              VStack(spacing: 0) {
                let tracks = summary.topTracks.map(\.track)
                ForEach(Array(summary.topTracks.enumerated()), id: \.element.track.id) { idx, item in
                  HStack(spacing: 6) {
                    TrackRow(track: item.track, rank: idx + 1, queue: tracks)
                    Text("\(item.count)×")
                      .font(Theme.font(12, .semibold))
                      .foregroundStyle(Theme.secondary)
                      .monospacedDigit()
                  }
                }
              }
              .padding(.horizontal, 20)
            }
          }
        }
      }
      .padding(.top, 10)
      .padding(.bottom, 24)
    }
    .background(Theme.canvas.ignoresSafeArea())
    .navigationTitle("Lume Replay")
    .navigationBarTitleDisplayMode(.large)
  }

  private func heroCard(_ s: LibraryStore.ReplaySummary) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Label("RESUMO MUSICAL", systemImage: "sparkles")
          .font(Theme.font(11.5, .bold))
          .tracking(1.1)
        Spacer()
        Text("2026").font(Theme.font(12, .bold))
      }
      .foregroundStyle(Theme.onPrism.opacity(0.85))

      HStack(spacing: 16) {
        statBlock("\(s.totalMinutes)", "minutos ouvindo")
        Divider().frame(height: 36).overlay(Theme.onPrism.opacity(0.25))
        statBlock("\(s.totalPlays)", "reproduções")
        Divider().frame(height: 36).overlay(Theme.onPrism.opacity(0.25))
        statBlock("\(s.uniqueArtists)", "artistas")
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.prismDiagonal))
    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.45), lineWidth: 0.9))
    .lumeShadow(16, y: 10, opacity: 0.45)
    .padding(.horizontal, 20)
  }

  private func statBlock(_ value: String, _ label: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(.system(size: 24, weight: .heavy, design: .rounded))
        .foregroundStyle(Theme.onPrism)
        .monospacedDigit()
      Text(label)
        .font(Theme.font(11.5, .medium))
        .foregroundStyle(Theme.onPrism.opacity(0.75))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Equalizador Real de 5 Bandas (EqualizerView)

struct EqualizerView: View {
  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var player = AudioPlayer.shared

  @State private var gains: [Float] = LibraryStore.shared.effectiveEQGains
  private let labels = ["60 Hz", "230 Hz", "910 Hz", "3,6 kHz", "14 kHz"]

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 24) {
        curveCard
        presetStrip
        slidersCard
        Button {
          Haptics.selection()
          gains = [0, 0, 0, 0, 0]
          player.applySoundProfile(.natural)
        } label: {
          Label("Zerar equalizador", systemImage: "arrow.counterclockwise")
            .font(Theme.font(15, .semibold))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .glassCapsule(interactive: true)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .padding(.horizontal, 20)
      }
      .padding(.top, 10)
      .padding(.bottom, 24)
    }
    .background(Theme.canvas.ignoresSafeArea())
    .navigationTitle("Equalizador")
    .navigationBarTitleDisplayMode(.large)
    .onAppear {
      gains = store.effectiveEQGains
    }
  }

  private var curveCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(store.soundProfile.rawValue)
          .font(Theme.font(16, .bold))
          .foregroundStyle(Theme.text)
        Spacer()
        Text("5 bandas · DSP em tempo real")
          .font(Theme.font(12))
          .foregroundStyle(Theme.secondary)
      }
      Canvas { ctx, size in
        let midY = size.height / 2
        var zero = Path()
        zero.move(to: CGPoint(x: 0, y: midY))
        zero.addLine(to: CGPoint(x: size.width, y: midY))
        ctx.stroke(zero, with: .color(Theme.hairline), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

        let pts: [CGPoint] = gains.enumerated().map { idx, db in
          let x = size.width * (CGFloat(idx) / 4.0)
          let y = midY - CGFloat(db / 12.0) * (size.height * 0.40)
          return CGPoint(x: x, y: y)
        }
        var line = Path()
        for (i, p) in pts.enumerated() {
          if i == 0 {
            line.move(to: p)
          } else {
            let prev = pts[i - 1]
            let cx = (prev.x + p.x) / 2
            line.addCurve(to: p, control1: CGPoint(x: cx, y: prev.y), control2: CGPoint(x: cx, y: p.y))
          }
        }
        ctx.stroke(
          line,
          with: .linearGradient(Gradient(colors: Theme.prismColors), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
          style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
        )
        for p in pts {
          ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.white))
        }
      }
      .frame(height: 120)
    }
    .padding(18)
    .glass(24)
    .padding(.horizontal, 20)
  }

  private var presetStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(SoundProfile.allCases) { p in
          PrismChip(title: p.rawValue, active: store.soundProfile == p) {
            player.applySoundProfile(p)
            gains = store.effectiveEQGains
          }
        }
      }
      .padding(.horizontal, 20)
    }
    .scrollClipDisabled()
  }

  private var slidersCard: some View {
    VStack(spacing: 16) {
      ForEach(0..<5, id: \.self) { idx in
        HStack(spacing: 12) {
          Text(labels[idx])
            .font(Theme.font(13, .semibold))
            .foregroundStyle(Theme.secondary)
            .frame(width: 56, alignment: .leading)
          Slider(
            value: Binding(
              get: { Double(gains[idx]) },
              set: { newVal in
                gains[idx] = Float(newVal)
                player.applyCustomEQ(gains)
              }
            ),
            in: -12...12,
            step: 0.5
          )
          .tint(Theme.accent)
          Text(String(format: "%+.0f dB", gains[idx]))
            .font(Theme.font(12.5, .semibold))
            .foregroundStyle(Theme.text)
            .monospacedDigit()
            .frame(width: 52, alignment: .trailing)
        }
      }
    }
    .padding(18)
    .glass(24)
    .padding(.horizontal, 20)
  }
}
