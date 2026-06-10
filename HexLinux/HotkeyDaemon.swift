#if !os(macOS)
import Foundation
import HexCore

private let logger = HexLog.hotKey

final class HotkeyDaemon {
  private let socketPath: String
  private var serverFD: Int32 = -1
  private var clientFD: Int32 = -1
  private var isRunning = false
  private var inputFDs: [Int32] = []

  init(socketPath: String = "/tmp/hex-hotkey.sock") {
    self.socketPath = socketPath
  }

  func start(hotkey: HotKey, minimumKeyTime: TimeInterval) throws {
    guard !isRunning else { return }
    isRunning = true

    unlink(socketPath)

    serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard serverFD >= 0 else {
      throw HotkeyDaemonError.cannotCreateSocket(String(cString: strerror(errno)))
    }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    socketPath.withCString { strcpy(&addr.sun_path.0, $0) }

    let addrPtr = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
    }
    let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

    guard bind(serverFD, addrPtr, addrLen) >= 0 else {
      close(serverFD)
      throw HotkeyDaemonError.cannotBind(String(cString: strerror(errno)))
    }

    guard listen(serverFD, 1) >= 0 else {
      close(serverFD)
      throw HotkeyDaemonError.cannotListen(String(cString: strerror(errno)))
    }

    logger.info("Hotkey daemon listening on \(socketPath)")

    DispatchQueue.global().async { [weak self] in
      self?.acceptLoop(hotkey: hotkey, minimumKeyTime: minimumKeyTime)
    }
  }

  func stop() {
    isRunning = false
    if clientFD >= 0 { close(clientFD); clientFD = -1 }
    if serverFD >= 0 { close(serverFD); serverFD = -1 }
    for fd in inputFDs { close(fd) }
    inputFDs.removeAll()
    unlink(socketPath)
    logger.info("Hotkey daemon stopped")
  }

  private func acceptLoop(hotkey: HotKey, minimumKeyTime: TimeInterval) {
    clientFD = accept(serverFD, nil, nil)
    guard clientFD >= 0 else {
      logger.error("Accept failed: \(String(cString: strerror(errno)))")
      return
    }

    logger.info("Hex client connected to hotkey daemon")

    openInputDevices()

    var processor = HotKeyProcessor(
      hotkey: hotkey,
      useDoubleTapOnly: false,
      doubleTapLockEnabled: true,
      minimumKeyTime: minimumKeyTime
    )

    var activeModifiers: UInt16 = 0
    var pressedKeys: Set<UInt16> = []

    while isRunning {
      var event = input_event()
      var handled = false

      for fd in inputFDs {
        if read(fd, &event, MemoryLayout<input_event>.size) == MemoryLayout<input_event>.size {
          handled = true
          break
        }
      }

      guard handled else {
        usleep(5000)
        continue
      }

      guard event.type == UInt16(EV_KEY) else { continue }

      let code = event.code
      let isRepeat = event.value == 2

      if event.value == 1 {
        if code == KEY_LEFTCTRL || code == KEY_RIGHTCTRL { activeModifiers |= MOD_CONTROL }
        else if code == KEY_LEFTSHIFT || code == KEY_RIGHTSHIFT { activeModifiers |= MOD_SHIFT }
        else if code == KEY_LEFTALT || code == KEY_RIGHTALT { activeModifiers |= MOD_ALT }
        else if code == KEY_LEFTMETA || code == KEY_RIGHTMETA { activeModifiers |= MOD_META }
        else { pressedKeys.insert(code) }
      } else if event.value == 0 {
        if code == KEY_LEFTCTRL || code == KEY_RIGHTCTRL { activeModifiers &= ~MOD_CONTROL }
        else if code == KEY_LEFTSHIFT || code == KEY_RIGHTSHIFT { activeModifiers &= ~MOD_SHIFT }
        else if code == KEY_LEFTALT || code == KEY_RIGHTALT { activeModifiers &= ~MOD_ALT }
        else if code == KEY_LEFTMETA || code == KEY_RIGHTMETA { activeModifiers &= ~MOD_META }
        else { pressedKeys.remove(code) }
      } else { continue }

      if isRepeat { continue }

      let modifiers = daemonModifiers(from: activeModifiers)
      let key = pressedKeys.first.flatMap { daemonKey(from: $0) }
      let keyEvent = KeyEvent(key: key, modifiers: modifiers)

      if let output = processor.process(keyEvent: keyEvent) {
        switch output {
        case .startRecording:
          sendCommand("RECORD_START")
        case .stopRecording:
          sendCommand("RECORD_STOP")
        case .cancel:
          sendCommand("RECORD_CANCEL")
        case .discard:
          break
        }
      }
    }
  }

  private func sendCommand(_ cmd: String) {
    guard clientFD >= 0 else { return }
    var msg = cmd
    msg.withUTF8 { ptr in
      _ = write(clientFD, ptr.baseAddress!, ptr.count)
    }
    _ = write(clientFD, "\n", 1)
    logger.info("Sent: \(cmd)")
  }

  private func openInputDevices() {
    let fm = FileManager.default
    let inputDir = "/dev/input"

    guard let files = try? fm.contentsOfDirectory(atPath: inputDir) else {
      logger.error("Cannot read /dev/input — try: sudo usermod -a -G input $USER")
      return
    }

    for file in files where file.hasPrefix("event") {
      let path = "\(inputDir)/\(file)"
      let fd = open(path, O_RDONLY | O_NONBLOCK)
      guard fd >= 0 else { continue }

      var name = [CChar](repeating: 0, count: 256)
      ioctl(fd, UInt(EVIOCGNAME(256)), &name)
      let deviceName = String(cString: name).lowercased()

      if deviceName.contains("keyboard") || deviceName.contains("key") {
        inputFDs.append(fd)
        logger.info("Opened: \(deviceName) (\(path))")
      } else {
        close(fd)
      }
    }

    if inputFDs.isEmpty {
      logger.error("No keyboard devices found. Hotkey daemon will not work.")
    }
  }
}

