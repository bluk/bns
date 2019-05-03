//  Copyright 2019 Bryant Luk
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

// swiftlint:disable line_length

// Original source from:
// https://raw.githubusercontent.com/apple/swift-nio/993a3b7521fa636cd8894c3c053bc93c7394c17d/Sources/NIOWebSocketServer/main.swift
// ===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// swiftlint:enable line_length

import Dispatch
import Foundation
import Logging
import NIO
import NIOHTTP1
import NIOWebSocket

import BNS
import func ExampleUtilities.makeRFC1123DateFormatter
import func ExampleUtilities.parseEnvironmentOptions
import func ExampleUtilities.trap

// swift run WebSocketServerExample --host 127.0.0.1 --port 8080
// Visit http://127.0.0.1:8080/ in a browser.
private let environmentOptions = try parseEnvironmentOptions()

private let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
private let dispatchGroup = DispatchGroup()

private var logger = Logger(label: "WebSocketServerExample")

internal let httpResponse = """
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Swift NIO WebSocket Test Page</title>
    <script>
        var wsconnection = new WebSocket("ws://localhost:\(environmentOptions.port)/websocket");
        wsconnection.onmessage = function (msg) {
            var element = document.createElement("p");
            element.innerHTML = msg.data;
            var textDiv = document.getElementById("websocket-stream");
            textDiv.insertBefore(element, null);
        };
    </script>
  </head>
  <body>
    <h1>WebSocket Stream</h1>
    <div id="websocket-stream"></div>
  </body>
</html>
"""

private func handleHTTPStream(_ httpStream: BNSHTTPStream) {
    httpStream.stateUpdateHandler = { state in
        switch state {
        case .setup, .preparing, .cancelled:
            break
        case .ready:
            guard let requestHead = httpStream.requestHead else {
                preconditionFailure("Request headers should be available in ready state.")
            }

            var headers = HTTPHeaders()
            switch (requestHead.isKeepAlive, requestHead.version.major, requestHead.version.minor) {
            case (true, 1, 0):
                headers.add(name: "connection", value: "keep-alive")
            case (false, 1, let minor) where minor >= 1:
                headers.add(name: "connection", value: "close")
            default:
                ()
            }

            headers.add(name: "server", value: "BNS")
            headers.add(name: "content-length", value: "\(httpResponse.utf8.count)")
            headers.add(name: "content-type", value: "text/html")
            headers.add(name: "date", value: makeRFC1123DateFormatter().string(from: Date()))
            httpStream.responseHead?.headers = headers

            let contentData = httpResponse.data(using: .utf8)!
            httpStream.send(
                content: contentData,
                contentContext: .finalMessage,
                isComplete: true,
                completion: .contentProcessed({ _ in
                    httpStream.cancel()
                })
            )
        case .failed:
            httpStream.cancel()
        }
    }

    httpStream.start(queue: DispatchQueue(label: "AHTTPStreamQueue"))
}

internal class WebSocketHandler {
    let stream: BNSWebSocketStream
    var awaitingClose: Bool = false

    init(stream: BNSWebSocketStream) {
        self.stream = stream
    }

    func sendTime() {
        guard !awaitingClose else {
            return
        }

        let theTime = NIODeadline.now().uptimeNanoseconds
        var buffer = stream.channel.allocator.buffer(capacity: 12)
        buffer.writeString("\(theTime)")

        let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
        stream.send(content: frame, completion: .contentProcessed({ error in
            if let error = error {
                logger.error("Error from WebSocketStream: \(error)")
                self.stream.cancel()
                return
            }

            self.stream.channel.eventLoop.scheduleTask(in: .seconds(1), { self.sendTime() })
        }))
    }

    func receive(
        content: WebSocketFrame?,
        contentContext _: BNSStreamContentContext?,
        isComplete _: Bool,
        error _: Error?
    ) {
        guard let frame = content else {
            return
        }

        switch frame.opcode {
        case .connectionClose:
            self.receivedClose(frame: frame)
        case .ping:
            self.pong(frame: frame)
        case .text, .binary, .continuation, .pong:
            break
        default:
            self.closeOnError()
        }
    }

