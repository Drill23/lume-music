import SwiftUI

/// Redesigned Full-Screen Liquid Glass Now Playing (v2.0):
/// - Airy, luxury spacing with zero stacked clutter
/// - Minimal top text switcher: Capa | Vinil | K7 | Ondas | Letra
/// - Tactile Vinyl Turntable & Cassette Deck + Apple Music Animated Artwork + Ares Waves + Karaoke w/ 1-click PT-BR translation
/// - Native edge-swipe right OR swipe-down gesture to dismiss smoothly
struct PlayerSheetView: View {
  @Binding var surfaceTab: PlayerSurfaceTab
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var downloads = DownloadManager.shared
  @Environment(\.dismiss) private var dismiss

  @State private var isScrubbing = false
  @State private var scrubValue: Double = 0
  @State private var showQueueSheet = false
  @State private var showPlaylistPicker = false
  @State private var showMoreSheet = false
  @State private var dragDismissOffset: CGFloat = 0

  var body: some View {
    ZStack {
      // Soft Liquid Glass ambient backdrop extracted from album art
      Theme.bg.ignoresSafeArea()
      RadialGradient(
        colors: [player.accentPrimary.opacity(0.42), player.accentSecondary.opacity(0.14), .clear],
        center: .topLeading,
        startRadius: 12,
        endRadius: 560
      )
      .ignoresSafeArea()
      RadialGradient(
        colors: [player.accentSecondary.opacity(0.28), .clear],
        center: .bottomTrailing,
        startRadius: 10,
        endRadius: 460
      )
      .ignoresSafeArea()

      VStack(spacing: 0) {
        topBar
          .padding(.horizontal, 20)
          .padding(.top, 10)
          .padding(.bottom, 10)

        // Spacious central hero stage
        Group {
          switch surfaceTab {
          case .artwork:
            artworkStage
          case .vinyl:
            vinylStage
          case .cassette:
            cassetteStage
          case .waves:
            wavesStage
          case .lyrics:
            lyricsStage
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)

        // Airy, balanced bottom controls (zero cramped boxes!)
        VStack(spacing: surfaceTab == .lyrics ? 14 : 20) {
          if let track = player.currentTrack {
            trackMetadataRow(track)
          }
          scrubberRow
          transportRow
        }
        .padding(.horizontal, 26)
        .padding(.top, 12)
        .padding(.bottom, 26)
      }
      .offset(y: max(0, dragDismissOffset))
    }
    .animation(.spring(response: 0.36, dampingFraction: 0.86), value: surfaceTab)
    .simultaneousGesture(
      DragGesture(minimumDistance: 24)
        .onChanged { val in
          // Swipe from left edge OR downward pull from top area to go back naturally
          if val.startLocation.x < 42 && val.translation.width > 0 && abs(val.translation.width) > abs(val.translation.height) {
            dragDismissOffset = val.translation.width * 0.45
          } else if val.startLocation.y < 140 && val.translation.height > 0 && abs(val.translation.height) > abs(val.translation.width) {
            dragDismissOffset = val.translation.height * 0.65
          }
        }
        .onEnded { val in
          let edgeBack = val.startLocation.x < 42 && val.translation.width > 78
          let pullDown = val.startLocation.y < 140 && val.translation.height > 90
          if edgeBack || pullDown {
            Haptics.light()
            dismiss()
          } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragDismissOffset = 0 }
          }
        }
    )
    .sheet(isPresented: $showQueueSheet) {
      QueueSheetView()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showPlaylistPicker) {
      if let tr = player.currentTrack {
        AddToPlaylistSheet(track: tr)
          .presentationDetents([.medium, .large])
          .presentationDragIndicator(.visible)
      }
    }
    .sheet(isPresented: $showMoreSheet) {
      PlayerOptionsSheet(onOpenPlaylistPicker: {
        showMoreSheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { showPlaylistPicker = true }
      })
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
  }

  // MARK: - Top Minimal Bar (Inspired by clean Pinterest turntable header)

