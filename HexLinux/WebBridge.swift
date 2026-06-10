#if !os(macOS)
import Foundation
import HexCore

enum WebBridge {
  static func statusJSON(from store: StoreOf<LinuxApp>) -> String {
    let state = store.state
    let registry = GGMLModelManifest.bundled()

    let modelEntry = registry.first { $0.name == state.hexSettings.selectedModel }

    let dict: [String: Any] = [
      "isRecording": state.isRecording,
      "isTranscribing": state.isTranscribing,
      "isDownloading": state.isDownloading,
      "downloadProgress": state.downloadProgress,
      "lastTranscription": state.lastTranscription,
      "error": state.error as Any,
      "selectedModel": state.hexSettings.selectedModel,
      "selectedModelDisplayName": modelEntry?.displayName ?? state.hexSettings.selectedModel,
      "outputLanguage": state.hexSettings.outputLanguage as Any,
      "modelsDownloaded": state.downloadedModels.count,
      "modelsAvailable": state.availableModels.count,
    ]

    guard let data = try? JSONSerialization.data(withJSONObject: dict),
          let json = String(data: data, encoding: .utf8) else {
      return "{}"
    }
    return json
  }

  static func modelsJSON(from store: StoreOf<LinuxApp>) -> String {
    let state = store.state
    let registry = GGMLModelManifest.bundled()

    var models: [[String: Any]] = []
    for model in state.availableModels {
      let entry = registry.first { $0.name == model }
      let isDownloaded = state.downloadedModels.contains(model)
      let isSelected = state.hexSettings.selectedModel == model

      models.append([
        "name": model,
        "displayName": entry?.displayName ?? model,
        "sizeBytes": entry?.sizeBytes ?? 0,
        "sizeHuman": humanReadableSize(entry?.sizeBytes ?? 0),
        "accuracyStars": entry?.accuracyStars ?? 0,
        "speedStars": entry?.speedStars ?? 0,
        "englishOnly": entry?.englishOnly ?? false,
        "isDownloaded": isDownloaded,
        "isSelected": isSelected,
      ])
    }

    let dict: [String: Any] = ["models": models]
    guard let data = try? JSONSerialization.data(withJSONObject: dict),
          let json = String(data: data, encoding: .utf8) else {
      return "{}"
    }
    return json
  }

  static func historyJSON(from store: StoreOf<LinuxApp>) -> String {
    return "[]"
  }

  private static func humanReadableSize(_ bytes: Int64) -> String {
    if bytes < 1024 { return "\(bytes)B" }
    if bytes < 1024 * 1024 { return String(format: "%.1fKB", Double(bytes) / 1024) }
    if bytes < 1024 * 1024 * 1024 { return String(format: "%.1fMB", Double(bytes) / (1024 * 1024)) }
    return String(format: "%.2fGB", Double(bytes) / (1024 * 1024 * 1024))
  }
}
#endif
