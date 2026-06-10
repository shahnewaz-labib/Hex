#if !os(macOS)
import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import HexCore

private let logger = HexLog.keyEvent

struct KeyEventMonitorToken: Sendable {
  private let cancelHandler: @Sendable () -> Void

  init(cancel: @escaping @Sendable () -> Void) {
    self.cancelHandler = cancel
  }

  func cancel() {
    cancelHandler()
  }

  static let noop = KeyEventMonitorToken(cancel: {})
}

@DependencyClient
struct KeyEventMonitorClient {
  var listenForKeyPress: @Sendable () async -> AsyncThrowingStream<KeyEvent, Error> = { .never }
  var handleKeyEvent: @Sendable (@Sendable @escaping (KeyEvent) -> Bool) -> KeyEventMonitorToken = { _ in .noop }
  var handleInputEvent: @Sendable (@Sendable @escaping (InputEvent) -> Bool) -> KeyEventMonitorToken = { _ in .noop }
  var startMonitoring: @Sendable () async -> Void = {}
  var stopMonitoring: @Sendable () -> Void = {}
  var startDaemonMonitoring: @Sendable (_ socketPath: String) async -> Void = { _ in }
}

extension KeyEventMonitorClient: DependencyKey {
  static var liveValue: KeyEventMonitorClient {
    let live = KeyEventMonitorClientLive()
    return KeyEventMonitorClient(
      listenForKeyPress: { live.listenForKeyPress() },
      handleKeyEvent: { handler in live.handleKeyEvent(handler) },
      handleInputEvent: { handler in live.handleInputEvent(handler) },
      startMonitoring: { live.startMonitoring() },
      stopMonitoring: { live.stopMonitoring() },
      startDaemonMonitoring: { path in live.startDaemonMonitoring(socketPath: path) }
    )
  }
}

extension DependencyValues {
  var keyEventMonitor: KeyEventMonitorClient {
    get { self[KeyEventMonitorClient.self] }
    set { self[KeyEventMonitorClient.self] = newValue }
  }
}

private struct InputEvent {
  var timeSec: Int
  var timeUsec: Int
  var type: UInt16
  var code: UInt16
  var value: Int32
}

private func linuxKeyCodeToKey(_ keyCode: UInt16) -> Key? {
  switch keyCode {
  case 1: return .escape
  case 2: return .one
  case 3: return .two
  case 4: return .three
  case 5: return .four
  case 6: return .five
  case 7: return .six
  case 8: return .seven
  case 9: return .eight
  case 10: return .nine
  case 11: return .zero
  case 12: return .minus
  case 13: return .equal
  case 14: return .delete
  case 15: return .tab
  case 16: return .q
  case 17: return .w
  case 18: return .e
  case 19: return .r
  case 20: return .t
  case 21: return .y
  case 22: return .u
  case 23: return .i
  case 24: return .o
  case 25: return .p
  case 26: return .leftBracket
  case 27: return .rightBracket
  case 28: return .return
  case 30: return .a
  case 31: return .s
  case 32: return .d
  case 33: return .f
  case 34: return .g
  case 35: return .h
  case 36: return .j
  case 37: return .k
  case 38: return .l
  case 39: return .semicolon
  case 40: return .quote
  case 41: return .grave
  case 43: return .backslash
  case 44: return .z
  case 45: return .x
  case 46: return .c
  case 47: return .v
  case 48: return .b
  case 49: return .n
  case 50: return .m
  case 51: return .comma
  case 52: return .period
  case 53: return .slash
  case 57: return .space
  case 59: return .f1
  case 60: return .f2
  case 61: return .f3
  case 62: return .f4
  case 63: return .f5
  case 64: return .f6
  case 65: return .f7
  case 66: return .f8
  case 67: return .f9
  case 68: return .f10
  case 69: return .f11
  case 70: return .f12
  case 71: return .keypad7
  case 72: return .keypad8
  case 73: return .keypad9
  case 74: return .keypadMinus
  case 75: return .keypad4
  case 76: return .keypad5
  case 77: return .keypad6
  case 78: return .keypadPlus
  case 79: return .keypad1
  case 80: return .keypad2
  case 81: return .keypad3
  case 82: return .keypad0
  case 83: return .keypadDecimal
  case 87: return .f11
  case 88: return .f12
  case 96: return .keypadEnter
  case 98: return .keypadDivide
  case 102: return .home
  case 103: return .upArrow
  case 104: return .pageUp
  case 105: return .leftArrow
  case 106: return .rightArrow
  case 107: return .end
  case 108: return .downArrow
  case 109: return .pageDown
  case 110: return .forwardDelete
  case 111: return .help
  default: return nil
  }
}

