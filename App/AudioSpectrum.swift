import Foundation
import AVFoundation
import Accelerate
import MediaToolbox
import Combine
import os

// MARK: - AudioSpectrum
//
// Analisador de espectro REAL (FFT 1024 + 24 bandas log) alimentado por um
// MTAudioProcessingTap no AVPlayerItem. Funciona com MP4/AAC progressivo e
// arquivos locais; em HLS (sem faixa de áudio acessível) fica isLive = false.
//
// Uso:
//   AudioSpectrum.shared.attach(to: item)   // a cada nova AVPlayerItem
//   AudioSpectrum.shared.detach()           // ao parar
//   @ObservedObject var spectrum = AudioSpectrum.shared  // bands, level, isLive

@MainActor
final class AudioSpectrum: ObservableObject {
  static let shared = AudioSpectrum()
  nonisolated static let bandCount = 24

  @Published private(set) var bands: [Float]
  @Published private(set) var level: Float = 0
  @Published private(set) var isLive: Bool = false

  private var context: SpectrumTapContext?
  private weak var attachedItem: AVPlayerItem?
  private var generation = 0
  private var timer: Timer?
  private var smoothed: [Float]
  private var smoothedLevel: Float = 0
  private var lastTick: UInt64 = 0
  private var currentEQGains: [Float] = [0, 0, 0, 0, 0]

  private static let attackTau: Float = 0.060
  private static let releaseTau: Float = 0.220
  private static let freshNs: UInt64 = 120_000_000    // além disso o alvo cai para 0
  private static let liveNs: UInt64 = 500_000_000     // isLive = false depois disso

