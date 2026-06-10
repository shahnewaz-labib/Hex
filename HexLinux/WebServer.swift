#if !os(macOS)
import Foundation
import HexCore
import NIOCore
import NIOHTTP1
import NIOPosix

private let serverLogger = HexLog.app

final class HexWebServer {
  private let port: Int
  private let group: MultiThreadedEventLoopGroup
  private var channel: Channel?
  private var store: StoreOf<LinuxApp>?

  init(port: Int = 8765) {
    self.port = port
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  }

  func start(store: StoreOf<LinuxApp>) async throws {
    self.store = store

    let bootstrap = ServerBootstrap(group: group)
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
      .childChannelInitializer { channel in
        channel.pipeline.configureHTTPServerPipeline().flatMap {
          channel.pipeline.addHandler(HexHTTPHandler(store: store))
        }
      }
      .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
      .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

    channel = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
    serverLogger.info("Web server listening on http://127.0.0.1:\(port)")
  }

  func stop() async {
    channel?.close(mode: .all, promise: nil)
    try? await group.shutdownGracefully()
    serverLogger.info("Web server stopped")
  }
}

final class HexHTTPHandler: ChannelInboundHandler {
  typealias InboundIn = HTTPServerRequestPart
  typealias OutboundOut = HTTPServerResponsePart

  private let store: StoreOf<LinuxApp>
  private var requestMethod: HTTPMethod = .GET
  private var requestURI: String = "/"
  private var requestBody: String = ""
  private var collectingBody = false

  init(store: StoreOf<LinuxApp>) {
    self.store = store
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let reqPart = unwrapInboundIn(data)

    switch reqPart {
    case .head(let head):
      requestMethod = head.method
      requestURI = head.uri
      requestBody = ""
      collectingBody = head.method == .POST

    case .body(let buffer):
      if collectingBody, let str = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) {
        requestBody += str
      }

    case .end:
      let response = handleRequest(method: requestMethod, uri: requestURI, body: requestBody)
      sendResponse(context: context, response: response)

    }
  }

  private func handleRequest(method: HTTPMethod, uri: String, body: String) -> (HTTPResponseStatus, String, String) {
    switch (method, uri) {
    case (.GET, "/"):
      return (.ok, "text/html", WebUI.html)

    case (.GET, "/api/status"):
      return jsonResponse(WebBridge.statusJSON(from: store))

    case (.POST, "/api/record/start"):
      Task { await store.send(.toggleRecording) }
      return jsonResponse(#"{"ok":true}"#)

    case (.POST, "/api/record/stop"):
      Task { await store.send(.toggleRecording) }
      return jsonResponse(#"{"ok":true}"#)

    case (.POST, "/api/paste"):
      Task { await store.send(.pasteTranscription) }
      return jsonResponse(#"{"ok":true}"#)

    case (.GET, "/api/models"):
      return jsonResponse(WebBridge.modelsJSON(from: store))

    case let (.POST, uri) where uri.hasPrefix("/api/download/"):
      let modelName = String(uri.dropFirst("/api/download/".count))
      Task { await store.send(.downloadModel(modelName)) }
      return jsonResponse(#"{"ok":true}"#)

    case let (.POST, uri) where uri.hasPrefix("/api/delete/"):
      let modelName = String(uri.dropFirst("/api/delete/".count))
      Task { await store.send(.deleteModel(modelName)) }
      return jsonResponse(#"{"ok":true}"#)

    case let (.POST, uri) where uri.hasPrefix("/api/select/"):
      let modelName = String(uri.dropFirst("/api/select/".count))
      store.state.$hexSettings.withLock { $0.selectedModel = modelName }
      return jsonResponse(#"{"ok":true}"#)

    case (.GET, "/api/history"):
      return jsonResponse(WebBridge.historyJSON(from: store))

    default:
      return (.notFound, "text/plain", "Not Found")
    }
  }

  private func jsonResponse(_ json: String) -> (HTTPResponseStatus, String, String) {
    (.ok, "application/json", json)
  }

  private func sendResponse(context: ChannelHandlerContext, response: (HTTPResponseStatus, String, String)) {
    let (status, contentType, body) = response

    var head = HTTPResponseHead(version: .http1_1, status: status)
    head.headers.add(name: "Content-Type", value: contentType)
    head.headers.add(name: "Content-Length", value: "\(body.utf8.count)")
    head.headers.add(name: "Connection", value: "close")
    head.headers.add(name: "Access-Control-Allow-Origin", value: "*")

    context.write(wrapOutboundOut(.head(head)), promise: nil)

    var buffer = context.channel.allocator.buffer(capacity: body.utf8.count)
    buffer.writeString(body)
    context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)

    context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    context.close(promise: nil)
  }
}
#endif
