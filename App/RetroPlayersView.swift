import SwiftUI

/// Tactile nostalgic player visual modes — Apple Design Award precision geometry:
/// 1. VinylTurntableView — Brushed anodized glass plinth, corner gimbal pivot cleanly outside platter,
///    progress-tracked tonearm gliding from outer groove (15°) to inner runout (30°), machined spindle.
/// 2. CassetteDeckView — Brushed metallic glass bay, 4 corner housing screws, translucent acrylic window
///    with shifting wound magnetic tape coils, dual 6-tooth spools, and precision analog hairline dial needle.

struct VinylTurntableView: View {
  let artworkURL: String
  let isPlaying: Bool
  let progress: Double
  let accent: Color

  @State private var baseAngle: Double = 0
  @State private var playStartedAt: Date = Date()

  var body: some View {
    GeometryReader { geo in
      let side = min(geo.size.width, geo.size.height)
      let discSize = side * 0.72
      let discCenterX = side * 0.445
      let discCenterY = side * 0.515

      ZStack {
        // 1. Brushed anodized / smoked Liquid Glass turntable plinth
        RoundedRectangle(cornerRadius: side * 0.10, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                Color(red: 0.22, green: 0.23, blue: 0.27),
                Color(red: 0.14, green: 0.15, blue: 0.19),
                Color(red: 0.095, green: 0.105, blue: 0.135)
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .overlay(
            LinearGradient(
              colors: [Color.white.opacity(0.20), Color.clear, Color.white.opacity(0.05), Color.black.opacity(0.24)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: side * 0.10, style: .continuous))
          )
          .overlay(
            RoundedRectangle(cornerRadius: side * 0.10, style: .continuous)
              .stroke(Theme.glassStroke, lineWidth: 1.1)
          )
          .shadow(color: .black.opacity(0.58), radius: 26, y: 14)

        // Subtle deck controls (top-left monogram, bottom-left LED power switch, bottom-right pitch fader)
        VStack {
          HStack {
            Image(systemName: "waveform.circle")
              .font(.system(size: side * 0.052, weight: .semibold))
              .foregroundStyle(Color.white.opacity(0.30))
            Spacer()
          }
          Spacer()
          HStack(alignment: .bottom) {
            VStack(spacing: 5) {
              Circle()
                .fill(isPlaying ? Theme.amber : Color.white.opacity(0.18))
                .frame(width: 6, height: 6)
                .shadow(color: isPlaying ? Theme.amber : .clear, radius: 5)
              Capsule()
                .fill(Color.black.opacity(0.55))
                .frame(width: 10, height: 26)
                .overlay(
                  Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.6), .gray.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 6, height: 12)
                    .offset(y: isPlaying ? -5 : 5)
                    .animation(.spring(response: 0.35, dampingFraction: 0.78), value: isPlaying)
                )
            }
            Spacer()
            ZStack {
              RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.48))
                .frame(width: 13, height: 38)
              RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Color(white: 0.78), Color(white: 0.36)], startPoint: .top, endPoint: .bottom))
                .frame(width: 11, height: 12)
                .offset(y: isPlaying ? -5 : 7)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isPlaying)
            }
          }
        }
        .padding(side * 0.065)

        // 2. Machined recessed aluminum platter well (shifted slightly left so right gimbal sits cleanly outside!)
        Circle()
          .fill(Color.black.opacity(0.54))
          .frame(width: discSize + 10, height: discSize + 10)
          .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1.4))
          .position(x: discCenterX, y: discCenterY)

        // 3. Spinning glossy black vinyl record with concentric grooves + rotating album label + chrome spindle
        TimelineView(.animation(paused: !isPlaying)) { timeline in
          let elapsed = isPlaying ? timeline.date.timeIntervalSince(playStartedAt) : 0
          let angle = baseAngle + elapsed * 36.0
          ZStack {
            Circle()
              .fill(
                RadialGradient(
                  colors: [Color(white: 0.14), Color(white: 0.05), Color(white: 0.09), Color(white: 0.035)],
                  center: .center,
                  startRadius: discSize * 0.18,
                  endRadius: discSize * 0.5
                )
              )

            ForEach(0..<10, id: \.self) { i in
              let inset = CGFloat(i) * (discSize * 0.026) + discSize * 0.028
              Circle()
                .stroke(Color.white.opacity(i % 2 == 0 ? 0.075 : 0.035), lineWidth: 0.65)
                .frame(width: discSize - inset * 2, height: discSize - inset * 2)
            }

            AngularGradient(
              colors: [.clear, .white.opacity(0.16), .clear, .clear, .white.opacity(0.12), .clear],
              center: .center
            )
            .clipShape(Circle())

            // Crisp circular center album art label
            RemoteArtwork(url: artworkURL, cornerRadius: discSize * 0.22)
              .frame(width: discSize * 0.42, height: discSize * 0.42)
              .clipShape(Circle())
              .overlay(Circle().stroke(Color.black.opacity(0.65), lineWidth: 2.5))
              .overlay(Circle().stroke(accent.opacity(0.45), lineWidth: 0.9))

            // Machined brushed aluminum center spindle with centered specular highlight
            ZStack {
              Circle()
                .fill(
                  RadialGradient(
                    colors: [Color(white: 0.94), Color(white: 0.56), Color(white: 0.24)],
                    center: .center,
                    startRadius: 1,
                    endRadius: discSize * 0.032
                  )
                )
                .frame(width: discSize * 0.060, height: discSize * 0.060)
              Circle()
                .stroke(Color.black.opacity(0.45), lineWidth: 1)
                .frame(width: discSize * 0.060, height: discSize * 0.060)
            }
          }
          .frame(width: discSize, height: discSize)
          .rotationEffect(.degrees(angle))
        }
        .shadow(color: .black.opacity(0.62), radius: 14, y: 6)
        .position(x: discCenterX, y: discCenterY)

        // 4. Precision corner gimbal + articulated tonearm (100% outside platter, stylus tracks outer->inner groove!)
        let pivotX = side * 0.87
        let pivotY = side * 0.165
        let clampedP = min(1.0, max(0.0, progress))
        // Paused: parked cleanly off vinyl (-2°); Playing: 15° (outer vinyl edge) -> 30° (inner groove, never hits label!)
        let armAngle: Double = isPlaying ? (15.0 + clampedP * 15.0) : -2.0
        let armLen = side * 0.52

        // Tonearm assembly pivoted directly at (pivotX, pivotY)
        ZStack {
          // Machined beveled counterweight behind pivot
          RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.80), Color(white: 0.34), Color(white: 0.56)], startPoint: .leading, endPoint: .trailing))
            .overlay(RoundedRectangle(cornerRadius: 3.5).stroke(Color.white.opacity(0.30), lineWidth: 0.6))
            .frame(width: 14, height: 18)
            .offset(y: -side * 0.075)

          // Brushed metallic arm tube extending downward from pivot
          Capsule()
            .fill(LinearGradient(colors: [Color(white: 0.90), Color(white: 0.45), Color(white: 0.74)], startPoint: .leading, endPoint: .trailing))
            .frame(width: 5, height: armLen)
            .shadow(color: .black.opacity(0.55), radius: 5, x: -3, y: 4)
            .offset(y: armLen * 0.46)

          // Angled matte headshell + amber stylus cartridge at tip
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
            .overlay(
              RoundedRectangle(cornerRadius: 1.5)
                .fill(Theme.amber)
                .frame(width: 8, height: 2.8)
                .offset(y: 9)
            )
            .frame(width: 13, height: 25)
            .rotationEffect(.degrees(18))
            .offset(x: -5, y: armLen * 0.92)
        }
        .rotationEffect(.degrees(armAngle))
        .position(x: pivotX, y: pivotY)
        .animation(.spring(response: 0.65, dampingFraction: 0.78), value: isPlaying)
        .animation(.linear(duration: 0.2), value: clampedP)

        // Concentric metallic gimbal bearing collar + center screw cap (cleanly in plinth corner)
        ZStack {
          Circle()
            .fill(
              RadialGradient(
                colors: [Color(white: 0.42), Color(white: 0.18), Color(white: 0.10)],
                center: .topLeading,
                startRadius: 2,
                endRadius: side * 0.07
              )
            )
            .frame(width: side * 0.13, height: side * 0.13)
            .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1.1))
          Circle()
            .stroke(Color.white.opacity(0.18), lineWidth: 1.0)
            .frame(width: side * 0.088, height: side * 0.088)
          Circle()
            .fill(
              RadialGradient(
                colors: [Color(white: 0.85), Color(white: 0.35)],
                center: .topLeading,
                startRadius: 0,
                endRadius: side * 0.025
              )
            )
            .frame(width: side * 0.042, height: side * 0.042)
        }
        .shadow(color: .black.opacity(0.55), radius: 8, y: 4)
        .position(x: pivotX, y: pivotY)
      }
      .frame(width: side, height: side)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .onChange(of: isPlaying) { was, now in
      if now { playStartedAt = Date() }
      else if was { baseAngle += Date().timeIntervalSince(playStartedAt) * 36.0 }
    }
  }
}