private func daemonKey(from linuxKeyCode: UInt16) -> Key? {
  switch linuxKeyCode {
  case 1: return .escape
  case 2: return .one; case 3: return .two; case 4: return .three
  case 5: return .four; case 6: return .five; case 7: return .six
  case 8: return .seven; case 9: return .eight; case 10: return .nine
  case 11: return .zero; case 12: return .minus; case 13: return .equal
  case 14: return .delete; case 15: return .tab
  case 16: return .q; case 17: return .w; case 18: return .e
  case 19: return .r; case 20: return .t; case 21: return .y
  case 22: return .u; case 23: return .i; case 24: return .o
  case 25: return .p; case 26: return .leftBracket; case 27: return .rightBracket
  case 28: return .return
  case 30: return .a; case 31: return .s; case 32: return .d
  case 33: return .f; case 34: return .g; case 35: return .h
  case 36: return .j; case 37: return .k; case 38: return .l
  case 39: return .semicolon; case 40: return .quote; case 41: return .grave
  case 43: return .backslash
  case 44: return .z; case 45: return .x; case 46: return .c
  case 47: return .v; case 48: return .b; case 49: return .n
  case 50: return .m; case 51: return .comma; case 52: return .period
  case 53: return .slash; case 57: return .space
  case 59: return .f1; case 60: return .f2; case 61: return .f3
  case 62: return .f4; case 63: return .f5; case 64: return .f6
  case 65: return .f7; case 66: return .f8; case 67: return .f9
  case 68: return .f10; case 69: return .f11; case 70: return .f12
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

enum HotkeyDaemonError: LocalizedError {
  case cannotCreateSocket(String)
  case cannotBind(String)
  case cannotListen(String)

  var errorDescription: String? {
    switch self {
    case .cannotCreateSocket(let msg): return "Cannot create socket: \(msg)"
    case .cannotBind(let msg): return "Cannot bind: \(msg)"
    case .cannotListen(let msg): return "Cannot listen: \(msg)"
    }
  }
}

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
private let EV_SYN: UInt16 = 0
private let EVIOCGNAME: @convention(c) (Int32) -> UInt = { _ in
  let base: UInt = 0x4500
  let size: UInt = 256
  return base + ((size << 16) | 1)
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
#endif