  private init() {
    let zeros = [Float](repeating: 0, count: AudioSpectrum.bandCount)
    self.bands = zeros
    self.smoothed = zeros
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

  // MARK: Tap

  private func releaseCurrent() {
    if let item = attachedItem { item.audioMix = nil }
    attachedItem = nil
    context?.deactivate()
    context = nil
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
        let status = MTAudioProcessingTapGetSourceAudio(
          tap, numberFrames, bufferList, flagsOut, nil, numberFramesOut)
        guard status == noErr else { return }
        let ctx = Unmanaged<SpectrumTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
        ctx.process(bufferList: bufferList, frames: numberFramesOut.pointee)
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
    context = ctx
    lastTick = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    startTimer()
  }

  // MARK: Timer / suavização

  private func startTimer() {
    guard timer == nil else { return }
    let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  private func resetOutputs() {
    stopTimer()
    let zeros = [Float](repeating: 0, count: AudioSpectrum.bandCount)
    smoothed = zeros
    smoothedLevel = 0
    if bands != zeros { bands = zeros }
    if level != 0 { level = 0 }
    if isLive { isLive = false }
  }

  private func tick() {
    let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    let dt = Float(min(max(Double(now &- lastTick) / 1e9, 0.005), 0.1))
    lastTick = now

    var target = [Float](repeating: 0, count: AudioSpectrum.bandCount)
    var targetLevel: Float = 0
    var live = false

    if let ctx = context {
      let snap = ctx.snapshot(into: &target)
      if snap.hasData {
        let age = now &- snap.time
        live = age < AudioSpectrum.liveNs
        if age < AudioSpectrum.freshNs {
          targetLevel = snap.level
        } else {
          for i in 0..<target.count { target[i] = 0 }
        }
      } else {
        for i in 0..<target.count { target[i] = 0 }
      }
    }

    let aAttack = 1 - expf(-dt / AudioSpectrum.attackTau)
    let aRelease = 1 - expf(-dt / AudioSpectrum.releaseTau)
    var allZero = true
    for i in 0..<smoothed.count {
      let cur = smoothed[i]
      let a = target[i] > cur ? aAttack : aRelease
      var v = cur + (target[i] - cur) * a
      if v < 0.003 { v = 0 }
      smoothed[i] = v
      if v > 0 { allZero = false }
    }
    let lcur = smoothedLevel
    var lv = lcur + (targetLevel - lcur) * (targetLevel > lcur ? aAttack : aRelease)
    if lv < 0.003 { lv = 0 }
    smoothedLevel = lv

    if smoothed != bands { bands = smoothed }
    if level != lv { level = lv }
    if isLive != live { isLive = live }

    // Sem tap ativo e tudo zerado: nada mais a animar.
    if context == nil && allZero && lv == 0 { stopTimer() }
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
  private var sinceLast = 0

  // estado publicado (protegido por lock)
  private let lock: UnsafeMutablePointer<os_unfair_lock>
  private let pubBands: UnsafeMutablePointer<Float>
  private var pubLevel: Float = 0
  private var pubTime: UInt64 = 0
  private var pubHasData = false
  private var active = true

  // Equalizador 5 bandas (60, 230, 910, 3600, 14000 Hz)
  private let eqLock: UnsafeMutablePointer<os_unfair_lock>
  private let eqGains: UnsafeMutablePointer<Float>
  private let eqCoeffs: UnsafeMutablePointer<Float>    // 5 bandas * 5 coeficientes (b0,b1,b2,a1,a2)
  private let eqStates: UnsafeMutablePointer<Float>    // até 4 canais * 5 bandas * 2 estados (z1,z2)
  private var eqBypass = true

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
    eqGains.deallocate(); eqCoeffs.deallocate(); eqStates.deallocate()
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
    sinceLast = 0
    ring.update(repeating: 0, count: SpectrumTapContext.ringSize)
    eqStates.update(repeating: 0, count: 40)
    computeBands()
    recomputeEQCoeffs()
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

  func process(bufferList: UnsafeMutablePointer<AudioBufferList>, frames: CMItemCount) {
    let n = Int(frames)
    guard n > 0, kind != .unsupported else { return }
    let abl = UnsafeMutableAudioBufferListPointer(bufferList)
    guard abl.count > 0 else { return }

    switch kind {
    case .float32:
      applyEQIfNeeded(abl, n)
      mix(abl, n, Float.self)
    case .int16: mix(abl, n, Int16.self)
    case .int32: mix(abl, n, Int32.self)
    case .unsupported: return
    }

    writeCount &+= n
    sinceLast += n
    if sinceLast >= SpectrumTapContext.hop && writeCount >= SpectrumTapContext.fftSize {
      sinceLast = 0
      analyze()
    }
  }

  @inline(__always)
  private func applyEQIfNeeded(_ abl: UnsafeMutableAudioBufferListPointer, _ n: Int) {
    os_unfair_lock_lock(eqLock)
    let bypass = eqBypass
    if bypass {
      os_unfair_lock_unlock(eqLock)
      return
    }
    var coeffs = [Float](repeating: 0, count: 25)
    for i in 0..<25 { coeffs[i] = eqCoeffs[i] }
    os_unfair_lock_unlock(eqLock)

    if interleaved {
      guard let raw = abl[0].mData else { return }
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
            p[idx] = min(1.0, max(-1.0, y))
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
            p[f] = min(1.0, max(-1.0, y))
          }
          eqStates[st] = z1
          eqStates[st + 1] = z2
        }
      }
    }
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

  private func analyze() {
    let n = SpectrumTapContext.fftSize
    let mask = SpectrumTapContext.ringSize - 1
    let start = (writeCount &- n) & mask

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

    let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    os_unfair_lock_lock(lock)
    if active {
      for i in 0..<nb { pubBands[i] = localBands[i] }
      pubLevel = level
      pubTime = now
      pubHasData = true
    }
    os_unfair_lock_unlock(lock)
  }

  // MARK: leitura (main)

  struct Snapshot { var level: Float; var time: UInt64; var hasData: Bool }

  func snapshot(into out: inout [Float]) -> Snapshot {
    let nb = SpectrumTapContext.bands
    os_unfair_lock_lock(lock)
    defer { os_unfair_lock_unlock(lock) }
    if pubHasData {
      for i in 0..<nb { out[i] = pubBands[i] }
    }
    return Snapshot(level: pubLevel, time: pubTime, hasData: pubHasData)
  }
}
