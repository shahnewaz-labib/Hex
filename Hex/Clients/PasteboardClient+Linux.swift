#if !os(macOS)
import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import HexCore

private let pasteboardLogger = HexLog.pasteboard

@DependencyClient
struct PasteboardClient {
    var paste: @Sendable (String) async -> Void
    var copy: @Sendable (String) async -> Void
    var sendKeyboardCommand: @Sendable (KeyboardCommand) async -> Void
}

extension PasteboardClient: DependencyKey {
    static var liveValue: Self {
        let live = PasteboardClientLive()
        return .init(
            paste: { text in await live.paste(text: text) },
            copy: { text in await live.copy(text: text) },
            sendKeyboardCommand: { command in await live.sendKeyboardCommand(command) }
        )
    }
}

extension DependencyValues {
    var pasteboard: PasteboardClient {
        get { self[PasteboardClient.self] }
        set { self[PasteboardClient.self] = newValue }
    }
}

struct PasteboardClientLive {
    @Shared(.hexSettings) var hexSettings: HexSettings

    func paste(text: String) async {
        if hexSettings.useClipboardPaste {
            await pasteWithClipboard(text)
        } else {
            await simulateTyping(text)
        }
    }

    func copy(text: String) async {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["bash", "-c", "echo -n \(text.replacingOccurrences(of: "'", with: "'\\''")) | xclip -selection clipboard"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try await runProcess(task)
        } catch {
            pasteboardLogger.error("Copy failed: \(error)")
        }
    }

    func sendKeyboardCommand(_ command: KeyboardCommand) async {
        var args: [String] = []

        if let key = command.key {
            switch key {
            case .return:
                args = ["key", "Return"]
            case .escape:
                args = ["key", "Escape"]
            case .space:
                args = ["key", "space"]
            case .tab:
                args = ["key", "Tab"]
            case .delete:
                args = ["key", "Delete"]
            case .leftArrow:
                args = ["key", "Left"]
            case .rightArrow:
                args = ["key", "Right"]
            case .upArrow:
                args = ["key", "Up"]
            case .downArrow:
                args = ["key", "Down"]
            case .home:
                args = ["key", "Home"]
            case .end:
                args = ["key", "End"]
            case .pageUp:
                args = ["key", "Prior"]
            case .pageDown:
                args = ["key", "Next"]
            case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12:
                let fn = key.rawValue.uppercased()
                args = ["key", fn]
            default:
                args = ["key", "--clearmodifiers", key.toString]
            }
        }

        if command.modifiers.contains(kind: .control) {
            args.insert("--clearmodifiers", at: 0)
            args.insert("ctrl+\(args.removeFirst())", at: 0)
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xdotool")
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try await runProcess(task)
        } catch {
            pasteboardLogger.error("Send keyboard command failed: \(error)")
        }
    }

    private func pasteWithClipboard(_ text: String) async {
        await copy(text: text)

        let pasteTask = Process()
        if hexSettings.useDoubleTapOnly {
            pasteTask.executableURL = URL(fileURLWithPath: "/usr/bin/xdotool")
            pasteTask.arguments = ["key", "--clearmodifiers", "ctrl+shift+v"]
        } else {
            pasteTask.executableURL = URL(fileURLWithPath: "/usr/bin/xdotool")
            pasteTask.arguments = ["key", "--clearmodifiers", "ctrl+v"]
        }
        pasteTask.standardOutput = FileHandle.nullDevice
        pasteTask.standardError = FileHandle.nullDevice

        do {
            try await runProcess(pasteTask)
        } catch {
            pasteboardLogger.error("Paste failed: \(error)")
        }
    }

    private func simulateTyping(_ text: String) async {
        let escaped = text.replacingOccurrences(of: "'", with: "'\\''")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["bash", "-c", "xdotool type --clearmodifiers --delay 1 '\(escaped)'"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try await runProcess(task)
        } catch {
            pasteboardLogger.error("Type simulation failed: \(error)")
        }
    }

    private func runProcess(_ process: Process) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let stderr = proc.standardError as? Pipe
                    let data = stderr?.fileHandleForReading.readDataToEndOfFile() ?? Data()
                    let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: NSError(domain: "Hex", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: msg]))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
#endif
