import Foundation
import AVFoundation
import Accelerate
import MediaToolbox
import Combine
import UIKit
import os

// MARK: - AudioSpectrum
//
// Analisador de espectro REAL (FFT 1024 + 24 bandas log + detector de batidas) alimentado por um
// MTAudioProcessingTap no AVPlayerItem. Funciona com M4A/MP4 progressivo e arquivos locais; em HLS
// (sem faixa de áudio acessível) fica isLive = false e `frame()` devolve uma simulação guiada pelo
// tempo da faixa (BPM estável, compasso de 4 tempos), nunca aleatória.
//
// 5.0 — modelo "pull" para não esquentar o aparelho:
//  • Só `isLive` é @Published (muda raramente). Bandas/nível/batida são LIDOS sob demanda por quem
//    desenha (TimelineView/Canvas) — antes um Timer de 30 Hz publicava `bands`, re-renderizando o
//    corpo inteiro de toda view que observava o objeto, inclusive em segundo plano.
//  • A FFT na thread de áudio só roda enquanto alguém leu o espectro nos últimos 0,6 s. Tela
//    bloqueada / app no fundo / palco sem visualizador ⇒ zero FFT (o EQ continua aplicado).
//
// Uso:
//   AudioSpectrum.shared.attach(to: item)              // a cada nova AVPlayerItem
//   let f = AudioSpectrum.shared.frame()               // dentro do TimelineView: bands, level, kick…
//   @ObservedObject var spectrum = AudioSpectrum.shared // só para `isLive`

/// Um quadro do analisador pronto para desenhar.
struct SpectrumFrame {
  var bands: [Float]
  /// Nível geral 0…1 (suavizado).
  var level: Float
  /// Pulso da batida 0…1: sobe na hora do bumbo e decai em ~170 ms.
  var kick: Float
  /// Energia dos graves 0…1 (suavizada).
  var bass: Float
  /// Contador de batidas (muda a cada batida detectada/simulada).
  var beat: Int
  /// Segundos desde a última batida.
  var sinceBeat: Double
  var live: Bool
}

@MainActor
final class AudioSpectrum: ObservableObject {
  static let shared = AudioSpectrum()
  nonisolated static let bandCount = 24

  @Published private(set) var isLive: Bool = false

  /// Compatibilidade: leitura sob demanda (não publica).
  var bands: [Float] { refresh(); return smoothed }
  var level: Float { refresh(); return smoothedLevel }
  var kick: Float { frame().kick }

  private var context: SpectrumTapContext?
  private weak var attachedItem: AVPlayerItem?
  private var generation = 0
  private var statusTimer: Timer?
  private var smoothed: [Float]
  private var scratch: [Float]
  private var smoothedLevel: Float = 0
  private var smoothedBass: Float = 0
  private var lastRefresh: UInt64 = 0
  private var currentEQGains: [Float] = [0, 0, 0, 0, 0]
  private var inBackground = false
  /// Ganho de saída em dB (volume igual entre as músicas). Reaplicado a cada tap novo.
  private var outputGainDb: Double = 0
  private var measureSilence = false

  // batida real
  private var seenBeatCount = -1
  private var kickStrength: Float = 0
  private var kickTimeNs: UInt64 = 0
  private var beatCounter = 0

  // simulação (HLS): relógio extrapolado entre os ticks de 0,15 s do PlaybackClock
  private var simAnchorSong: Double = 0
  private var simAnchorWall: Double = 0
  private var simLastClock: Double = -1

  private static let attackTau: Float = 0.050
  private static let releaseTau: Float = 0.200
  private static let kickDecay: Double = 0.17
  private static let freshNs: UInt64 = 160_000_000    // além disso o alvo cai para 0
  private static let liveNs: UInt64 = 700_000_000     // isLive = false depois disso

