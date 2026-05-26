//
//  VisualizerTap.swift
//  NullSpot
//
//  Taps PCM samples flowing into AudioRenderer, runs an FFT on a background
//  task, and publishes 12 log-binned band magnitudes for the header visualizer.
//
//  - submit() is called from librespot's audio thread; it must be lock-free
//    and allocation-free.
//  - A detached worker task wakes ~30 times per second, snapshots the ring,
//    runs vDSP FFT, applies peak-hold decay, and publishes bands on MainActor.
//

import Accelerate
import Foundation
import Synchronization

@Observable
final nonisolated class VisualizerTap: @unchecked Sendable {
    static let shared = VisualizerTap()

    // MARK: - Tuning

    static let bandCount = 12
    private static let fftSize = 1024
    private static let ringCapacity = 4096
    private static let frameIntervalMs: UInt64 = 33
    private static let noiseFloor: Float = 0.02
    private static let decay: Float = 0.88
    private static let attackSmoothing: Float = 0.35
    private static let referenceScale: Float = 1.0 / 22.0
    /// Hysteresis: keep `hasAudio = true` for ~1.5s after the last active frame
    /// so brief gaps (track boundaries, buffer underruns) don't flip back to the wordmark.
    private static let audioHoldFrames: Int = 45

    // MARK: - Published

    @MainActor private(set) var bands: [Float] = Array(repeating: 0, count: bandCount)
    @MainActor private(set) var hasAudio: Bool = false

    // MARK: - Audio-thread state (single-writer ring + atomic counter)

    private let ring: UnsafeMutableBufferPointer<Float>
    private let writeCount = Atomic<UInt64>(0)

    // MARK: - Worker-thread state (read-only after init)

    private let hannWindow: [Float]
    private let fftSetup: vDSP.FFT<DSPSplitComplex>
    private let logBandEdges: [Int]

    // MARK: - Lifecycle (MainActor-only)

    @MainActor private var workerTask: Task<Void, Never>?
    @MainActor private var isWindowVisible: Bool = true
    @MainActor private var isMounted: Bool = false

    // MARK: - Init

    private init() {
        ring = UnsafeMutableBufferPointer.allocate(capacity: Self.ringCapacity)
        ring.initialize(repeating: 0)

        var window = [Float](repeating: 0, count: Self.fftSize)
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        hannWindow = window

        let log2n = vDSP_Length(log2(Double(Self.fftSize)))
        guard let setup = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self) else {
            fatalError("VisualizerTap: failed to create FFT setup")
        }
        fftSetup = setup

        logBandEdges = Self.computeLogBandEdges(
            bandCount: Self.bandCount,
            minBin: 2,
            maxBin: Self.fftSize / 4,
        )
        // Worker is started lazily via setMounted / setWindowVisible — see syncWorker().
    }

    deinit {
        ring.deallocate()
    }

    // MARK: - Audio-thread entry point

    /// Push interleaved stereo f32 samples into the tap.
    /// Lock-free; safe to call from librespot's audio thread.
    /// `sampleCount` is the total f32 count (L+R interleaved). Frames = sampleCount / 2.
    func submit(interleavedStereo samples: UnsafePointer<Float>, sampleCount: Int) {
        let frameCount = sampleCount / 2
        guard frameCount > 0 else { return }

        let current = writeCount.load(ordering: .relaxed)
        let writeIdx = Int(current % UInt64(Self.ringCapacity))
        let firstChunk = min(frameCount, Self.ringCapacity - writeIdx)

        let base = ring.baseAddress!
        for i in 0 ..< firstChunk {
            let l = samples[2 * i]
            let r = samples[2 * i + 1]
            base[writeIdx + i] = (l + r) * 0.5
        }
        if firstChunk < frameCount {
            let tail = frameCount - firstChunk
            let srcOffset = 2 * firstChunk
            for i in 0 ..< tail {
                let l = samples[srcOffset + 2 * i]
                let r = samples[srcOffset + 2 * i + 1]
                base[i] = (l + r) * 0.5
            }
        }

        writeCount.add(UInt64(frameCount), ordering: .releasing)
    }

    // MARK: - Lifecycle

    /// Called when the host window's occlusion state changes. Pauses the FFT
    /// worker whenever the window is fully hidden (occluded, minimized, on a
    /// different Space). Resumes when it becomes visible again — there's a
    /// ~100 ms cold-start lag that the hasAudio hysteresis hides.
    @MainActor func setWindowVisible(_ visible: Bool) {
        guard isWindowVisible != visible else { return }
        isWindowVisible = visible
        syncWorker()
    }

    /// Called when the visualizer view enters/leaves the SwiftUI hierarchy
    /// (e.g., the header swaps it out for the search field).
    @MainActor func setMounted(_ mounted: Bool) {
        guard isMounted != mounted else { return }
        isMounted = mounted
        syncWorker()
    }

    @MainActor private func syncWorker() {
        if isWindowVisible, isMounted {
            startWorkerIfNeeded()
        } else {
            stopWorker()
        }
    }

    @MainActor private func startWorkerIfNeeded() {
        guard workerTask == nil else { return }
        startWorker()
    }

    @MainActor private func stopWorker() {
        guard let task = workerTask else { return }
        task.cancel()
        workerTask = nil
        // Reset published state so a stale bars frame doesn't linger if the
        // worker is restarted with the same values later.
        bands = Array(repeating: 0, count: Self.bandCount)
        hasAudio = false
    }

    // MARK: - Worker

    @MainActor private func startWorker() {
        workerTask = Task.detached(priority: .userInitiated) { [weak self] in
            var smoothed = [Float](repeating: 0, count: Self.bandCount)
            var display = [Float](repeating: 0, count: Self.bandCount)
            var framesSinceActive = Self.audioHoldFrames
            var lastWriteCount: UInt64 = 0
            var lastPublishedBands = [Float](repeating: 0, count: Self.bandCount)
            var lastPublishedHasAudio = false
            var framesSinceWrite = 0
            while !Task.isCancelled {
                guard let self else { return }

                // Skip the entire FFT pipeline when no new audio has arrived.
                // librespot stops writing while paused / when a Connect device
                // is active; running the FFT on stale ring contents wastes CPU
                // for a result that only decays toward zero.
                let currentWriteCount = writeCount.load(ordering: .acquiring)
                let hasNewSamples = currentWriteCount != lastWriteCount
                lastWriteCount = currentWriteCount

                if hasNewSamples {
                    framesSinceWrite = 0
                    if let raw = computeRawBands() {
                        let spatial = Self.spatialSmooth(raw)
                        for i in 0 ..< Self.bandCount {
                            smoothed[i] = smoothed[i] * (1 - Self.attackSmoothing) + spatial[i] * Self.attackSmoothing
                            display[i] = max(smoothed[i], display[i] * Self.decay)
                        }
                    } else {
                        for i in 0 ..< Self.bandCount {
                            smoothed[i] *= Self.decay
                            display[i] *= Self.decay
                        }
                    }
                } else if framesSinceWrite < Self.audioHoldFrames {
                    // Brief silence — keep decaying so bars fall smoothly.
                    framesSinceWrite += 1
                    for i in 0 ..< Self.bandCount {
                        smoothed[i] *= Self.decay
                        display[i] *= Self.decay
                    }
                }
                // After audioHoldFrames of silence: display is already ~0 and
                // hasAudio has flipped to false. Stop computing entirely until
                // new samples arrive — we'll only re-check writeCount.

                let snapshot = display
                if snapshot.contains(where: { $0 > Self.noiseFloor }) {
                    framesSinceActive = 0
                } else if framesSinceActive < Self.audioHoldFrames {
                    framesSinceActive += 1
                }
                let active = framesSinceActive < Self.audioHoldFrames

                // Only hop to MainActor + invalidate SwiftUI observers when
                // the published values actually change. During silence the
                // arrays settle to zero and republishing is pure overhead.
                if active != lastPublishedHasAudio || snapshot != lastPublishedBands {
                    lastPublishedBands = snapshot
                    lastPublishedHasAudio = active
                    await MainActor.run {
                        self.bands = snapshot
                        self.hasAudio = active
                    }
                }

                // Idle longer when truly silent — no new writes and the bars
                // have already settled. Wakes back up within ~100 ms once
                // audio resumes (next writeCount change).
                let isIdle = !hasNewSamples && framesSinceWrite >= Self.audioHoldFrames
                let sleepMs: UInt64 = isIdle ? 100 : Self.frameIntervalMs
                try? await Task.sleep(for: .milliseconds(sleepMs))
            }
        }
    }

    /// 3-point [0.25, 0.5, 0.25] filter across adjacent bands to damp single-bin spikes.
    private static func spatialSmooth(_ bands: [Float]) -> [Float] {
        let n = bands.count
        guard n >= 3 else { return bands }
        var out = bands
        for i in 1 ..< (n - 1) {
            out[i] = 0.25 * bands[i - 1] + 0.5 * bands[i] + 0.25 * bands[i + 1]
        }
        return out
    }

    // MARK: - FFT pipeline (worker thread)

    private func computeRawBands() -> [Float]? {
        let current = writeCount.load(ordering: .acquiring)
        guard current >= UInt64(Self.fftSize) else { return nil }

        let endIdx = Int(current % UInt64(Self.ringCapacity))
        let startIdx = (endIdx - Self.fftSize + Self.ringCapacity) % Self.ringCapacity

        var samples = [Float](repeating: 0, count: Self.fftSize)
        let base = ring.baseAddress!
        if startIdx + Self.fftSize <= Self.ringCapacity {
            samples.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress!.update(from: base.advanced(by: startIdx), count: Self.fftSize)
            }
        } else {
            let firstChunk = Self.ringCapacity - startIdx
            samples.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress!.update(from: base.advanced(by: startIdx), count: firstChunk)
                dst.baseAddress!.advanced(by: firstChunk).update(from: base, count: Self.fftSize - firstChunk)
            }
        }

        var windowed = [Float](repeating: 0, count: Self.fftSize)
        vDSP.multiply(samples, hannWindow, result: &windowed)

        let half = Self.fftSize / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)

        real.withUnsafeMutableBufferPointer { realBuf in
            imag.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                windowed.withUnsafeBufferPointer { wPtr in
                    wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(half))
                    }
                }
                fftSetup.forward(input: split, output: &split)
                vDSP.absolute(split, result: &magnitudes)
            }
        }

        var bands = [Float](repeating: 0, count: Self.bandCount)
        for band in 0 ..< Self.bandCount {
            let lo = logBandEdges[band]
            let hi = max(logBandEdges[band + 1], lo + 1)
            var peak: Float = 0
            for bin in lo ..< min(hi, half) {
                if magnitudes[bin] > peak { peak = magnitudes[bin] }
            }
            bands[band] = min(1, max(0, peak * Self.referenceScale))
        }
        return bands
    }

    // MARK: - Helpers

    private static func computeLogBandEdges(bandCount: Int, minBin: Int, maxBin: Int) -> [Int] {
        let logMin = log(Double(minBin))
        let logMax = log(Double(maxBin))
        var edges: [Int] = []
        edges.reserveCapacity(bandCount + 1)
        for i in 0 ... bandCount {
            let t = Double(i) / Double(bandCount)
            edges.append(Int(exp(logMin + (logMax - logMin) * t)))
        }
        return edges
    }
}
