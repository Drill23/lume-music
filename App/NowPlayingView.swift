import AVKit
import MediaPlayer
import SwiftUI

/// Full-screen Now Playing — ambient mesh from the artwork, Liquid Glass controls,
/// and five stages: Capa, Vinil, K7, Ondas 3D and Letra.
struct NowPlayingView: View {
  @ObservedObject private var app = AppModel.shared
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var downloads = DownloadManager.shared
  @Environment(\.dismiss) private var dismiss

  @State private var showQueue = false
  @State private var showOptions = false
  @State private var dragY: CGFloat = 0

  private var mode: PlayerSurfaceTab { app.playerTab }

  var body: some View {
    ZStack {
      AmbientMeshBackground(palette: player.palette, artworkURL: player.currentArtwork, animate: player.isPlaying)

      VStack(spacing: 0) {
        topBar
          .padding(.horizontal, 20)
          .padding(.top, 6)
          .contentShape(Rectangle())
          .gesture(dismissDrag)

        stageSwitcher
          .padding(.top, 6)
          .padding(.bottom, 4)
          .zIndex(10)

        stage
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        controls
          .padding(.horizontal, 24)
          .padding(.bottom, 8)
          .zIndex(10)
      }
      .offset(y: dragY)
      .scaleEffect(1 - min(dragY, 300) / 3000, anchor: .top)
      .clipShape(RoundedRectangle(cornerRadius: dragY > 2 ? 38 : 0, style: .continuous))
    }
    .background(Color.black.opacity(dragY > 0 ? max(0.0, 0.55 - Double(dragY) / 500.0) : 0).ignoresSafeArea())
    .animation(.spring(response: 0.36, dampingFraction: 0.88), value: mode)
    .sheet(isPresented: $showQueue) {
      QueueSheet()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }
    .sheet(isPresented: $showOptions) {
      PlayerOptionsSheet()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }
    .statusBarHidden(false)
  }

  private var dismissDrag: some Gesture {
    DragGesture(minimumDistance: 12)
      .onChanged { v in if v.translation.height > 0 { dragY = v.translation.height } }
      .onEnded { v in
        if v.translation.height > 120 || v.predictedEndTranslation.height > 320 {
          Haptics.light()
          dismiss()
        } else {
          withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { dragY = 0 }
        }
      }
  }

  // MARK: Top bar

  private var topBar: some View {
    VStack(spacing: 12) {
      Capsule().fill(Theme.text.opacity(0.28)).frame(width: 40, height: 5)
      HStack {
        GlassIconButton(systemName: "chevron.down", size: 40) { dismiss() }
        Spacer()
        VStack(spacing: 1) {
          Text("TOCANDO AGORA")
            .font(Theme.font(10.5, .semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.secondary)
          Text(player.contextTitle.isEmpty ? "Lume Music" : player.contextTitle)
            .font(Theme.font(13, .semibold))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
        }
        Spacer()
        GlassIconButton(systemName: "ellipsis", size: 40) { showOptions = true }
      }
    }
  }

  // MARK: Stage

  private var stageSwitcher: some View {
    StageSwitcher(selection: mode) { t in
      withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
        if t != .lyrics { app.playerStyle = t }
        app.playerTab = t
      }
    }
  }

  @ViewBuilder
  private var stage: some View {
    ZStack {
      if let track = player.currentTrack {
        switch mode {
        case .artwork: ArtworkStage(track: track).transition(StageTransition())
        case .vinyl: TurntableStage(track: track).transition(StageTransition())
        case .cassette: CassetteStage(track: track).transition(StageTransition())
        case .waves: WavesStage(track: track).transition(StageTransition())
        case .lyrics: LyricsStage().transition(StageTransition())
        }
      } else {
        EmptyStateView(icon: "music.note", title: "Nada tocando", message: "Escolha uma música para começar.")
      }
    }
  }

  // MARK: Controls

  private var controls: some View {
    VStack(spacing: mode == .lyrics ? 14 : 20) {
      if let track = player.currentTrack { metadata(track) }
      ProgressScrubber()
      transport
      if mode != .lyrics {
        VolumeRow()
      }
      bottomRow
    }
  }

