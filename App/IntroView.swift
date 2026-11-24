import SwiftUI

/// Abertura cinematográfica a 120Hz (~0.95s, toque para pular):
/// ondas acústicas concêntricas com brilho prismático irradiam do novo emblema 3D,
/// o nome Lume surge nítido e o app aparece sem blur pesado.
struct IntroView: View {
  let done: () -> Void

  @State private var markScale: CGFloat = 0.72
  @State private var markOpacity: Double = 0
  @State private var pulseA: CGFloat = 0.6
  @State private var pulseAAlpha: Double = 0
  @State private var pulseB: CGFloat = 0.6
  @State private var pulseBAlpha: Double = 0
  @State private var sweep: CGFloat = -1
  @State private var wordIn = false
  @State private var leaving = false

  var body: some View {
    ZStack {
      Theme.canvas.ignoresSafeArea()
      RadialGradient(
        colors: [Theme.lavender.opacity(markOpacity * 0.20), Theme.rose.opacity(markOpacity * 0.09), .clear],
        center: .center, startRadius: 0, endRadius: 340
      )
      .ignoresSafeArea()

      VStack(spacing: 22) {
        ZStack {
          // Ondas acústicas prismáticas concêntricas
          Circle()
            .stroke(Theme.prismAngular, lineWidth: 2.5)
            .frame(width: 146, height: 146)
            .scaleEffect(pulseA)
            .opacity(pulseAAlpha)

          Circle()
            .stroke(Theme.prismAngular, lineWidth: 1.6)
            .frame(width: 146, height: 146)
            .scaleEffect(pulseB)
            .opacity(pulseBAlpha)

          PrismMark(size: 112)
            .overlay {
              LinearGradient(colors: [.clear, .white.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 44)
                .rotationEffect(.degrees(22))
                .offset(x: sweep * 96)
                .mask(Circle().frame(width: 112, height: 112))
                .blendMode(.plusLighter)
            }
            .scaleEffect(markScale)
            .opacity(markOpacity)
        }

        VStack(spacing: 5) {
          Text("Lume")
            .font(.system(size: 42, weight: .bold, design: .rounded))
            .tracking(wordIn ? -0.5 : 3)
            .foregroundStyle(Theme.text)
          Text("MUSIC")
            .font(Theme.font(11.5, .bold))
            .tracking(wordIn ? 5.5 : 8.5)
            .foregroundStyle(Theme.secondary)
        }
        .opacity(wordIn ? 1 : 0)
        .offset(y: wordIn ? 0 : 8)
      }
      .scaleEffect(leaving ? 1.08 : 1)
      .opacity(leaving ? 0 : 1)

      VStack {
        Spacer()
        Text(Theme.credit)
          .font(Theme.font(11))
          .foregroundStyle(Theme.tertiary)
          .opacity(wordIn && !leaving ? 1 : 0)
          .padding(.bottom, 18)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture { finish(fast: true) }
    .accessibilityLabel("Lume Music")
    .task { await run() }
  }

  private func run() async {
    guard Theme.motion else {
      markScale = 1; markOpacity = 1; wordIn = true
      try? await Task.sleep(for: .milliseconds(320))
      finish(fast: true)
      return
    }
    withAnimation(.spring(response: 0.48, dampingFraction: 0.78)) {
      markScale = 1
      markOpacity = 1
    }
    pulseAAlpha = 0.85
    withAnimation(.easeOut(duration: 0.75)) {
      pulseA = 1.48
      pulseAAlpha = 0
    }
    try? await Task.sleep(for: .milliseconds(160))
    pulseBAlpha = 0.65
    withAnimation(.easeOut(duration: 0.72)) {
      pulseB = 1.32
      pulseBAlpha = 0
    }
    withAnimation(.easeInOut(duration: 0.55)) { sweep = 1 }
    withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) { wordIn = true }

    try? await Task.sleep(for: .milliseconds(620))
    finish(fast: false)
  }

  private func finish(fast: Bool) {
    guard !leaving else { return }
    withAnimation(.easeInOut(duration: fast ? 0.18 : 0.28)) {
      leaving = true
    }
    Task {
      try? await Task.sleep(for: .milliseconds(fast ? 180 : 280))
      done()
    }
  }
}
