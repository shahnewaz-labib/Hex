#if !os(macOS)
import Foundation
import HexCore
import Logging

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

    let app = AppModel()
    await app.task()

    let server = HexWebServer(port: 8765, app: app)
    do {
      try await server.start()
    } catch {
      logger.error("Failed to start web server: \(error)")
      print("ERROR: Could not start web server on port 8765.")
      return
    }

    let daemonSocketPath = "/tmp/hex-hotkey.sock"
    var daemonProcess: Process?

    let daemonBin = "\(installPrefix())/bin/hex-hotkeyd"
    if FileManager.default.fileExists(atPath: daemonBin) {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: daemonBin)
      let keyStr = app.settings.hotkey.key?.rawValue ?? "nil"
      let modStr = app.settings.hotkey.modifiers.sorted.map(\.kind.rawValue).joined(separator: ",")
      process.arguments = [daemonSocketPath, keyStr, modStr, String(app.settings.minimumKeyTime)]
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      try? process.run()
      daemonProcess = process
      logger.info("Hotkey daemon started")
    }

    Task {
      let monitor = KeyEventMonitorClientLive()
      await monitor.startDaemonMonitoring(socketPath: daemonSocketPath)
    }

    openBrowser("http://127.0.0.1:8765")

    print("""
    ╔═══════════════════════════════════════════╗
    ║           Hex — Voice to Text             ║
    ║           Linux Edition                   ║
    ╠═══════════════════════════════════════════╣
    ║  Web UI: http://127.0.0.1:8765           ║
    ║  CLI: Enter=record p=paste q=quit         ║
    ╚═══════════════════════════════════════════╝
    """)

    while true {
      guard let line = readLine(strippingNewline: true) else { break }
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      switch trimmed.lowercased() {
      case "", "r", "record":
        await app.toggleRecording()
        if app.isRecording { print("  [RECORDING]") }
        else if app.isTranscribing { print("  [TRANSCRIBING]") }

      case "p", "paste":
        if !app.lastTranscription.isEmpty {
          await app.pasteTranscription()
          print("  [PASTED]")
        } else { print("  Nothing to paste.") }

      case "models":
        let reg = GGMLModelManifest.bundled()
        for m in app.availableModels {
          let dl = app.downloadedModels.contains(m) ? "✓" : " "
          let entry = reg.first { $0.name == m }
          print("  [\(dl)] \(m)  \(entry.map { Self.humanReadableSize($0.sizeBytes) } ?? "?")")
        }

      case "fetch":
        await app.fetchModels()
        print("  Refreshing...")

      case let dl where dl.hasPrefix("download"):
        let parts = dl.components(separatedBy: .whitespaces).dropFirst()
        if let name = parts.first {
          print("  Downloading \(name)...")
          await app.downloadModel(name)
          while app.isDownloading {
            let pct = Int(app.downloadProgress * 100)
            print("\r  \(Self.bar(f: app.downloadProgress)) \(pct)%", terminator: "")
            fflush(stdout)
            try? await Task.sleep(nanoseconds: 500_000_000)
          }
          print("")
          print(app.error != nil ? "  [ERROR] \(app.error!)" : "  [DONE]")
        }

      case let del where del.hasPrefix("delete"):
        if let name = del.components(separatedBy: .whitespaces).dropFirst().first {
          await app.deleteModel(name)
          print("  Deleted \(name)")
        }

      case "status":
        print("  Rec:\(app.isRecording) Trans:\(app.isTranscribing) DL:\(app.isDownloading) Models:\(app.downloadedModels.count)/\(app.availableModels.count)")

      case "q", "quit", "exit":
        print("  Shutting down...")
        break

      case "h", "help":
        print("  Enter=record, p=paste, models, download <n>, delete <n>, status, q=quit")

      default:
        print("  Unknown: '\(trimmed)' (h for help)")
      }
    }

    daemonProcess?.terminate()
    await server.stop()
    logger.info("Hex Linux exiting.")
    print("Goodbye!")
  }

  static func installPrefix() -> String {
    ProcessInfo.processInfo.environment["HEX_INSTALL_PREFIX"]
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local").path
  }

  static func openBrowser(_ url: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["xdg-open", url]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
  }

  private static func humanReadableSize(_ bytes: Int64) -> String {
    if bytes < 1024 { return "\(bytes)B" }
    if bytes < 1024 * 1024 { return String(format: "%.1fKB", Double(bytes) / 1024) }
    if bytes < 1024 * 1024 * 1024 { return String(format: "%.1fMB", Double(bytes) / (1024 * 1024)) }
    return String(format: "%.2fGB", Double(bytes) / (1024 * 1024 * 1024))
  }

  private static func bar(_ f: Double, _ w: Int = 30) -> String {
    let n = Int(Double(w) * max(0, min(1, f)))
    return "[" + String(repeating: "=", count: n) + String(repeating: " ", count: w - n) + "]"
  }
}
#endif