  private func metadata(_ track: Track) -> some View {
    HStack(alignment: .center, spacing: 12) {
      if mode == .lyrics {
        TrackArtwork(track: track, cornerRadius: 8, maxPixel: 160)
          .frame(width: 48, height: 48)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(track.title)
          .font(Theme.font(mode == .lyrics ? 17 : 22, .bold))
          .foregroundStyle(Theme.text)
          .lineLimit(1)
        Button {
          app.navigateFromPlayer(.artist(LibraryStore.mainArtist(track.artist), nil))
        } label: {
          Text(track.artist)
            .font(Theme.font(mode == .lyrics ? 14 : 17))
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
        }
        .buttonStyle(.plain)
      }
      Spacer(minLength: 8)
      downloadButton(track)
      let fav = store.isFavorite(track.id)
      Button {
        store.toggleFavorite(track)
      } label: {
        Image(systemName: fav ? "heart.fill" : "heart")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(fav ? Theme.rose : Theme.text)
          .symbolEffect(.bounce, value: fav)
          .frame(width: 40, height: 40)
          .glassCircle(interactive: true)
      }
      .buttonStyle(PressableStyle(scale: 0.88))
    }
  }

  private func downloadButton(_ track: Track) -> some View {
    Button {
      if store.isDownloaded(track.id) {
        Haptics.selection()
        app.showToast("Esta música já está salva no iPhone")
      } else if downloads.isDownloading(track.id) {
        downloads.cancel(track.id)
      } else {
        Haptics.light()
        downloads.download(track)
      }
    } label: {
      ZStack {
        if let p = downloads.progressById[track.id] {
          Circle().stroke(Theme.text.opacity(0.15), lineWidth: 2.4).frame(width: 20, height: 20)
          Circle().trim(from: 0, to: CGFloat(p))
            .stroke(Theme.text, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: 20, height: 20)
        } else {
          Image(systemName: store.isDownloaded(track.id) ? "arrow.down.circle.fill" : "arrow.down")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.text)
        }
      }
      .frame(width: 40, height: 40)
      .glassCircle(interactive: true)
    }
    .buttonStyle(PressableStyle(scale: 0.88))
  }

  private var transport: some View {
    HStack {
      Button { player.shuffleEnabled.toggle(); Haptics.selection() } label: {
        Image(systemName: "shuffle")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(player.shuffleEnabled ? Theme.accent : Theme.secondary)
          .frame(width: 44, height: 44)
      }
      Spacer()
      Button { player.previousTrack() } label: {
        Image(systemName: "backward.fill")
          .font(.system(size: 30, weight: .semibold))
          .foregroundStyle(Theme.text)
          .frame(width: 60, height: 60)
      }
      .buttonStyle(PressableStyle(scale: 0.82))
      Spacer()
      Button { player.togglePlayPause() } label: {
        ZStack {
          if player.isLoading {
            ProgressView().controlSize(.large).tint(Theme.text)
          } else {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 34, weight: .bold))
              .foregroundStyle(Theme.text)
              .contentTransition(.symbolEffect(.replace.downUp))
              .offset(x: player.isPlaying ? 0 : 2)
          }
        }
        .frame(width: mode == .lyrics ? 70 : 84, height: mode == .lyrics ? 70 : 84)
        .glassCircle(interactive: true)
      }
      .buttonStyle(PressableStyle(scale: 0.9))
      Spacer()
      Button { player.nextTrack() } label: {
        Image(systemName: "forward.fill")
          .font(.system(size: 30, weight: .semibold))
          .foregroundStyle(Theme.text)
          .frame(width: 60, height: 60)
      }
      .buttonStyle(PressableStyle(scale: 0.82))
      Spacer()
      Button { player.repeatMode = player.repeatMode.next; Haptics.selection() } label: {
        Image(systemName: player.repeatMode.icon)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(player.repeatMode == .off ? Theme.secondary : Theme.accent)
          .frame(width: 44, height: 44)
      }
    }
  }

  private var bottomRow: some View {
    HStack {
      Button {
        Haptics.selection()
        app.playerTab = mode == .lyrics ? app.playerStyle : .lyrics
      } label: {
        Image(systemName: mode == .lyrics ? "quote.bubble.fill" : "quote.bubble")
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(mode == .lyrics ? Theme.accent : Theme.secondary)
          .frame(width: 48, height: 40)
      }
      Spacer()
      if player.sleepRemainingSeconds > 0 {
        Label(Theme.formatTime(Double(player.sleepRemainingSeconds)), systemImage: "moon.zzz.fill")
          .font(Theme.font(12.5, .semibold))
          .foregroundStyle(Theme.secondary)
          .monospacedDigit()
        Spacer()
      }
      AirPlayButton()
        .frame(width: 48, height: 40)
      Spacer()
      Button { showQueue = true; Haptics.light() } label: {
        Image(systemName: "list.bullet")
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(Theme.secondary)
          .frame(width: 48, height: 40)
      }
    }
  }
}