struct CassetteDeckView: View {
  let title: String
  let artist: String
  let artworkURL: String
  let isPlaying: Bool
  let progress: Double
  let accent: Color

  @State private var baseSpin: Double = 0
  @State private var startedAt: Date = Date()

  var body: some View {
    GeometryReader { geo in
      let w = min(geo.size.width, 336)
      let h = min(geo.size.height - 54, w * 0.68)
      let clampedP = min(1.0, max(0.0, progress))

      VStack(spacing: 20) {
        // Brushed dark aluminum cassette deck housing
        ZStack {
          RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(
              LinearGradient(
                colors: [Color(red: 0.19, green: 0.20, blue: 0.24), Color(red: 0.10, green: 0.11, blue: 0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .overlay(
              RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Theme.glassStroke, lineWidth: 1.1)
            )
            .shadow(color: .black.opacity(0.58), radius: 24, y: 12)

          // Detailed molded Cassette Shell
          ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
              .fill(LinearGradient(colors: [Color(white: 0.14), Color(white: 0.065)], startPoint: .top, endPoint: .bottom))
              .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 0.9))

            // 4 tiny recessed metallic corner screws
            VStack {
              HStack { screwDot; Spacer(); screwDot }
              Spacer()
              HStack { screwDot; Spacer(); screwDot }
            }
            .padding(7)

            VStack(spacing: 0) {
              // Printed cream paper cassette label
              ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                  .fill(Color(red: 0.95, green: 0.935, blue: 0.895))

                VStack(spacing: 0) {
                  HStack {
                    Text("A")
                      .font(Theme.font(10.5, .heavy))
                      .foregroundStyle(Color.black.opacity(0.78))
                      .padding(.horizontal, 6).padding(.vertical, 2)
                      .background(Color.black.opacity(0.09), in: RoundedRectangle(cornerRadius: 4))
                    Spacer()
                    Text(title.uppercased())
                      .font(Theme.font(11.5, .heavy))
                      .tracking(0.6)
                      .foregroundStyle(Color(white: 0.09))
                      .lineLimit(1)
                    Spacer()
                    Text("90")
                      .font(Theme.font(10.5, .bold))
                      .foregroundStyle(Color.black.opacity(0.55))
                  }
                  .padding(.horizontal, 12)
                  .padding(.top, 8)
                  .padding(.bottom, 6)

                  // Signature Lume warm amber→coral stripe band + translucent smoked acrylic reel bay
                  ZStack {
                    LinearGradient(colors: [Theme.amber, Theme.coral], startPoint: .leading, endPoint: .trailing)

                    TimelineView(.animation(paused: !isPlaying)) { timeline in
                      let elapsed = isPlaying ? timeline.date.timeIntervalSince(startedAt) : 0
                      let spin = baseSpin + elapsed * 72.0
                      ZStack {
                        // Recessed dark smoked-acrylic cassette window showing shifting magnetic tape coils!
                        Capsule()
                          .fill(Color(red: 0.06, green: 0.055, blue: 0.055))
                          .overlay(Capsule().stroke(Color.white.opacity(0.24), lineWidth: 0.9))

                        HStack(spacing: 14) {
                          CassetteSpool(angle: -spin, tapeRadius: max(0.42, 0.96 - clampedP * 0.50))
                          // Translucent tape bridge showing wound magnetic ribbon
                          ZStack {
                            RoundedRectangle(cornerRadius: 5)
                              .fill(Color.black.opacity(0.72))
                            HStack(spacing: 4) {
                              Capsule().fill(Color.white.opacity(0.26)).frame(width: 2, height: 14)
                              Capsule().fill(Theme.amber.opacity(0.85)).frame(width: 2, height: 18)
                              Capsule().fill(Color.white.opacity(0.26)).frame(width: 2, height: 14)
                            }
                          }
                          .frame(width: 44, height: 24)
                          CassetteSpool(angle: -spin * 1.12, tapeRadius: min(0.96, 0.44 + clampedP * 0.50))
                        }
                        .padding(.horizontal, 12)

                        // Glossy diagonal acrylic window reflection
                        LinearGradient(
                          colors: [Color.white.opacity(0.22), Color.clear, Color.white.opacity(0.06)],
                          startPoint: .topLeading,
                          endPoint: .bottomTrailing
                        )
                        .clipShape(Capsule())
                        .allowsHitTesting(false)
                      }
                      .frame(width: 196, height: 48)
                    }
                  }
                  .frame(height: 58)

                  HStack {
                    Text(artist)
                      .font(Theme.font(10.5, .bold))
                      .foregroundStyle(Color(white: 0.22))
                      .lineLimit(1)
                    Spacer()
                    Text("LUME STEREO")
                      .font(Theme.font(8.5, .heavy))
                      .tracking(1.4)
                      .foregroundStyle(Color.black.opacity(0.45))
                  }
                  .padding(.horizontal, 12)
                  .padding(.vertical, 5)
                }
              }
              .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
              .padding(.horizontal, 14)
              .padding(.top, 12)

              Spacer(minLength: 4)

              // Bottom trapezoidal tape head guide
              HStack(spacing: 22) {
                Circle().fill(Color.black.opacity(0.75)).frame(width: 9, height: 9)
                RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.7)).frame(width: 44, height: 6)
                Circle().fill(Color.black.opacity(0.75)).frame(width: 9, height: 9)
              }
              .padding(.horizontal, 26)
              .padding(.vertical, 6)
              .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
              .padding(.bottom, 8)
            }

            LinearGradient(
              colors: [Color.white.opacity(0.13), Color.clear, Color.clear],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .allowsHitTesting(false)
          }
          .padding(14)
        }
        .frame(width: w, height: h)

        // Precision Analog Tape Counter Ruler (0..9) with sleek inline glowing slider (Ref #3 style!)
        VStack(spacing: 6) {
          HStack(spacing: 0) {
            ForEach(0..<10, id: \.self) { n in
              VStack(spacing: 3) {
                Text("\(n)")
                  .font(Theme.font(9.5, .bold))
                  .foregroundStyle(Theme.muted)
                  .monospacedDigit()
                Rectangle()
                  .fill(Color.white.opacity(0.28))
                  .frame(width: 1, height: 6)
              }
              .frame(maxWidth: .infinity)
            }
          }
          GeometryReader { g in
            let inset = g.size.width / 20.0
            let span = max(1, g.size.width - inset * 2)
            let indicatorW: CGFloat = 18
            let travel = max(0, span - indicatorW)
            ZStack(alignment: .leading) {
              // Recessed metallic groove track spanning cleanly from 0 to 9
              Capsule()
                .fill(Color.black.opacity(0.55))
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.7))
                .frame(width: span, height: 5)
                .offset(x: inset)

              // Soft progress fill inside groove
              Capsule()
                .fill(Theme.amber.opacity(0.38))
                .frame(width: max(indicatorW, indicatorW + travel * clampedP), height: 5)
                .offset(x: inset)

              // Sleek horizontal glowing coral tape position block sliding inline inside the groove
              Capsule()
                .fill(Theme.aurora)
                .frame(width: indicatorW, height: 5)
                .shadow(color: Theme.coral.opacity(0.75), radius: 5)
                .offset(x: inset + travel * clampedP)
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .leading)
          }
          .frame(height: 10)
        }
        .frame(width: w - 8)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .onChange(of: isPlaying) { was, now in
      if now { startedAt = Date() }
      else if was { baseSpin += Date().timeIntervalSince(startedAt) * 72.0 }
    }
  }

  private var screwDot: some View {
    Circle()
      .fill(RadialGradient(colors: [Color(white: 0.45), Color(white: 0.14)], center: .topLeading, startRadius: 0, endRadius: 3))
      .frame(width: 5.5, height: 5.5)
      .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 0.5))
  }
}

private struct CassetteSpool: View {
  let angle: Double
  let tapeRadius: Double

  var body: some View {
    ZStack {
      // Visible dark brown-umber wound magnetic tape mass with subtle grooves
      Circle()
        .fill(
          RadialGradient(
            colors: [Color(red: 0.24, green: 0.16, blue: 0.12), Color(red: 0.15, green: 0.10, blue: 0.08)],
            center: .center,
            startRadius: 11,
            endRadius: 24
          )
        )
        .frame(width: 46 * tapeRadius, height: 46 * tapeRadius)
        .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.6))

      // White 6-tooth precision cassette hub
      ZStack {
        Circle().fill(Color(white: 0.93)).frame(width: 23, height: 23)
        ForEach(0..<6, id: \.self) { i in
          Rectangle()
            .fill(Color(white: 0.10))
            .frame(width: 2.8, height: 5.5)
            .offset(y: -7.5)
            .rotationEffect(.degrees(Double(i) * 60))
        }
        Circle().fill(Color(white: 0.09)).frame(width: 10.5, height: 10.5)
      }
      .rotationEffect(.degrees(angle))
    }
    .frame(width: 46, height: 46)
    .clipped()
  }
}