  private var topBar: some View {
    VStack(spacing: 12) {
      Capsule()
        .fill(Color.white.opacity(0.28))
        .frame(width: 38, height: 4)

      HStack(spacing: 8) {
        Button {
          Haptics.light()
          dismiss()
        } label: {
          Image(systemName: "chevron.down")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.text)
            .frame(width: 36, height: 36)
            .liquidGlassCircle(interactive: true)
        }

        Spacer(minLength: 4)

        // Airy minimal text mode selector (zero chunky box!)
        HStack(spacing: 14) {
          ForEach(PlayerSurfaceTab.allCases) { tab in
            let active = surfaceTab == tab
            Button {
              Haptics.selection()
              surfaceTab = tab
            } label: {
              VStack(spacing: 3) {
                Text(tab.rawValue)
                  .font(Theme.font(active ? 14 : 13, active ? .heavy : .medium))
                  .foregroundStyle(active ? Color.white : Color.white.opacity(0.50))
                Capsule()
                  .fill(active ? Theme.amber : Color.clear)
                  .frame(width: active ? 16 : 4, height: 2.5)
              }
            }
          }
        }

        Spacer(minLength: 4)

        Button {
          Haptics.light()
          showMoreSheet = true
        } label: {
          Image(systemName: "ellipsis")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.text)
            .frame(width: 36, height: 36)
            .liquidGlassCircle(interactive: true)
        }
      }
    }
  }

  // MARK: - Stage 1: Animated Artwork (Liquid Glass)

  private var artworkStage: some View {
    GeometryReader { geo in
      let side = min(geo.size.width - 48, geo.size.height - 44, 344)
      VStack {
        Spacer(minLength: 0)
        if let tr = player.currentTrack {
          ZStack(alignment: .topTrailing) {
            AnimatedArtworkView(
              staticURL: tr.artworkURL,
              animatedURL: player.currentAnimatedArtURL,
              isPlaying: player.isPlaying,
              cornerRadius: 28,
              enableLiveMotion: store.animatedArtEnabled
            )
            .frame(width: side, height: side)
            .scaleEffect(player.isPlaying ? 1.0 : 0.94)
            .shadow(color: player.accentPrimary.opacity(player.isPlaying ? 0.38 : 0.16), radius: player.isPlaying ? 34 : 16, y: 18)
            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: player.isPlaying)

            if player.currentAnimatedArtURL != nil && store.animatedArtEnabled {
              HStack(spacing: 4) {
                Image(systemName: "sparkles").font(.system(size: 9.5, weight: .bold)).foregroundStyle(Theme.amber)
                Text("Animada").font(Theme.font(10, .bold)).foregroundStyle(Color.white)
              }
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .liquidGlassCapsule()
              .padding(14)
            }
          }
        }
        Spacer(minLength: 0)
      }
      .frame(width: geo.size.width, height: geo.size.height)
    }
  }

  // MARK: - Stage 2: Realistic Spinning Vinyl Turntable

  private var vinylStage: some View {
    GeometryReader { geo in
      let side = min(geo.size.width - 40, geo.size.height - 20, 348)
      VStack {
        Spacer(minLength: 0)
        VinylTurntableView(
          artworkURL: player.currentTrack?.artworkURL ?? "",
          isPlaying: player.isPlaying,
          progress: player.duration > 0 ? player.currentTime / player.duration : 0,
          accent: player.accentPrimary
        )
        .frame(width: side, height: side)
        Spacer(minLength: 0)
      }
      .frame(width: geo.size.width, height: geo.size.height)
    }
  }

  // MARK: - Stage 3: Tactile Retro Cassette Deck (K7)

  private var cassetteStage: some View {
    let prog = player.duration > 0 ? player.currentTime / player.duration : 0
    return CassetteDeckView(
      title: player.currentTrack?.title ?? "Lume Tape",
      artist: player.currentTrack?.artist ?? "Lume Music",
      artworkURL: player.currentTrack?.artworkURL ?? "",
      isPlaying: player.isPlaying,
      progress: prog,
      accent: player.accentPrimary
    )
    .padding(.horizontal, 22)
    .padding(.vertical, 12)
  }

  // MARK: - Stage 4: Nostalgic Ares Wave Visualizer (Airy Luminous Borderless Stage)

  private var wavesStage: some View {
    VStack(spacing: 22) {
      Spacer(minLength: 0)
      ZStack {
        // Soft ambient radial bloom behind the Ares waves (zero rigid dark box!)
        RadialGradient(
          colors: [player.accentPrimary.opacity(0.24), player.accentSecondary.opacity(0.10), .clear],
          center: .center,
          startRadius: 10,
          endRadius: 200
        )

        AresVisualizerView(
          style: store.visualizerStyle == .off ? .ares : store.visualizerStyle,
          isPlaying: player.isPlaying,
          accentA: player.accentPrimary,
          accentB: player.accentSecondary,
          compact: false
        )
        .mask(
          LinearGradient(
            stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.06), .init(color: .white, location: 0.94), .init(color: .clear, location: 1)],
            startPoint: .leading, endPoint: .trailing
          )
        )
      }
      .padding(.horizontal, 12)
      .frame(height: 276)

      HStack(spacing: 10) {
        ForEach([VisualizerStyle.ares, .aurora, .orb]) { st in
          let active = (store.visualizerStyle == .off ? .ares : store.visualizerStyle) == st
          Button {
            Haptics.selection()
            store.visualizerStyle = st
          } label: {
            HStack(spacing: 6) {
              Image(systemName: st.icon).font(.system(size: 12, weight: .semibold))
              Text(st.rawValue).font(Theme.font(12, .bold))
            }
            .foregroundStyle(active ? Theme.ink : Theme.text)
            .padding(.horizontal, 15)
            .frame(height: 36)
            .background(active ? AnyShapeStyle(Theme.aurora) : AnyShapeStyle(Color.clear), in: Capsule())
            .modifier(OptionalGlassCapsule(enabled: !active))
          }
        }
      }
      Spacer(minLength: 0)
    }
  }

  // MARK: - Stage 5: Karaoke Synced Lyrics + 1-Click PT-BR Translation

  private var lyricsStage: some View {
    VStack(spacing: 12) {
      HStack {
        Text(player.lyrics?.source ?? "Letra sincronizada")
          .font(Theme.font(12, .semibold))
          .foregroundStyle(Theme.muted)
        Spacer()
        Button {
          player.toggleTranslation()
        } label: {
          HStack(spacing: 6) {
            if player.isTranslatingLyrics {
              ProgressView().tint(Theme.ink).scaleEffect(0.72)
            } else {
              Image(systemName: "translate").font(.system(size: 12, weight: .bold))
            }
            Text(player.showTranslation ? "PT-BR Ativo" : "Traduzir PT-BR")
              .font(Theme.font(12, .bold))
          }
          .foregroundStyle(player.showTranslation ? Theme.ink : Theme.text)
          .padding(.horizontal, 14)
          .frame(height: 34)
          .background(player.showTranslation ? AnyShapeStyle(Theme.aurora) : AnyShapeStyle(Color.clear), in: Capsule())
          .modifier(OptionalGlassCapsule(enabled: !player.showTranslation))
        }
        .disabled(player.lyrics == nil || player.isTranslatingLyrics)
      }
      .padding(.horizontal, 26)

      if player.isLoadingLyrics {
        Spacer()
        ProgressView().tint(Theme.amber)
        Spacer()
      } else if let bundle = player.lyrics, !bundle.lines.isEmpty {
        let activeIdx = activeLyricIndex(in: bundle)
        ScrollViewReader { proxy in
          ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 20) {
              Color.clear.frame(height: 22)
              ForEach(Array(bundle.lines.enumerated()), id: \.element.id) { idx, line in
                let isCurrent = bundle.synced && idx == activeIdx
                let isPast = bundle.synced && idx < activeIdx
                VStack(alignment: .leading, spacing: 5) {
                  Text(line.text)
                    .font(Theme.font(isCurrent ? 26 : 20, isCurrent ? .heavy : .bold))
                    .foregroundStyle(isCurrent ? Color.white : (isPast ? Color.white.opacity(0.32) : Color.white.opacity(0.52)))
                    .shadow(color: isCurrent ? player.accentPrimary.opacity(0.45) : .clear, radius: 12)
                    .fixedSize(horizontal: false, vertical: true)

                  if player.showTranslation, let tr = line.translated, !tr.isEmpty {
                    Text(tr)
                      .font(Theme.font(isCurrent ? 16 : 14, isCurrent ? .semibold : .medium))
                      .foregroundStyle(isCurrent ? Theme.amber : Theme.amber.opacity(isPast ? 0.30 : 0.55))
                      .fixedSize(horizontal: false, vertical: true)
                  }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .id(line.id)
                .onTapGesture {
                  if bundle.synced {
                    Haptics.light()
                    player.seek(to: line.time)
                  }
                }
                .animation(.easeOut(duration: 0.25), value: activeIdx)
              }
              Color.clear.frame(height: 80)
            }
            .padding(.horizontal, 26)
          }
          .mask(
            LinearGradient(
              stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.08), .init(color: .white, location: 0.78), .init(color: .clear, location: 1)],
              startPoint: .top, endPoint: .bottom
            )
          )
          .onChange(of: activeIdx) { _, newIdx in
            guard bundle.synced, newIdx >= 0, newIdx < bundle.lines.count else { return }
            withAnimation(.easeInOut(duration: 0.42)) {
              proxy.scrollTo(bundle.lines[newIdx].id, anchor: .center)
            }
          }
        }
      } else {
        Spacer()
        VStack(spacing: 8) {
          Image(systemName: "quote.bubble").font(.system(size: 30)).foregroundStyle(Theme.muted)
          Text("Letra indisponível para esta faixa").font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
        }
        Spacer()
      }
    }
  }

  private func activeLyricIndex(in bundle: LyricsBundle) -> Int {
    guard bundle.synced else { return -1 }
    let t = player.currentTime + 0.25
    var best = 0
    for (i, line) in bundle.lines.enumerated() {
      if line.time <= t { best = i } else { break }
    }
    return best
  }

  // MARK: - Clean Airy Bottom Controls

  private func trackMetadataRow(_ track: Track) -> some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(track.title)
          .font(Theme.font(21, .heavy))
          .foregroundStyle(Theme.text)
          .lineLimit(1)
        HStack(spacing: 6) {
          Text(track.artist)
            .font(Theme.font(14.5, .medium))
            .foregroundStyle(Theme.text.opacity(0.68))
            .lineLimit(1)
          Text("· \(player.currentBitrateLabel)")
            .font(Theme.font(11, .bold))
            .foregroundStyle(Theme.amber.opacity(0.85))
            .lineLimit(1)
        }
      }

      Spacer(minLength: 4)

      Button {
        store.toggleFavorite(track)
      } label: {
        let fav = store.isFavorite(track.id)
        Image(systemName: fav ? "heart.fill" : "heart")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(fav ? Theme.coral : Theme.text)
          .frame(width: 40, height: 40)
          .liquidGlassCircle(interactive: true)
      }

      Button {
        if store.isDownloaded(track.id) {
          Haptics.selection()
        } else if downloads.isDownloading(track.id) {
          downloads.cancel(track.id)
        } else {
          Haptics.light()
          downloads.download(track)
        }
      } label: {
        ZStack {
          if let p = downloads.progressById[track.id] {
            Circle()
              .trim(from: 0, to: CGFloat(p))
              .stroke(Theme.amber, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
              .rotationEffect(.degrees(-90))
              .frame(width: 20, height: 20)
          } else if store.isDownloaded(track.id) {
            Image(systemName: "arrow.down.circle.fill")
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(Theme.ok)
          } else {
            Image(systemName: "arrow.down.to.line")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(Theme.text)
          }
        }
        .frame(width: 40, height: 40)
        .liquidGlassCircle(interactive: true)
      }
    }
  }

  private var scrubberRow: some View {
    let total = max(1, player.duration)
    let cur = isScrubbing ? scrubValue : player.currentTime
    let frac = min(1.0, max(0.0, cur / total))
    return VStack(spacing: 8) {
      // Custom Apple Music-style slim Liquid Glass interactive scrubber (zero squashed thumb artifact!)
      GeometryReader { geo in
        let w = max(1, geo.size.width)
        let barH: CGFloat = isScrubbing ? 9 : 5.5
        ZStack(alignment: .leading) {
          Capsule()
            .fill(Color.white.opacity(0.18))
            .frame(height: barH)
          Capsule()
            .fill(Color.white.opacity(isScrubbing ? 1.0 : 0.90))
            .frame(width: max(barH, w * frac), height: barH)
            .shadow(color: isScrubbing ? Color.white.opacity(0.45) : .clear, radius: 6)
        }
        .frame(height: 24)
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { v in
              if !isScrubbing { Haptics.light() }
              isScrubbing = true
              let p = min(1.0, max(0.0, v.location.x / w))
              scrubValue = p * total
            }
            .onEnded { v in
              let p = min(1.0, max(0.0, v.location.x / w))
              let target = p * total
              scrubValue = target
              isScrubbing = false
              player.seek(to: target)
            }
        )
        .animation(.spring(response: 0.24, dampingFraction: 0.8), value: isScrubbing)
      }
      .frame(height: 24)

      HStack {
        Text(Theme.formatTime(cur))
          .font(Theme.font(11.5, .semibold))
          .foregroundStyle(Theme.text.opacity(0.62))
          .monospacedDigit()
        Spacer()
        if player.sleepRemainingSeconds > 0 {
          Label(Theme.formatTime(Double(player.sleepRemainingSeconds)), systemImage: "moon.zzz.fill")
            .font(Theme.font(11, .bold))
            .foregroundStyle(Theme.amber)
          Spacer()
        }
        Text("-\(Theme.formatTime(max(0, total - cur)))")
          .font(Theme.font(11.5, .semibold))
          .foregroundStyle(Theme.text.opacity(0.62))
          .monospacedDigit()
      }
    }
  }

  private var transportRow: some View {
    HStack {
      Button {
        Haptics.selection()
        player.shuffleEnabled.toggle()
      } label: {
        Image(systemName: "shuffle")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(player.shuffleEnabled ? Theme.amber : Theme.text.opacity(0.68))
          .frame(width: 44, height: 44)
      }

      Spacer()

      Button { player.previousTrack() } label: {
        Image(systemName: "backward.fill")
          .font(.system(size: 26, weight: .semibold))
          .foregroundStyle(Theme.text)
          .frame(width: 52, height: 52)
      }

      Spacer()

      Button { player.togglePlayPause() } label: {
        ZStack {
          Circle()
            .fill(Color.white)
            .frame(width: 70, height: 70)
            .shadow(color: player.accentPrimary.opacity(0.42), radius: 22, y: 8)
          if player.isLoading {
            ProgressView().tint(Theme.ink)
          } else {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 26, weight: .bold))
              .foregroundStyle(Theme.ink)
              .offset(x: player.isPlaying ? 0 : 2)
          }
        }
      }

      Spacer()

      Button { player.nextTrack() } label: {
        Image(systemName: "forward.fill")
          .font(.system(size: 26, weight: .semibold))
          .foregroundStyle(Theme.text)
          .frame(width: 52, height: 52)
      }

      Spacer()

      Button {
        Haptics.light()
        showQueueSheet = true
      } label: {
        Image(systemName: "list.bullet")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(Theme.text.opacity(0.75))
          .frame(width: 44, height: 44)
      }
    }
  }
}