  private init() {
    let zeros = [Float](repeating: 0, count: AudioSpectrum.bandCount)
    self.smoothed = zeros
    self.scratch = zeros
    let nc = NotificationCenter.default
    nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.inBackground = true
        self?.stopStatusTimer()
      }
    }
    nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.inBackground = false
        if self.context != nil { self.startStatusTimer() }
      }
    }
  }

  // MARK: API

  func attach(to item: AVPlayerItem) {
    releaseCurrent()
    generation += 1
    let gen = generation
    let asset = item.asset
    attachedItem = item

    Task { [weak self, weak item] in
      let track: AVAssetTrack?
      do {
        track = try await asset.loadTracks(withMediaType: .audio).first
      } catch {
        track = nil
      }
      guard let self, let item, let track, self.generation == gen else { return }
      self.install(track: track, on: item)
    }
  }

  func detach() {
    generation += 1
    releaseCurrent()
    resetOutputs()
  }

  /// Atualiza os ganhos do equalizador de 5 bandas em dB: [60 Hz, 230 Hz, 910 Hz, 3.6 kHz, 14 kHz].
  func setEQGains(_ gains: [Float]) {
    var normalized = [Float](repeating: 0, count: 5)
    for i in 0..<min(5, gains.count) {
      normalized[i] = min(12, max(-12, gains[i]))
    }
    currentEQGains = normalized
    context?.setEQGains(normalized)
  }

  /// Ganho de saída (normalização) em dB. `immediate` = faixa nova (sem rampa); senão rampa de ~300 ms.
  /// O limitador de pico (-1 dBFS) entra sozinho quando o ganho é positivo ou o equalizador está ativo.
  func setOutputGain(db: Double, immediate: Bool) {
    outputGainDb = db
    context?.setGain(LoudnessMath.linear(fromDb: db), immediate: immediate)
  }

  /// Liga/desliga a medição de silêncio na thread de áudio (só mede; quem decide é o AudioPlayer).
  func setSilenceMeasuring(_ on: Bool) {
    measureSilence = on
    context?.setMeasureSilence(on)
  }

  /// Último estado de silêncio medido pelo tap (nil se não há tap ou nunca mediu).
  func silenceSnapshot() -> SilenceSnapshot? {
    guard let ctx = context else { return nil }
    return ctx.silence(now: clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
  }

  /// Quadro atual para desenhar. Chame dentro do TimelineView (a leitura também "acorda" a FFT).
  /// Sem espectro real, simula batidas guiadas pelo tempo da faixa.
  func frame() -> SpectrumFrame { frame(isPlaying: AudioPlayer.shared.isPlaying) }

  func frame(isPlaying: Bool) -> SpectrumFrame {
    refresh()
    let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    if isLive {
      let since = kickTimeNs == 0 ? 10 : Double(now &- kickTimeNs) / 1e9
      let k = kickStrength * Float(exp(-max(0, since) / AudioSpectrum.kickDecay))
      return SpectrumFrame(bands: smoothed, level: smoothedLevel, kick: k, bass: smoothedBass,
                           beat: beatCounter, sinceBeat: since, live: true)
    }
    return simulatedFrame(isPlaying: isPlaying)
  }

  // MARK: Tap

  private func releaseCurrent() {
    if let item = attachedItem { item.audioMix = nil }
    attachedItem = nil
    context?.deactivate()
    context = nil
    stopStatusTimer()
  }

  private func install(track: AVAssetTrack, on item: AVPlayerItem) {
    let ctx = SpectrumTapContext()
    let retained = Unmanaged.passRetained(ctx)   // balanceado no finalize do tap

    var callbacks = MTAudioProcessingTapCallbacks(
      version: kMTAudioProcessingTapCallbacksVersion_0,
      clientInfo: retained.toOpaque(),
      init: { _, clientInfo, tapStorageOut in
        tapStorageOut.pointee = clientInfo
      },
      finalize: { tap in
        Unmanaged<SpectrumTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
      },
      prepare: { tap, maxFrames, format in
        let ctx = Unmanaged<SpectrumTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
        ctx.prepare(format: format.pointee)
      },
      unprepare: { _ in },
      process: { tap, numberFrames, flags, bufferList, numberFramesOut, flagsOut in
        var range = CMTimeRange()
        let status = MTAudioProcessingTapGetSourceAudio(
          tap, numberFrames, bufferList, flagsOut, &range, numberFramesOut)
        guard status == noErr else { return }
        let ctx = Unmanaged<SpectrumTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
        let start = range.start.isNumeric ? range.start.seconds : Double.nan
        ctx.process(bufferList: bufferList, frames: numberFramesOut.pointee, start: start)
      }
    )

    var tapOut: MTAudioProcessingTap?
    let status = MTAudioProcessingTapCreate(
      kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tapOut)
    guard status == noErr, let tapRef = tapOut else {
      retained.release()   // o init/finalize nunca rodaram
      return
    }

    let params = AVMutableAudioMixInputParameters(track: track)
    params.audioTapProcessor = tapRef
    let mix = AVMutableAudioMix()
    mix.inputParameters = [params]
    item.audioMix = mix

    ctx.setEQGains(currentEQGains)
    ctx.setGain(LoudnessMath.linear(fromDb: outputGainDb), immediate: true)
    ctx.setMeasureSilence(measureSilence)
    context = ctx
    seenBeatCount = -1
    if !inBackground { startStatusTimer() }
  }

  // MARK: Status (2 Hz, só para isLive; parado em segundo plano)

  private func startStatusTimer() {
    guard statusTimer == nil else { return }
    let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.updateLiveFlag() }
    }
    t.tolerance = 0.2
    RunLoop.main.add(t, forMode: .common)
    statusTimer = t
    updateLiveFlag()
  }

  private func stopStatusTimer() {
    statusTimer?.invalidate()
    statusTimer = nil
  }

  private func updateLiveFlag() {
    let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    var live = false
    if let ctx = context {
      let st = ctx.status()
      live = st.supported && st.lastProcess != 0 && now &- st.lastProcess < AudioSpectrum.liveNs
    }
    if isLive != live { isLive = live }
    if AudioSpectrum.debugStatus {
      let line = "isLive=\(live) level=\(String(format: "%.2f", smoothedLevel)) beats=\(beatCounter) label=\(AudioPlayer.shared.currentBitrateLabel)\n"
      try? line.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("lm-status.txt"), atomically: true, encoding: .utf8)
    }
  }

  /// Depuração: `-LMDebugStatus` grava o estado do analisador em tmp/lm-status.txt (2 Hz).
  private static let debugStatus = ProcessInfo.processInfo.arguments.contains("-LMDebugStatus")

  private func resetOutputs() {
    stopStatusTimer()
    for i in 0..<smoothed.count { smoothed[i] = 0 }
    smoothedLevel = 0
    smoothedBass = 0
    kickStrength = 0
    if isLive { isLive = false }
  }

  /// Suaviza (attack/release) o último snapshot da thread de áudio. No máximo 1x a cada 6 ms.
  private func refresh() {
    let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    let elapsed = now &- lastRefresh
    guard elapsed > 6_000_000 else { return }
    let dt = Float(min(max(Double(elapsed) / 1e9, 0.005), 0.1))
    lastRefresh = now

    var targetLevel: Float = 0
    for i in 0..<scratch.count { scratch[i] = 0 }

    if let ctx = context {
      ctx.markDemand(now)
      let snap = ctx.snapshot(into: &scratch)
      if snap.hasData && now &- snap.time < AudioSpectrum.freshNs {
        targetLevel = snap.level
      } else {
        for i in 0..<scratch.count { scratch[i] = 0 }
      }
      if snap.beatCount != seenBeatCount {
        if seenBeatCount >= 0 && snap.beatCount > seenBeatCount {
          kickStrength = snap.beatStrength
          kickTimeNs = snap.beatTime
          beatCounter &+= 1
        }
        seenBeatCount = snap.beatCount
      }
    }

    let aAttack = 1 - expf(-dt / AudioSpectrum.attackTau)
    let aRelease = 1 - expf(-dt / AudioSpectrum.releaseTau)
    for i in 0..<smoothed.count {
      let cur = smoothed[i]
      let a = scratch[i] > cur ? aAttack : aRelease
      var v = cur + (scratch[i] - cur) * a
      if v < 0.003 { v = 0 }
      smoothed[i] = v
    }
    let lcur = smoothedLevel
    var lv = lcur + (targetLevel - lcur) * (targetLevel > lcur ? aAttack : aRelease)
    if lv < 0.003 { lv = 0 }
    smoothedLevel = lv
    let bassNow = (smoothed[0] + smoothed[1] + smoothed[2] + smoothed[3]) * 0.25
    smoothedBass += (bassNow - smoothedBass) * (bassNow > smoothedBass ? 0.6 : 0.18)
  }

  // MARK: Simulação plausível (HLS / sem tap)

  private func simulatedFrame(isPlaying: Bool) -> SpectrumFrame {
    let n = AudioSpectrum.bandCount
    let player = AudioPlayer.shared
    let wall = CACurrentMediaTime()
    let clockNow = PlaybackClock.shared.currentTime
    if clockNow != simLastClock {
      simLastClock = clockNow
      simAnchorSong = clockNow
      simAnchorWall = wall
    }
    let song = isPlaying ? simAnchorSong + min(0.5, wall - simAnchorWall) : simAnchorSong
    // BPM estável por faixa (92…127), derivado do id — cada música tem "seu" andamento.
    var h: UInt32 = 2166136261
    for b in (player.currentTrack?.id ?? "lume").utf8 { h = (h ^ UInt32(b)) &* 16777619 }
    let bpm = 92.0 + Double(h % 36)
    let spb = 60.0 / bpm
    let beatPos = max(0, song) / spb
    let beatIdx = Int(beatPos)
    let phase = beatPos - Double(beatIdx)
    let since = phase * spb
    let accent: Double = beatIdx % 4 == 0 ? 1.0 : (beatIdx % 2 == 0 ? 0.8 : 0.68)
    let amp: Double = isPlaying ? 1 : 0
    let kick = amp * accent * exp(-since / AudioSpectrum.kickDecay)
    // chimbal no contratempo, "frase" lenta de 8 tempos para dar dinâmica
    let hatPhase = (phase + 0.5).truncatingRemainder(dividingBy: 1) * spb
    let hat = amp * exp(-hatPhase / 0.06)
    let phrase = 0.75 + 0.25 * sin(beatPos * .pi / 8)
    var bands = [Float](repeating: 0, count: n)
    for i in 0..<n {
      let f = Double(i) / Double(n - 1)
      let tilt = 0.55 * (1 - f) + 0.12
      let low = f < 0.25 ? kick * (1 - f * 3) * 0.5 : 0
      let mid = 0.16 * (0.5 + 0.5 * sin(song * 1.7 + Double(i) * 0.9)) * (f > 0.2 && f < 0.75 ? 1 : 0.4)
      let high = f > 0.6 ? hat * 0.28 * f : 0
      bands[i] = Float(min(1, max(0.02, amp * (tilt * phrase + low + mid + high))))
    }
    let level = Float(amp * (0.45 + 0.25 * kick + 0.1 * phrase))
    let bass = Float(amp * (0.35 + 0.55 * kick))
    return SpectrumFrame(bands: bands, level: level, kick: Float(kick), bass: bass,
                         beat: beatIdx, sinceBeat: since, live: false)
  }
}

