#if !os(macOS)
import Dependencies
import DependenciesMacros
import Foundation
import HexCore

private let modelsLogger = HexLog.models

@DependencyClient
struct ModelDownloadClient {
  var downloadModel: @Sendable (_ modelName: String, _ progress: @escaping (Double) -> Void) async throws -> URL
  var deleteModel: @Sendable (_ modelName: String) async throws -> Void
  var isModelDownloaded: @Sendable (_ modelName: String) -> Bool
  var getAvailableModels: @Sendable () -> [String]
  var getModelSize: @Sendable (_ modelName: String) -> Int64?
  var getDownloadedSize: @Sendable (_ modelName: String) -> Int64?
}

extension ModelDownloadClient: DependencyKey {
  static var liveValue: ModelDownloadClient {
    let live = ModelDownloadClientLive()
    return ModelDownloadClient(
      downloadModel: { name, progress in try await live.downloadModel(name, progress: progress) },
      deleteModel: { name in try await live.deleteModel(name) },
      isModelDownloaded: { live.isModelDownloaded($0) },
      getAvailableModels: { live.getAvailableModels() },
      getModelSize: { live.getModelSize($0) },
      getDownloadedSize: { live.getDownloadedSize($0) }
    )
  }
}

extension DependencyValues {
  var modelDownload: ModelDownloadClient {
    get { self[ModelDownloadClient.self] }
    set { self[ModelDownloadClient.self] = newValue }
  }
}