private struct OptionalGlassCapsule: ViewModifier {
  let enabled: Bool
  func body(content: Content) -> some View {
    if enabled { content.liquidGlassCapsule(interactive: true) } else { content }
  }
}

/// Clean modal sheet for Up Next Queue & Autoplay Radio.
struct QueueSheetView: View {
  @ObservedObject private var player = AudioPlayer.shared
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        Theme.bg.ignoresSafeArea()
        ScrollView(showsIndicators: false) {
          VStack(spacing: 14) {
            HStack {
              Text("\(player.queue.count) faixas na fila")
                .font(Theme.font(13, .semibold)).foregroundStyle(Theme.muted)
              Spacer()
              Button {
                Haptics.selection()
                player.autoplayRadio.toggle()
              } label: {
                Label("Rádio Auto", systemImage: "infinity")
                  .font(Theme.font(12, .bold))
                  .foregroundStyle(player.autoplayRadio ? Theme.ink : Theme.text)
                  .padding(.horizontal, 12).frame(height: 32)
                  .background(player.autoplayRadio ? AnyShapeStyle(Theme.aurora) : AnyShapeStyle(Color.white.opacity(0.1)), in: Capsule())
              }
              Button {
                Haptics.selection()
                player.repeatMode = player.repeatMode.next
              } label: {
                Image(systemName: player.repeatMode.icon)
                  .font(.system(size: 14, weight: .bold))
                  .foregroundStyle(player.repeatMode == .off ? Theme.muted : Theme.amber)
                  .frame(width: 34, height: 32)
                  .liquidGlassCapsule()
              }
            }

            LazyVStack(spacing: 8) {
              ForEach(Array(player.queue.enumerated()), id: \.offset) { idx, item in
                let cur = idx == player.currentIndex
                Button {
                  player.jumpToQueueIndex(idx)
                } label: {
                  HStack(spacing: 12) {
                    RemoteArtwork(url: item.artworkURL, cornerRadius: 10).frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 2) {
                      Text(item.title).font(Theme.font(14, cur ? .bold : .semibold)).foregroundStyle(cur ? Theme.amber : Theme.text).lineLimit(1)
                      Text(item.artist).font(Theme.font(12, .medium)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Spacer()
                    if cur {
                      Image(systemName: player.isPlaying ? "waveform" : "pause.fill").foregroundStyle(Theme.amber)
                    } else {
                      Text(item.formattedDuration).font(Theme.font(11.5, .medium)).foregroundStyle(Theme.muted)
                    }
                  }
                  .padding(10)
                  .liquidGlass(radius: 14, tint: cur ? Theme.amber : .clear)
                }
              }
            }
          }
          .padding(20)
        }
      }
      .navigationTitle("Fila de Reprodução")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { Button("OK") { dismiss() }.foregroundStyle(Theme.amber) }
      }
    }
  }
}