// MARK: - Contexto do tap (thread de áudio)

private protocol SpectrumSample {
  var asFloat: Float { get }
}
extension Float: SpectrumSample { @inline(__always) var asFloat: Float { self } }
extension Int16: SpectrumSample { @inline(__always) var asFloat: Float { Float(self) * (1.0 / 32768.0) } }
extension Int32: SpectrumSample { @inline(__always) var asFloat: Float { Float(self) * (1.0 / 2147483648.0) } }

private final class SpectrumTapContext: @unchecked Sendable {
  enum Kind { case float32, int16, int32, unsupported }

  static let fftSize = 1024
  static let log2n: vDSP_Length = 10
  static let ringSize = 8192            // potência de 2
  static let hop = 512
  static let bands = AudioSpectrum.bandCount

  // formato (definido no prepare; não concorre com process)
  private var kind: Kind = .unsupported
  private var channels = 2
  private var interleaved = false
  private var sampleRate: Double = 44100

  // buffers pré-alocados
  private let ring: UnsafeMutablePointer<Float>
  private let window: UnsafeMutablePointer<Float>
  private let frame: UnsafeMutablePointer<Float>
  private let realp: UnsafeMutablePointer<Float>
  private let imagp: UnsafeMutablePointer<Float>
  private let power: UnsafeMutablePointer<Float>
  private let db: UnsafeMutablePointer<Float>
  private let localBands: UnsafeMutablePointer<Float>
  private let bandLo: UnsafeMutablePointer<Int32>
  private let bandHi: UnsafeMutablePointer<Int32>    // hi < lo => interpolar em bandPos
  private let bandPos: UnsafeMutablePointer<Float>
  private let fftSetup: FFTSetup

