# Lume Music 4.0.0

Aplicativo nativo de música para iPhone e iPad construído em **SwiftUI** com estética **Prisma Liquid Glass** (iOS 18–26+), combinando o melhor de **Apple Music**, **Spotify** e **Amazon Music** com visualizadores musicais exclusivos.

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

```bash
xcodegen generate
xcodebuild -project LumeMusic.xcodeproj -scheme LumeMusic -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

---
Desenvolvido por A.A · Demerzel Studio
