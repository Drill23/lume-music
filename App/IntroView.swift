import SwiftUI

/// Opening — quiet and iOS-like: the Lume record mark resolves out of blur, a prism ring of light
/// draws around it, the wordmark settles in, and the app zooms in from behind. ~1.4 s, tap to skip.
struct IntroView: View {
  let done: () -> Void

  @State private var markIn = false
  @State private var ring: CGFloat = 0
  @State private var ringFade = false
  @State private var sweep: CGFloat = -1
  @State private var wordIn = false
  @State private var leaving = false
  @State private var finished = false

  var body: some View {
    ZStack {
      Theme.canvas.ignoresSafeArea()
      RadialGradient(colors: [Theme.lavender.opacity(markIn ? 0.22 : 0), Theme.rose.opacity(markIn ? 0.08 : 0), .clear],
                     center: .center, startRadius: 0, endRadius: 320)
        .ignoresSafeArea()

      VStack(spacing: 22) {
        ZStack {
          // Prism ring of light
          Circle()
            .trim(from: 0, to: ring)
            .stroke(Theme.prismAngular, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: 150, height: 150)
            .rotationEffect(.degrees(-90 + Double(ring) * 120))
            .blur(radius: 0.5)
            .opacity(ringFade ? 0 : 1)
          Circle()
            .trim(from: 0, to: ring)
            .stroke(Theme.prismAngular, style: StrokeStyle(lineWidth: 10, lineCap: .round))
            .frame(width: 150, height: 150)
            .rotationEffect(.degrees(-90 + Double(ring) * 120))
            .blur(radius: 14)
            .opacity(ringFade ? 0 : 0.7)

          PrismMark(size: 104)
            .overlay {
              // Specular sweep
              LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 40)
                .rotationEffect(.degrees(20))
                .offset(x: sweep * 90)
                .mask(Circle().frame(width: 104, height: 104))
                .blendMode(.plusLighter)
            }
            .scaleEffect(markIn ? 1 : 0.62)
            .blur(radius: markIn ? 0 : 14)
            .opacity(markIn ? 1 : 0)
        }

        VStack(spacing: 6) {
          Text("Lume")
            .font(.system(size: 44, weight: .bold, design: .rounded))
            .tracking(wordIn ? -0.6 : 6)
            .foregroundStyle(Theme.text)
          Text("MUSIC")
            .font(Theme.font(12, .semibold))
            .tracking(wordIn ? 5 : 10)
            .foregroundStyle(Theme.secondary)
        }
        .opacity(wordIn ? 1 : 0)
        .offset(y: wordIn ? 0 : 10)
        .blur(radius: wordIn ? 0 : 6)
      }
      .scaleEffect(leaving ? 1.18 : 1)
      .blur(radius: leaving ? 10 : 0)
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
    .opacity(finished ? 0 : 1)
    .contentShape(Rectangle())
    .onTapGesture { finish(fast: true) }
    .accessibilityLabel("Lume Music")
    .task { await run() }
  }

  private func run() async {
    let motion = Theme.motion
    if !motion {
      markIn = true; wordIn = true; ring = 1
      try? await Task.sleep(for: .milliseconds(450))
      finish(fast: true)
      return
    }
    withAnimation(.spring(response: 0.62, dampingFraction: 0.74)) { markIn = true }
    withAnimation(.easeInOut(duration: 0.9)) { ring = 1 }
    try? await Task.sleep(for: .milliseconds(260))
    withAnimation(.easeInOut(duration: 0.7)) { sweep = 1 }
    withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) { wordIn = true }
    try? await Task.sleep(for: .milliseconds(820))
    withAnimation(.easeOut(duration: 0.35)) { ringFade = true }
    try? await Task.sleep(for: .milliseconds(180))
    finish(fast: false)
  }

  private func finish(fast: Bool) {
    guard !leaving else { return }
    withAnimation(.easeIn(duration: fast ? 0.22 : 0.42)) { leaving = true }
    withAnimation(.easeOut(duration: fast ? 0.25 : 0.45).delay(fast ? 0.05 : 0.12)) { finished = true }
    Task {
      try? await Task.sleep(for: .milliseconds(fast ? 300 : 560))
      done()
    }
  }
}