  private var writeCount = 0
  private var analyzedUpTo = 0

  // detector de batidas (fluxo espectral nos graves + limiar adaptativo)
  private var prevBassE: Float = 0
  private var fluxMean: Float = 0
  private var fluxVar: Float = 0
  private var samplesSinceBeat = 1 << 30
  private var beatCountLocal = 0
  private var lastBeatStrength: Float = 0
  private var lastBeatTime: UInt64 = 0

  // estado publicado (protegido por lock)
  private let lock: UnsafeMutablePointer<os_unfair_lock>
  private let pubBands: UnsafeMutablePointer<Float>
  private var pubLevel: Float = 0
  private var pubTime: UInt64 = 0
  private var pubHasData = false
  private var active = true
  private var demandTime: UInt64 = 0        // última leitura da main (FFT só roda com demanda)
  private var lastProcess: UInt64 = 0       // último callback de áudio (para isLive)
  private var pubBeatCount = 0
  private var pubBeatStrength: Float = 0
  private var pubBeatTime: UInt64 = 0
  private static let demandNs: UInt64 = 600_000_000

  // Equalizador 5 bandas (60, 230, 910, 3600, 14000 Hz)
  private let eqLock: UnsafeMutablePointer<os_unfair_lock>
  private let eqGains: UnsafeMutablePointer<Float>
  private let eqCoeffs: UnsafeMutablePointer<Float>    // 5 bandas * 5 coeficientes (b0,b1,b2,a1,a2)
  private let eqStates: UnsafeMutablePointer<Float>    // até 4 canais * 5 bandas * 2 estados (z1,z2)
  private let eqLocal: UnsafeMutablePointer<Float>     // cópia dos coeficientes (sem alocar na thread de áudio)
  private var eqBypass = true

  // Ganho + limitador (flags simples: a main escreve, a thread de áudio lê — sem lock no caminho quente)
  private let dspFlags: UnsafeMutablePointer<Float>          // [0]=ganho alvo (linear) [1]=medir silêncio [2]=pular rampa
  private let chPtr: UnsafeMutablePointer<UnsafeMutablePointer<Float>>   // até 8 canais, preenchido por callback
  private var proc = LoudnessProcessor()

  // Medição de silêncio (estado da thread de áudio; publicado sob `lock`)
  private var silentRun = 0.0
  private var silentSince = Double.nan
  private var silentEnd = Double.nan
  private var lastSourceEnd = Double.nan
  private var pubSilentRun = 0.0
  private var pubSilentSince = Double.nan
  private var pubSilentEnd = Double.nan
  private var pubLevelDb: Float = -120
  private var pubSilenceTime: UInt64 = 0