// MARK: - Progress scrubber (Apple Music style)

struct ProgressScrubber: View {
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var clock = PlaybackClock.shared
  @State private var scrubbing = false
  @State private var value: Double = 0

  var body: some View {
    let total = max(1, clock.duration)
    let cur = scrubbing ? value : clock.currentTime
    let frac = min(1, max(0, cur / total))
    VStack(spacing: 6) {
      GeometryReader { g in
        let h: CGFloat = scrubbing ? 12 : 6
        ZStack(alignment: .leading) {
          Capsule().fill(Theme.text.opacity(0.18))
          Capsule().fill(Theme.text.opacity(scrubbing ? 1 : 0.82))
            .frame(width: max(h, g.size.width * frac))
        }
        .frame(height: h)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { v in
              if !scrubbing { Haptics.soft(); scrubbing = true }
              value = min(1, max(0, v.location.x / max(1, g.size.width))) * total
            }
            .onEnded { v in
              let target = min(1, max(0, v.location.x / max(1, g.size.width))) * total
              player.seek(to: target)
              value = target
              scrubbing = false
            }
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: scrubbing)
      }
      .frame(height: 22)

      HStack {
        Text(Theme.formatTime(cur)).monospacedDigit()
        Spacer()
        Text(player.currentBitrateLabel)
          .font(Theme.font(10.5, .bold))
          .padding(.horizontal, 7)
          .padding(.vertical, 2)
          .overlay(Capsule().stroke(Theme.secondary.opacity(0.6), lineWidth: 0.8))
        Spacer()
        Text("-" + Theme.formatTime(max(0, total - cur))).monospacedDigit()
      }
      .font(Theme.font(12, .medium))
      .foregroundStyle(Theme.secondary)
    }
  }
}

// MARK: - System volume

struct VolumeRow: View {
  @StateObject private var volume = SystemVolume()

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "speaker.fill").font(.system(size: 12, weight: .semibold))
      GeometryReader { g in
        ZStack(alignment: .leading) {
          Capsule().fill(Theme.text.opacity(0.18))
          Capsule().fill(Theme.text.opacity(0.75)).frame(width: max(6, g.size.width * CGFloat(volume.level)))
        }
        .frame(height: 6)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { v in volume.set(Float(min(1, max(0, v.location.x / max(1, g.size.width))))) }
        )
      }
      .frame(height: 22)
      Image(systemName: "speaker.wave.3.fill").font(.system(size: 12, weight: .semibold))
    }
    .foregroundStyle(Theme.secondary)
    .background(VolumeViewHost(volume: volume).frame(width: 1, height: 1).opacity(0.01))
  }
}

@MainActor
final class SystemVolume: ObservableObject {
  @Published var level: Float = AVAudioSession.sharedInstance().outputVolume
  weak var slider: UISlider?
  private var obs: NSKeyValueObservation?

  init() {
    obs = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] s, _ in
      let v = s.outputVolume
      Task { @MainActor in self?.level = v }
    }
  }

  func set(_ v: Float) {
    level = v
    slider?.setValue(v, animated: false)
    slider?.sendActions(for: .valueChanged)
  }
}

