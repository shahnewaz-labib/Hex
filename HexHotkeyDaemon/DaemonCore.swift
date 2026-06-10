#if !os(macOS)
import Foundation
import HexCore

private let logger = HexLog.hotKey

// Shared constants
private let MOD_SHIFT: UInt16 = 0x01
private let MOD_CONTROL: UInt16 = 0x04
private let MOD_ALT: UInt16 = 0x08
private let MOD_META: UInt16 = 0x40
private let KEY_LEFTCTRL: UInt16 = 29
private let KEY_LEFTSHIFT: UInt16 = 42
private let KEY_LEFTALT: UInt16 = 56
private let KEY_LEFTMETA: UInt16 = 125
private let KEY_RIGHTCTRL: UInt16 = 97
private let KEY_RIGHTSHIFT: UInt16 = 54
private let KEY_RIGHTALT: UInt16 = 100
private let KEY_RIGHTMETA: UInt16 = 126
private let EV_KEY: UInt16 = 1

private let EVIOCGNAME: @convention(c) (Int32) -> UInt = { _ in
  UInt(0x4500) + ((256 << 16) | 1)
}()

private struct input_event {
  var time: timeval = timeval()
  var type: UInt16 = 0
  var code: UInt16 = 0
  var value: Int32 = 0
}

private struct timeval {
  var tv_sec: Int = 0
  var tv_usec: Int = 0
}

func runHotkeyDaemon(hotkey: HotKey, minimumKeyTime: TimeInterval, socketPath: String) throws {
  unlink(socketPath)

  let serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
  guard serverFD >= 0 else { throw NSError(domain: "hexd", code: 1, userInfo: [NSLocalizedDescriptionKey: "socket failed"]) }

  var addr = sockaddr_un()
  addr.sun_family = sa_family_t(AF_UNIX)
  socketPath.withCString { strcpy(&addr.sun_path.0, $0) }

  let addrPtr = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 } }
  guard bind(serverFD, addrPtr, socklen_t(MemoryLayout<sockaddr_un>.size)) >= 0 else {
    close(serverFD); throw NSError(domain: "hexd", code: 2, userInfo: [NSLocalizedDescriptionKey: "bind failed"])
  }
  guard listen(serverFD, 1) >= 0 else {
    close(serverFD); throw NSError(domain: "hexd", code: 3, userInfo: [NSLocalizedDescriptionKey: "listen failed"])
  }

  logger.info("Hotkey daemon on \(socketPath)")

  let clientFD = accept(serverFD, nil, nil)
  guard clientFD >= 0 else {
    close(serverFD); throw NSError(domain: "hexd", code: 4, userInfo: [NSLocalizedDescriptionKey: "accept failed"])
  }

  logger.info("Client connected")

  let fds = openKeyboards()
  if fds.isEmpty {
    logger.error("No keyboards found. Run: sudo usermod -a -G input $USER && newgrp input")
    close(clientFD); close(serverFD); unlink(socketPath)
    return
  }

  var processor = HotKeyProcessor(hotkey: hotkey, minimumKeyTime: minimumKeyTime)
  var activeModifiers: UInt16 = 0
  var pressedKeys: Set<UInt16> = []

  while true {
    var event = input_event()
    var handled = false

    for fd in fds {
      if read(fd, &event, MemoryLayout<input_event>.size) == MemoryLayout<input_event>.size {
        handled = true
        break
      }
    }

    guard handled else {
      usleep(5000)
      continue
    }

    guard event.type == EV_KEY, event.value != 2 else { continue }

    let code = event.code
    let isDown = event.value == 1

    if isDown {
      switch code {
      case KEY_LEFTCTRL, KEY_RIGHTCTRL: activeModifiers |= MOD_CONTROL
      case KEY_LEFTSHIFT, KEY_RIGHTSHIFT: activeModifiers |= MOD_SHIFT
      case KEY_LEFTALT, KEY_RIGHTALT: activeModifiers |= MOD_ALT
      case KEY_LEFTMETA, KEY_RIGHTMETA: activeModifiers |= MOD_META
      default: pressedKeys.insert(code)
      }
    } else {
      switch code {
      case KEY_LEFTCTRL, KEY_RIGHTCTRL: activeModifiers &= ~MOD_CONTROL
      case KEY_LEFTSHIFT, KEY_RIGHTSHIFT: activeModifiers &= ~MOD_SHIFT
      case KEY_LEFTALT, KEY_RIGHTALT: activeModifiers &= ~MOD_ALT
      case KEY_LEFTMETA, KEY_RIGHTMETA: activeModifiers &= ~MOD_META
      default: pressedKeys.remove(code)
      }
    }

    let modifiers = daemonModifiers(from: activeModifiers)
    let key = pressedKeys.first.flatMap { linuxKeyToHexKey($0) }
    let keyEvent = KeyEvent(key: isDown ? key : nil, modifiers: modifiers)

    if let output = processor.process(keyEvent: keyEvent) {
      let cmd: String
      switch output {
      case .startRecording: cmd = "RECORD_START"
      case .stopRecording: cmd = "RECORD_STOP"
      case .cancel: cmd = "RECORD_CANCEL"
      case .discard: cmd = "RECORD_DISCARD"
      }
      _ = cmd.withUTF8 { buf in write(clientFD, buf.baseAddress!, buf.count) }
      _ = write(clientFD, "\n", 1)
      logger.info("Sent: \(cmd)")
    }
  }
}

