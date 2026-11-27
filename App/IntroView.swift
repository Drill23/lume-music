import SwiftUI

/// Abertura de toda vez (~1,1 s, toque para pular, não bloqueia o app que carrega por baixo):
/// um anel prismático se desenha, o disco de vidro se forma com brilho que atravessa e o nome Lume surge letra a letra.
struct IntroView: View {
  let done: () -> Void

  @State private var ring: CGFloat = 0
  @State private var discIn = false
  @State private var sweep: CGFloat = -1.2
  @State private var glow = false
  @State private var letters = false
  @State private var leaving = false

  private let word = Array("Lume")

  var body: some View {
    ZStack {
      Theme.canvas.ignoresSafeArea()
      RadialGradient(
        colors: [Theme.lavender.opacity(glow ? 0.26 : 0), Theme.rose.opacity(glow ? 0.12 : 0), .clear],
        center: .center, startRadius: 0, endRadius: 360
      )
      .ignoresSafeArea()

      VStack(spacing: 24) {
        ZStack {
          // Anel prismático que se desenha ao redor do disco.
          Circle()
            .trim(from: 0, to: ring)
            .stroke(Theme.prismAngular, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: 148, height: 148)

          // Disco de vidro.
          Circle()
            .fill(Color.clear)
            .frame(width: 124, height: 124)
            .glassCircle(tint: Theme.lavender.opacity(0.2))
            .scaleEffect(discIn ? 1 : 0.55)
            .opacity(discIn ? 1 : 0)

          PrismMark(size: 100)
            .drawingGroup()
            .overlay {
              // Brilho prisma que atravessa o disco.
              LinearGradient(colors: [.clear, .white.opacity(0.7), Theme.peach.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 40)
                .rotationEffect(.degrees(22))
                .offset(x: sweep * 90)
                .mask(Circle().frame(width: 100, height: 100))
                .blendMode(.plusLighter)
            }
            .scaleEffect(discIn ? 1 : 0.5)
            .opacity(discIn ? 1 : 0)
            .rotationEffect(.degrees(discIn ? 0 : -50))
        }

        HStack(spacing: 1) {
          ForEach(Array(word.enumerated()), id: \.offset) { i, ch in
            Text(String(ch))
              .font(.system(size: 42, weight: .bold, design: .rounded))
              .foregroundStyle(Theme.text)
              .opacity(letters ? 1 : 0)
              .offset(y: letters ? 0 : 14)
              .animation(.spring(response: 0.45, dampingFraction: 0.78).delay(Double(i) * 0.05), value: letters)
          }
        }
      }
      .scaleEffect(leaving ? 1.1 : 1)
      .opacity(leaving ? 0 : 1)

      VStack {
        Spacer()
        Text(Theme.credit)
          .font(Theme.font(11))
          .foregroundStyle(Theme.tertiary)
          .opacity(letters && !leaving ? 1 : 0)
          .animation(.easeOut(duration: 0.3), value: letters)
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
      ring = 1; discIn = true; letters = true; glow = true; sweep = 1.2
      try? await Task.sleep(for: .milliseconds(300))
      finish(fast: true)
      return
    }
    withAnimation(.easeInOut(duration: 0.5)) { ring = 1; glow = true }
    withAnimation(.spring(response: 0.5, dampingFraction: 0.72).delay(0.08)) { discIn = true }
    withAnimation(.easeInOut(duration: 0.5).delay(0.3)) { sweep = 1.2 }
    try? await Task.sleep(for: .milliseconds(380))
    letters = true
    try? await Task.sleep(for: .milliseconds(480))
    finish(fast: false)
  }

  private func finish(fast: Bool) {
    guard !leaving else { return }
    withAnimation(.easeInOut(duration: fast ? 0.16 : 0.24)) { leaving = true }
    Task {
      try? await Task.sleep(for: .milliseconds(fast ? 160 : 240))
      done()
    }
  }
}