    func receivedClose(frame: WebSocketFrame) {
        guard !self.awaitingClose else {
            self.stream.cancel()
            return
        }

        var data = frame.unmaskedData
        let closeDataCode = data.readSlice(length: 2) ?? stream.channel.allocator.buffer(capacity: 0)
        let closeFrame = WebSocketFrame(fin: true, opcode: .connectionClose, data: closeDataCode)
        self.stream.send(content: closeFrame, completion: .contentProcessed { _ in
            self.stream.cancel()
        })
    }

    func pong(frame: WebSocketFrame) {
        var frameData = frame.data
        let maskingKey = frame.maskKey

        if let maskingKey = maskingKey {
            frameData.webSocketUnmask(maskingKey)
        }

        let responseFrame = WebSocketFrame(fin: true, opcode: .pong, data: frameData)
        self.stream.send(content: responseFrame, completion: .idempotent)
    }

    func closeOnError() {
        var data = self.stream.channel.allocator.buffer(capacity: 2)
        data.write(webSocketErrorCode: .protocolError)

        let frame = WebSocketFrame(fin: true, opcode: .connectionClose, data: data)
        let stream = self.stream
        self.stream.send(content: frame, completion: .contentProcessed { _ in
            stream.cancel()
        })

        self.awaitingClose = true
    }
}

private func handleWebSocketStream(_ webSocketStream: BNSWebSocketStream) {
    let webSocketHandler: WebSocketHandler = WebSocketHandler(stream: webSocketStream)
    webSocketStream.stateUpdateHandler = { state in
        switch state {
        case .setup, .preparing, .cancelled:
            break
        case .ready:
            webSocketHandler.sendTime()
        case .failed:
            webSocketStream.cancel()
        }
    }

    webSocketStream.receive(completion: webSocketHandler.receive)
    webSocketStream.start(queue: DispatchQueue(label: "AWebSocketStreamQueue"))
}

private let listener = BNSListener(configuration: BNSListener.Configuration(
    protocolSupportOptions: [.http1, .webSocket]
))

listener.stateUpdateHandler = { state in
    switch state {
    case .setup, .waiting:
        break
    case .ready:
        guard let localAddress = listener.channel?.localAddress else {
            fatalError("Was unable to bind the listener.")
        }

        logger.info("Listening on \(localAddress)")
    case let .failed(error):
        logger.error("Listener error: \(error)")
        listener.cancel()
    case .cancelled:
        eventLoopGroup.shutdownGracefully(queue: DispatchQueue.global(qos: .userInitiated)) { error in
            defer { dispatchGroup.leave() }
            guard let error = error else {
                logger.info("Shutdown without error")
                return
            }
            logger.error("Shutdown with error: \(error)")
        }
    }
}

listener.bootstrapChannelHandler = { childChannelInitializer in
    ServerBootstrap(group: eventLoopGroup)
        .serverChannelOption(ChannelOptions.backlog, value: 256)
        .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        .childChannelInitializer { channel in
            childChannelInitializer(channel)
        }
        .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
        .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
        .bind(host: environmentOptions.host, port: environmentOptions.port)
}

listener.newConnectionHandler = { connectionType in
    switch connectionType {
    case let .http1(http1Connection):
        http1Connection.newStreamHandler = { (stream: BNSHTTP1Stream) in
            handleHTTPStream(stream)
        }
        http1Connection.shouldUpgradeToWebSocketHandler = { _, completion in
            completion(Result.success(HTTPHeaders()))
        }
    case let .webSocket(webSocketConnection):
        webSocketConnection.newStreamHandler = { (stream: BNSWebSocketStream) in
            handleWebSocketStream(stream)
        }
    case .http2:
        preconditionFailure("Unexpected HTTP/2 connection.")
    }
    let connection: BNSBaseConnection = connectionType.baseConnection
    connection.stateUpdateHandler = { state in
        switch state {
        case .setup, .preparing, .ready, .cancelled:
            break
        case .failed:
            connection.cancel()
        }
    }

    connection.start(queue: DispatchQueue(label: "AConnectionQueue"))
}

private let signalSource: DispatchSourceSignal = trap(signal: SIGINT) { [weak listener] _ in
    listener?.cancel()
}

dispatchGroup.enter()

listener.start(queue: DispatchQueue(label: "ListenerQueue"))

dispatchGroup.wait()
signalSource.cancel()
