#if !os(macOS)
import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import HexCore

private let soundLogger = HexLog.sound

public enum SoundEffect: String, CaseIterable {
  case pasteTranscript
  case startRecording
  case stopRecording
  case cancel

  public var fileName: String { rawValue }
  var fileExtension: String { "mp3" }
}

@DependencyClient
public struct SoundEffectsClient {
  public var play: @Sendable (SoundEffect) -> Void
  public var stop: @Sendable (SoundEffect) -> Void
  public var stopAll: @Sendable () -> Void
  public var preloadSounds: @Sendable () async -> Void
  public var setEnabled: @Sendable (Bool) async -> Void
}

extension SoundEffectsClient: DependencyKey {
  public static var liveValue: SoundEffectsClient {
    let live = SoundEffectsClientLive()
    return SoundEffectsClient(
      play: { soundEffect in
        Task { await live.play(soundEffect) }
      },
      stop: { soundEffect in
        Task { await live.stop(soundEffect) }
      },
      stopAll: {
        Task { await live.stopAll() }
      },
      preloadSounds: {
        await live.preloadSounds()
      },
      setEnabled: { enabled in
        await live.setEnabled(enabled)
      }
    )
  }
}

public extension DependencyValues {
  var soundEffects: SoundEffectsClient {
    get { self[SoundEffectsClient.self] }
    set { self[SoundEffectsClient.self] = newValue }
  }
}

actor SoundEffectsClientLive {
  private let logger = HexLog.sound
  private let baselineVolume = HexSettings.baseSoundEffectsVolume

  @Shared(.hexSettings) var hexSettings: HexSettings
  private var soundPaths: [SoundEffect: String] = [:]
  private var isEnabled = true
  private var currentProcesses: [SoundEffect: Process] = [:]

  func play(_ soundEffect: SoundEffect) {
    guard hexSettings.soundEffectsEnabled else { return }
    guard let path = soundPaths[soundEffect] else {
      logger.error("Requested sound \(soundEffect.rawValue) not preloaded")
      return
    }

    stop(soundEffect)

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/paplay")
    task.arguments = ["--volume=\(Int(hexSettings.soundEffectsVolume * 65536))", path]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice

    do {
      try task.run()
      currentProcesses[soundEffect] = task
    } catch {
      logger.error("Failed to play sound \(soundEffect.rawValue): \(error)")
    }
  }

  func stop(_ soundEffect: SoundEffect) {
    currentProcesses[soundEffect]?.terminate()
    currentProcesses.removeValue(forKey: soundEffect)
  }

  func stopAll() {
    for (effect, _) in currentProcesses {
      stop(effect)
    }
  }

  func preloadSounds() async {
    guard soundPaths.isEmpty else { return }

    let soundDir = Bundle.module.path(forResource: "Audio", ofType: nil)
      ?? Bundle.main.path(forResource: "Audio", ofType: nil)

    for effect in SoundEffect.allCases {
      let filename = "\(effect.fileName).\(effect.fileExtension)"
      let path: String
      if let dir = soundDir {
        path = (dir as NSString).appendingPathComponent(filename)
      } else {
        path = filename
      }
      if FileManager.default.fileExists(atPath: path) {
        soundPaths[effect] = path
      } else {
        logger.error("Missing sound resource: \(filename)")
      }
    }
  }

  func setEnabled(_ enabled: Bool) async {
    isEnabled = enabled
    if !enabled {
      stopAll()
    }
  }
}
#endif
