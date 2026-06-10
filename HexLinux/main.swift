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
    var isDownloading = false
    var downloadProgress: Double = 0
    var lastTranscription = ""
    var error: String?
    var recordingStartTime: Date?
    var downloadedModels: [String] = []
    var availableModels: [String] = []

    @Shared(.hexSettings) var hexSettings: HexSettings
    @Shared(.linuxIsRunning) var isRunning: Bool
  }

  enum Action {
    case task
    case toggleRecording
    case recordingStarted
    case recordingStopped(URL)
    case transcriptionResult(Result<String, Error>)
    case fetchModels
    case modelsLoaded(Result<[String], Error>)
    case downloadModel(String)
    case downloadProgress(Double)
    case downloadCompleted(Result<String, Error>)
    case deleteModel(String)
    case pasteTranscription
    case quit
  }

  @Dependency(\.recording) var recording
  @Dependency(\.transcription) var transcription

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        return .send(.fetchModels)

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
            let text = try await transcription.transcribe(url, settings.outputLanguage, settings.selectedModel)
            await send(.transcriptionResult(.success(text)))
          } catch {
            await send(.transcriptionResult(.failure(error)))
          }
        }

      case let .transcriptionResult(.success(text)):
        state.isTranscribing = false
        state.lastTranscription = text
        state.error = nil
        return .none

      case let .transcriptionResult(.failure(error)):
        state.isTranscribing = false
        state.error = error.localizedDescription
        return .none

      case .fetchModels:
        return .run { send in
          let available = await transcription.getAvailableModels()
          await send(.modelsLoaded(.success(available)))
        }

      case let .modelsLoaded(.success(models)):
        state.availableModels = models
        var downloaded: [String] = []
        for model in models {
          if await transcription.isModelDownloaded(model) {
            downloaded.append(model)
          }
        }
        state.downloadedModels = downloaded
        return .none

      case let .modelsLoaded(.failure(error)):
        state.error = error.localizedDescription
        return .none

      case let .downloadModel(name):
        state.isDownloading = true
        state.downloadProgress = 0
        state.error = nil
        let modelID = UUID()
        return .run { send in
          do {
            try await transcription.downloadModel(name) { fraction in
              Task { await send(.downloadProgress(fraction)) }
            }
            await send(.downloadCompleted(.success(name)))
          } catch {
            await send(.downloadCompleted(.failure(error)))
          }
        }.cancellable(id: modelID)

      case let .downloadProgress(progress):
        state.downloadProgress = progress
        return .none

      case let .downloadCompleted(.success(name)):
        state.isDownloading = false
        state.downloadProgress = 1.0
        if !state.downloadedModels.contains(name) {
          state.downloadedModels.append(name)
        }
        return .send(.fetchModels)

      case let .downloadCompleted(.failure(error)):
        state.isDownloading = false
        state.downloadProgress = 0
        state.error = error.localizedDescription
        return .none

      case let .deleteModel(name):
        return .run { send in
          do {
            try await transcription.deleteModel(name)
            await send(.fetchModels)
          } catch {
            await send(.downloadCompleted(.failure(error)))
          }
        }

      case .pasteTranscription:
        guard !state.lastTranscription.isEmpty else { return .none }
        @Dependency(\.pasteboard) var pasteboard
        return .run { [text = state.lastTranscription] _ in
          await pasteboard.paste(text)
        }

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

// MARK: - Formatting

private func humanReadableSize(_ bytes: Int64) -> String {
  if bytes < 1024 { return "\(bytes)B" }
  if bytes < 1024 * 1024 { return String(format: "%.1fKB", Double(bytes) / 1024) }
  if bytes < 1024 * 1024 * 1024 { return String(format: "%.1fMB", Double(bytes) / (1024 * 1024)) }
  return String(format: "%.2fGB", Double(bytes) / (1024 * 1024 * 1024))
}

private func progressBar(fraction: Double, width: Int = 30) -> String {
  let filled = Int(Double(width) * max(0, min(1, fraction)))
  let empty = width - filled
  return "[" + String(repeating: "=", count: filled) + String(repeating: " ", count: empty) + "]"
}

