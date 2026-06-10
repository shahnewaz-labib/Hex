#if !os(macOS)
import Foundation
import HexCore

private let logger = HexLog.recording

enum CaptureRecordingMode: String {
  case standard
  case superFast

  var preRollDuration: TimeInterval {
    switch self {
    case .standard: return 0
    case .superFast: return 0.45
    }
  }

  var keepsWarmBuffer: Bool {
    self == .superFast
  }
}

final class SuperFastCaptureController {
  struct StopTimingEstimate {
    let gracePeriod: TimeInterval
    let callbackInterval: TimeInterval
    let bufferDuration: TimeInterval
  }

  private let processingQueue = DispatchQueue(label: "com.hex.SuperFastCapture")
  private let meterContinuation: AsyncStream<Meter>.Continuation
  private let onEngineConfigurationChange: @Sendable () -> Void

  private var isActiveRecording = false
  private var keepWarmBuffer = false

  private let ringBufferCapacity: Int
  private var ringBuffer: [Float]
  private var ringWriteIndex = 0
  private var ringValidCount = 0

  var isRunning: Bool { isActiveRecording }
  var isRecording: Bool { processingQueue.sync { isActiveRecording } }

  var stopTimingEstimate: StopTimingEstimate {
    StopTimingEstimate(gracePeriod: 0.05, callbackInterval: 0.0, bufferDuration: 0.0)
  }

  init(
    meterContinuation: AsyncStream<Meter>.Continuation,
    onEngineConfigurationChange: @escaping @Sendable () -> Void
  ) {
    self.meterContinuation = meterContinuation
    self.onEngineConfigurationChange = onEngineConfigurationChange
    self.ringBufferCapacity = Int(16000 * 1.0)
    self.ringBuffer = Array(repeating: 0, count: ringBufferCapacity)
  }

  deinit {
    stop()
  }

  func startIfNeeded(reason: String = "unknown", keepWarmBuffer: Bool = false) throws {
    self.keepWarmBuffer = keepWarmBuffer
    logger.debug("Capture engine armed reason=\(reason) keepWarmBuffer=\(keepWarmBuffer)")
  }

  func startRecording(to url: URL, mode: CaptureRecordingMode = .standard, metadata: RecordingMetadata = .init()) throws {
    processingQueue.sync {
      let preRollSamples = Int(Double(ringBufferCapacity) * mode.preRollDuration / 1.0)
      let recent = recentSamples(count: preRollSamples)
      isActiveRecording = true
      meterContinuation.yield(Meter(averagePower: -20, peakPower: -10))
    }
    logger.info("Started recording to \(url.path) mode=\(mode.rawValue)")
  }

  func stopRecording() -> URL? {
    processingQueue.sync {
      isActiveRecording = false
    }
    logger.info("Stopped recording")
    return nil
  }

  func stop(reason: String = "stopping") {
    processingQueue.sync {
      isActiveRecording = false
      if keepWarmBuffer {
        ringWriteIndex = 0
        ringValidCount = 0
      }
    }
    logger.info("Capture engine stopped reason=\(reason)")
  }

  func appendSamples(_ samples: [Float]) {
    processingQueue.async {
      for sample in samples {
        self.ringBuffer[self.ringWriteIndex] = sample
        self.ringWriteIndex = (self.ringWriteIndex + 1) % self.ringBufferCapacity
      }
      self.ringValidCount = min(self.ringBufferCapacity, self.ringValidCount + samples.count)
    }
  }

  func recentSamples(count requestedCount: Int) -> [Float] {
    processingQueue.sync {
      let sampleCount = min(max(0, requestedCount), ringValidCount)
      guard sampleCount > 0 else { return [] }

      let startIndex = (ringWriteIndex - sampleCount + ringBufferCapacity) % ringBufferCapacity
      if startIndex + sampleCount <= ringBufferCapacity {
        return Array(ringBuffer[startIndex..<(startIndex + sampleCount)])
      }

      let firstChunk = Array(ringBuffer[startIndex..<ringBufferCapacity])
      let secondChunk = Array(ringBuffer[0..<(sampleCount - firstChunk.count)])
      return firstChunk + secondChunk
    }
  }
}

struct RecordingMetadata {
  let sourceAppBundleID: String? = nil
  let sourceAppName: String? = nil
  let requestStopTime: Date? = nil
  let didRequestStop: Bool = false
}
#endif
