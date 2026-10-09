import Accelerate
import Foundation

/// Turns a stream of mono audio samples into a handful of smoothed, log-spaced frequency bands (0...1), for visualisers.
/// Pure DSP: no audio-capture code lives here, so it can be tested with synthetic tones.
public final class SpectrumAnalyzer {
    public let bandCount: Int
    public let sampleRate: Double
    public let fftSize: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]
    private var ring: [Float]
    private var filled = 0
    private var smoothed: [Float]
    private let edges: [Int]       // FFT bin edges for each band (bandCount + 1)

    public init(bands: Int = 24, sampleRate: Double = 48_000, fftSize: Int = 1024, minHz: Double = 40, maxHz: Double = 16_000) {
        bandCount = bands; self.sampleRate = sampleRate; self.fftSize = fftSize
        log2n = vDSP_Length(log2(Double(fftSize)).rounded())
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        ring = [Float](repeating: 0, count: fftSize)
        smoothed = [Float](repeating: 0, count: bands)
        var e: [Int] = []
        let half = fftSize / 2
        for i in 0...bands {
            let f = minHz * pow(maxHz / minHz, Double(i) / Double(bands))
            e.append(min(half - 1, max(1, Int((f / sampleRate * Double(fftSize)).rounded()))))
        }
        // Make sure every band owns at least one bin.
        for i in 1...bands where e[i] <= e[i - 1] { e[i] = min(half, e[i - 1] + 1) }
        edges = e
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Feed samples (any count); returns the latest bands. Attack is fast and release slow, so bars snap up and fall away.
    @discardableResult
    public func process(_ samples: [Float]) -> [Float] {
        for s in samples {
            ring[filled % fftSize] = s
            filled += 1
        }
        guard filled >= fftSize else { return smoothed }
        // Unroll the ring oldest-first, window it, and transform.
        var frame = [Float](repeating: 0, count: fftSize)
        let start = filled % fftSize
        for i in 0..<fftSize { frame[i] = ring[(start + i) % fftSize] * window[i] }
        let half = fftSize / 2
        var real = [Float](repeating: 0, count: half), imag = [Float](repeating: 0, count: half)
        var mags = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                frame.withUnsafeBufferPointer { fp in
                    fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(half))
            }
        }
        let norm = 2 / Float(fftSize)
        for b in 0..<bandCount {
            let lo = edges[b], hi = max(edges[b] + 1, edges[b + 1])
            var peak: Float = 0
            for k in lo..<min(hi, half) { peak = max(peak, mags[k] * norm) }
            // To decibels, mapped from [-70, -8] dB onto 0...1, with a little tilt so the highs are not always lost.
            let db = 20 * log10(max(peak, 1e-7)) + 2.5 * Float(b) / Float(bandCount)
            let v = max(0, min(1, (db + 70) / 62))
            let up: Float = 0.7, down: Float = 0.16
            smoothed[b] += (v - smoothed[b]) * (v > smoothed[b] ? up : down)
        }
        return smoothed
    }

    public var bands: [Float] { smoothed }
    public func reset() { filled = 0; for i in smoothed.indices { smoothed[i] = 0 }; for i in ring.indices { ring[i] = 0 } }
}
