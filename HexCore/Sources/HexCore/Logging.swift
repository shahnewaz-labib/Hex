#if os(macOS)
import os.log
#else
import Logging
#endif

/// Shared helper for creating consistent logger instances across the Hex app and HexCore.
public enum HexLog {
  public static let subsystem = "com.kitlangton.Hex"

  public enum Category: String {
    case app = "App"
    case caches = "Caches"
    case transcription = "Transcription"
    case models = "Models"
    case recording = "Recording"
    case media = "Media"
    case pasteboard = "Pasteboard"
    case sound = "SoundEffect"
    case hotKey = "HotKey"
    case keyEvent = "KeyEvent"
    case parakeet = "Parakeet"
    case history = "History"
    case settings = "Settings"
    case permissions = "Permissions"
  }

  #if os(macOS)
  public static func logger(_ category: Category) -> os.Logger {
    os.Logger(subsystem: subsystem, category: category.rawValue)
  }

  public static let app = logger(.app)
  public static let caches = logger(.caches)
  public static let transcription = logger(.transcription)
  public static let models = logger(.models)
  public static let recording = logger(.recording)
  public static let media = logger(.media)
  public static let pasteboard = logger(.pasteboard)
  public static let sound = logger(.sound)
  public static let hotKey = logger(.hotKey)
  public static let keyEvent = logger(.keyEvent)
  public static let parakeet = logger(.parakeet)
  public static let history = logger(.history)
  public static let settings = logger(.settings)
  public static let permissions = logger(.permissions)
  #else
  public static func logger(_ category: Category) -> Logging.Logger {
    var logger = Logging.Logger(label: "\(subsystem).\(category.rawValue)")
    #if DEBUG
    logger.logLevel = .debug
    #endif
    return logger
  }

  public static let app = logger(.app)
  public static let caches = logger(.caches)
  public static let transcription = logger(.transcription)
  public static let models = logger(.models)
  public static let recording = logger(.recording)
  public static let media = logger(.media)
  public static let pasteboard = logger(.pasteboard)
  public static let sound = logger(.sound)
  public static let hotKey = logger(.hotKey)
  public static let keyEvent = logger(.keyEvent)
  public static let parakeet = logger(.parakeet)
  public static let history = logger(.history)
  public static let settings = logger(.settings)
  public static let permissions = logger(.permissions)
  #endif
}
