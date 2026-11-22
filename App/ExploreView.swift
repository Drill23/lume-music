import SwiftUI

/// Novidades — lançamentos, paradas e estilos. Raiz da aba (a barra de navegação fica escondida).
struct ExploreView: View {
  @ObservedObject private var app = AppModel.shared
  @ObservedObject private var player = AudioPlayer.shared

  var body: some View {
    ScrollView(showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 28) {
        header
        if let feed = app.feed {
          content(feed)
            .transition(.opacity)
        } else {
          skeleton
        }
      }
      .padding(.top, 6)
      .animation(.easeInOut(duration: 0.25), value: app.feed == nil)
    }
    .background(backdrop)
    .refreshable {
      await app.loadFeed(force: true)
      await app.refreshArtistReleases()
    }
  }

  private var backdrop: some View {
    ZStack(alignment: .top) {
      Theme.canvas
      LinearGradient(
        colors: [Theme.sky.opacity(0.14), Theme.lavender.opacity(0.06), .clear],
        startPoint: .top, endPoint: .bottom
      )
      .frame(height: 380)
      .blur(radius: 20)
    }
    .ignoresSafeArea()
  }

  // MARK: Header

  private var header: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("Novidades")
        .font(Theme.font(34, .bold))
        .foregroundStyle(Theme.text)
      if let updated = app.feed?.updatedAt {
        Text(updatedText(updated))
          .font(Theme.font(14))
          .foregroundStyle(Theme.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20)
  }

  private func updatedText(_ date: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: "pt_BR")
    f.unitsStyle = .full
    if abs(date.timeIntervalSinceNow) < 60 { return "Atualizado agora" }
    return "Atualizado " + f.localizedString(for: date, relativeTo: Date())
  }

  // MARK: Content

  @ViewBuilder
  private func content(_ feed: DiscoverFeed) -> some View {
    if !app.artistReleases.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Dos seus artistas", subtitle: "Lançamentos de quem você ouve", actionLabel: "Ver tudo") {
          app.push(.releases)
        }
        HRow {
          ForEach(app.artistReleases.prefix(12)) { alb in
            AlbumTile(album: alb, width: 150, showDate: true)
          }
        }
      }
    }

    weekReleases(feed.newReleases.isEmpty ? feed.brazilReleases : feed.newReleases)

    if !feed.brazilReleases.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Novidades do Brasil", actionLabel: "Ver tudo") {
          app.push(.albums("Novidades do Brasil", feed.brazilReleases))
        }
        HRow {
          ForEach(feed.brazilReleases.prefix(16)) { a in
            AlbumTile(album: a, width: 150, showDate: a.releaseDate != nil)
          }
        }
      }
    }

    chart(title: "Top 50 Brasil", subtitle: "As mais tocadas por aqui", tracks: feed.topBrazil, count: 10)
    chart(title: "Top 50 Mundo", subtitle: "As mais tocadas no planeta", tracks: feed.topGlobal, count: 10)
    chart(title: "Em alta", subtitle: "Subindo rápido nas paradas", tracks: feed.trending, count: 8)

    VStack(alignment: .leading, spacing: 14) {
      SectionHeader(title: "Explorar por estilo")
      MoodGrid()
    }
  }

  @ViewBuilder
  private func weekReleases(_ albums: [AlbumShowcase]) -> some View {
    if !albums.isEmpty {
      VStack(alignment: .leading, spacing: 14) {
        SectionHeader(title: "Lançamentos da semana", actionLabel: "Ver tudo") {
          app.push(.albums("Lançamentos da semana", albums))
        }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 20) {
          ForEach(albums.prefix(6)) { a in
            GeometryReader { g in
              AlbumTile(album: a, width: g.size.width, showDate: true)
            }
            .aspectRatio(0.78, contentMode: .fit)
          }
        }
        .padding(.horizontal, 20)
      }
    }
  }

  @ViewBuilder
  private func chart(title: String, subtitle: String?, tracks: [Track], count: Int) -> some View {
    if !tracks.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        SectionHeader(title: title, subtitle: subtitle, actionLabel: "Ver tudo") {
          app.push(.tracks(title, tracks))
        }
        VStack(spacing: 0) {
          ForEach(Array(tracks.prefix(count).enumerated()), id: \.element.id) { idx, tr in
            TrackRow(track: tr, rank: idx + 1, queue: tracks)
          }
        }
        .padding(.horizontal, 20)
      }
    }
  }

  private var skeleton: some View {
    VStack(alignment: .leading, spacing: 20) {
      SkeletonBlock(width: 200, height: 22, radius: 8).padding(.horizontal, 20)
      HStack(spacing: 14) {
        SkeletonBlock(height: 190, radius: 14)
        SkeletonBlock(height: 190, radius: 14)
      }
      .padding(.horizontal, 20)
      SkeletonBlock(width: 160, height: 22, radius: 8).padding(.horizontal, 20)
      ForEach(0..<5, id: \.self) { _ in
        HStack(spacing: 12) {
          SkeletonBlock(width: 50, height: 50, radius: 8)
          VStack(alignment: .leading, spacing: 6) {
            SkeletonBlock(width: 170, height: 14, radius: 6)
            SkeletonBlock(width: 110, height: 12, radius: 6)
          }
        }
        .padding(.horizontal, 20)
      }
    }
  }
}

// MARK: - Cartões de estilo (reutilizados na Busca)

struct MoodGrid: View {
  var body: some View {
    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
      ForEach(MoodCategory.presets) { m in MoodCard(mood: m) }
    }
    .padding(.horizontal, 20)
  }
}

/// Cartão gradiente no estilo "Navegar" do Apple Music: título embaixo à esquerda e ícone girado saindo pelo canto.
struct MoodCard: View {
  let mood: MoodCategory

  var body: some View {
    Button {
      Haptics.light()
      AppModel.shared.push(.mood(mood))
    } label: {
      ZStack(alignment: .bottomLeading) {
        LinearGradient(colors: [Theme.hex(mood.hexA), Theme.hex(mood.hexB)], startPoint: .topLeading, endPoint: .bottomTrailing)
        LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
        Image(systemName: mood.icon)
          .font(.system(size: 64, weight: .bold))
          .foregroundStyle(.white.opacity(0.28))
          .rotationEffect(.degrees(15))
          .offset(x: 20, y: 6)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
          .padding(.top, 8)
          .padding(.trailing, 4)
        Text(mood.title)
          .font(Theme.font(17, .bold))
          .foregroundStyle(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
          .padding(.horizontal, 14)
          .padding(.bottom, 12)
      }
      .frame(height: 100)
      .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 0.8))
      .lumeShadow(10, y: 6, opacity: 0.45)
      .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    .buttonStyle(PressableStyle(scale: 0.97))
    .accessibilityLabel(mood.title)
  }
}