private struct VolumeViewHost: UIViewRepresentable {
  let volume: SystemVolume
  func makeUIView(context: Context) -> MPVolumeView {
    let v = MPVolumeView(frame: .zero)
    v.showsVolumeSlider = true
    DispatchQueue.main.async {
      volume.slider = v.subviews.compactMap { $0 as? UISlider }.first
    }
    return v
  }
  func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

struct AirPlayButton: UIViewRepresentable {
  func makeUIView(context: Context) -> AVRoutePickerView {
    let v = AVRoutePickerView()
    v.prioritizesVideoDevices = false
    v.tintColor = UIColor.label.withAlphaComponent(0.62)
    v.activeTintColor = UIColor(Theme.accent)
    return v
  }
  func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - Stage: Artwork

struct ArtworkStage: View {
  let track: Track
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var store = LibraryStore.shared
  @State private var swipe: CGFloat = 0

  var body: some View {
    GeometryReader { g in
      let side = min(g.size.width - 48, g.size.height - 24, 390)
      AnimatedArtworkView(
        staticURL: player.currentArtwork,
        animatedURL: player.currentAnimatedArtURL,
        isPlaying: player.isPlaying,
        cornerRadius: 16,
        enableLiveMotion: store.animatedArtEnabled
      )
      .frame(width: side, height: side)
      .scaleEffect(player.isPlaying ? 1 : 0.84)
      .shadow(color: .black.opacity(player.isPlaying ? 0.38 : 0.22), radius: player.isPlaying ? 30 : 16, y: player.isPlaying ? 20 : 10)
      .offset(x: swipe)
      .rotation3DEffect(.degrees(Double(swipe) / 12), axis: (0, 1, 0), perspective: 0.6)
      .animation(.spring(response: 0.5, dampingFraction: 0.72), value: player.isPlaying)
      .position(x: g.size.width / 2, y: g.size.height / 2)
      .gesture(
        DragGesture(minimumDistance: 20)
          .onChanged { v in if abs(v.translation.width) > abs(v.translation.height) { swipe = v.translation.width * 0.6 } }
          .onEnded { v in
            if v.translation.width < -80 { player.nextTrack() } else if v.translation.width > 80 { player.previousTrack() }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) { swipe = 0 }
          }
      )
      .onTapGesture(count: 2) { store.toggleFavorite(track) }
    }
  }
}

// MARK: - Queue sheet

struct QueueSheet: View {
  @ObservedObject private var player = AudioPlayer.shared
  @State private var tab: QueueTab = .upNext

  enum QueueTab: String, CaseIterable, Identifiable {
    case upNext = "Fila"
    case history = "Histórico"
    var id: String { rawValue }
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          Picker("Modo", selection: $tab) {
            ForEach(QueueTab.allCases) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }

