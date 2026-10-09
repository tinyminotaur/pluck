import AppKit
import Combine
import CoreMedia
import TwangCore
import ScreenCaptureKit

/// Live system-audio spectrum for the Equalizer style.
///
/// This is strictly opt-in (a Settings toggle, off by default) and only runs while the Equalizer style is selected.
/// It uses ScreenCaptureKit's audio-only path, which needs macOS's Screen Recording permission; the system shows its
/// own prompt and its own recording indicator. Twang's own sounds are excluded, nothing is recorded or stored, and
/// only 24 band levels leave this file. If the permission is missing the Equalizer simply animates on its own.
final class AudioSpectrum: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    static let shared = AudioSpectrum()

    static let bands = 24
    private let analyzer = SpectrumAnalyzer(bands: AudioSpectrum.bands, sampleRate: 48_000)
    private let lock = NSLock()
    private var latest = [Float](repeating: 0, count: AudioSpectrum.bands)
    private var lastBuffer: CFAbsoluteTime = 0
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "twang.audio.spectrum", qos: .userInitiated)
    private var starting = false
    private var _running = false
    var running: Bool { lock.lock(); defer { lock.unlock() }; return _running }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }
    @discardableResult static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// Bass-first band levels (0...1), or nil when we are not capturing (so the caller falls back to its own animation).
    func snapshot() -> [CGFloat]? {
        lock.lock(); defer { lock.unlock() }
        guard _running else { return nil }
        // No buffers lately means the system is silent: let the bars fall to rest.
        if CFAbsoluteTimeGetCurrent() - lastBuffer > 0.35 { return [CGFloat](repeating: 0, count: Self.bands) }
        return latest.map { CGFloat($0) }
    }

    func start() {
        lock.lock()
        if _running || starting { lock.unlock(); return }
        starting = true
        lock.unlock()
        guard Self.hasPermission else {
            lock.lock(); starting = false; lock.unlock()
            Diagnostics.log("audio: Screen Recording permission not granted; the equalizer animates on its own")
            return
        }
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { throw NSError(domain: "twang.audio", code: 1) }
                let cfg = SCStreamConfiguration()
                cfg.capturesAudio = true
                cfg.excludesCurrentProcessAudio = true
                cfg.sampleRate = 48_000
                cfg.channelCount = 1
                cfg.width = 2; cfg.height = 2                                   // no real video: the smallest frame, once a second
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                let s = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg, delegate: self)
                try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
                try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)   // received and discarded
                try await s.startCapture()
                markRunning(s)
                Diagnostics.log("audio: capturing system audio for the equalizer")
            } catch {
                clearStarting()
                Diagnostics.log("audio: could not start capture: \(error.localizedDescription)")
            }
        }
    }

    private func markRunning(_ s: SCStream) { lock.lock(); stream = s; _running = true; starting = false; lastBuffer = CFAbsoluteTimeGetCurrent(); lock.unlock() }
    private func clearStarting() { lock.lock(); starting = false; lock.unlock() }

    func stop() {
        lock.lock()
        let s = stream; stream = nil; _running = false; starting = false
        for i in latest.indices { latest[i] = 0 }
        lock.unlock()
        analyzer.reset()
        guard let s else { return }
        Task { try? await s.stopCapture(); Diagnostics.log("audio: stopped") }
    }

    // MARK: SCStreamOutput / delegate

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sb.isValid, sb.numSamples > 0 else { return }
        var samples: [Float] = []
        try? sb.withAudioBufferList { list, _ in
            guard let desc = sb.formatDescription?.audioStreamBasicDescription else { return }
            let isFloat = desc.mFormatFlags & kAudioFormatFlagIsFloat != 0
            let channels = max(1, Int(desc.mChannelsPerFrame))
            for buf in list {
                guard let data = buf.mData else { continue }
                if isFloat {
                    let n = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
                    let p = data.assumingMemoryBound(to: Float.self)
                    if samples.isEmpty { samples.reserveCapacity(n / channels) }
                    var i = 0
                    while i < n { samples.append(p[i]); i += channels }        // first channel (we asked for mono)
                } else {
                    let n = Int(buf.mDataByteSize) / MemoryLayout<Int16>.size
                    let p = data.assumingMemoryBound(to: Int16.self)
                    var i = 0
                    while i < n { samples.append(Float(p[i]) / 32768); i += channels }
                }
                break                                                           // one buffer is enough for mono
            }
        }
        guard !samples.isEmpty else { return }
        let bands = analyzer.process(samples)
        lock.lock(); latest = bands; lastBuffer = CFAbsoluteTimeGetCurrent(); lock.unlock()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock(); self.stream = nil; _running = false; starting = false; lock.unlock()
        Diagnostics.log("audio: stream stopped: \(error.localizedDescription)")
    }
}

/// Starts and stops the capture to match the settings: only while the Equalizer style is selected and the toggle is on.
@MainActor
final class AudioSpectrumController {
    static let shared = AudioSpectrumController()
    private var bag = Set<AnyCancellable>()

    func bind() {
        let cfg = TwangConfig.shared
        cfg.$audioReactive.combineLatest(cfg.$styleID)
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] on, style in self?.apply(on: on, style: style) }
            .store(in: &bag)
    }

    private func apply(on: Bool, style: String) {
        if on, style == AnimationStyle.equalizer.rawValue {
            if !AudioSpectrum.hasPermission { AudioSpectrum.requestPermission() }   // the system asks the person
            AudioSpectrum.shared.start()
        } else {
            AudioSpectrum.shared.stop()
        }
    }

    /// Called when the app regains focus, in case the permission was granted in System Settings meanwhile.
    func refresh() { let c = TwangConfig.shared; apply(on: c.audioReactive, style: c.styleID) }
}
