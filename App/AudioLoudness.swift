import Foundation
import Accelerate

// MARK: - Áudio 5.2 (contrato, seção C)
//
// • "Volume igual entre as músicas": ganho = -loudnessDb (YouTube `playerConfig.audioConfig.loudnessDb`),
//   limitado a [-12, +6] dB; sem dado → 0 dB. A troca de ganho usa rampa de ~300 ms (sem estalo).
// • "Limitador de pico": suave em -1 dBFS (attack ~1 ms, release ~100 ms). Roda sempre que há ganho
//   positivo (normalização) ou o equalizador está ativo.
// • "Pular silêncio": a thread de áudio só mede o nível (RMS por bloco); quem decide é o AudioPlayer.
//
// Este arquivo só tem matemática pura e armazenamento — nada aqui depende de AVFoundation, então o
// autoteste (`-LMSelfTest`) cobre tudo sem simulador.

enum AudioPrefs {
  static let normalizeKey = "lume.audio.normalize"
  static let skipSilenceKey = "lume.audio.skipSilence"

  /// Volume igual entre as músicas — LIGADO por padrão.
  static var normalizeEnabled: Bool {
    UserDefaults.standard.object(forKey: normalizeKey) as? Bool ?? true
  }
  /// Pular silêncio (começo e fim da faixa) — DESLIGADO por padrão.
  static var skipSilenceEnabled: Bool {
    UserDefaults.standard.bool(forKey: skipSilenceKey)
  }
}

enum LoudnessMath {
  static let minGainDb = -12.0
  static let maxGainDb = 6.0
  static let ceilingDb: Float = -1.0
  static let silenceDb: Float = -50.0

  /// -1 dBFS em amplitude linear (≈ 0,8913).
  static let ceilingLinear: Float = powf(10, ceilingDb / 20)

  /// loudnessDb do YouTube (positivo = faixa mais alta que a referência) → ganho em dB a aplicar.
  static func gainDb(forLoudnessDb loudness: Double?) -> Double {
    guard let loudness, loudness.isFinite else { return 0 }
    return min(max(-loudness, minGainDb), maxGainDb)
  }

  static func linear(fromDb db: Double) -> Float {
    guard db.isFinite else { return 1 }
    return Float(pow(10.0, db / 20.0))
  }

  /// Nível RMS em dBFS de um bloco (piso em -120 dB).
  static func rmsDb(_ p: UnsafePointer<Float>, count: Int, stride: Int = 1) -> Float {
    guard count > 0 else { return -120 }
    var ss: Float = 0
    vDSP_svesq(p, vDSP_Stride(stride), &ss, vDSP_Length(count))
    return 10 * log10f(max(ss / Float(count), 1e-12))
  }
}

/// Ganho com rampa + limitador de pico (sem lookahead, sem alocação: roda na thread de áudio).
///
/// O limitador segue o pico com um envelope (attack 1 ms / release 100 ms) e reduz o ganho para manter o
/// envelope em -1 dBFS; uma trava final por amostra garante que NENHUMA amostra passe de -1 dBFS mesmo
/// durante os primeiros milissegundos do ataque.
struct LoudnessProcessor {
  private(set) var gain: Float = 1
  private var env: Float = 0
  private var gainCoef: Float = 0.0003
  private var attackCoef: Float = 0.02
  private var releaseCoef: Float = 0.0002

  /// Constante de tempo da rampa de ganho: ~98% do caminho em 300 ms.
  static let rampTau = 0.075
  static let attackSeconds = 0.001
  static let releaseSeconds = 0.100

  init(sampleRate: Double = 44100) { configure(sampleRate: sampleRate) }

  mutating func configure(sampleRate: Double) {
    let fs = max(8000, sampleRate)
    gainCoef = Float(1 - exp(-1 / (Self.rampTau * fs)))
    attackCoef = Float(1 - exp(-1 / (Self.attackSeconds * fs)))
    releaseCoef = Float(1 - exp(-1 / (Self.releaseSeconds * fs)))
  }

  /// Pula a rampa (início de faixa nova: não há sinal anterior para emendar).
  mutating func snap(to g: Float) { gain = g; env = 0 }

  /// O envelope do limitador ainda está acima do teto: não desligue o limitador agora.
  var limiterBusy: Bool { env > LoudnessMath.ceilingLinear * 0.98 }

