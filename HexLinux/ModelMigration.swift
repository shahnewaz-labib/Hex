#if !os(macOS)
import Foundation
import HexCore

enum ModelMigration {
  struct Mapping {
    let whisperKitName: String
    let ggmlName: String
    let displayName: String
  }

  static let mappings: [Mapping] = [
    Mapping(whisperKitName: "openai_whisper-tiny", ggmlName: "ggml-tiny.en.bin", displayName: "Whisper Tiny (English)"),
    Mapping(whisperKitName: "openai_whisper-base", ggmlName: "ggml-base.en.bin", displayName: "Whisper Base (English)"),
    Mapping(whisperKitName: "openai_whisper-small", ggmlName: "ggml-small.en.bin", displayName: "Whisper Small (English)"),
    Mapping(whisperKitName: "openai_whisper-medium", ggmlName: "ggml-medium.en.bin", displayName: "Whisper Medium (English)"),
    Mapping(whisperKitName: "openai_whisper-large-v3", ggmlName: "ggml-large-v3.bin", displayName: "Whisper Large v3"),
    Mapping(whisperKitName: "openai_whisper-large-v3-turbo", ggmlName: "ggml-large-v3-turbo.bin", displayName: "Whisper Large v3 Turbo"),
    Mapping(whisperKitName: "openai_whisper-large-v2", ggmlName: "ggml-large-v3.bin", displayName: "Whisper Large v3"),
    Mapping(whisperKitName: "distil-whisper_large-v3", ggmlName: "ggml-large-v3.bin", displayName: "Whisper Large v3"),
  ]

  static func mapToGGML(_ name: String) -> String? {
    if name.hasSuffix(".bin") { return name }

    if let mapping = mappings.first(where: { $0.whisperKitName == name }) {
      return mapping.ggmlName
    }

    if let mapping = mappings.first(where: { name.contains($0.whisperKitName) }) {
      return mapping.ggmlName
    }

    for mapping in mappings {
      let short = mapping.whisperKitName
        .replacingOccurrences(of: "openai_whisper-", with: "")
        .replacingOccurrences(of: "openai/", with: "")
        .replacingOccurrences(of: "distil-", with: "")
      if name.contains(short) {
        return mapping.ggmlName
      }
    }

    return nil
  }

  static func mapToDisplayName(_ name: String) -> String {
    if let mapping = mappings.first(where: { $0.whisperKitName == name || $0.ggmlName == name }) {
      return mapping.displayName
    }
    return name
      .replacingOccurrences(of: "-", with: " ")
      .replacingOccurrences(of: "_", with: " ")
      .capitalized
  }

  static func migrateSettings(_ settings: inout HexSettings) {
    let current = settings.selectedModel
    guard !current.isEmpty else { return }

    if let ggml = mapToGGML(current) {
      settings.selectedModel = ggml
    } else if current.hasSuffix(".bin") || current.hasSuffix(".ggml") {
    } else {
      settings.selectedModel = "ggml-base.en.bin"
    }
  }
}
#endif