private func linuxModifierToModifiers(_ activeModifiers: UInt16) -> Modifiers {
  var mods: Set<Modifier> = []

  if activeModifiers & 0x01 != 0 { mods.insert(.shift) }
  if activeModifiers & 0x04 != 0 { mods.insert(.control) }
  if activeModifiers & 0x08 != 0 { mods.insert(.command) }
  if activeModifiers & 0x10 != 0 { mods.insert(.fn) }
  if activeModifiers & 0x20 != 0 { mods.insert(.option) }

  return Modifiers(modifiers: mods)
}

actor KeyEventMonitorClientLive {
  private let queue = DispatchQueue(label: "com.hex.KeyEventMonitor")
  private var isMonitoring = false
  private var shouldStop = false
  private var inputFDs: [Int32] = []
  private var source: DispatchSourceProtocol?

  func handleKeyEvent(_ handler: @Sendable @escaping (KeyEvent) -> Bool) -> KeyEventMonitorToken {
    let id = UUID()
    cancellations[id] = handler
    return KeyEventMonitorToken {
      self.cancellations[id] = nil
    }
  }

  func handleInputEvent(_ handler: @Sendable @escaping (InputEvent) -> Bool) -> KeyEventMonitorToken {
    let id = UUID()
    inputCancellations[id] = handler
    return KeyEventMonitorToken {
      self.inputCancellations[id] = nil
    }
  }

  func listenForKeyPress() -> AsyncThrowingStream<KeyEvent, Error> {
    AsyncThrowingStream { continuation in
      let token = handleKeyEvent { event in
        continuation.yield(event)
        return true
      }
      continuation.onTermination = { @Sendable _ in
        token.cancel()
      }
    }
  }

  func startMonitoring() {
    guard !isMonitoring else { return }
    isMonitoring = true
    shouldStop = false

    queue.async { [weak self] in
      self?.openInputDevices()
    }
  }

  func stopMonitoring() {
    shouldStop = true
    isMonitoring = false
    source?.cancel()
    for fd in inputFDs {
      close(fd)
    }
    inputFDs.removeAll()
    daemonReadTask?.cancel()
    daemonReadTask = nil
    if daemonFD >= 0 { close(daemonFD); daemonFD = -1 }
  }

  func startDaemonMonitoring(socketPath: String) {
    guard !isMonitoring else { return }
    isMonitoring = true
    shouldStop = false

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
      logger.error("Daemon socket create failed")
      isMonitoring = false
      return
    }

    #if os(Linux)
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    socketPath.withCString { strcpy(&addr.sun_path.0, $0) }

    let addrPtr = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 } }
    if connect(fd, addrPtr, socklen_t(MemoryLayout<sockaddr_un>.size)) < 0 {
      logger.error("Daemon connect failed: \(String(cString: strerror(errno)))")
      close(fd)
      isMonitoring = false
      return
    }
    #endif

    daemonFD = fd
    logger.info("Connected to hotkey daemon at \(socketPath)")

    daemonReadTask = Task { [weak self] in
      guard let self = self else { return }
      var buffer = [UInt8](repeating: 0, count: 64)
      while !self.shouldStop && !Task.isCancelled {
        let n = read(fd, &buffer, buffer.count)
        if n > 0 {
          let cmd = String(bytes: buffer[0..<n], encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          if !cmd.isEmpty {
            await self.handleDaemonCommand(cmd)
          }
        } else if n < 0 && errno != EAGAIN && errno != EWOULDBLOCK {
          break
        } else {
          try? await Task.sleep(nanoseconds: 50_000_000)
        }
      }
      close(fd)
    }
  }

  private func handleDaemonCommand(_ cmd: String) async {
    logger.info("Daemon command: \(cmd)")
    switch cmd {
    case "RECORD_START":
      for handler in cancellations.values {
        let event = KeyEvent(key: nil, modifiers: Modifiers(modifiers: []))
        _ = handler(event)
      }
    case "RECORD_STOP":
      break
    case "RECORD_CANCEL":
      break
    default:
      break
    }
  }

  private var daemonFD: Int32 = -1
  private var daemonReadTask: Task<Void, Never>?

  private var cancellations: [UUID: @Sendable (KeyEvent) -> Bool] = [:]
  private var inputCancellations: [UUID: @Sendable (InputEvent) -> Bool] = [:]
  private var activeModifiers: UInt16 = 0
  private var pressedKeys: [UInt16: Bool] = [:]

  private func openInputDevices() {
    let fm = FileManager.default
    let inputDir = "/dev/input"

    guard let files = try? fm.contentsOfDirectory(atPath: inputDir) else {
      logger.error("Cannot read /dev/input")
      return
    }

    var devices: [(Int32, String)] = []

    for file in files where file.hasPrefix("event") {
      let path = "\(inputDir)/\(file)"
      let fd = open(path, O_RDONLY | O_NONBLOCK)
      guard fd >= 0 else { continue }

      var name = [CChar](repeating: 0, count: 256)
      ioctl(fd, UInt(EVIOCGNAME(256)), &name)
      let deviceName = String(cString: name)

      if deviceName.lowercased().contains("keyboard") || deviceName.lowercased().contains("key") {
        devices.append((fd, deviceName))
      } else {
        close(fd)
      }
    }

    if devices.isEmpty {
      logger.error("No keyboard devices found in /dev/input")
      return
    }

    inputFDs = devices.map { $0.0 }
    logger.info("Opened \(devices.count) keyboard device(s)")

    startPollingDevices()
  }

  private func startPollingDevices() {
    let fds = inputFDs
    guard !fds.isEmpty else { return }

    let timer = DispatchSource.makeTimerSource(flags: [], queue: queue)
    timer.schedule(deadline: .now(), repeating: .milliseconds(5))

    timer.setEventHandler { [weak self] in
      guard let self = self, !self.shouldStop else {
        timer.cancel()
        return
      }
      self.pollDevices(fds: fds)
    }

    timer.resume()
    source = timer
  }

  private func pollDevices(fds: [Int32]) {
    for fd in fds {
      var event = input_event()
      while read(fd, &event, MemoryLayout<input_event>.size) == MemoryLayout<input_event>.size {
        processRawEvent(event)
      }
    }
  }

  private func processRawEvent(_ event: input_event) {
    guard event.type == UInt16(EV_KEY) else { return }

    let isKeyDown = event.value == 1
    let isKeyUp = event.value == 0
    guard isKeyDown || isKeyUp else { return }

    let code = event.code
    let isRepeat = event.value == 2

    guard !isRepeat else { return }

    if isKeyDown {
      pressedKeys[code] = true
    } else {
      pressedKeys.removeValue(forKey: code)
    }

    let currentKeys = pressedKeys.keys

    for _ in cancellations {
      let key = isKeyDown ? linuxKeyCodeToKey(code) : nil
      let modifiers = linuxModifierToModifiers(activeModifiers)
      let keyEvent = KeyEvent(key: key, modifiers: modifiers)

      let consumed = cancellations.values.contains { $0(keyEvent) }
      if consumed { break }
    }
  }
}

private let FD_CLOEXEC: Int32 = 1

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

private let EV_KEY: UInt16 = 1
private let EV_SYN: UInt16 = 0
#endif
