import AVFoundation
import UIKit

/// Efeitos sonoros sintetizados em código (sem arquivos de áudio) para a abertura/onboarding.
/// - "plink" de vidro (notas de uma escala pentatônica, sobem a cada toque),
/// - "whoosh" suave de transição,
/// - acorde suave de conclusão.
/// Volume baixo, categoria `.ambient` (respeita o botão de silencioso e não interrompe músicas de outros apps).
/// Se o Lume estiver tocando música, a sessão de áudio NÃO é alterada.
@MainActor
final class SoundFX {
  static let shared = SoundFX()

  enum Effect { case tap, select, deselect, whoosh, chord, error, success }

  private let sampleRate: Double = 44_100
  private let engine = AVAudioEngine()
  private var voices: [AVAudioPlayerNode] = []
  private var nextVoice = 0
  private var buffers: [String: AVAudioPCMBuffer] = [:]
  private var started = false
  private var previousCategory: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
  private var scaleIndex = 0
  private let masterVolume: Float = 0.42

  /// Escala pentatônica maior (C5…) para os toques ficarem melódicos.
  private let scale: [Double] = [523.25, 587.33, 659.25, 783.99, 880.00, 1046.50, 1174.66, 1318.51, 1567.98]

  private init() {}

  // MARK: Ciclo de vida

  /// Prepara o motor (idempotente). Chame ao abrir o onboarding.
  func begin() {
    guard !started else { return }
    let session = AVAudioSession.sharedInstance()
    // Só mexe na sessão se o Lume não estiver tocando música agora.
    if !AudioPlayer.shared.isPlaying {
      previousCategory = (session.category, session.mode, session.categoryOptions)
      try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
      try? session.setActive(true)
    }
    for _ in 0..<4 {
      let node = AVAudioPlayerNode()
      engine.attach(node)
      engine.connect(node, to: engine.mainMixerNode, format: format)
      voices.append(node)
    }
    engine.mainMixerNode.outputVolume = masterVolume
    engine.prepare()
    do {
      try engine.start()
      started = true
    } catch {
      started = false
    }
    prewarm()
  }

  /// Desliga o motor e devolve a sessão de áudio como estava (importante para o player do Lume).
  func end() {
    guard started else { return }
    voices.forEach { $0.stop() }
    engine.stop()
    for v in voices { engine.detach(v) }
    voices.removeAll()
    started = false
    if let p = previousCategory {
      let session = AVAudioSession.sharedInstance()
      try? session.setCategory(p.0, mode: p.1, options: p.2)
      try? session.setActive(true)
    }
    previousCategory = nil
    buffers.removeAll()
  }

  private var format: AVAudioFormat {
    AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
  }

  // MARK: Reprodução

  func play(_ effect: Effect) {
    if !started { begin() }
    guard started else { return }
    let buffer: AVAudioPCMBuffer?
    switch effect {
    case .tap:
      buffer = makeBuffer("tap") { self.plink(freq: 1318.51, length: 0.5, decay: 0.16) }
    case .select:
      let f = scale[scaleIndex % scale.count]
      scaleIndex += 1
      buffer = makeBuffer("sel\(scaleIndex % scale.count)") { self.plink(freq: f, length: 0.8, decay: 0.26) }
    case .deselect:
      buffer = makeBuffer("desel") { self.plink(freq: 392.0, length: 0.4, decay: 0.12, gain: 0.7) }
    case .whoosh:
      buffer = makeBuffer("whoosh") { self.whoosh() }
    case .chord:
      buffer = makeBuffer("chord") { self.chord() }
    case .error:
      buffer = makeBuffer("error") { self.errorTone() }
    case .success:
      buffer = makeBuffer("success") { self.successArp() }
    }
    guard let buffer, !voices.isEmpty else { return }
    let node = voices[nextVoice % voices.count]
    nextVoice += 1
    node.stop()
    node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    node.play()
  }

  /// Zera a escala melódica (ao entrar numa tela nova).
  func resetScale() { scaleIndex = 0 }

  private func prewarm() {
    for e in [Effect.tap, .select, .whoosh] { _ = bufferExists(e) }
  }

  private func bufferExists(_ e: Effect) -> Bool {
    switch e {
    case .tap: return makeBuffer("tap") { self.plink(freq: 1318.51, length: 0.5, decay: 0.16) } != nil
    case .whoosh: return makeBuffer("whoosh") { self.whoosh() } != nil
    default: return true
    }
  }