        if tab == .upNext {
          Section {
            HStack(spacing: 10) {
              QueueToggle(title: "Aleatório", icon: "shuffle", on: player.shuffleEnabled) { player.shuffleEnabled.toggle() }
              QueueToggle(title: "Repetir", icon: player.repeatMode.icon, on: player.repeatMode != .off) { player.repeatMode = player.repeatMode.next }
              QueueToggle(title: "Rádio", icon: "infinity", on: player.autoplayRadio) { player.autoplayRadio.toggle() }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
          }
          if let cur = player.currentTrack {
            Section("Tocando agora") {
              QueueRow(track: cur, current: true)
            }
          }
          Section {
            ForEach(upNextIndices, id: \.self) { idx in
              QueueRow(track: player.queue[idx], current: false)
                .contentShape(Rectangle())
                .onTapGesture { player.jumpToQueueIndex(idx) }
            }
            .onMove { from, to in
              let base = player.currentIndex + 1
              player.moveQueue(from: IndexSet(from.map { $0 + base }), to: to + base)
            }
            .onDelete { offsets in
              let base = player.currentIndex + 1
              player.removeFromQueue(at: IndexSet(offsets.map { $0 + base }))
            }
          } header: {
            HStack {
              Text("A seguir")
              Spacer()
              if player.autoplayRadio { Text("rádio automática ligada").textCase(nil) }
            }
          }
        } else {
          if player.sessionHistory.isEmpty {
            Section {
              Text("Nenhuma música tocada ainda nesta sessão.")
                .font(Theme.font(14))
                .foregroundStyle(Theme.secondary)
            }
          } else {
            Section("Tocadas nesta sessão") {
              ForEach(player.sessionHistory) { tr in
                QueueRow(track: tr, current: tr.id == player.currentTrack?.id)
                  .contentShape(Rectangle())
                  .onTapGesture { player.play(tr, in: player.sessionHistory) }
              }
            }
          }
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .environment(\.editMode, .constant(tab == .upNext ? .active : .inactive))
      .navigationTitle(tab.rawValue)
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  private var upNextIndices: [Int] {
    let start = player.currentIndex + 1
    guard start < player.queue.count else { return [] }
    return Array(start..<player.queue.count)
  }
}

private struct QueueToggle: View {
  let title: String
  let icon: String
  let on: Bool
  let action: () -> Void
  var body: some View {
    Button {
      Haptics.selection()
      action()
    } label: {
      VStack(spacing: 4) {
        Image(systemName: icon).font(.system(size: 16, weight: .semibold))
        Text(title).font(Theme.font(12, .semibold))
      }
      .foregroundStyle(on ? Theme.onPrism : Theme.text)
      .frame(maxWidth: .infinity)
      .frame(height: 54)
      .background {
        if on { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.prismDiagonal) }
      }
      .modifier(QueueGlass(enabled: !on))
    }
    .buttonStyle(.plain)
  }
}

private struct QueueGlass: ViewModifier {
  let enabled: Bool
  func body(content: Content) -> some View {
    if enabled { content.glass(16, interactive: true) } else { content }
  }
}

private struct QueueRow: View {
  let track: Track
  let current: Bool
  @ObservedObject private var player = AudioPlayer.shared
  var body: some View {
    HStack(spacing: 12) {
      TrackArtwork(track: track, cornerRadius: 6, maxPixel: 140)
        .frame(width: 44, height: 44)
      VStack(alignment: .leading, spacing: 1) {
        Text(track.title).font(Theme.font(15, current ? .semibold : .regular)).lineLimit(1)
        Text(track.artist).font(Theme.font(13)).foregroundStyle(Theme.secondary).lineLimit(1)
      }
      Spacer()
      if current {
        Image(systemName: "waveform")
          .foregroundStyle(Theme.accent)
          .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
      } else if !track.formattedDuration.isEmpty {
        Text(track.formattedDuration).font(Theme.font(12.5)).foregroundStyle(Theme.secondary).monospacedDigit()
      }
    }
    .listRowBackground(Color.white.opacity(0.06))
  }
}

// MARK: - Player options

struct PlayerOptionsSheet: View {
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var app = AppModel.shared
  @Environment(\.dismiss) private var dismiss
  @State private var showShareCard = false