  init() {
    let n = SpectrumTapContext.fftSize
    func alloc(_ c: Int) -> UnsafeMutablePointer<Float> {
      let p = UnsafeMutablePointer<Float>.allocate(capacity: c)
      p.initialize(repeating: 0, count: c)
      return p
    }
    ring = alloc(SpectrumTapContext.ringSize)
    window = alloc(n)
    frame = alloc(n)
    realp = alloc(n / 2)
    imagp = alloc(n / 2)
    power = alloc(n / 2 + 2)
    db = alloc(n / 2 + 2)
    localBands = alloc(SpectrumTapContext.bands)
    pubBands = alloc(SpectrumTapContext.bands)
    bandLo = UnsafeMutablePointer<Int32>.allocate(capacity: SpectrumTapContext.bands)
    bandHi = UnsafeMutablePointer<Int32>.allocate(capacity: SpectrumTapContext.bands)
    bandLo.initialize(repeating: 1, count: SpectrumTapContext.bands)
    bandHi.initialize(repeating: 1, count: SpectrumTapContext.bands)
    bandPos = alloc(SpectrumTapContext.bands)
    lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    lock.initialize(to: os_unfair_lock())
    eqLock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    eqLock.initialize(to: os_unfair_lock())
    eqGains = alloc(5)
    eqCoeffs = alloc(25)
    eqStates = alloc(4 * 5 * 2)
    eqLocal = alloc(25)
    dspFlags = alloc(4)
    dspFlags[0] = 1
    chPtr = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 8)
    fftSetup = vDSP_create_fftsetup(SpectrumTapContext.log2n, FFTRadix(kFFTRadix2))!
    vDSP_hann_window(window, vDSP_Length(n), Int32(vDSP_HANN_DENORM))
    computeBands()
    recomputeEQCoeffs()
  }

  deinit {
    vDSP_destroy_fftsetup(fftSetup)
    ring.deallocate(); window.deallocate(); frame.deallocate()
    realp.deallocate(); imagp.deallocate(); power.deallocate(); db.deallocate()
    localBands.deallocate(); pubBands.deallocate()
    bandLo.deallocate(); bandHi.deallocate(); bandPos.deallocate()
    eqGains.deallocate(); eqCoeffs.deallocate(); eqStates.deallocate(); eqLocal.deallocate()
    dspFlags.deallocate(); chPtr.deallocate()
    lock.deallocate(); eqLock.deallocate()
  }

  /// Chamado pela main ao soltar o contexto: o tap pode continuar vivo um instante.
  func deactivate() {
    os_unfair_lock_lock(lock)
    active = false
    pubHasData = false
    os_unfair_lock_unlock(lock)
  }

  // MARK: prepare (fora da thread de render)

  func prepare(format asbd: AudioStreamBasicDescription) {
    sampleRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 44100
    channels = max(1, Int(asbd.mChannelsPerFrame))
    let flags = asbd.mFormatFlags
    interleaved = (flags & kAudioFormatFlagIsNonInterleaved) == 0
    let isFloat = (flags & kAudioFormatFlagIsFloat) != 0
    if asbd.mFormatID != kAudioFormatLinearPCM {
      kind = .unsupported
    } else if isFloat && asbd.mBitsPerChannel == 32 {
      kind = .float32
    } else if !isFloat && asbd.mBitsPerChannel == 16 {
      kind = .int16
    } else if !isFloat && asbd.mBitsPerChannel == 32 {
      kind = .int32
    } else {
      kind = .unsupported
    }
    writeCount = 0
    analyzedUpTo = 0
    prevBassE = 0; fluxMean = 0; fluxVar = 0
    samplesSinceBeat = 1 << 30
    ring.update(repeating: 0, count: SpectrumTapContext.ringSize)
    eqStates.update(repeating: 0, count: 40)
    proc.configure(sampleRate: sampleRate)
    proc.snap(to: dspFlags[0])
    silentRun = 0; silentSince = .nan; silentEnd = .nan; lastSourceEnd = .nan
    computeBands()
    recomputeEQCoeffs()
  }

  func setGain(_ linear: Float, immediate: Bool) {
    dspFlags[0] = min(4, max(0.05, linear))
    if immediate { dspFlags[2] = 1 }
  }

  func setMeasureSilence(_ on: Bool) { dspFlags[1] = on ? 1 : 0 }

  func silence(now: UInt64) -> SilenceSnapshot? {
    os_unfair_lock_lock(lock)
    defer { os_unfair_lock_unlock(lock) }
    guard pubSilenceTime != 0 else { return nil }
    return SilenceSnapshot(run: pubSilentRun, since: pubSilentSince, end: pubSilentEnd, levelDb: pubLevelDb,
                           age: Double(now &- min(now, pubSilenceTime)) / 1e9)
  }

  func setEQGains(_ gains: [Float]) {
    os_unfair_lock_lock(eqLock)
    for i in 0..<5 { eqGains[i] = i < gains.count ? gains[i] : 0 }
    recomputeEQCoeffsLocked()
    os_unfair_lock_unlock(eqLock)
  }

  private func recomputeEQCoeffs() {
    os_unfair_lock_lock(eqLock)
    recomputeEQCoeffsLocked()
    os_unfair_lock_unlock(eqLock)
  }

  private func recomputeEQCoeffsLocked() {
    let freqs: [Double] = [60, 230, 910, 3600, 14000]
    let fs = max(8000.0, sampleRate)
    var activeAny = false
    for b in 0..<5 {
      let db = Double(eqGains[b])
      if abs(db) >= 0.05 { activeAny = true }
      let a = pow(10.0, db / 40.0)
      let w0 = 2.0 * .pi * min(freqs[b], fs * 0.45) / fs
      let cosW = cos(w0), sinW = sin(w0)
      let q = 1.0
      let alpha = sinW / (2.0 * q)
      let b0, b1, b2, a0, a1, a2: Double
      if b == 0 {
        let twoSqrtAAlpha = 2.0 * sqrt(a) * (sinW / 2.0 * sqrt(2.0))
        b0 = a * ((a + 1) - (a - 1) * cosW + twoSqrtAAlpha)
        b1 = 2 * a * ((a - 1) - (a + 1) * cosW)
        b2 = a * ((a + 1) - (a - 1) * cosW - twoSqrtAAlpha)
        a0 = (a + 1) + (a - 1) * cosW + twoSqrtAAlpha
        a1 = -2 * ((a - 1) + (a + 1) * cosW)
        a2 = (a + 1) + (a - 1) * cosW - twoSqrtAAlpha
      } else if b == 4 {
        let twoSqrtAAlpha = 2.0 * sqrt(a) * (sinW / 2.0 * sqrt(2.0))
        b0 = a * ((a + 1) + (a - 1) * cosW + twoSqrtAAlpha)
        b1 = -2 * a * ((a - 1) + (a + 1) * cosW)
        b2 = a * ((a + 1) + (a - 1) * cosW - twoSqrtAAlpha)
        a0 = (a + 1) - (a - 1) * cosW + twoSqrtAAlpha
        a1 = 2 * ((a - 1) - (a + 1) * cosW)
        a2 = (a + 1) - (a - 1) * cosW - twoSqrtAAlpha
      } else {
        b0 = 1 + alpha * a
        b1 = -2 * cosW
        b2 = 1 - alpha * a
        a0 = 1 + alpha / a
        a1 = -2 * cosW
        a2 = 1 - alpha / a
      }
      let base = b * 5
      eqCoeffs[base + 0] = Float(b0 / a0)
      eqCoeffs[base + 1] = Float(b1 / a0)
      eqCoeffs[base + 2] = Float(b2 / a0)
      eqCoeffs[base + 3] = Float(a1 / a0)
      eqCoeffs[base + 4] = Float(a2 / a0)
    }
    eqBypass = !activeAny
  }

  private func computeBands() {
    let n = SpectrumTapContext.fftSize
    let nb = SpectrumTapContext.bands
    let binHz = sampleRate / Double(n)
    let fMin = 40.0
    let fMax = min(16000.0, sampleRate * 0.5 * 0.97)
    let ratio = fMax / fMin
    let maxBin = n / 2 - 1
    for i in 0..<nb {
      let f0 = fMin * pow(ratio, Double(i) / Double(nb))
      let f1 = fMin * pow(ratio, Double(i + 1) / Double(nb))
      let lo = Int(ceil(f0 / binHz))
      let hi = Int(floor(f1 / binHz))
      bandLo[i] = Int32(min(max(lo, 1), maxBin))
      bandHi[i] = Int32(min(hi, maxBin))
      bandPos[i] = Float(sqrt(f0 * f1) / binHz)
    }
  }

  // MARK: process (thread de áudio — sem alocação)

  func process(bufferList: UnsafeMutablePointer<AudioBufferList>, frames: CMItemCount, start: Double) {
    let n = Int(frames)
    guard n > 0, kind != .unsupported else { return }
    let abl = UnsafeMutableAudioBufferListPointer(bufferList)
    guard abl.count > 0 else { return }

    let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    os_unfair_lock_lock(lock)
    lastProcess = now
    let wanted = demandTime != 0 && now &- demandTime < SpectrumTapContext.demandNs
    os_unfair_lock_unlock(lock)

    if kind == .float32 {
      measureSilenceIfNeeded(abl, n, start: start, now: now)   // nível da fonte, antes de EQ/ganho
      let eqApplied = applyEQIfNeeded(abl, n)
      applyLoudness(abl, n, eqApplied: eqApplied)
    }
    // Ninguém olhando (tela bloqueada, outro palco, app no fundo): nada de FFT.
    guard wanted else {
      analyzedUpTo = writeCount
      return
    }

    switch kind {
    case .float32: mix(abl, n, Float.self)
    case .int16: mix(abl, n, Int16.self)
    case .int32: mix(abl, n, Int32.self)
    case .unsupported: return
    }

    writeCount &+= n
    // Uma análise a cada 512 amostras (~86 Hz), mesmo que o callback traga 4096 de uma vez:
    // o detector de batidas precisa dessa resolução. Só a última janela publica as bandas.
    let hop = SpectrumTapContext.hop
    if writeCount - analyzedUpTo > SpectrumTapContext.ringSize - SpectrumTapContext.fftSize {
      analyzedUpTo = writeCount - SpectrumTapContext.ringSize + SpectrumTapContext.fftSize
    }
    while analyzedUpTo + hop <= writeCount {
      analyzedUpTo += hop
      guard analyzedUpTo >= SpectrumTapContext.fftSize else { continue }
      let lagSamples = writeCount - analyzedUpTo
      analyze(endingAt: analyzedUpTo, publish: analyzedUpTo + hop > writeCount, now: now,
              lagNs: UInt64(Double(lagSamples) / sampleRate * 1e9))
    }
  }

  func markDemand(_ t: UInt64) {
    os_unfair_lock_lock(lock)
    demandTime = t
    os_unfair_lock_unlock(lock)
  }

  struct Status { var supported: Bool; var lastProcess: UInt64 }

  func status() -> Status {
    os_unfair_lock_lock(lock)
    defer { os_unfair_lock_unlock(lock) }
    return Status(supported: kind != .unsupported && active, lastProcess: lastProcess)
  }

  @inline(__always)
  private func applyEQIfNeeded(_ abl: UnsafeMutableAudioBufferListPointer, _ n: Int) -> Bool {
    os_unfair_lock_lock(eqLock)
    let bypass = eqBypass
    if bypass {
      os_unfair_lock_unlock(eqLock)
      return false
    }
    let coeffs = eqLocal
    for i in 0..<25 { coeffs[i] = eqCoeffs[i] }
    os_unfair_lock_unlock(eqLock)

    if interleaved {
      guard let raw = abl[0].mData else { return false }
      let p = raw.assumingMemoryBound(to: Float.self)
      let c = min(4, max(1, Int(abl[0].mNumberChannels)))
      for ch in 0..<c {
        for b in 0..<5 {
          let cb = b * 5
          let b0 = coeffs[cb], b1 = coeffs[cb + 1], b2 = coeffs[cb + 2], a1 = coeffs[cb + 3], a2 = coeffs[cb + 4]
          let st = (ch * 5 + b) * 2
          var z1 = eqStates[st], z2 = eqStates[st + 1]
          for f in 0..<n {
            let idx = f * c + ch
            let x = p[idx]
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            p[idx] = y
          }
          eqStates[st] = z1
          eqStates[st + 1] = z2
        }
      }
    } else {
      let c = min(4, abl.count)
      for ch in 0..<c {
        guard let raw = abl[ch].mData else { continue }
        let p = raw.assumingMemoryBound(to: Float.self)
        for b in 0..<5 {
          let cb = b * 5
          let b0 = coeffs[cb], b1 = coeffs[cb + 1], b2 = coeffs[cb + 2], a1 = coeffs[cb + 3], a2 = coeffs[cb + 4]
          let st = (ch * 5 + b) * 2
          var z1 = eqStates[st], z2 = eqStates[st + 1]
          for f in 0..<n {
            let x = p[f]
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            p[f] = y
          }
          eqStates[st] = z1
          eqStates[st + 1] = z2
        }
      }
    }
    // Sem o corte duro por banda: o limitador (applyLoudness) roda sempre que o EQ está ativo.
    return true
  }

  /// Preenche `chPtr` com os canais do buffer (float32). Devolve (canais, passo entre amostras).
  @inline(__always)
  private func bindChannels(_ abl: UnsafeMutableAudioBufferListPointer) -> (Int, Int) {
    if interleaved {
      guard let raw = abl[0].mData else { return (0, 1) }
      let p = raw.assumingMemoryBound(to: Float.self)
      let c = min(8, max(1, Int(abl[0].mNumberChannels)))
      for ch in 0..<c { chPtr[ch] = p + ch }
      return (c, c)
    }
    var c = 0
    for b in 0..<min(8, abl.count) {
      guard let raw = abl[b].mData else { continue }
      chPtr[c] = raw.assumingMemoryBound(to: Float.self)
      c += 1
    }
    return (c, 1)
  }

  /// Ganho com rampa (volume igual) + limitador de pico em -1 dBFS. Sem alocação, sem lock.
  @inline(__always)
  private func applyLoudness(_ abl: UnsafeMutableAudioBufferListPointer, _ n: Int, eqApplied: Bool) {
    let target = dspFlags[0]
    if dspFlags[2] != 0 {
      dspFlags[2] = 0
      proc.snap(to: target)
    }
    let g = proc.gain
    let ramping = abs(target - g) > 1e-5
    let needLimiter = eqApplied || target > 1.0001 || g > 1.0001 || proc.limiterBusy
    if !needLimiter && !ramping && abs(g - 1) < 1e-5 { return }   // caminho comum: nada a fazer
    let (c, stride) = bindChannels(abl)
    guard c > 0 else { return }
    if !needLimiter && !ramping {
      // ganho constante (< 1): multiplicação vetorizada
      var gg = g
      for ch in 0..<c { vDSP_vsmul(chPtr[ch], vDSP_Stride(stride), &gg, chPtr[ch], vDSP_Stride(stride), vDSP_Length(n)) }
      return
    }
    proc.process(chPtr, channels: c, stride: stride, frames: n, target: target, limiter: needLimiter)
  }

  /// Mede o nível RMS do bloco (antes de EQ/ganho) e acompanha o trecho silencioso contínuo.
  /// `start` = tempo de mídia do 1º frame do bloco (NaN se o tap não informa).
  @inline(__always)
  private func measureSilenceIfNeeded(_ abl: UnsafeMutableAudioBufferListPointer, _ n: Int, start: Double, now: UInt64) {
    guard dspFlags[1] != 0 else { return }
    let (c, stride) = bindChannels(abl)
    guard c > 0 else { return }
    var total: Float = 0
    for ch in 0..<c {
      var ss: Float = 0
      vDSP_svesq(chPtr[ch], vDSP_Stride(stride), &ss, vDSP_Length(n))
      total += ss
    }
    let db = 10 * log10f(max(total / Float(n * c), 1e-12))
    let dur = Double(n) / sampleRate
    // Salto no tempo de mídia (seek / rebuffer): recomeça a contagem.
    if start.isFinite {
      if lastSourceEnd.isFinite && abs(start - lastSourceEnd) > 0.1 { silentRun = 0 }
      lastSourceEnd = start + dur
    }
    if db < LoudnessMath.silenceDb {
      if silentRun == 0 { silentSince = start }
      silentRun += dur
      silentEnd = start.isFinite ? start + dur : .nan
    } else {
      silentRun = 0
      silentSince = .nan
      silentEnd = start
    }
    os_unfair_lock_lock(lock)
    pubSilentRun = silentRun
    pubSilentSince = silentSince
    pubSilentEnd = silentEnd
    pubLevelDb = db
    pubSilenceTime = now
    os_unfair_lock_unlock(lock)
  }

  @inline(__always)
  private func mix<T: SpectrumSample>(_ abl: UnsafeMutableAudioBufferListPointer, _ n: Int, _: T.Type) {
    let mask = SpectrumTapContext.ringSize - 1
    let w = writeCount
    if interleaved {
      guard let raw = abl[0].mData else { return }
      let p = raw.assumingMemoryBound(to: T.self)
      let c = max(1, Int(abl[0].mNumberChannels))
      let inv = 1 / Float(c)
      for f in 0..<n {
        var s: Float = 0
        for ch in 0..<c { s += p[f * c + ch].asFloat }
        ring[(w &+ f) & mask] = s * inv
      }
    } else {
      let count = abl.count
      let inv = 1 / Float(count)
      var first = true
      for b in 0..<count {
        guard let raw = abl[b].mData else { continue }
        let p = raw.assumingMemoryBound(to: T.self)
        if first {
          for f in 0..<n { ring[(w &+ f) & mask] = p[f].asFloat * inv }
          first = false
        } else {
          for f in 0..<n { ring[(w &+ f) & mask] += p[f].asFloat * inv }
        }
      }
      if first { for f in 0..<n { ring[(w &+ f) & mask] = 0 } }
    }
  }

  private func analyze(endingAt end: Int, publish: Bool, now: UInt64, lagNs: UInt64) {
    let n = SpectrumTapContext.fftSize
    let mask = SpectrumTapContext.ringSize - 1
    let start = (end &- n) & mask

    // copia os últimos 1024 samples
    let first = min(n, SpectrumTapContext.ringSize - start)
    memcpy(frame, ring + start, first * MemoryLayout<Float>.size)
    if first < n { memcpy(frame + first, ring, (n - first) * MemoryLayout<Float>.size) }

    // nível geral (RMS)
    var rms: Float = 0
    vDSP_rmsqv(frame, 1, &rms, vDSP_Length(n))
    let rmsDb = 20 * log10f(max(rms, 1e-7))
    let level = min(max((rmsDb + 50) / 41, 0), 1)

    // janela Hann + FFT real
    vDSP_vmul(frame, 1, window, 1, frame, 1, vDSP_Length(n))
    var split = DSPSplitComplex(realp: realp, imagp: imagp)
    frame.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { cp in
      vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(n / 2))
    }
    vDSP_fft_zrip(fftSetup, &split, 1, SpectrumTapContext.log2n, FFTDirection(FFT_FORWARD))
    realp[0] = 0; imagp[0] = 0   // DC / Nyquist empacotados

    // |X|^2 normalizado: senoide de amplitude A => A^2 (0 dB = fundo de escala)
    let half = n / 2
    vDSP_zvmags(&split, 1, power, 1, vDSP_Length(half))
    var scale = 4.0 / Float(n * n)
    vDSP_vsmul(power, 1, &scale, power, 1, vDSP_Length(half))
    power[half] = power[half - 1]
    var eps: Float = 1e-12
    vDSP_vsadd(power, 1, &eps, power, 1, vDSP_Length(half + 1))
    // Detector de batidas: fluxo positivo da energia dos graves (~40–170 Hz) com limiar adaptativo
    // (média + 1,5 desvio) e intervalo mínimo de 0,27 s (≤ 220 BPM).
    let binHz = Float(sampleRate) / Float(n)
    let bLo = max(1, Int(40 / binHz)), bHi = max(bLo, min(half - 1, Int(170 / binHz)))
    var bassP: Float = 0
    for k in bLo...bHi { bassP += power[k] }
    let bassE = log10f(1 + 2000 * bassP)
    let flux = max(0, bassE - prevBassE)
    prevBassE = bassE
    samplesSinceBeat += SpectrumTapContext.hop
    let std = sqrtf(max(fluxVar, 1e-6))
    let thr = fluxMean + 1.5 * std + 0.015
    if flux > thr && samplesSinceBeat > Int(0.27 * sampleRate) && level > 0.08 {
      samplesSinceBeat = 0
      beatCountLocal &+= 1
      lastBeatStrength = min(1, max(0.35, (flux - fluxMean) / (4 * std + 0.02)))
      lastBeatTime = now &- min(lagNs, now)
    }
    let a: Float = 0.025   // ~0,45 s de memória a 86 Hz
    let d = flux - fluxMean
    fluxMean += a * d
    fluxVar = (1 - a) * (fluxVar + a * d * d)

    guard publish else {
      os_unfair_lock_lock(lock)
      if active {
        pubBeatCount = beatCountLocal
        pubBeatStrength = lastBeatStrength
        pubBeatTime = lastBeatTime
      }
      os_unfair_lock_unlock(lock)
      return
    }

    var one: Float = 1
    vDSP_vdbcon(power, 1, &one, db, 1, vDSP_Length(half + 1), 0)

    // 24 bandas: máximo em dB dentro da banda (ou interpolação nas bandas mais estreitas que 1 bin)
    let nb = SpectrumTapContext.bands
    for i in 0..<nb {
      let lo = Int(bandLo[i]), hi = Int(bandHi[i])
      var d: Float
      if hi >= lo {
        d = db[lo]
        var k = lo + 1
        while k <= hi { if db[k] > d { d = db[k] }; k += 1 }
      } else {
        let pos = bandPos[i]
        let i0 = min(max(Int(pos), 1), half - 1)
        let fr = min(max(pos - Float(i0), 0), 1)
        d = db[i0] * (1 - fr) + db[i0 + 1] * fr
      }
      // leve ênfase nos agudos (a música cai com a frequência)
      let t = Float(i) / Float(nb - 1)
      d += 3 + 14 * t
      localBands[i] = min(max((d + 65) / 55, 0), 1)
    }

    os_unfair_lock_lock(lock)
    if active {
      for i in 0..<nb { pubBands[i] = localBands[i] }
      pubLevel = level
      pubTime = now
      pubHasData = true
      pubBeatCount = beatCountLocal
      pubBeatStrength = lastBeatStrength
      pubBeatTime = lastBeatTime
    }
    os_unfair_lock_unlock(lock)
  }

  // MARK: leitura (main)

  struct Snapshot {
    var level: Float; var time: UInt64; var hasData: Bool
    var beatCount: Int; var beatStrength: Float; var beatTime: UInt64
  }

  func snapshot(into out: inout [Float]) -> Snapshot {
    let nb = SpectrumTapContext.bands
    os_unfair_lock_lock(lock)
    defer { os_unfair_lock_unlock(lock) }
    if pubHasData {
      for i in 0..<nb { out[i] = pubBands[i] }
    }
    return Snapshot(level: pubLevel, time: pubTime, hasData: pubHasData,
                    beatCount: pubBeatCount, beatStrength: pubBeatStrength, beatTime: pubBeatTime)
  }
}
