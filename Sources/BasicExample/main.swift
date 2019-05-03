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

import Dispatch
import Foundation
import Logging
import NIO
import NIOHTTP1

import BNS
import func ExampleUtilities.makeRFC1123DateFormatter
import func ExampleUtilities.parseEnvironmentOptions
import func ExampleUtilities.trap

// swift run BasicExample --host 127.0.0.1 --port 8080
// Visit http://127.0.0.1:8080 in a browser or use curl.
private let environmentOptions = try parseEnvironmentOptions()

private let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
private let dispatchGroup = DispatchGroup()

private var logger = Logger(label: "BasicExample")

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
            headers.add(name: "content-type", value: "text/plain")
            headers.add(name: "date", value: makeRFC1123DateFormatter().string(from: Date()))
            httpStream.responseHead?.headers = headers

            httpStream.send(
                content: "Hello World!".data(using: .utf8)!,
                contentContext: .finalMessage,
                isComplete: true,
                completion: .contentProcessed({ _ in httpStream.cancel() })
            )
        case .failed:
            httpStream.cancel()
        }
    }

    httpStream.start(queue: DispatchQueue(label: "AStreamQueue"))
}

private let listener = BNSListener(configuration: BNSListener.Configuration(
    protocolSupportOptions: [.http1]
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
    let connection: BNSBaseConnection = connectionType.baseConnection
    connection.stateUpdateHandler = { state in
        switch state {
        case .setup, .preparing, .ready, .cancelled:
            break
        case .failed:
            connection.cancel()
        }
    }

    switch connectionType {
    case let .http1(httpConnection):
        httpConnection.newStreamHandler = handleHTTPStream
    case .webSocket:
        preconditionFailure("Unexpected WebSocket connection.")
    case .http2:
        preconditionFailure("Unexpected HTTP/2 connection.")
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