  var body: some View {
    NavigationStack {
      List {
        if let tr = player.currentTrack {
          Section {
            HStack(spacing: 12) {
              TrackArtwork(track: tr, cornerRadius: 8, maxPixel: 160).frame(width: 52, height: 52)
              VStack(alignment: .leading, spacing: 2) {
                Text(tr.title).font(Theme.font(16, .semibold)).lineLimit(1)
                Text(tr.artist).font(Theme.font(14)).foregroundStyle(Theme.secondary).lineLimit(1)
              }
            }
            Button { dismiss(); app.playlistPickerTrack = tr } label: { Label("Adicionar a uma playlist", systemImage: "text.badge.plus") }
            Button { dismiss(); app.navigateFromPlayer(.artist(LibraryStore.mainArtist(tr.artist), nil)) } label: { Label("Ver artista", systemImage: "music.mic") }
            Button { player.startRadio(from: tr); dismiss() } label: { Label("Iniciar rádio desta música", systemImage: "dot.radiowaves.left.and.right") }
            Button { showShareCard = true } label: {
              Label("Compartilhar cartão da música", systemImage: "photo.on.rectangle.angled")
            }
            ShareLink(item: "Ouvindo \(tr.title) — \(tr.artist) no Lume Music 🎧") {
              Label("Compartilhar link", systemImage: "square.and.arrow.up")
            }
          }
        }

        Section("Estilo do Tocando agora") {
          HStack(spacing: 8) {
            ForEach(PlayerStyleOption.all) { o in
              let active = app.playerStyle == o.style
              Button {
                Haptics.selection()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { app.playerStyle = o.style }
              } label: {
                VStack(spacing: 6) {
                  Image(systemName: o.icon).font(.system(size: 19, weight: .semibold))
                  Text(o.title.replacingOccurrences(of: " clássica", with: ""))
                    .font(Theme.font(11.5, .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
                .foregroundStyle(active ? Theme.onPrism : Theme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(
                  RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(active ? AnyShapeStyle(Theme.prismDiagonal) : AnyShapeStyle(Theme.fill))
                )
              }
              .buttonStyle(.plain)
            }
          }
          .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        }

        Section("Temporizador") {
          Picker(selection: Binding(get: { player.sleepTimerOption }, set: { player.setSleepTimer($0) })) {
            ForEach(SleepTimerOption.allCases) { Text($0.label).tag($0) }
          } label: {
            Label("Parar de tocar", systemImage: "moon.zzz")
          }
        }

        Section("Velocidade") {
          Picker("Velocidade", selection: Binding(get: { player.playbackRate }, set: { player.setRate($0) })) {
            Text("0,75×").tag(Float(0.75))
            Text("0,85×").tag(Float(0.85))
            Text("1×").tag(Float(1.0))
            Text("1,15×").tag(Float(1.15))
            Text("1,25×").tag(Float(1.25))
            Text("1,5×").tag(Float(1.5))
          }
          .pickerStyle(.segmented)
        }

        Section("Som & Equalizador") {
          Picker(selection: Binding(get: { store.soundProfile }, set: { player.applySoundProfile($0) })) {
            ForEach(SoundProfile.allCases) { p in
              Text(p.rawValue).tag(p)
            }
          } label: {
            Label("Perfil de som", systemImage: "slider.vertical.3")
          }
          Button {
            dismiss()
            app.navigateFromPlayer(.equalizer)
          } label: {
            Label("Abrir Equalizador (5 bandas)", systemImage: "dial.medium")
          }
          Picker(selection: $store.crossfadeSeconds) {
            Text("Desligado").tag(0.0)
            Text("3 segundos").tag(3.0)
            Text("6 segundos").tag(6.0)
            Text("9 segundos").tag(9.0)
          } label: {
            Label("Crossfade", systemImage: "waveform.path")
          }
        }

        Section("Visual") {
          Toggle(isOn: $store.animatedArtEnabled) { Label("Capas animadas", systemImage: "sparkles.tv") }
          Toggle(isOn: $store.autoTranslateLyrics) { Label("Traduzir letras automaticamente", systemImage: "translate") }
          Picker(selection: $store.visualizerStyle) {
            ForEach(VisualizerStyle.activeStyles) { Text($0.title).tag($0) }
          } label: {
            Label("Estilo das ondas", systemImage: "waveform")
          }
        }
      }
      .scrollContentBackground(.hidden)
      .tint(Theme.accent)
      .navigationTitle("Opções")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
      }
      .sheet(isPresented: $showShareCard) {
        if let tr = player.currentTrack {
          TrackShareCardSheet(track: tr, artworkURL: player.currentArtwork, palette: player.palette)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
      }
    }
  }
}

private struct TrackShareCardSheet: View {
  let track: Track
  let artworkURL: String
  let palette: ArtworkPalette
  @Environment(\.dismiss) private var dismiss
  @State private var rendered: UIImage?

  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        cardView
          .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        if let rendered {
          ShareLink(item: Image(uiImage: rendered), preview: SharePreview("\(track.title) — \(track.artist)", image: Image(uiImage: rendered))) {
            Label("Compartilhar imagem", systemImage: "square.and.arrow.up")
              .font(Theme.font(16, .bold))
              .foregroundStyle(Theme.onPrism)
              .frame(maxWidth: .infinity)
              .frame(height: 50)
              .background(Capsule().fill(Theme.prismDiagonal))
          }
          .padding(.horizontal, 24)
        }
      }
      .padding()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Theme.canvas.ignoresSafeArea())
      .navigationTitle("Cartão da música")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
      .task {
        let renderer = ImageRenderer(content: cardView.padding(16))
        renderer.scale = 3.0
        rendered = renderer.uiImage
      }
    }
  }

