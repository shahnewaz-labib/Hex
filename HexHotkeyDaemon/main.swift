#if !os(macOS)
import Foundation
import HexCore
import Logging

LoggingSystem.bootstrap { label in
  var handler = StreamLogHandler.standardOutput(label: label)
  handler.logLevel = .info
  return handler
}

let logger = HexLog.app

let args = CommandLine.arguments

let socketPath: String
let hotkey: HotKey
let minimumKeyTime: Double

if args.count >= 2 {
  socketPath = args[1]
} else {
  socketPath = "/tmp/hex-hotkey.sock"
}

if args.count >= 4 {
  let keyStr = args.count > 2 ? args[2] : ""
  let modStr = args.count > 3 ? args[3] : ""

  let key: Key? = keyStr.isEmpty || keyStr == "nil" ? nil : Key(rawValue: keyStr)

  var modifiers: Set<Modifier> = []
  for mod in modStr.components(separatedBy: ",") {
    switch mod.lowercased().trimmingCharacters(in: .whitespaces) {
    case "command", "cmd", "super": modifiers.insert(.command)
    case "option", "opt", "alt": modifiers.insert(.option)
    case "shift": modifiers.insert(.shift)
    case "control", "ctrl": modifiers.insert(.control)
    case "fn": modifiers.insert(.fn)
    default: break
    }
  }

  hotkey = HotKey(key: key, modifiers: Modifiers(modifiers: modifiers))
} else {
  hotkey = HotKey(key: nil, modifiers: [.option])
}

minimumKeyTime = args.count >= 6 ? Double(args[5]) ?? 0.2 : 0.2

logger.info("Hex Hotkey Daemon")
logger.info("Socket: \(socketPath)")
logger.info("Hotkey: key=\(hotkey.key?.rawValue ?? "nil") modifiers=\(hotkey.modifiers.sorted.map(\.kind.rawValue))")
logger.info("Min key time: \(minimumKeyTime)s")

do {
  try runHotkeyDaemon(hotkey: hotkey, minimumKeyTime: minimumKeyTime, socketPath: socketPath)
} catch {
  logger.error("Daemon failed: \(error)")
  exit(1)
}
#endif
