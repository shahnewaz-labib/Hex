#if os(macOS)
import Dependencies
import IOKit.pwr_mgt

extension SleepManagementClient: DependencyKey {
  public static var liveValue: Self {
    let live = SleepManagementClientLive()
    return Self(
      preventSleep: { reason in
        await live.preventSleep(reason: reason)
      },
      allowSleep: {
        await live.allowSleep()
      }
    )
  }
}

actor SleepManagementClientLive {
  private var currentAssertionID: IOPMAssertionID?

  func preventSleep(reason: String) {
    if let existingID = currentAssertionID {
      IOPMAssertionRelease(existingID)
      currentAssertionID = nil
    }

    let reasonForActivity = reason as CFString
    var assertionID: IOPMAssertionID = 0
    let success = IOPMAssertionCreateWithName(
      kIOPMAssertionTypeNoDisplaySleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      reasonForActivity,
      &assertionID
    )

    if success == kIOReturnSuccess {
      currentAssertionID = assertionID
    }
  }

  func allowSleep() {
    if let assertionID = currentAssertionID {
      IOPMAssertionRelease(assertionID)
      currentAssertionID = nil
    }
  }
}
#else
import Dependencies
import Foundation

extension SleepManagementClient: DependencyKey {
  public static var liveValue: Self {
    let live = SleepManagementClientLive()
    return Self(
      preventSleep: { reason in
        await live.preventSleep(reason: reason)
      },
      allowSleep: {
        await live.allowSleep()
      }
    )
  }
}

actor SleepManagementClientLive {
  private var process: Process?

  func preventSleep(reason: String) {
    allowSleep()

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/systemd-inhibit")
    task.arguments = ["--what=idle:sleep", "--who=hex", "--why=\(reason)", "--mode=block", "sleep", "infinity"]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice

    do {
      try task.run()
      process = task
    } catch {
      let logger = HexLog.permissions
      logger.error("Failed to start systemd-inhibit: \(error)")
    }
  }

  func allowSleep() {
    if let task = process, task.isRunning {
      task.terminate()
    }
    process = nil
  }
}
#endif