  private var cardView: some View {
    VStack(spacing: 16) {
      ArtworkImage(url: artworkURL, cornerRadius: 16, maxPixel: 600)
        .frame(width: 210, height: 210)
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
      VStack(spacing: 4) {
        Text(track.title)
          .font(.system(size: 20, weight: .bold))
          .foregroundStyle(.white)
          .multilineTextAlignment(.center)
          .lineLimit(2)
        Text(track.artist)
          .font(Theme.font(14.5, .medium))
          .foregroundStyle(.white.opacity(0.82))
          .lineLimit(1)
      }
      HStack {
        Text("Ouvindo no Lume Music")
          .font(Theme.font(11.5, .bold))
          .foregroundStyle(.white.opacity(0.8))
        Spacer()
        Image(systemName: "waveform")
          .foregroundStyle(.white.opacity(0.85))
      }
    }
    .padding(22)
    .frame(width: 300)
    .background(
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .fill(LinearGradient(colors: [palette.vibrant, palette.vibrant2, Theme.lavender], startPoint: .topLeading, endPoint: .bottomTrailing))
    )
    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 1))
  }
}

// MARK: - Add to playlist

struct AddToPlaylistSheet: View {
  let track: Track
  @ObservedObject private var store = LibraryStore.shared
  @Environment(\.dismiss) private var dismiss
  @State private var newName = ""

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack(spacing: 10) {
            TextField("Nova playlist", text: $newName)
              .submitLabel(.done)
              .onSubmit(create)
            Button("Criar", action: create)
              .fontWeight(.semibold)
              .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
          }
        }
        if !store.playlists.isEmpty {
          Section("Suas playlists") {
            ForEach(store.playlists) { pl in
              let already = pl.trackIds.contains(track.id)
              Button {
                store.addTrack(track, toPlaylist: pl.id)
                Haptics.success()
                AppModel.shared.showToast("Adicionada em \(pl.name)")
                dismiss()
              } label: {
                HStack(spacing: 12) {
                  ArtworkImage(url: pl.artworkURL, cornerRadius: 6, maxPixel: 140, placeholderIcon: "music.note.list")
                    .frame(width: 44, height: 44)
                  VStack(alignment: .leading) {
                    Text(pl.name).foregroundStyle(Theme.text)
                    Text("\(pl.trackIds.count) músicas").font(Theme.font(13)).foregroundStyle(Theme.secondary)
                  }
                  Spacer()
                  Image(systemName: already ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(already ? Theme.ok : Theme.accent)
                }
              }
            }
          }
        }
      }
      .navigationTitle("Adicionar à playlist")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
    }
  }

  private func create() {
    let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    store.createPlaylist(name: clean, tracks: [track])
    Haptics.success()
    AppModel.shared.showToast("Playlist “\(clean)” criada")
    dismiss()
  }
}

/// The selectable Now Playing styles (shown in Settings and in the player menu).
struct PlayerStyleOption: Identifiable {
  let style: PlayerSurfaceTab
  let title: String
  let subtitle: String
  let icon: String
  var id: String { style.rawValue }

  static let all: [PlayerStyleOption] = [
    PlayerStyleOption(style: .artwork, title: "Capa clássica", subtitle: "A capa grande, limpa, com capas animadas", icon: "square.fill"),
    PlayerStyleOption(style: .vinyl, title: "Vinil", subtitle: "Toca-discos com a capa no selo do disco", icon: "record.circle"),
    PlayerStyleOption(style: .cassette, title: "Fita K7", subtitle: "Deck com a capa na fita e VU analógico", icon: "recordingtape"),
    PlayerStyleOption(style: .waves, title: "Ondas 3D", subtitle: "Visualizador que reage ao som de verdade", icon: "waveform"),
  ]
}
