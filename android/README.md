# Lume Music — Android (fase 1)

Versão 5.0.0 · package `com.adriano.lumemusic` · minSdk 26 · targetSdk 36 · Kotlin + Jetpack Compose + Media3.

## Compilar

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
cd android
./gradlew testDebugUnitTest      # testes JVM (parsers InnerTube, letras, Código de Acesso)
./gradlew assembleRelease        # APK release assinado em app/build/outputs/apk/release/
```

A assinatura lê `~/.config/lume-music-android/signing.properties` (keystore **fora da repo**; nunca commitar).
Sem esse arquivo o release cai para a chave de debug.

APK final: `~/.gemini/antigravity/scratch/lume-music/outputs/5.0.0/android/Lume-Music-Android-5.0.0-fase1.apk`.

## Estrutura

- `engine/` — MusicEngine (InnerTube, stream itag 140/18), ArtworkResolver, SearchService, DiscoveryService,
  CatalogExplorerService, LyricsService, ImportService.
- `data/` — Models, LibraryStore (JSON local), DownloadManager (fila de 2, pausa/retomada), ArtworkStore.
- `audio/` — AudioPlayer (fila, aleatório, repetir, crossfade, sleep timer, rádio), PlayerHolder (ExoPlayer),
  LumeAudioProcessor (EQ de 5 bandas + FFT real, sem microfone), AudioSpectrum, PlaybackService (MediaSession).
- `access/` — AccessService (Código de Acesso v1: config remota, device id, activate/check, token no Keystore).
- `ui/` — tema "Prisma", vidro (Haze), componentes, telas; `ui/screens/PlayerStages.kt` é a arquitetura de palcos.

## Fase 2 (pendente)

Palcos finais Vinil / K7 / Ondas / Cover Flow, onboarding, nova Home e tela do portão de Código de Acesso.