  private func makeBuffer(_ key: String, _ build: () -> [Float]) -> AVAudioPCMBuffer? {
    if let b = buffers[key] { return b }
    let mono = build()
    guard !mono.isEmpty,
          let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(mono.count)) else { return nil }
    buf.frameLength = AVAudioFrameCount(mono.count)
    let l = buf.floatChannelData![0]
    let r = buf.floatChannelData![1]
    for i in 0..<mono.count { l[i] = mono[i]; r[i] = mono[i] }
    buffers[key] = buf
    return buf
  }

  // MARK: Síntese

  /// Plink de vidro: fundamental + parciais inarmônicos com decaimento exponencial.
  private func plink(freq: Double, length: Double, decay: Double, gain: Float = 1) -> [Float] {
    let n = Int(length * sampleRate)
    var out = [Float](repeating: 0, count: n)
    let partials: [(Double, Double, Double)] = [(1.0, 1.0, 1.0), (2.76, 0.30, 0.55), (5.40, 0.11, 0.30)]
    for i in 0..<n {
      let t = Double(i) / sampleRate
      let attack = min(1, t / 0.003)
      var s = 0.0
      for (ratio, amp, dk) in partials {
        s += amp * sin(2 * .pi * freq * ratio * t) * exp(-t / (decay * dk))
      }
      out[i] = Float(s * attack) * 0.30 * gain * Self.fadeOut(i, n)
    }
    return out
  }

  /// Sopro filtrado que sobe de timbre (transição entre telas).
  private func whoosh() -> [Float] {
    let length = 0.42
    let n = Int(length * sampleRate)
    var out = [Float](repeating: 0, count: n)
    var lp: Double = 0
    var seed: UInt32 = 0x1234ABCD
    for i in 0..<n {
      let t = Double(i) / Double(n)
      seed = seed &* 1664525 &+ 1013904223
      let noise = Double(Int32(bitPattern: seed)) / Double(Int32.max)
      let cutoff = 0.02 + 0.22 * sin(.pi * t) // abre e fecha
      lp += cutoff * (noise - lp)
      let env = sin(.pi * t) * sin(.pi * t)
      out[i] = Float(lp * env * 0.55) * Self.fadeOut(i, n)
    }
    return out
  }

  /// Acorde suave (Cmaj9) com ataque lento e cauda longa.
  private func chord() -> [Float] {
    let length = 2.2
    let n = Int(length * sampleRate)
    var out = [Float](repeating: 0, count: n)
    let freqs: [Double] = [261.63, 329.63, 392.00, 493.88, 587.33, 783.99]
    for i in 0..<n {
      let t = Double(i) / sampleRate
      let env = min(1, t / 0.07) * exp(-t / 0.95)
      var s = 0.0
      for (k, f) in freqs.enumerated() {
        let delay = Double(k) * 0.045
        let tt = max(0, t - delay)
        let e = tt > 0 ? min(1, tt / 0.05) : 0
        s += e * (sin(2 * .pi * f * t) + 0.25 * sin(2 * .pi * f * 2 * t)) / Double(freqs.count)
      }
      out[i] = Float(s * env) * 0.55 * Self.fadeOut(i, n)
    }
    return out
  }

  /// Dois tons graves curtos (erro suave).
  private func errorTone() -> [Float] {
    let length = 0.34
    let n = Int(length * sampleRate)
    var out = [Float](repeating: 0, count: n)
    for i in 0..<n {
      let t = Double(i) / sampleRate
      let f = t < 0.14 ? 233.08 : 196.0
      let local = t < 0.14 ? t : t - 0.14
      let env = min(1, local / 0.004) * exp(-local / 0.09)
      out[i] = Float(sin(2 * .pi * f * t) * env) * 0.28 * Self.fadeOut(i, n)
    }
    return out
  }

  /// Arpejo ascendente curto (código aceito).
  private func successArp() -> [Float] {
    let notes: [Double] = [523.25, 659.25, 783.99, 1046.50]
    let length = 1.3
    let n = Int(length * sampleRate)
    var out = [Float](repeating: 0, count: n)
    for (k, f) in notes.enumerated() {
      let start = Int(Double(k) * 0.085 * sampleRate)
      let tone = plink(freq: f, length: 0.9, decay: 0.3)
      for j in 0..<tone.count where start + j < n { out[start + j] += tone[j] * 0.8 }
    }
    return out
  }

  private static func fadeOut(_ i: Int, _ n: Int) -> Float {
    let tail = 600
    return i > n - tail ? Float(n - i) / Float(tail) : 1
  }
}