  /// `ch[i]` aponta para a 1ª amostra do canal i; `stride` é o passo entre amostras (canais intercalados = nº de canais).
  mutating func process(_ ch: UnsafeMutablePointer<UnsafeMutablePointer<Float>>, channels c: Int, stride: Int,
                        frames n: Int, target: Float, limiter: Bool) {
    guard c > 0, n > 0 else { return }
    var g = gain
    var e = env
    let ceil = LoudnessMath.ceilingLinear
    let gc = gainCoef, ac = attackCoef, rc = releaseCoef
    for f in 0..<n {
      g += (target - g) * gc
      let idx = f * stride
      if limiter {
        var peak: Float = 0
        for k in 0..<c {
          let v = ch[k][idx] * g
          ch[k][idx] = v
          peak = max(peak, abs(v))
        }
        e += (peak - e) * (peak > e ? ac : rc)
        var lg: Float = e > ceil ? ceil / e : 1
        if peak > ceil { lg = min(lg, ceil / peak) }
        if lg < 1 { for k in 0..<c { ch[k][idx] *= lg } }
      } else {
        for k in 0..<c { ch[k][idx] *= g }
      }
    }
    if abs(target - g) < 1e-5 { g = target }
    gain = g
    env = e
  }
}

/// Estado da medição de silêncio feita na thread de áudio (tempos em segundos de mídia da faixa).
struct SilenceSnapshot {
  /// Segundos CONSECUTIVOS de silêncio (< -50 dBFS) vistos pelo tap até agora; 0 se o último bloco tinha som.
  var run: Double
  /// Início/fim (tempo de mídia) do trecho silencioso atual; NaN se o tap não informa o tempo.
  var since: Double
  var end: Double
  var levelDb: Float
  /// Segundos desde a última medição (alto = tap parado/pausado/HLS).
  var age: Double
}

/// Sonoridade (loudnessDb) por faixa, para valer também offline. Independente do LibraryStore.
/// `seen`: tudo que já foi resolvido (limitado); `pinned`: músicas baixadas (nunca é podado).
final class LoudnessStore: @unchecked Sendable {
  static let shared = LoudnessStore()
  private let lock = NSLock()
  private let seenKey = "lume.audio.loudnessSeen"
  private let pinnedKey = "lume.audio.loudnessPinned"
  private var seen: [String: Double]
  private var pinned: [String: Double]

  private init() {
    let d = UserDefaults.standard
    seen = (d.dictionary(forKey: seenKey) as? [String: Double]) ?? [:]
    pinned = (d.dictionary(forKey: pinnedKey) as? [String: Double]) ?? [:]
  }

  func db(for keys: String?...) -> Double? {
    lock.lock(); defer { lock.unlock() }
    for k in keys {
      guard let k else { continue }
      if let v = pinned[k] ?? seen[k] { return v }
    }
    return nil
  }

  func record(db: Double?, key: String) {
    guard let db, db.isFinite else { return }
    lock.lock()
    if seen[key] == db { lock.unlock(); return }
    seen[key] = db
    if seen.count > 1500 { for k in seen.keys.prefix(300) { seen.removeValue(forKey: k) } }
    let snapshot = seen
    lock.unlock()
    UserDefaults.standard.set(snapshot, forKey: seenKey)
  }

  /// Guarda de forma permanente (música baixada: o ganho precisa existir sem internet).
  func pin(db: Double?, keys: [String]) {
    guard let db, db.isFinite else { return }
    lock.lock()
    for k in keys { pinned[k] = db }
    let snapshot = pinned
    lock.unlock()
    UserDefaults.standard.set(snapshot, forKey: pinnedKey)
  }
}

/// Casos puros para o autoteste (`-LMSelfTest`), sem simulador.
enum LoudnessSelfTest {
  private static func run(_ p: inout LoudnessProcessor, _ a: inout [Float], target: Float, limiter: Bool, block: Int = 1024) {
    a.withUnsafeMutableBufferPointer { buf in
      var off = 0
      while off < buf.count {
        let m = min(block, buf.count - off)
        var ptr = buf.baseAddress! + off
        p.process(&ptr, channels: 1, stride: 1, frames: m, target: target, limiter: limiter)
        off += m
      }
    }
  }

