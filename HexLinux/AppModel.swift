#if !os(macOS)
import Foundation
import HexCore
import Logging

@Observable
final class AppModel: @unchecked Sendable {
  var isRecording = false
  var isTranscribing = false
  var isDownloading = false
  var downloadProgress: Double = 0
  var lastTranscription = ""
  var error: String?
  var recordingStartTime: Date?
  var downloadedModels: [String] = []
  var availableModels: [String] = []

  var settings: HexSettings {
    didSet { saveSettings() }
  }

  private let settingsURL: URL

  init() {
    settingsURL = HexLinuxPaths.settingsFile()
    if let data = try? Data(contentsOf: settingsURL),
       let decoded = try? JSONDecoder().decode(HexSettings.self, from: data) {
      settings = decoded
    } else {
      settings = HexSettings()
    }

    let oldModel = settings.selectedModel
    ModelMigration.migrateSettings(&settings)
    if settings.selectedModel != oldModel {
      HexLog.app.notice("Migrated model: '\(oldModel)' -> '\(settings.selectedModel)'")
    }
  }

  private func saveSettings() {
    if let data = try? JSONEncoder().encode(settings) {
      try? data.write(to: settingsURL)
    }
  }

  func task() async {
    await fetchModels()
  }

  func toggleRecording() async {
    if isRecording {
      isRecording = false
      isTranscribing = true
      let url = await RecordingClient.liveValue.stopRecording()
      await handleRecordingStopped(url)
    } else {
      lastTranscription = ""
      error = nil
      recordingStartTime = Date()
      await RecordingClient.liveValue.startRecording()
      isRecording = true
    }
  }

  private func handleRecordingStopped(_ url: URL) async {
    do {
      let text = try await TranscriptionClient.liveValue.transcribe(url, settings.outputLanguage, settings.selectedModel)
      isTranscribing = false
      lastTranscription = text
      error = nil
    } catch {
      isTranscribing = false
      error = error.localizedDescription
    }
  }

  func fetchModels() async {
    availableModels = await TranscriptionClient.liveValue.getAvailableModels()
    var downloaded: [String] = []
    for model in availableModels {
      if await TranscriptionClient.liveValue.isModelDownloaded(model) {
        downloaded.append(model)
      }
    }
    downloadedModels = downloaded
  }

  func downloadModel(_ name: String) async {
    isDownloading = true
    downloadProgress = 0
    error = nil
    do {
      try await TranscriptionClient.liveValue.downloadModel(name) { [weak self] fraction in
        Task { @MainActor [weak self] in
          self?.downloadProgress = fraction
        }
      }
      isDownloading = false
      downloadProgress = 1.0
      if !downloadedModels.contains(name) {
        downloadedModels.append(name)
      }
      await fetchModels()
    } catch {
      isDownloading = false
      downloadProgress = 0
      self.error = error.localizedDescription
    }
  }

  func deleteModel(_ name: String) async {
    do {
      try await TranscriptionClient.liveValue.deleteModel(name)
      await fetchModels()
    } catch {
      self.error = error.localizedDescription
    }
  }

  func pasteTranscription() async {
    guard !lastTranscription.isEmpty else { return }
    await PasteboardClient.liveValue.paste(lastTranscription)
  }
}

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
#endif
