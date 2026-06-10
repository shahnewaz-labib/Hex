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

    print("""
    ╔══════════════════════════════════════════╗
    ║          Hex — Voice to Text             ║
    ║          Linux Edition                   ║
    ╚══════════════════════════════════════════╝

    Type 'h' for help.
    """)

    let store = Store(initialState: LinuxApp.State()) {
      LinuxApp()
    }

    await store.send(.task).finish()

    while true {
      print("\n> ", terminator: "")
      fflush(stdout)
      guard let line = readLine(strippingNewline: true) else { break }
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      switch trimmed.lowercased() {
      case "", "r", "record":
        await store.send(.toggleRecording)
        let state = store.state
        if state.isRecording {
          print("  [RECORDING] Speak now... Press Enter to stop.")
        } else if state.isTranscribing {
          print("  [TRANSCRIBING] Processing audio...")
        }

      case "p", "paste":
        let text = store.state.lastTranscription
        if !text.isEmpty {
          await store.send(.pasteTranscription)
          print("  [PASTED] \(text.prefix(80))...")
        } else {
          print("  Nothing to paste. Record something first.")
        }

      case "models":
        let models = store.state.availableModels
        let downloaded = store.state.downloadedModels
        let registry = GGMLModelManifest.bundled()

        if models.isEmpty {
          print("  No models available. Type 'fetch' to refresh.")
        } else {
          print("\n  Available models:\n")
          for model in models {
            let entry = registry.first { $0.name == model }
            let isDownloaded = downloaded.contains(model)
            let marker = isDownloaded ? "✓" : " "
            let sizeStr = entry.map { humanReadableSize($0.sizeBytes) } ?? "?"
            let speedStr = entry.map { "speed:\(stars($0.speedStars))" } ?? ""
            let accStr = entry.map { "acc:\(stars($0.accuracyStars))" } ?? ""
            let lang = entry.map { $0.englishOnly ? "EN" : "ML" } ?? "?"

            print("  [\(marker)] \(model)")
            print("         \(sizeStr)  \(lang)  \(speedStr)  \(accStr)")
          }
          print("")
        }

      case "fetch":
        await store.send(.fetchModels)
        print("  Fetching models...")
        try? await Task.sleep(nanoseconds: 500_000_000)
        let state = store.state
        print("  Found \(state.availableModels.count) models, \(state.downloadedModels.count) downloaded.")

      case let dl where dl.hasPrefix("download"):
        let parts = dl.components(separatedBy: .whitespaces).dropFirst()
        guard let modelName = parts.first, !modelName.isEmpty else {
          print("  Usage: download <model-name>")
          print("  Example: download ggml-base.en.bin")
          print("  Use 'models' to see available models.")
          continue
        }
        print("  Downloading \(modelName)...")
        await store.send(.downloadModel(modelName))

        while store.state.isDownloading {
          let progress = store.state.downloadProgress
          let pct = Int(progress * 100)
          print("\r  \(progressBar(fraction: progress)) \(pct)%", terminator: "")
          fflush(stdout)
          try? await Task.sleep(nanoseconds: 500_000_000)
        }
        print("")

        let state = store.state
        if let error = state.error {
          print("  [ERROR] \(error)")
        } else {
          print("  [DONE] Model downloaded: \(modelName)")
        }

      case let del where del.hasPrefix("delete"):
        let parts = del.components(separatedBy: .whitespaces).dropFirst()
        guard let modelName = parts.first, !modelName.isEmpty else {
          print("  Usage: delete <model-name>")
          continue
        }
        print("  Deleting \(modelName)...")
        await store.send(.deleteModel(modelName))
        try? await Task.sleep(nanoseconds: 500_000_000)
        print("  [DONE]")

      case "status":
        let state = store.state
        print("""
          Recording: \(state.isRecording ? "active" : "idle")
          Transcribing: \(state.isTranscribing ? "yes" : "no")
          Models downloaded: \(state.downloadedModels.count)/\(state.availableModels.count)
          Selected model: \(state.hexSettings.selectedModel)
          Language: \(state.hexSettings.outputLanguage ?? "auto")
        """)

      case "lang", "language":
        let args = trimmed.components(separatedBy: .whitespaces).dropFirst()
        if let lang = args.first {
          store.state.$hexSettings.withLock { $0.outputLanguage = lang }
          print("  Language set to: \(lang)")
        } else {
          print("  Usage: lang <code>  (e.g., lang en, lang fr, lang auto)")
          print("  Current: \(store.state.hexSettings.outputLanguage ?? "auto")")
        }

      case "model", "select":
        let args = trimmed.components(separatedBy: .whitespaces).dropFirst()
        if let model = args.first {
          store.state.$hexSettings.withLock { $0.selectedModel = model }
          print("  Selected model: \(model)")
        } else {
          print("  Usage: model <model-name>")
          print("  Current: \(store.state.hexSettings.selectedModel)")
        }

      case "q", "quit", "exit":
        await store.send(.quit)
        break

      case "h", "help":
        print("""

          Commands:
          ─────────────────────────────────────────
          Enter / r      Start/stop recording
          p              Paste last transcription
          models         List available models
          fetch          Refresh model list
          download <n>   Download a model by name
          delete <n>     Delete a downloaded model
          model <n>      Select model for transcription
          lang <code>    Set output language (en, fr, auto, etc.)
          status         Show current state
          q / quit       Exit
          h / help       Show this help

          Quick start:
          1. models          (view available)
          2. download ggml-tiny.en.bin   (smallest, fastest)
          3. Press Enter to record, Enter again to stop
          4. p to paste the result
        """)

      default:
        print("  Unknown: '\(trimmed)'. Type 'h' for help.")
      }

      if !store.state.lastTranscription.isEmpty && !store.state.isRecording && !store.state.isTranscribing {
        let text = store.state.lastTranscription

        print("""

        ┌\(String(repeating: "─", count: min(text.count + 2, 72)))┐
        │ \(text.prefix(70)) │
        └\(String(repeating: "─", count: min(text.count + 2, 72)))┘

        Press 'p' to paste, Enter to record again.
        """)
      }

      if let error = store.state.error, !store.state.isDownloading {
        print("  [ERROR] \(error)")
        store.state.error = nil
      }
    }

    print("\nGoodbye!")
  }
}
#endif
