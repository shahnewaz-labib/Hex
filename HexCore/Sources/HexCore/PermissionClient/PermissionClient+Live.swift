#if os(macOS)
@preconcurrency import AppKit
import AVFoundation
import CoreGraphics
import Dependencies
import Foundation
import IOKit
import IOKit.hidsystem

private let logger = HexLog.permissions

extension PermissionClient: DependencyKey {
  public static var liveValue: Self {
    let live = PermissionClientLive()
    return Self(
      microphoneStatus: { await live.microphoneStatus() },
      accessibilityStatus: { live.accessibilityStatus() },
      inputMonitoringStatus: { live.inputMonitoringStatus() },
      requestMicrophone: { await live.requestMicrophone() },
      requestAccessibility: { await live.requestAccessibility() },
      requestInputMonitoring: { await live.requestInputMonitoring() },
      openMicrophoneSettings: { await live.openMicrophoneSettings() },
      openAccessibilitySettings: { await live.openAccessibilitySettings() },
      openInputMonitoringSettings: { await live.openInputMonitoringSettings() },
      observeAppActivation: { live.observeAppActivation() }
    )
  }
}

actor PermissionClientLive {
  private let (activationStream, activationContinuation) = AsyncStream<AppActivation>.makeStream()
  private nonisolated(unsafe) var observations: [Any] = []

  init() {
    logger.debug("Initializing PermissionClient, setting up app activation observers")
    let didBecomeActiveObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      logger.debug("App became active")
      Task {
        self?.activationContinuation.yield(.didBecomeActive)
      }
    }

    let willResignActiveObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willResignActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      logger.debug("App will resign active")
      Task {
        self?.activationContinuation.yield(.willResignActive)
      }
    }

    observations = [didBecomeActiveObserver, willResignActiveObserver]
  }

  deinit {
    observations.forEach { NotificationCenter.default.removeObserver($0) }
  }

  func microphoneStatus() async -> PermissionStatus {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    let result: PermissionStatus
    switch status {
    case .authorized:
      result = .granted
    case .denied, .restricted:
      result = .denied
    case .notDetermined:
      result = .notDetermined
    @unknown default:
      result = .denied
    }
    logger.info("Microphone status: \(String(describing: result))")
    return result
  }

  func requestMicrophone() async -> Bool {
    logger.info("Requesting microphone permission...")
    let granted = await withCheckedContinuation { continuation in
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        continuation.resume(returning: granted)
      }
    }
    logger.info("Microphone permission granted: \(granted)")
    return granted
  }

  func openMicrophoneSettings() async {
    logger.info("Opening microphone settings in System Preferences...")
    await MainActor.run {
      _ = NSWorkspace.shared.open(
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
      )
    }
  }

  nonisolated func accessibilityStatus() -> PermissionStatus {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
    let result = AXIsProcessTrustedWithOptions(options) ? PermissionStatus.granted : .denied
    logger.info("Accessibility status: \(String(describing: result))")
    return result
  }

  nonisolated func inputMonitoringStatus() -> PermissionStatus {
    let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    let result = mapIOHIDAccess(access)
    logger.info("Input monitoring status: \(String(describing: result)) (IOHIDAccess: \(String(describing: access)))")
    return result
  }

  func requestAccessibility() async {
    logger.info("Requesting accessibility permission...")
    await MainActor.run {
      let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
      _ = AXIsProcessTrustedWithOptions(options)
    }
    await openAccessibilitySettings()
  }

  func requestInputMonitoring() async -> Bool {
    logger.info("Requesting input monitoring permission...")
    let granted = await MainActor.run {
      if CGPreflightListenEventAccess() {
        return true
      }
      return CGRequestListenEventAccess()
    }

    if !granted {
      logger.info("Input monitoring not granted, opening Settings...")
      await openInputMonitoringSettings()
    } else {
      logger.info("Input monitoring permission granted: \(granted)")
    }

    return granted
  }

  func openAccessibilitySettings() async {
    logger.info("Opening accessibility settings in System Preferences...")
    await MainActor.run {
      _ = NSWorkspace.shared.open(
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
      )
    }
  }

  func openInputMonitoringSettings() async {
    logger.info("Opening input monitoring settings in System Preferences...")
    await MainActor.run {
      _ = NSWorkspace.shared.open(
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
      )
    }
  }

  nonisolated func observeAppActivation() -> AsyncStream<AppActivation> {
    activationStream
  }

  private nonisolated func mapIOHIDAccess(_ access: IOHIDAccessType) -> PermissionStatus {
    switch access {
    case kIOHIDAccessTypeGranted:
      return .granted
    case kIOHIDAccessTypeDenied:
      return .denied
    default:
      return .notDetermined
    }
  }
}
#else
import Dependencies
import Foundation

private let logger = HexLog.permissions

extension PermissionClient: DependencyKey {
  public static var liveValue: Self {
    let live = PermissionClientLive()
    return Self(
      microphoneStatus: { await live.microphoneStatus() },
      accessibilityStatus: { live.accessibilityStatus() },
      inputMonitoringStatus: { live.inputMonitoringStatus() },
      requestMicrophone: { await live.requestMicrophone() },
      requestAccessibility: { await live.requestAccessibility() },
      requestInputMonitoring: { await live.requestInputMonitoring() },
      openMicrophoneSettings: { await live.openMicrophoneSettings() },
      openAccessibilitySettings: { await live.openAccessibilitySettings() },
      openInputMonitoringSettings: { await live.openInputMonitoringSettings() },
      observeAppActivation: { live.observeAppActivation() }
    )
  }
}

/// Linux implementation: most permissions are essentially always granted.
/// PulseAudio/PipeWire handles mic access at the audio system level.
/// Global hotkey access is determined by input group membership or Wayland portal.
actor PermissionClientLive {
  private let (activationStream, activationContinuation) = AsyncStream<AppActivation>.makeStream()

  init() {
    logger.debug("Initializing Linux PermissionClient")
  }

  func microphoneStatus() async -> PermissionStatus {
    logger.info("Microphone status: granted (Linux PulseAudio/PipeWire)")
    return .granted
  }

  func requestMicrophone() async -> Bool {
    logger.info("Microphone permission: granted (no prompt on Linux)")
    return true
  }

  func openMicrophoneSettings() async {
    logger.info("Open microphone settings: no-op on Linux")
  }

  nonisolated func accessibilityStatus() -> PermissionStatus {
    logger.info("Accessibility status: granted (no prompt on Linux)")
    return .granted
  }

  nonisolated func inputMonitoringStatus() -> PermissionStatus {
    logger.info("Input monitoring status: granted on Linux")
    return .granted
  }

  func requestAccessibility() async {
    logger.info("Accessibility permission: granted (no prompt on Linux)")
  }

  func requestInputMonitoring() async -> Bool {
    logger.info("Input monitoring permission: granted on Linux")
    return true
  }

  func openAccessibilitySettings() async {
    logger.info("Open accessibility settings: no-op on Linux")
  }

  func openInputMonitoringSettings() async {
    logger.info("Open input monitoring settings: no-op on Linux")
  }

  nonisolated func observeAppActivation() -> AsyncStream<AppActivation> {
    activationStream
  }
}
#endif
