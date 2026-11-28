import SwiftUI

/// Ajustes — lista agrupada nativa com seletor visual do estilo do Tocando agora.
struct SettingsView: View {
  @ObservedObject private var app = AppModel.shared
  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var update = UpdateService.shared
  @AppStorage("lume.appearance") private var appearance = "system"
  @State private var confirmClear = false

  var body: some View {
    List {
      if AccessService.shared.gateEnabled {
        Section {
          AccessStatusCard()
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            .listRowBackground(Color.clear)
        } header: {
          Text("Seu acesso")
        }
      }

      Section {
        PlayerStylePicker()
          .listRowInsets(EdgeInsets())
          .listRowBackground(Color.clear)
      } header: {
        Text("Estilo do Tocando agora")
      } footer: {
        Text("Escolha como a capa aparece na tela de reprodução.")
      }

      Section("Aparência") {
        Picker("Aparência", selection: $appearance) {
          Text("Automático").tag("system")
          Text("Claro").tag("light")
          Text("Escuro").tag("dark")
        }
        .pickerStyle(.segmented)
        .onChange(of: appearance) { _, _ in Haptics.selection() }
        Toggle(isOn: $store.introEnabled) {
          Label("Abertura animada", systemImage: "sparkles")
        }
        Button {
          Haptics.success()
          Onboarding.reset()
        } label: {
          Label("Rever apresentação", systemImage: "play.rectangle.on.rectangle")
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .listRowBackground(Theme.canvasRaised)

      Section("Reprodução") {
        Toggle(isOn: $player.autoplayRadio) {
          Label("Rádio automática", systemImage: "dot.radiowaves.left.and.right")
        }
        NavigationLink(value: LumeRoute.equalizer) {
          LabeledContent {
            Text(store.soundProfile.rawValue)
          } label: {
            Label("Equalizador (5 bandas)", systemImage: "dial.medium")
          }
        }
        Picker(selection: Binding(
          get: { store.soundProfile },
          set: { player.applySoundProfile($0) }
        )) {
          ForEach(SoundProfile.allCases) { Text($0.rawValue).tag($0) }
        } label: {
          Label("Perfil de som", systemImage: "slider.horizontal.3")
        }
        Picker(selection: $store.crossfadeSeconds) {
          Text("Desligado").tag(0.0)
          Text("3 segundos").tag(3.0)
          Text("6 segundos").tag(6.0)
          Text("9 segundos").tag(9.0)
        } label: {
          Label("Crossfade entre faixas", systemImage: "waveform.path")
        }
        Toggle(isOn: $store.animatedArtEnabled) {
          Label("Capas animadas", systemImage: "sparkles.tv")
        }
        Toggle(isOn: $store.autoTranslateLyrics) {
          Label("Traduzir letras automaticamente", systemImage: "translate")
        }
        Picker(selection: $store.visualizerStyle) {
          ForEach(VisualizerStyle.activeStyles) { Text($0.title).tag($0) }
        } label: {
          Label("Estilo das ondas", systemImage: "waveform")
        }
      }
      .listRowBackground(Theme.canvasRaised)

      SettingsAudioExtras()

      Section("Estúdio Vinil & K7") {
        Picker(selection: $store.turntableFinish) {
          ForEach(TurntableFinish.allCases) { Text($0.rawValue).tag($0) }
        } label: {
          Label("Acabamento do toca-discos", systemImage: "paintpalette")
        }
        Picker(selection: $store.vinylEdition) {
          ForEach(VinylEdition.allCases) { Text($0.rawValue).tag($0) }
        } label: {
          Label("Edição do disco", systemImage: "record.circle")
        }
        Toggle(isOn: $store.turntable3D) {
          Label("Perspectiva 3D no Vinil", systemImage: "cube")
        }
        Picker(selection: $store.cassetteStyle) {
          ForEach(CassetteStyle.allCases) { Text($0.rawValue).tag($0) }
        } label: {
          Label("Estilo da fita K7", systemImage: "recordingtape")
        }
      }
      .listRowBackground(Theme.canvasRaised)

      Section {
        Picker(selection: Binding(
          get: { store.lockArtStyle },
          set: { v in
            Haptics.selection()
            store.lockArtStyle = v
            player.refreshLockScreenArtwork()
          }
        )) {
          ForEach(LockArtStyle.allCases) { Text($0.title).tag($0) }
        } label: {
          Label("Arte na tela de bloqueio", systemImage: "lock.iphone")
        }
      } header: {
        Text("Tela de bloqueio")
      } footer: {
        Text("Com o celular bloqueado aparece o disco de vinil ou a fita K7 com a capa da música. No Automático, segue o estilo do Tocando agora.")
      }
      .listRowBackground(Theme.canvasRaised)

      Section {
        Toggle(isOn: $store.economyMode) {
          Label("Modo economia", systemImage: "leaf")
        }
      } header: {
        Text("Desempenho")
      } footer: {
        Text("Menos quadros por segundo e efeitos mais leves: o celular esquenta menos e a bateria dura mais. Liga sozinho no Modo de Pouca Energia ou quando o aparelho está quente.")
      }
      .listRowBackground(Theme.canvasRaised)

      SettingsScrobbleSection()

      SettingsBackupSection()

      Section("Biblioteca") {
        NavigationLink(value: LumeRoute.replay) {
          Label("Lume Replay · Seu Resumo", systemImage: "sparkles")
        }
        NavigationLink(value: LumeRoute.importHub) {
          Label("Importar músicas", systemImage: "square.and.arrow.down")
        }
        if store.followedArtists.isEmpty {
          LabeledContent {
            Text("0")
          } label: {
            Label("Artistas seguidos", systemImage: "person.2")
          }
        } else {
          NavigationLink(value: LumeRoute.artists("Artistas seguidos", followedInfos)) {
            LabeledContent {
              Text("\(store.followedArtists.count)")
            } label: {
              Label("Artistas seguidos", systemImage: "person.2")
            }
          }
        }
      }
      .listRowBackground(Theme.canvasRaised)

      Section("Armazenamento & Offline") {
        Toggle(isOn: $store.offlineMode) {
          Label("Modo Offline", systemImage: "airplane.circle")
        }
        Toggle(isOn: $store.autoDownloadFavorites) {
          Label("Baixar curtidas automaticamente", systemImage: "heart.circle")
        }
        NavigationLink(value: LumeRoute.downloads) {
          LabeledContent {
            Text(store.offlineStorageFormatted)
          } label: {
            Label("Central de Downloads", systemImage: "arrow.down.circle")
          }
        }
        Button {
          Haptics.light()
          confirmClear = true
        } label: {
          Label("Limpar cache de imagens e letras", systemImage: "trash")
            .foregroundStyle(Theme.danger)
        }
      }
      .listRowBackground(Theme.canvasRaised)

      Section {
        Button {
          guard !update.checking else { return }
          Haptics.light()
          Task {
            let outcome = await update.check(manual: true)
            switch outcome {
            case .found:
              Haptics.success()
            case .upToDate:
              app.showToast("Você já está na versão mais recente (\(AccessConfig.appVersion))")
            case .offline:
              app.showToast("Sem conexão para verificar atualizações")
            }
          }
        } label: {
          HStack {
            Label(update.checking ? "Verificando atualizações…" : "Verificar atualizações", systemImage: "arrow.down.circle")
              .foregroundStyle(Theme.text)
            Spacer()
            if update.checking {
              ProgressView().controlSize(.small)
            } else {
              Text("v\(AccessConfig.appVersion)")
                .font(Theme.font(14))
                .foregroundStyle(Theme.secondary)
            }
          }
          .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(update.checking)
        LabeledContent("Versão", value: versionString)
        VStack(alignment: .leading, spacing: 6) {
          Text(Theme.credit)
            .font(Theme.font(14, .medium))
            .foregroundStyle(Theme.text)
          Text("Fontes: Apple Music · Deezer · YouTube Music · LRCLIB · NetEase · Letras.mus.br")
            .font(Theme.font(12.5))
            .foregroundStyle(Theme.secondary)
        }
        .padding(.vertical, 2)
      } header: {
        Text("Sobre")
      }
      .listRowBackground(Theme.canvasRaised)
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .lumeTabScroll()
    .background(Theme.canvas.ignoresSafeArea())
    .tint(Theme.accent)
    .lumeDetailChrome(title: "Ajustes", alwaysShowTitle: true)
    .confirmationDialog("Limpar cache?", isPresented: $confirmClear, titleVisibility: .visible) {
      Button("Limpar cache", role: .destructive) { clearCache() }
      Button("Cancelar", role: .cancel) {}
    } message: {
      Text("Imagens e letras salvas serão apagadas e baixadas de novo quando precisar. Suas músicas baixadas não são afetadas.")
    }
  }

  private var followedInfos: [ArtistInfo] {
    store.followedArtists.map { ArtistInfo(id: "lib_" + $0, name: $0, pictureURL: "", deezerId: nil, fans: nil, rank: nil) }
  }

  private var versionString: String {
    let info = Bundle.main.infoDictionary
    let v = info?["CFBundleShortVersionString"] as? String
    let b = info?["CFBundleVersion"] as? String
    if let v, let b { return "\(v) (\(b))" }
    return "5.1.8 (15)"
  }

  private func clearCache() {
    URLCache.shared.removeAllCachedResponses()
    ImagePipeline.shared.memory.removeAllObjects()
    if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
      try? FileManager.default.removeItem(at: caches.appendingPathComponent("LumeMusicLyrics", isDirectory: true))
    }
    Haptics.success()
    app.showToast("Cache limpo")
  }
}

// MARK: - Seletor visual do estilo do Tocando agora

struct PlayerStylePicker: View {
  @ObservedObject private var app = AppModel.shared
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var store = LibraryStore.shared

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 12) {
        ForEach(PlayerStyleOption.all) { option in
          card(option)
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 8)
      .environment(\.lumeFlatGlass, true)   // 5 cartões numa lista rolando: superfície leve em vez de 5 vidros
    }
    .scrollClipDisabled()
  }

  private func card(_ option: PlayerStyleOption) -> some View {
    let selected = app.playerStyle == option.style
    let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    return Button {
      Haptics.selection()
      withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { app.playerStyle = option.style }
    } label: {
      VStack(spacing: 6) {
        preview(option.style)
          .frame(width: 116, height: 92)
          .clipped()
        VStack(spacing: 2) {
          Text(option.title)
            .font(Theme.font(13, .semibold))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
          Text(option.subtitle)
            .font(Theme.font(10.5))
            .foregroundStyle(Theme.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.9)
        }
        .frame(maxWidth: .infinity)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 10)
      .frame(width: 132, height: 168)
      .glass(22)
      .overlay {
        if selected {
          shape.strokeBorder(Theme.prismDiagonal, lineWidth: 2)
        }
      }
      .overlay(alignment: .topTrailing) {
        if selected {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 19))
            .symbolRenderingMode(.palette)
            .foregroundStyle(Theme.onPrism, Theme.rose)
            .background(Circle().fill(.white).padding(3))
            .padding(8)
            .transition(.scale.combined(with: .opacity))
        }
      }
      .contentShape(shape)
    }
    .buttonStyle(PressableStyle(scale: 0.96))
    .accessibilityLabel(option.title)
    .accessibilityAddTraits(selected ? [.isSelected] : [])
  }

  @ViewBuilder
  private func preview(_ style: PlayerSurfaceTab) -> some View {
    let art = player.currentArtwork
    switch style {
    case .artwork, .lyrics:
      ZStack {
        if art.isEmpty {
          RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.prismDiagonal)
        } else {
          ArtworkImage(url: art, cornerRadius: 12, maxPixel: 300)
        }
      }
      .frame(width: 84, height: 84)
      .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
      .lumeShadow(8, y: 5, opacity: 0.6)
    case .vinyl:
      RecordDisc(side: 120, artworkURL: art, edition: store.vinylEdition)
        .frame(width: 120, height: 120)
        .scaleEffect(0.78)
        .frame(width: 96, height: 92)
    case .cassette:
      CassetteTape(width: 116, title: "Lume", artist: "Mix", artworkURL: art, sideB: false, progress: 0.35, seconds: 200, style: store.cassetteStyle)
    case .waves:
      WavesPreview()
        .frame(width: 112, height: 84)
    }
  }
}

/// Mini prévia estática do visualizador "Ondas 3D".
private struct WavesPreview: View {
  var body: some View {
    Canvas { ctx, size in
      let lines = 6
      let gradient = Gradient(colors: Theme.prismColors)
      for i in 0..<lines {
        let t = CGFloat(i) / CGFloat(lines - 1)
        let baseY = size.height * (0.22 + 0.62 * t)
        let amp = size.height * (0.05 + 0.13 * (1 - abs(t - 0.45)))
        var path = Path()
        let steps = 56
        for s in 0...steps {
          let x = size.width * CGFloat(s) / CGFloat(steps)
          let nx = CGFloat(s) / CGFloat(steps)
          let envelope = sin(nx * .pi)
          let y = baseY - amp * envelope * sin(nx * .pi * 3.2 + t * 2.4)
          if s == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.opacity = 0.45 + 0.55 * Double(t)
        ctx.stroke(
          path,
          with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: 0)),
          style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
        )
      }
    }
    .accessibilityHidden(true)
  }
}
