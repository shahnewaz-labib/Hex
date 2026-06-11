#if !os(macOS)
import Foundation
import HexCore

enum WebBridge {
  static func statusJSON(_ app: AppModel) -> String {
    let registry = GGMLModelManifest.bundled()
    let entry = registry.first { $0.name == app.settings.selectedModel }

    let dict: [String: Any] = [
      "isRecording": app.isRecording,
      "isTranscribing": app.isTranscribing,
      "isDownloading": app.isDownloading,
      "downloadProgress": app.downloadProgress,
      "lastTranscription": app.lastTranscription,
      "error": app.error as Any,
      "selectedModel": app.settings.selectedModel,
      "selectedModelDisplayName": entry?.displayName ?? app.settings.selectedModel,
      "outputLanguage": app.settings.outputLanguage as Any,
      "modelsDownloaded": app.downloadedModels.count,
      "modelsAvailable": app.availableModels.count,
    ]

    guard let data = try? JSONSerialization.data(withJSONObject: dict),
          let json = String(data: data, encoding: .utf8) else { return "{}" }
    return json
  }

  static func modelsJSON(_ app: AppModel) -> String {
    let registry = GGMLModelManifest.bundled()
    var models: [[String: Any]] = []
    for model in app.availableModels {
      let entry = registry.first { $0.name == model }
      let isDownloaded = app.downloadedModels.contains(model)
      let isSelected = app.settings.selectedModel == model
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
          let json = String(data: data, encoding: .utf8) else { return "{}" }
    return json
  }

  private static func humanReadableSize(_ bytes: Int64) -> String {
    if bytes < 1024 { return "\(bytes)B" }
    if bytes < 1024 * 1024 { return String(format: "%.1fKB", Double(bytes) / 1024) }
    if bytes < 1024 * 1024 * 1024 { return String(format: "%.1fMB", Double(bytes) / (1024 * 1024)) }
    return String(format: "%.2fGB", Double(bytes) / (1024 * 1024 * 1024))
  }
}
#endif