private func openKeyboards() -> [Int32] {
  var fds: [Int32] = []
  guard let files = try? FileManager.default.contentsOfDirectory(atPath: "/dev/input") else { return fds }
  for file in files where file.hasPrefix("event") {
    let path = "/dev/input/\(file)"
    let fd = open(path, O_RDONLY | O_NONBLOCK)
    guard fd >= 0 else { continue }
    var name = [CChar](repeating: 0, count: 256)
    ioctl(fd, UInt(EVIOCGNAME(256)), &name)
    let devName = String(cString: name).lowercased()
    if devName.contains("keyboard") || devName.contains("key") {
      fds.append(fd)
      logger.info("Keyboard: \(devName)")
    } else { close(fd) }
  }
  return fds
}

private func linuxKeyToHexKey(_ code: UInt16) -> Key? {
  switch code {
  case 1: return .escape
  case 2: return .one; case 3: return .two; case 4: return .three; case 5: return .four
  case 6: return .five; case 7: return .six; case 8: return .seven; case 9: return .eight
  case 10: return .nine; case 11: return .zero; case 12: return .minus; case 13: return .equal
  case 14: return .delete; case 15: return .tab
  case 16: return .q; case 17: return .w; case 18: return .e; case 19: return .r; case 20: return .t
  case 21: return .y; case 22: return .u; case 23: return .i; case 24: return .o; case 25: return .p
  case 26: return .leftBracket; case 27: return .rightBracket; case 28: return .return
  case 30: return .a; case 31: return .s; case 32: return .d; case 33: return .f
  case 34: return .g; case 35: return .h; case 36: return .j; case 37: return .k; case 38: return .l
  case 39: return .semicolon; case 40: return .quote; case 41: return .grave; case 43: return .backslash
  case 44: return .z; case 45: return .x; case 46: return .c; case 47: return .v; case 48: return .b
  case 49: return .n; case 50: return .m; case 51: return .comma; case 52: return .period; case 53: return .slash
  case 57: return .space
  case 59...68: return Key(rawValue: "f\(code - 58)")
  case 87: return .f11; case 88: return .f12
  case 96: return .keypadEnter; case 98: return .keypadDivide
  case 102: return .home; case 103: return .upArrow; case 104: return .pageUp
  case 105: return .leftArrow; case 106: return .rightArrow
  case 107: return .end; case 108: return .downArrow; case 109: return .pageDown
  case 110: return .forwardDelete; case 111: return .help
  default: return nil
  }
}

private func daemonModifiers(from mask: UInt16) -> Modifiers {
  var mods: Set<Modifier> = []
  if mask & MOD_SHIFT != 0 { mods.insert(.shift) }
  if mask & MOD_CONTROL != 0 { mods.insert(.control) }
  if mask & MOD_ALT != 0 { mods.insert(.option) }
  if mask & MOD_META != 0 { mods.insert(.command) }
  return Modifiers(modifiers: mods)
}
#endif
