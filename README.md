# Lume Music 5.2.0

**Site:** https://lume-music-enq.pages.dev (espelho: https://drill23.github.io/lume-music/)

**Baixar:** [Android (APK)](https://github.com/Drill23/lume-music/releases/latest/download/Lume-Music-Android.apk) · [iPhone (IPA para LiveContainer/SideStore)](https://github.com/Drill23/lume-music/releases/latest/download/Lume-Music-iPhone.ipa)

## Novidades da versão 5.0.0

- **iPhone e Android** com a mesma aparência e as mesmas funções (Android em Kotlin + Jetpack Compose + Media3, pasta `android/`).
- **Ícone novo** claro e translúcido: disco de vidro com anel prisma.
- **Apresentação interativa** na primeira abertura: gêneros com som, artistas, importação (Apple Music, Spotify, YouTube Music, Deezer, Amazon Music, Tidal, arquivo) e carregamento animado "Carregando suas músicas".
- **Código de acesso** com validade (meses ou vitalício) e limite de pessoas, definido no painel.
- **Palcos redesenhados:** toca-discos realista (prato estroboscópico, braço que desce no play, 33⅓/45, pitch), fita K7 com etiqueta escrita à mão e carretéis que acompanham a música, ondas de vidro que reagem às batidas.
- **Cover Flow** clássico em paisagem (acelerômetro), com capas em 3D, reflexo e capa que vira mostrando as faixas.
- **Tela inicial limpa** com Top 10 de 20 países + Global e fontes de paradas auditadas.
- **Tela de bloqueio** com arte de vinil ou fita, **player só de música** (sem vídeo) e otimizações contra aquecimento.


Aplicativo nativo de música para iPhone e iPad construído em **SwiftUI** com estética **Prisma Liquid Glass** (iOS 18–26+), texturas procedurais pré-aquecidas em disco e GPU a 120Hz, combinando o melhor de **Apple Music**, **Spotify** e **Amazon Music** com palcos analógicos e visualizadores exclusivos.

## Destaques da versão 4.2.0

- **Fita K7 Livre em Primeiro Plano:** Fita cassete exibida por inteiro (sem estojo recortando a arte), painel `BrushedPanel` com geometria corrigida (`GeometryReader` isolado), VU meters balísticos com LED `PEAK` e flip 3D Lado A / Lado B.
- **Toca-Discos Fotorrealista:** Vinil 180g redesenhado em 768×768 com 118 sulcos concêntricos livres de moiré, reflexo especular neutro de estúdio, anel prensado no selo de papel, eixo metálico torneado e perspectiva 3D natural de 10°.
- **Orbe Retrátil de Estilos (`StageStyleOrb`):** Seletor circular compacto no canto superior direito dos palcos *Vinil*, *K7* e *Ondas* que abre as opções de acabamento/estilo sob demanda e retrai automaticamente ao selecionar ou tocar fora, mantendo toda a tela livre de barras e sobreposições.
- **Otimizações de Velocidade:** Cache em disco (`Caches/LumeTextures`) com pré-aquecimento em background no lançamento, formatadores de data estáticos em cache, cache de `videoId` no `MusicEngine` e persistência assíncrona com debounce no `LibraryStore`.

## Destaques da versão 4.1.0 ("Masterpiece Edition")

- **Novo Ícone & Abertura Cinematográfica:** Ícone 3D minimalista com vinil polido e anel prismático, mais abertura a 120Hz sem engasgos com ondas acústicas concêntricas.
- **Toca-Discos 3D com Texturas Procedurais GPU:** Chassi em 4 acabamentos (*Obsidian Pro, Prata Estúdio, Nogueira Vintage, Titânio Dourado*), 4 edições de disco (*Preto 180g, Cristal Prisma, Ouro Limitado, Mármore Branco*), profundidade 3D chanfrada com pés isoladores, braço em S com alavanca Cue real e cálculo geométrico O(1).
- **Deck K7 3D Aprimorado:** 4 estilos de fita (*Fumê Estúdio, Cristal Transparente, Cromo Metálico, Vintage Creme*), flip Lado A/B corrigido sem espelhamento, cabeçote magnético dourado, pinch rollers e VU meters balísticos com LED `PEAK`.
- **6 Visualizadores em Tempo Real (60fps):** *Ondas 3D*, *Espectro* (com peak-hold caps), *Orbe*, *Anel Solar*, *Osciloscópio* e *Nebulosa* com barra seletora rápida.
- **Performance & Resiliência:** `PlaybackClock` isolado (zero re-renderização desnecessária da interface), pré-carregamento da próxima faixa (gapless preload) e auto-retry automático de stream expirado.
- **Transições Fluidas & Compartilhamento:** Troca espacial sedosa entre abas, gestos suaves no player e geração de cartão visual compartilhável da música tocando.

## Destaques da versão 4.0.0

- **Início Personalizado ("Prisma Studio"):** Saudação dinâmica, grade rápida *Retomar rápido*, *Feito para você* (No Repeat, Mixes Diários, Radar de Curtidas, Radar Brasil, Onda Global), *Lume Flow* (rádio infinita personalizada) e *Cover Flow 3D*.
- **Paradas por País (18 países):** Top 50 músicas, álbuns em destaque, artistas e músicas em alta de Brasil, EUA, Reino Unido, Japão, Coreia do Sul, Portugal, Argentina, México, França, Alemanha e outros.
- **20 Gêneros & Estilos Reais + Climas + Décadas:** Separação dedicada entre estilos brasileiros (Sertanejo, Funk & Trap BR, Pagode & Samba, MPB & Bossa, Forró & Piseiro, Gospel) e internacionais (Pop, Rock, Hip-Hop & Rap, Eletrônica, R&B, Latina, K-Pop, Metal, Indie, Jazz, Clássica, Reggae, Country, Trilhas & Games).
- **Cantores Mais Ouvidos (Brasil & Mundo):** Ranking em tempo real com selos `#1`, `#2`, `#3` e páginas completas de artista com discografia filtrável.
- **Busca Inteligente:** Autocomplete ao vivo, filtros por músicas, artistas, álbuns, playlists editoriais e **Busca por Trecho de Letra** (LRCLIB).
- **Player 5 Palcos + Letras Karaokê:** Capa Animada, Vinil interativo com pitch/varispeed, Fita K7 com VU analógico, Ondas 3D FFT em tempo real e Letras Sincronizadas com tradução automática para PT-BR e compartilhamento de cartão de letra.
- **Equalizador Real de 5 Bandas & Crossfade:** Processamento DSP em tempo real (`60 Hz`, `230 Hz`, `910 Hz`, `3,6 kHz`, `14 kHz`) via `MTAudioProcessingTap` + transição suave entre faixas.
- **Central de Downloads Offline:** Fila gerenciada com até 2 downloads simultâneos, pausa/retomada, prefetch de capa e letra, **Modo Offline** e download automático de curtidas.
- **Lume Replay:** Estatísticas de tempo ouvindo, reproduções, top artistas e top músicas com exportação para playlist.

## Requisitos e Build

- Xcode 16+ / iOS 18.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Android: `cd android && ./gradlew assembleRelease` (JDK do Android Studio; a chave de assinatura fica fora do repositório).

```bash
xcodegen generate
xcodebuild -project LumeMusic.xcodeproj -scheme LumeMusic -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

---
Desenvolvido por A.A · Demerzel Studio
