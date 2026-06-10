#if !os(macOS)
import Foundation
import HexCore

private let modelsLogger = HexLog.models

struct GGMLModelManifest: Codable {
  struct Entry: Codable {
    let name: String
    let url: String
    let sha256: String?
    let sizeBytes: Int64
    let displayName: String
    let englishOnly: Bool
    let accuracyStars: Int
    let speedStars: Int
  }

  let models: [Entry]

  static let defaultManifestURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/raw/main/models.json")!

  static func bundled() -> [Entry] {
    return [
      Entry(
        name: "ggml-tiny.en.bin",
        url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin",
        sha256: nil,
        sizeBytes: 77_886_016,
        displayName: "Whisper Tiny (English)",
        englishOnly: true,
        accuracyStars: 2,
        speedStars: 5
      ),
      Entry(
        name: "ggml-tiny.bin",
        url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin",
        sha256: nil,
        sizeBytes: 77_886_016,
        displayName: "Whisper Tiny (Multilingual)",
        englishOnly: false,
        accuracyStars: 2,
        speedStars: 5
      ),
      Entry(
        name: "ggml-base.en.bin",
        url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin",
        sha256: nil,
        sizeBytes: 147_964_352,
        displayName: "Whisper Base (English)",
        englishOnly: true,
        accuracyStars: 3,
        speedStars: 4
      ),
      Entry(
        name: "ggml-base.bin",
        url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin",
        sha256: nil,
        sizeBytes: 147_964_352,
        displayName: "Whisper Base (Multilingual)",
        englishOnly: false,
        accuracyStars: 3,
        speedStars: 4
      ),
      Entry(
        name: "ggml-small.en.bin",
        url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin",
        sha256: nil,
        sizeBytes: 487_841_216,
        displayName: "Whisper Small (English)",
        englishOnly: true,
        accuracyStars: 3,
        speedStars: 3
      ),
      Entry(
        name: "ggml-small.bin",
        url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin",
        sha256: nil,
        sizeBytes: 487_841_216,
        displayName: "Whisper Small (Multilingual)",
        englishOnly: false,
        accuracyStars: 3,
        speedStars: 3
      ),
      Entry(
        name: "ggml-medium.en.bin",
        url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin",
        sha256: nil,
        sizeBytes: 1_539_069_376,
        displayName: "Whisper Medium (English)",
        englishOnly: true,
        accuracyStars: 4,
        speedStars: 2
      ),
      Entry(
        name: "ggml-medium.bin",
        url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin",
        sha256: nil,
        sizeBytes: 1_539_069_376,
        displayName: "Whisper Medium (Multilingual)",
        englishOnly: false,
        accuracyStars: 4,
        speedStars: 2
      ),
      Entry(
        name: "ggml-large-v3.bin",
        url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin",
        sha256: nil,
        sizeBytes: 3_097_321_408,
        displayName: "Whisper Large v3 (Multilingual)",
        englishOnly: false,
        accuracyStars: 5,
        speedStars: 1
      ),
      Entry(
        name: "ggml-large-v3-turbo.bin",
        url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin",
        sha256: nil,
        sizeBytes: 1_618_431_552,
        displayName: "Whisper Large v3 Turbo (Multilingual)",
        englishOnly: false,
        accuracyStars: 5,
        speedStars: 2
      ),
    ]
  }

  func entry(for name: String) -> Entry? {
    models.first { $0.name == name }
  }

  static func loadFromDisk() -> [Entry] {
    let modelsDir = (try? URL.hexModelsDirectory) ?? URL(fileURLWithPath: "")
    let manifestURL = modelsDir.appendingPathComponent("ggml-models.json")
    if let data = try? Data(contentsOf: manifestURL),
       let manifest = try? JSONDecoder().decode(GGMLModelManifest.self, from: data) {
      return manifest.models
    }
    return bundled()
  }
}
#endif