  static func cases() -> [(String, Bool)] {
    var out: [(String, Bool)] = []

    // dB → ganho, com limites e dado ausente.
    out.append(("volume igual: loudness -3 dB → ganho +3 dB", LoudnessMath.gainDb(forLoudnessDb: -3) == 3))
    out.append(("volume igual: loudness +4,5 dB → ganho -4,5 dB", LoudnessMath.gainDb(forLoudnessDb: 4.5) == -4.5))
    out.append(("volume igual: ganho limitado a +6 dB", LoudnessMath.gainDb(forLoudnessDb: -20) == 6))
    out.append(("volume igual: ganho limitado a -12 dB", LoudnessMath.gainDb(forLoudnessDb: 30) == -12))
    out.append(("volume igual: sem dado → 0 dB", LoudnessMath.gainDb(forLoudnessDb: nil) == 0 && LoudnessMath.gainDb(forLoudnessDb: .nan) == 0))
    let lin6 = LoudnessMath.linear(fromDb: 6)
    out.append(("dB → linear: +6 dB ≈ 1,995 e -12 dB ≈ 0,251", abs(lin6 - 1.9953) < 0.001 && abs(LoudnessMath.linear(fromDb: -12) - 0.2512) < 0.001))

    // Limitador: senoide de fundo de escala com +6 dB de ganho nunca passa de -1 dBFS.
    let fs = 44100.0, n = 44100
    var sine = [Float](repeating: 0, count: n)
    for i in 0..<n { sine[i] = sinf(2 * .pi * 1000 * Float(i) / Float(fs)) }
    var proc = LoudnessProcessor(sampleRate: fs)
    proc.snap(to: 1.9953)
    run(&proc, &sine, target: 1.9953, limiter: true)
    var peak: Float = 0
    var tail: Float = 0
    for i in 0..<n {
      let a = abs(sine[i])
      peak = max(peak, a)
      if i > n / 2 { tail = max(tail, a) }
    }
    out.append(("limitador: senoide +6 dB não passa de -1 dBFS", peak <= LoudnessMath.ceilingLinear + 1e-4))
    out.append(("limitador: segura perto do teto (sem cortar demais)", tail > 0.8 && tail <= LoudnessMath.ceilingLinear + 1e-4))

    // Abaixo do teto o limitador é transparente.
    var quiet = [Float](repeating: 0, count: 4096)
    for i in 0..<quiet.count { quiet[i] = 0.5 * sinf(2 * .pi * 440 * Float(i) / Float(fs)) }
    let ref = quiet
    var p2 = LoudnessProcessor(sampleRate: fs)
    p2.snap(to: 1)
    run(&p2, &quiet, target: 1, limiter: true)
    var maxDiff: Float = 0
    for i in 0..<quiet.count { maxDiff = max(maxDiff, abs(quiet[i] - ref[i])) }
    out.append(("limitador: transparente abaixo de -1 dBFS", maxDiff < 1e-6))

    // Rampa: mudança de ganho é gradual (sem degrau) e termina no alvo.
    var dc = [Float](repeating: 0.1, count: 22050)   // 500 ms
    var p3 = LoudnessProcessor(sampleRate: fs)
    p3.snap(to: 1)
    run(&p3, &dc, target: 2, limiter: false)
    var maxStep: Float = 0
    for i in 1..<dc.count { maxStep = max(maxStep, abs(dc[i] - dc[i - 1])) }
    out.append(("rampa de ganho: sem degrau e chega ao alvo em ~300 ms", maxStep < 0.001 && abs(dc[dc.count - 1] - 0.2) < 0.005 && dc[0] < 0.11))

    // Silêncio: abaixo de -50 dBFS RMS.
    let zeros = [Float](repeating: 0, count: 2048)
    let hush = [Float](repeating: 0.001, count: 2048)      // -60 dBFS
    let music = [Float](repeating: 0.1, count: 2048)       // -20 dBFS
    let zDb = zeros.withUnsafeBufferPointer { LoudnessMath.rmsDb($0.baseAddress!, count: $0.count) }
    let hDb = hush.withUnsafeBufferPointer { LoudnessMath.rmsDb($0.baseAddress!, count: $0.count) }
    let mDb = music.withUnsafeBufferPointer { LoudnessMath.rmsDb($0.baseAddress!, count: $0.count) }
    out.append(("silêncio: -60 dBFS é silêncio, -20 dBFS não", zDb < LoudnessMath.silenceDb && hDb < LoudnessMath.silenceDb && mDb > LoudnessMath.silenceDb))

    // Armazém de sonoridade (música baixada).
    let store = LoudnessStore.shared
    let k = "selftest-\(UUID().uuidString)"
    store.pin(db: -2.5, keys: [k])
    out.append(("sonoridade: valor guardado volta pela chave (offline)", store.db(for: nil, k) == -2.5))
    return out
  }
}