actor ModelDownloadClientLive {
  private let registry = GGMLModelManifest.loadFromDisk()

  func downloadModel(_ modelName: String, progress: @escaping (Double) -> Void) async throws -> URL {
    let resolvedName: String
    if registry.contains(where: { $0.name == modelName }) {
      resolvedName = modelName
    } else if let mapped = ModelMigration.mapToGGML(modelName) {
      resolvedName = mapped
      modelsLogger.info("Auto-mapped download: '\(modelName)' -> '\(mapped)'")
    } else {
      throw ModelDownloadError.modelNotFound(modelName)
    }

    guard let entry = registry.first(where: { $0.name == resolvedName }) else {
      throw ModelDownloadError.modelNotFound(modelName)
    }

    let modelsDir = try URL.hexModelsDirectory
    let destURL = modelsDir.appendingPathComponent(resolvedName)
    let partialURL = destURL.appendingPathExtension("part")

    modelsLogger.info("Downloading \(resolvedName) from \(entry.url)")

    if FileManager.default.fileExists(atPath: destURL.path) {
      modelsLogger.info("Model already fully downloaded: \(modelName)")
      progress(1.0)
      return destURL
    }

    var existingSize: Int64 = 0
    if FileManager.default.fileExists(atPath: partialURL.path),
       let attrs = try? FileManager.default.attributesOfItem(atPath: partialURL.path),
       let fileSize = attrs[.size] as? Int64 {
      existingSize = fileSize
      modelsLogger.info("Resuming download from byte \(existingSize)")
    }

    let curExeURL: URL
    if let whichOutput = try? await runCurl(executableURL: URL(fileURLWithPath: "/usr/bin/which"), arguments: ["curl"]) {
      curExeURL = URL(fileURLWithPath: "/usr/bin/curl")
    } else {
      modelsLogger.error("curl not found")
      throw ModelDownloadError.curlNotFound
    }

    var args: [String] = [
      "-L",
      "-f",
      "--retry", "3",
      "-o", partialURL.path,
      entry.url
    ]

    if existingSize > 0 {
      args.insert(contentsOf: ["-C", "-"], at: 2)
    } else {
      args.insert(contentsOf: ["-C", "-"], at: 2)
    }

    do {
      try await downloadWithCurlProgress(
        url: entry.url,
        dest: partialURL,
        expectedSize: entry.sizeBytes,
        existingSize: existingSize,
        progress: progress
      )

      try FileManager.default.moveItem(at: partialURL, to: destURL)
      modelsLogger.info("Downloaded \(modelName)")
      progress(1.0)
    } catch {
      modelsLogger.error("Download failed: \(error)")
      throw error
    }

    return destURL
  }

  func deleteModel(_ modelName: String) async throws {
    let modelsDir = try URL.hexModelsDirectory
    let modelURL = modelsDir.appendingPathComponent(modelName)
    let partURL = modelsDir.appendingPathComponent(modelName).appendingPathExtension("part")

    let fm = FileManager.default
    var removed = false

    if fm.fileExists(atPath: modelURL.path) {
      try fm.removeItem(at: modelURL)
      modelsLogger.info("Deleted model: \(modelName)")
      removed = true
    }

    if fm.fileExists(atPath: partURL.path) {
      try fm.removeItem(at: partURL)
      modelsLogger.info("Removed partial download: \(modelName)")
      removed = true
    }

    if !removed {
      modelsLogger.info("Model not found on disk: \(modelName)")
    }
  }

  func isModelDownloaded(_ modelName: String) -> Bool {
    guard let modelsDir = try? URL.hexModelsDirectory else { return false }

    if FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent(modelName).path) {
      return true
    }

    if let mapped = ModelMigration.mapToGGML(modelName) {
      if FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent(mapped).path) {
        return true
      }
    }

    return false
  }

  func getAvailableModels() -> [String] {
    registry.map(\.name)
  }

  func getModelSize(_ modelName: String) -> Int64? {
    registry.first(where: { $0.name == modelName })?.sizeBytes
  }

  func getDownloadedSize(_ modelName: String) -> Int64? {
    guard let modelsDir = try? URL.hexModelsDirectory else { return nil }
    let modelURL = modelsDir.appendingPathComponent(modelName)
    if FileManager.default.fileExists(atPath: modelURL.path),
       let attrs = try? FileManager.default.attributesOfItem(atPath: modelURL.path),
       let size = attrs[.size] as? Int64 {
      return size
    }
    return nil
  }

  private func downloadWithCurlProgress(
    url: String,
    dest: URL,
    expectedSize: Int64,
    existingSize: Int64,
    progress: @escaping (Double) -> Void
  ) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")

    var args = [
      "-L", "-f",
      "--retry", "3",
      "-o", dest.path,
      url
    ]
    if existingSize > 0 {
      args.insert(contentsOf: ["--continue-at", "-"], at: 2)
    }
    process.arguments = args
    process.standardOutput = FileHandle.nullDevice

    let pipe = Pipe()
    process.standardError = pipe

    var progressDone = false

    try process.run()

    let handle = pipe.fileHandleForReading
    handle.readabilityHandler = { [expectedSize] fh in
      guard !progressDone else { return }
      let data = fh.availableData
      guard data.count > 0 else { return }

      if let text = String(data: data, encoding: .utf8) {
        let downloadedSize = Self.parseCurlProgress(text)
        if downloadedSize > 0 {
          let totalSize = max(expectedSize, downloadedSize)
          let fraction = min(Double(downloadedSize) / Double(totalSize), 0.99)
          progress(fraction)
        }

        if text.contains("100") && text.contains("%") {
          progressDone = true
        }
      }
    }

    process.waitUntilExit()

    handle.readabilityHandler = nil

    guard process.terminationStatus == 0 else {
      let errorData = try? handle.readToEnd()
      let errorMsg = errorData.flatMap { String(data: $0, encoding: .utf8) } ?? "curl exited with code \(process.terminationStatus)"
      throw ModelDownloadError.downloadFailed(errorMsg.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  private static func parseCurlProgress(_ text: String) -> Int64 {
    for line in text.components(separatedBy: .newlines).reversed() {
      if line.contains("%") {
        let scanner = line.trimmingCharacters(in: .whitespaces)
        let parts = scanner.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for i in 0..<parts.count {
          if parts[i].hasSuffix("%") && i + 1 < parts.count {
            let sizeStr = parts[i + 1]
            if let bytes = parseHumanSize(sizeStr) {
              return bytes
            }
          }
        }
      }
    }
    return 0
  }

  private static func parseHumanSize(_ s: String) -> Int64? {
    if let v = Int64(s) { return v }

    let multipliers: [Character: Int64] = ["k": 1024, "K": 1024, "m": 1024 * 1024, "M": 1024 * 1024, "g": 1024 * 1024 * 1024, "G": 1024 * 1024 * 1024]

    for (suffix, mult) in multipliers {
      if s.hasSuffix(String(suffix)) {
        let numPart = String(s.dropLast())
        if let v = Double(numPart) {
          return Int64(v * Double(mult))
        }
      }
    }

    return nil
  }
}

func runCurl(executableURL: URL, arguments: [String]) async throws -> String {
  let process = Process()
  process.executableURL = executableURL
  process.arguments = arguments
  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = FileHandle.nullDevice
  try process.run()
  process.waitUntilExit()
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  return String(data: data, encoding: .utf8) ?? ""
}

enum ModelDownloadError: LocalizedError {
  case modelNotFound(String)
  case curlNotFound
  case downloadFailed(String)

  var errorDescription: String? {
    switch self {
    case .modelNotFound(let name):
      return "Model not found in registry: \(name)"
    case .curlNotFound:
      return "curl is required for model downloads. Install it: sudo apt install curl"
    case .downloadFailed(let msg):
      return "Download failed: \(msg)"
    }
  }
}

struct ModelSupport {
  let `default`: String
  let available: [String]
  let curated: [CuratedModelInfo]

  struct CuratedModelInfo: Equatable {
    let name: String
    let displayName: String
    let size: String
    let accuracyStars: Int
    let speedStars: Int
    let englishOnly: Bool
  }
}
#endif
