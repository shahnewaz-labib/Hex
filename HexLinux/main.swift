#if !os(macOS)
import ComposableArchitecture
import Dependencies
import Foundation
import HexCore
import Logging

// MARK: - Linux App Reducer

@Reducer
struct LinuxApp {
  @ObservableState
  struct State {
    var isRecording = false
    var isTranscribing = false
    var lastTranscription = ""
    var error: String?
    var recordingStartTime: Date?

    @Shared(.hexSettings) var hexSettings: HexSettings
    @Shared(.linuxIsRunning) var isRunning: Bool
  }

  enum Action {
    case task
    case toggleRecording
    case recordingStarted
    case recordingStopped(URL)
    case transcriptionResult(Result<String, Error>)
    case pasteTranscription
    case openSettings
    case quit
  }

  @Dependency(\.recording) var recording
  @Dependency(\.transcription) var transcription
  @Dependency(\.pasteboard) var pasteboard

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        return .run { send in
          await send(.openSettings)
        }

      case .toggleRecording:
        if state.isRecording {
          state.isRecording = false
          state.isTranscribing = true
          return .run { send in
            let url = await recording.stopRecording()
            await send(.recordingStopped(url))
          }
        } else {
          state.lastTranscription = ""
          state.error = nil
          state.recordingStartTime = Date()
          return .run { send in
            await recording.startRecording()
            await send(.recordingStarted)
          }
        }

      case .recordingStarted:
        state.isRecording = true
        return .none

      case let .recordingStopped(url):
        return .run { [settings = state.hexSettings] send in
          do {
            let text = try await transcription.transcribe(url, settings.outputLanguage, nil)
            await send(.transcriptionResult(.success(text)))
          } catch {
            await send(.transcriptionResult(.failure(error)))
          }
        }

      case let .transcriptionResult(.success(text)):
        state.isTranscribing = false
        state.lastTranscription = text
        return .none

      case let .transcriptionResult(.failure(error)):
        state.isTranscribing = false
        state.error = error.localizedDescription
        return .none

      case .pasteTranscription:
        guard !state.lastTranscription.isEmpty else { return .none }
        return .run { [text = state.lastTranscription] _ in
          await pasteboard.paste(text)
        }

      case .openSettings:
        let logger = HexLog.app
        logger.info("Settings file: \(HexLinuxPaths.settingsFile().path)")
        return .none

      case .quit:
        state.isRunning = false
        return .none
      }
    }
  }
}

// MARK: - Shared State Keys

extension SharedReaderKey where Self == InMemoryKey<Bool>.Default {
  static var linuxIsRunning: Self {
    Self[.inMemory("linuxIsRunning"), default: true]
  }
}

// MARK: - Settings Persistence

extension SharedReaderKey where Self == FileStorageKey<HexSettings>.Default {
  static var hexSettings: Self {
    Self[.fileStorage(HexLinuxPaths.settingsFile()), default: .init()]
  }
}

// MARK: - Paths

enum HexLinuxPaths {
  static func configDirectory() -> URL {
    let xdgConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
      ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config")
        .path
    let dir = URL(fileURLWithPath: xdgConfigHome)
      .appendingPathComponent("hex", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  static func settingsFile() -> URL {
    configDirectory().appendingPathComponent("settings.json")
  }
}

// MARK: - Main Entry Point

@main
struct HexLinux {
  static func main() async {
    LoggingSystem.bootstrap { label in
      var handler = StreamLogHandler.standardOutput(label: label)
      #if DEBUG
      handler.logLevel = .debug
      #else
      handler.logLevel = .info
      #endif
      return handler
    }

    let logger = HexLog.app
    logger.info("Hex Linux starting...")

    print("""
    ╔══════════════════════════════════════╗
    ║        Hex - Voice to Text           ║
    ║        Linux Edition (MVP)           ║
    ╚══════════════════════════════════════╝

    Press Enter to start/stop recording.
    Press Esc to quit after stopping.
    Press p to paste last transcription.

    System dependencies needed:
      - whisper-cpp  (transcription engine)
      - arecord      (ALSA audio capture)
      - xdotool/xclip (pasteboard)
      - paplay       (sound effects)
    """)

    let store = Store(initialState: LinuxApp.State()) {
      LinuxApp()
    }

    await store.send(.task).finish()

    var shouldQuit = false
    while !shouldQuit {
      guard let line = readLine(strippingNewline: true) else { break }

      switch line.lowercased() {
      case "", "r":
        await store.send(.toggleRecording)
        let state = store.state
        if state.isRecording {
          print("[RECORDING] Speak now... Press Enter to stop.")
        } else if state.isTranscribing {
          print("[TRANSCRIBING] Processing audio...")
        }

      case "p":
        let text = store.state.lastTranscription
        if !text.isEmpty {
          await store.send(.pasteTranscription)
          print("[PASTED]")
        }

      case "q", "quit", "exit":
        shouldQuit = true
        await store.send(.quit)

      case "h", "help":
        print("""
        Commands:
          Enter/r  - Start/stop recording
          p        - Paste last transcription
          q/quit   - Exit
          h/help   - Show this help
        """)

      default:
        print("Unknown command: \(line). Type 'h' for help.")
      }

      if case let .transcriptionResult(.success(text)) = store.state, let _ = text {
        let displayedText = text

        print("""

        ┌──────────────────────────────────────┐
        │ Transcription Result:
        │ \(displayedText.prefix(500))
        └──────────────────────────────────────┘

        Press 'p' to paste, Enter to record again.
        """)
      }

      if let error = store.state.error {
        print("[ERROR] \(error)")
      }
    }

    logger.info("Hex Linux exiting.")
    print("Goodbye!")
  }
}
#endif