private func stars(_ count: Int) -> String {
  String(repeating: "★", count: count) + String(repeating: "☆", count: max(0, 5 - count))
}

// MARK: - Main Entry Point

@main
struct HexLinux {
  static func main() async {
    LoggingSystem.bootstrap { label in
      var handler = StreamLogHandler.standardOutput(label: label)
      handler.logLevel = .info
      return handler
    }

    let logger = HexLog.app
    logger.info("Hex Linux starting...")

    let store = Store(initialState: LinuxApp.State()) {
      LinuxApp()
    }

    await store.send(.task).finish()

    let server = HexWebServer(port: 8765)
    do {
      try await server.start(store: store)
    } catch {
      logger.error("Failed to start web server: \(error)")
      print("ERROR: Could not start web server on port 8765.")
      print("Is another instance running?")
      return
    }

    openBrowser("http://127.0.0.1:8765")

    print("""
    ╔═══════════════════════════════════════════╗
    ║           Hex — Voice to Text             ║
    ║           Linux Edition                   ║
    ╠═══════════════════════════════════════════╣
    ║  Web UI: http://127.0.0.1:8765           ║
    ║                                           ║
    ║  CLI commands also available here:        ║
    ║    Enter → record/stop                    ║
    ║    p     → paste                          ║
    ║    models → list models                   ║
    ║    q     → quit                           ║
    ╚═══════════════════════════════════════════╝
    """)

    let readLoop = Task {
      while true {
        guard let line = readLine(strippingNewline: true) else { break }
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        switch trimmed.lowercased() {
        case "", "r", "record":
          await store.send(.toggleRecording)
          let st = store.state
          if st.isRecording {
            print("  [RECORDING] Speak now...")
          } else if st.isTranscribing {
            print("  [TRANSCRIBING] Processing...")
          }

        case "p", "paste":
          let text = store.state.lastTranscription
          if !text.isEmpty {
            await store.send(.pasteTranscription)
            print("  [PASTED]")
          } else {
            print("  Nothing to paste.")
          }

        case "models":
          let st = store.state
          let registry = GGMLModelManifest.bundled()
          for model in st.availableModels {
            let dl = st.downloadedModels.contains(model) ? "✓" : " "
            let entry = registry.first { $0.name == model }
            print("  [\(dl)] \(model)  \(entry.map { humanReadableSize($0.sizeBytes) } ?? "?")")
          }

        case "fetch":
          await store.send(.fetchModels)
          print("  Refreshing models...")

        case let dl where dl.hasPrefix("download"):
          let parts = dl.components(separatedBy: .whitespaces).dropFirst()
          if let name = parts.first {
            print("  Downloading \(name)...")
            await store.send(.downloadModel(name))
            while store.state.isDownloading {
              let pct = Int(store.state.downloadProgress * 100)
              print("\r  \(progressBar(fraction: store.state.downloadProgress)) \(pct)%", terminator: "")
              fflush(stdout)
              try? await Task.sleep(nanoseconds: 500_000_000)
            }
            print("")
            if let err = store.state.error { print("  [ERROR] \(err)") }
            else { print("  [DONE]") }
          }

        case let del where del.hasPrefix("delete"):
          let parts = del.components(separatedBy: .whitespaces).dropFirst()
          if let name = parts.first {
            await store.send(.deleteModel(name))
            print("  Deleted \(name)")
          }

        case "status":
          let st = store.state
          print("  Rec:\(st.isRecording) Trans:\(st.isTranscribing) Models:\(st.downloadedModels.count)/\(st.availableModels.count)")

        case "q", "quit", "exit":
          print("  Shutting down...")
          break

        case "h", "help":
          print("  Enter=record, p=paste, models, download <n>, delete <n>, status, q=quit")

        default:
          print("  Unknown: '\(trimmed)' (h for help)")
        }
      }
    }

    let _ = await readLoop.result

    await server.stop()
    logger.info("Hex Linux exiting.")
    print("Goodbye!")
  }

  static func openBrowser(_ url: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["xdg-open", url]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
  }
}
#endif
