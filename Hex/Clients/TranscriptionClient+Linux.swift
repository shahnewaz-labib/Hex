#if !os(macOS)
import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import HexCore

private let transcriptionLogger = HexLog.transcription

@DependencyClient
struct TranscriptionClient {
  var transcribe: @Sendable (_ audioURL: URL, _ language: String?, _ modelPath: String?) async throws -> String
  var loadModel: @Sendable (_ modelPath: String) async throws -> Void
  var getAvailableModels: @Sendable () async -> [String]
  var defaultModelPath: @Sendable () -> String
}

extension TranscriptionClient: DependencyKey {
  static var liveValue: Self {
    let live = TranscriptionClientLive()
    return .init(
      transcribe: { url, lang, path in try await live.transcribe(audioURL: url, language: lang, modelPath: path) },
      loadModel: { path in try await live.loadModel(modelPath: path) },
      getAvailableModels: { await live.getAvailableModels() },
      defaultModelPath: { live.defaultModelPath() }
    )
  }

  static var testValue: Self {
    .init(
      transcribe: { _, _, _ in "Test transcription" },
      loadModel: { _ in },
      getAvailableModels: { [] },
      defaultModelPath: { "" }
    )
  }
}

extension DependencyValues {
  var transcription: TranscriptionClient {
    get { self[TranscriptionClient.self] }
    set { self[TranscriptionClient.self] = newValue }
  }
}

actor TranscriptionClientLive {
  private var loadedModelPath: String?
  private let whisperBinPath: String

  init(whisperBinPath: String = "whisper-cpp") {
    self.whisperBinPath = whisperBinPath
  }

  func transcribe(audioURL: URL, language: String?, modelPath: String?) async throws -> String {
    let model = modelPath ?? defaultModelPath()

    let resolvedModelPath: String
    if model.hasPrefix("/") || model.hasPrefix("~") {
      resolvedModelPath = (model as NSString).expandingTildeInPath
    } else {
      let modelsDir = (try? URL.hexModelsDirectory.path) ?? ""
      resolvedModelPath = (modelsDir as NSString).appendingPathComponent(model)
    }

    guard FileManager.default.fileExists(atPath: resolvedModelPath) else {
      throw TranscriptionError.modelNotFound(resolvedModelPath)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: whisperBinPath)

    var args = [
      "-m", resolvedModelPath,
      "-f", audioURL.path,
      "-otxt",
      "-of", audioURL.deletingPathExtension().path,
      "--no-timestamps"
    ]

    if let lang = language {
      args.append(contentsOf: ["-l", lang])
    }

    process.arguments = args

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()

      let outputPath = audioURL.deletingPathExtension().path + ".txt"
      if FileManager.default.fileExists(atPath: outputPath),
         let text = try? String(contentsOfFile: outputPath, encoding: .utf8) {
        try? FileManager.default.removeItem(atPath: outputPath)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
      }

      if process.terminationStatus != 0 {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw TranscriptionError.transcriptionFailed(errorMsg)
      }

      return ""
    } catch let error as TranscriptionError {
      throw error
    } catch {
      throw TranscriptionError.transcriptionFailed(error.localizedDescription)
    }
  }

  func loadModel(modelPath: String) async throws {
    let resolvedPath: String
    if modelPath.hasPrefix("/") || modelPath.hasPrefix("~") {
      resolvedPath = (modelPath as NSString).expandingTildeInPath
    } else {
      let modelsDir = (try? URL.hexModelsDirectory.path) ?? ""
      resolvedPath = (modelsDir as NSString).appendingPathComponent(modelPath)
    }

    guard FileManager.default.fileExists(atPath: resolvedPath) else {
      throw TranscriptionError.modelNotFound(resolvedPath)
    }

    loadedModelPath = resolvedPath
    transcriptionLogger.info("Model loaded: \(resolvedPath)")
  }

  func getAvailableModels() async -> [String] {
    var models: [String] = []

    do {
      let modelsDir = try URL.hexModelsDirectory
      let files = (try? FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: nil)) ?? []

      for file in files where file.pathExtension == "bin" || file.pathExtension == "ggml" {
        models.append(file.lastPathComponent)
      }
    } catch {
      transcriptionLogger.error("Failed to enumerate models: \(error)")
    }

    return models.sorted()
  }

  func defaultModelPath() -> String {
    return "ggml-base.en.bin"
  }
}

enum TranscriptionError: LocalizedError {
  case modelNotFound(String)
  case transcriptionFailed(String)
  case noModelsAvailable

  var errorDescription: String? {
    switch self {
    case .modelNotFound(let path):
      return "Whisper model not found: \(path)"
    case .transcriptionFailed(let message):
      return "Transcription failed: \(message)"
    case .noModelsAvailable:
      return "No whisper models available. Please download a model first."
    }
  }
}
#endif
