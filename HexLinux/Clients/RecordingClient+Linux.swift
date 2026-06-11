#if !os(macOS)
import Dependencies
import DependenciesMacros
import Foundation
import HexCore

private let recordingLogger = HexLog.recording

struct AudioInputDevice: Identifiable, Equatable {
  var id: String
  var name: String
  var legacyID: String
}

@DependencyClient
struct RecordingClient {
  var startRecording: @Sendable () async -> Void = {}
  var stopRecording: @Sendable () async -> URL = { URL(fileURLWithPath: "") }
  var requestMicrophoneAccess: @Sendable () async -> Bool = { false }
  var observeAudioLevel: @Sendable () async -> AsyncStream<Meter> = { AsyncStream { _ in } }
  var getAvailableInputDevices: @Sendable () async -> [AudioInputDevice] = { [] }
  var getDefaultInputDeviceName: @Sendable () async -> String? = { nil }
  var warmUpRecorder: @Sendable () async -> Void = {}
  var cleanup: @Sendable () async -> Void = {}
}

extension RecordingClient: DependencyKey {
  static var liveValue: Self {
    let live = RecordingClientLive()
    return Self(
      startRecording: { await live.startRecording() },
      stopRecording: { await live.stopRecording() },
      requestMicrophoneAccess: { await live.requestMicrophoneAccess() },
      observeAudioLevel: { await live.observeAudioLevel() },
      getAvailableInputDevices: { await live.getAvailableInputDevices() },
      getDefaultInputDeviceName: { await live.getDefaultInputDeviceName() },
      warmUpRecorder: { await live.warmUpRecorder() },
      cleanup: { await live.cleanup() }
    )
  }
}

struct Meter: Equatable {
  let averagePower: Double
  let peakPower: Double
}

extension DependencyValues {
  var recording: RecordingClient {
    get { self[RecordingClient.self] }
    set { self[RecordingClient.self] = newValue }
  }
}

actor RecordingClientLive {
  private let sampleRate: Double = 16000
  private let channels: UInt16 = 1
  private let bitsPerSample: UInt16 = 16

  private var isRecording = false
  private var recordingProcess: Process?
  private var recordingOutputPipe: Pipe?
  private var audioBuffer = Data()
  private var audioLevelContinuation: AsyncStream<Meter>.Continuation?
  private var recordingOutputURL: URL?

  func startRecording() {
    guard !isRecording else { return }
    isRecording = true

    audioBuffer = Data()

    let tempDir = FileManager.default.temporaryDirectory
    let fileName = "hex_recording_\(UUID().uuidString).wav"
    let outputURL = tempDir.appendingPathComponent(fileName)
    recordingOutputURL = outputURL

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/arecord")
    process.arguments = [
      "-f", "S16_LE",
      "-r", "\(Int(sampleRate))",
      "-c", "\(channels)",
      "-t", "raw",
      outputURL.path
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      recordingProcess = process
      recordingLogger.info("Recording started -> \(outputURL.path)")
    } catch {
      recordingLogger.error("Failed to start recording: \(error)")
      isRecording = false
    }
  }

  func stopRecording() async -> URL {
    guard isRecording, let process = recordingProcess else {
      return URL(fileURLWithPath: "")
    }

    process.terminate()
    process.waitUntilExit()
    isRecording = false
    recordingProcess = nil

    guard let outputURL = recordingOutputURL else {
      return URL(fileURLWithPath: "")
    }

    let wavURL: URL
    do {
      wavURL = try await convertToWAV(rawURL: outputURL)
    } catch {
      recordingLogger.error("WAV conversion failed: \(error)")
      wavURL = outputURL
    }

    recordingLogger.info("Recording stopped -> \(wavURL.path)")
    return wavURL
  }

  func requestMicrophoneAccess() async -> Bool {
    return true
  }

  func observeAudioLevel() async -> AsyncStream<Meter> {
    AsyncStream { continuation in
      self.audioLevelContinuation = continuation
      continuation.onTermination = { @Sendable _ in
        Task { [weak self] in
          await self?.clearMeterContinuation()
        }
      }
    }
  }

  func getAvailableInputDevices() async -> [AudioInputDevice] {
    var devices: [AudioInputDevice] = []

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/arecord")
    process.arguments = ["-L"]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      guard let output = String(data: data, encoding: .utf8) else { return devices }

      var deviceName: String?
      for line in output.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty, let name = deviceName {
          devices.append(AudioInputDevice(id: name, name: name, legacyID: name))
          deviceName = nil
        } else if !trimmed.hasPrefix("#") {
          deviceName = trimmed
        }
      }
    } catch {
      recordingLogger.error("Failed to enumerate devices: \(error)")
    }

    if devices.isEmpty {
      devices.append(AudioInputDevice(id: "default", name: "Default", legacyID: "default"))
    }

    return devices
  }

  func getDefaultInputDeviceName() async -> String? {
    return "default"
  }

  func warmUpRecorder() async {
  }

  func cleanup() async {
    recordingProcess?.terminate()
    recordingProcess = nil
    isRecording = false
    audioBuffer.removeAll()
    audioLevelContinuation?.finish()
    audioLevelContinuation = nil
  }

  private func clearMeterContinuation() {
    audioLevelContinuation = nil
  }

  private func convertToWAV(rawURL: URL) async throws -> URL {
    let wavURL = rawURL.deletingPathExtension().appendingPathExtension("wav")

    let rawData = try Data(contentsOf: rawURL)

    var wav = Data()

    wav.append("RIFF".data(using: .ascii)!)
    let fileSize = UInt32(36 + rawData.count)
    wav.append(Data(bytes: &wavSizeVar(fileSize), count: 4))

    wav.append("WAVE".data(using: .ascii)!)

    wav.append("fmt ".data(using: .ascii)!)
    let fmtSize: UInt32 = 16
    wav.append(Data(bytes: &wavSizeVar(fmtSize), count: 4))

    let audioFormat: UInt16 = 1
    var af = audioFormat
    var nc = channels
    var sr = UInt32(sampleRate)
    let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
    var br = byteRate
    let blockAlign = channels * (bitsPerSample / 8)
    var ba = blockAlign
    var bps = bitsPerSample

    wav.append(Data(bytes: &af, count: 2))
    wav.append(Data(bytes: &nc, count: 2))
    wav.append(Data(bytes: &sr, count: 4))
    wav.append(Data(bytes: &br, count: 4))
    wav.append(Data(bytes: &ba, count: 2))
    wav.append(Data(bytes: &bps, count: 2))

    wav.append("data".data(using: .ascii)!)
    let dataSize = UInt32(rawData.count)
    wav.append(Data(bytes: &wavSizeVar(dataSize), count: 4))

    wav.append(rawData)

    try wav.write(to: wavURL)

    try? FileManager.default.removeItem(at: rawURL)

    return wavURL
  }
}

private func wavSizeVar(_ value: UInt32) -> UInt32 { value }
#endif