/// Add track to an existing or new playlist.
struct AddToPlaylistSheet: View {
  let track: Track
  @ObservedObject private var store = LibraryStore.shared
  @Environment(\.dismiss) private var dismiss
  @State private var newName = ""

  var body: some View {
    NavigationStack {
      ZStack {
        Theme.bg.ignoresSafeArea()
        ScrollView {
          VStack(spacing: 16) {
            HStack(spacing: 10) {
              TextField("Nome da nova playlist…", text: $newName)
                .font(Theme.font(14.5, .medium))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .liquidGlass(radius: 14)
              Button {
                let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { return }
                store.createPlaylist(name: clean, tracks: [track])
                Haptics.success()
                dismiss()
              } label: {
                Text("Criar")
                  .font(Theme.font(14, .bold))
                  .foregroundStyle(Theme.ink)
                  .padding(.horizontal, 18)
                  .frame(height: 44)
                  .background(Theme.aurora, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
              }
            }

            if store.playlists.isEmpty {
              Text("Crie sua primeira playlist acima para guardar \(track.title).")
                .font(Theme.font(13, .medium))
                .foregroundStyle(Theme.muted)
                .padding(.top, 14)
            } else {
              VStack(spacing: 8) {
                ForEach(store.playlists) { pl in
                  let already = pl.trackIds.contains(track.id)
                  Button {
                    store.addTrack(track, toPlaylist: pl.id)
                    Haptics.success()
                    dismiss()
                  } label: {
                    HStack(spacing: 12) {
                      RemoteArtwork(url: pl.artworkURL, cornerRadius: 10, placeholderIcon: "music.note.list")
                        .frame(width: 46, height: 46)
                      VStack(alignment: .leading, spacing: 2) {
                        Text(pl.name).font(Theme.font(14.5, .bold)).foregroundStyle(Theme.text).lineLimit(1)
                        Text("\(pl.trackIds.count) faixas").font(Theme.font(12, .medium)).foregroundStyle(Theme.muted)
                      }
                      Spacer()
                      Image(systemName: already ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(already ? Theme.ok : Theme.amber)
                    }
                    .padding(10)
                    .liquidGlass(radius: 14)
                  }
                }
              }
            }
          }
          .padding(20)
        }
      }
      .navigationTitle("Adicionar à Playlist")
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}

/// Player options sheet: Add to Playlist, Sound Profile, Sleep Timer, Playback Speed, Animated Covers & Auto-Translate.
struct PlayerOptionsSheet: View {
  var onOpenPlaylistPicker: (() -> Void)? = nil
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var store = LibraryStore.shared
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        Theme.bg.ignoresSafeArea()
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            if let openPl = onOpenPlaylistPicker {
              Button {
                Haptics.light()
                openPl()
              } label: {
                HStack(spacing: 12) {
                  Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.amber)
                  Text("Adicionar esta música a uma Playlist").font(Theme.font(14.5, .bold)).foregroundStyle(Theme.text)
                  Spacer()
                  Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                }
                .padding(14)
                .liquidGlass(radius: 16, tint: Theme.amber)
              }
            }

            VStack(alignment: .leading, spacing: 10) {
              Text("PERFIL DE SOM").font(Theme.font(11, .bold)).tracking(1.6).foregroundStyle(Theme.amber)
              ForEach(SoundProfile.allCases) { prof in
                let active = store.soundProfile == prof
                Button { player.applySoundProfile(prof) } label: {
                  HStack {
                    VStack(alignment: .leading, spacing: 2) {
                      Text(prof.rawValue).font(Theme.font(14.5, .bold)).foregroundStyle(Theme.text)
                      Text(prof.subtitle).font(Theme.font(12, .medium)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    if active { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.amber) }
                  }
                  .padding(12)
                  .liquidGlass(radius: 14, tint: active ? Theme.amber : .clear)
                }
              }
            }

            VStack(alignment: .leading, spacing: 10) {
              Text("TEMPORIZADOR PARA DORMIR").font(Theme.font(11, .bold)).tracking(1.6).foregroundStyle(Theme.amber)
              LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(SleepTimerOption.allCases) { opt in
                  let active = player.sleepTimerOption == opt
                  Button { player.setSleepTimer(opt) } label: {
                    Text(opt.label)
                      .font(Theme.font(13, .bold))
                      .foregroundStyle(active ? Theme.ink : Theme.text)
                      .frame(maxWidth: .infinity).frame(height: 40)
                      .background(active ? AnyShapeStyle(Theme.aurora) : AnyShapeStyle(Color.white.opacity(0.08)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                  }
                }
              }
            }

            VStack(alignment: .leading, spacing: 10) {
              Text("VELOCIDADE").font(Theme.font(11, .bold)).tracking(1.6).foregroundStyle(Theme.amber)
              HStack(spacing: 8) {
                ForEach([Float(0.75), 1.0, 1.25, 1.5], id: \.self) { r in
                  let active = abs(player.playbackRate - r) < 0.01
                  Button { player.setRate(r) } label: {
                    Text(r == 1.0 ? "1×" : String(format: "%.2g×", r))
                      .font(Theme.font(13, .bold))
                      .foregroundStyle(active ? Theme.ink : Theme.text)
                      .frame(maxWidth: .infinity).frame(height: 38)
                      .background(active ? AnyShapeStyle(Theme.aurora) : AnyShapeStyle(Color.white.opacity(0.08)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                  }
                }
              }
            }

            VStack(spacing: 12) {
              Toggle(isOn: $store.animatedArtEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                  Text("Capas Animadas").font(Theme.font(14.5, .bold)).foregroundStyle(Theme.text)
                  Text("Reproduz arte animada estilo Apple Music").font(Theme.font(12, .medium)).foregroundStyle(Theme.muted)
                }
              }
              .tint(Theme.amber)

              Toggle(isOn: $store.autoTranslateLyrics) {
                VStack(alignment: .leading, spacing: 2) {
                  Text("Traduzir letras automaticamente").font(Theme.font(14.5, .bold)).foregroundStyle(Theme.text)
                  Text("Exibe tradução PT-BR sincronizada no Karaokê").font(Theme.font(12, .medium)).foregroundStyle(Theme.muted)
                }
              }
              .tint(Theme.amber)
            }
            .padding(14)
            .liquidGlass(radius: 16)
          }
          .padding(20)
        }
      }
      .navigationTitle("Opções do Player")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { Button("OK") { dismiss() }.foregroundStyle(Theme.amber) }
      }
    }
  }
}
