import SwiftUI

/// Nostalgic iPod Classic 3D Cover Flow reimagined in Liquid Glass:
/// 3D perspective carousel with mirrored glass floor reflections, center forward pop,
/// specular glowing rim, and tap-to-play / tap-to-flip 3D interaction.
struct CoverFlowView: View {
  let items: [CoverFlowItem]
  var cardSize: CGFloat = 200
  var onSelect: (CoverFlowItem) -> Void

  @State private var activeIndex: Int = 0
  @State private var dragOffset: CGFloat = 0

  struct CoverFlowItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let badge: String
    let artworkURL: String
    let track: Track?
    let album: AlbumShowcase?
  }

  var body: some View {
    VStack(spacing: 14) {
      GeometryReader { geo in
        let midX = geo.size.width / 2
        let spacing = cardSize * 0.62

        ZStack {
          ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
            let rawDelta = Double(idx - activeIndex) + Double(dragOffset / spacing)
            let clamped = max(-3.2, min(3.2, rawDelta))
            let absD = abs(clamped)
            let isCenter = absD < 0.35

            // Classic iPod 3D Cover Flow math: side covers rotate inward ~54°, recede & tuck neatly
            let angle = clamped == 0 ? 0.0 : -Double(clamped > 0 ? 1 : -1) * min(56.0, absD * 52.0)
            let xOffset = clamped * Double(spacing) + (clamped == 0 ? 0 : Double(clamped > 0 ? 1 : -1) * Double(cardSize) * 0.14 * min(1, absD))
            let scale = max(0.72, 1.0 - min(absD, 1.8) * 0.17)
            let opacity = absD > 2.8 ? 0.0 : max(0.28, 1.0 - absD * 0.26)
            let z = 100.0 - absD * 10.0

            VStack(spacing: 0) {
              // Main 3D Cover Card
              ZStack(alignment: .bottomLeading) {
                RemoteArtwork(url: item.artworkURL, cornerRadius: 18)
                  .frame(width: cardSize, height: cardSize)

                // Specular Liquid Glass gloss
                LinearGradient(
                  colors: [Color.white.opacity(isCenter ? 0.24 : 0.12), Color.clear, Color.black.opacity(0.22)],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                if isCenter && !item.badge.isEmpty {
                  Text(item.badge)
                    .font(Theme.font(10, .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Theme.aurora, in: Capsule())
                    .padding(10)
                }
              }
              .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                  .stroke(
                    isCenter
                      ? LinearGradient(colors: [.white.opacity(0.92), Theme.amber.opacity(0.75), Theme.coral.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                      : Theme.glassStroke,
                    lineWidth: isCenter ? 2.0 : 0.8
                  )
              )
              .shadow(color: isCenter ? Theme.amber.opacity(0.32) : .black.opacity(0.55), radius: isCenter ? 24 : 12, y: isCenter ? 10 : 6)

              // Mirrored iPod Liquid Glass Floor Reflection
              RemoteArtwork(url: item.artworkURL, cornerRadius: 18)
                .frame(width: cardSize, height: cardSize * 0.34, alignment: .bottom)
                .scaleEffect(y: -1)
                .clipped()
                .mask(
                  LinearGradient(
                    colors: [Color.white.opacity(0.34), Color.white.opacity(0.06), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                  )
                )
                .opacity(isCenter ? 0.85 : 0.45)
                .offset(y: 4)
            }
            .scaleEffect(scale)
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.46)
            .position(x: midX + CGFloat(xOffset), y: cardSize * 0.62)
            .opacity(opacity)
            .zIndex(z)
            .onTapGesture {
              if idx == activeIndex {
                Haptics.medium()
                onSelect(item)
              } else {
                Haptics.selection()
                withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                  activeIndex = idx
                }
              }
            }
          }
        }
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 8)
            .onChanged { value in
              dragOffset = value.translation.width
            }
            .onEnded { value in
              let threshold = cardSize * 0.24
              var next = activeIndex
              if value.predictedEndTranslation.width < -threshold {
                next = min(items.count - 1, activeIndex + 1)
              } else if value.predictedEndTranslation.width > threshold {
                next = max(0, activeIndex - 1)
              }
              if next != activeIndex { Haptics.selection() }
              withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                activeIndex = next
                dragOffset = 0
              }
            }
        )
      }
      .frame(height: cardSize * 1.42)

      // Focused Cover Title + Subtitle (100% firm, crisp typography below the 3D reflection)
      if activeIndex >= 0 && activeIndex < items.count {
        let cur = items[activeIndex]
        VStack(spacing: 4) {
          Text(cur.title)
            .font(Theme.font(17, .bold))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
          Text(cur.subtitle)
            .font(Theme.font(13, .medium))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
        }
        .padding(.horizontal, 28)
        .onTapGesture {
          Haptics.medium()
          onSelect(cur)
        }
      }
    }
    .onChange(of: items.count) { _, newCount in
      if activeIndex >= newCount { activeIndex = max(0, newCount - 1) }
    }
  }
}

/// Full-screen immersive iPod 3D Cover Flow stage (pushed inside NavigationStack -> native swipe-back!).
struct CoverFlowFullScreenView: View {
  let items: [CoverFlowView.CoverFlowItem]
  let onPlay: (CoverFlowView.CoverFlowItem) -> Void
  @ObservedObject private var player = AudioPlayer.shared

  var body: some View {
    ZStack {
      Theme.bg.ignoresSafeArea()
      RadialGradient(
        colors: [player.accentPrimary.opacity(0.32), player.accentSecondary.opacity(0.12), .clear],
        center: .top,
        startRadius: 20,
        endRadius: 520
      )
      .ignoresSafeArea()

      VStack(spacing: 22) {
        VStack(spacing: 4) {
          Text("COVER FLOW 3D")
            .font(Theme.font(11, .bold))
            .tracking(2.6)
            .foregroundStyle(Theme.amber)
          Text("Deslize as capas e toque na central para abrir")
            .font(Theme.font(13, .medium))
            .foregroundStyle(Theme.muted)
        }
        .padding(.top, 12)

        Spacer(minLength: 0)

        CoverFlowView(items: items, cardSize: 238) { item in
          onPlay(item)
        }

        if player.currentTrack != nil {
          AresVisualizerView(
            style: .ares,
            isPlaying: player.isPlaying,
            accentA: player.accentPrimary,
            accentB: player.accentSecondary,
            compact: true
          )
          .frame(height: 44)
          .padding(.horizontal, 28)
        }

        Spacer(minLength: 16)
      }
    }
    .navigationTitle("Vitrine 3D")
    .navigationBarTitleDisplayMode(.inline)
  }
}
