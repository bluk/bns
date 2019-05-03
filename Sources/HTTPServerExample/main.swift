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
import NIOExtras
import NIOHTTP1

import BNS
import func ExampleUtilities.makeRFC1123DateFormatter
import func ExampleUtilities.parseEnvironmentOptions
import func ExampleUtilities.trap

// swiftlint:disable line_length

// swift run HTTPServerExample --host 127.0.0.1 --port 8080
// Visit http://127.0.0.1:8080/ in a browser.

// swift run HTTPServerExample --host 127.0.0.1 --port 8080 --tls-certchain /path/to/fullchain.pem --tls-privatekey /path/to/privkey.pem
// Visit https://127.0.0.1:8080/ in a browser (note: HTTPS). HTTP/2 will also be enabled.
private let environmentOptions = try parseEnvironmentOptions()

// swiftlint:enable line_length

private let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
private let dispatchGroup = DispatchGroup()

private var logger = Logger(label: "HTTP1ServerExample")

logger.logLevel = .debug

private let quiesceHelper = ServerQuiescingHelper(group: eventLoopGroup)

private func handleHTTPStream(_ httpStream: BNSHTTPStream, logger: Logger) {
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

    httpStream.logger = logger
    httpStream.start(queue: DispatchQueue(label: "AStreamQueue"))
}

private let listener = BNSListener(configuration: BNSListener.Configuration(
    protocolSupportOptions: environmentOptions.tlsConfiguration != nil ? [.http1, .http2] : [.http1],
    featureOptions: [
        .supportsPipelining,
    ],
    tlsConfiguration: environmentOptions.tlsConfiguration
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
        .serverChannelInitializer { channel in
            channel.pipeline.addHandlers([
                quiesceHelper.makeServerChannelHandler(channel: channel),
                AcceptBackoffHandler(),
            ])
        }
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
        case .setup, .preparing, .ready:
            break
        case let .failed(error):
            switch error {
            case let connectionError as BNSConnectionError:
                switch connectionError {
                case .connectionReset:
                    break
                default:
                    logger.error("BNSConnectionError: \(connectionError)")
                }
            default:
                logger.error("Connection error: \(error)")
            }
            connection.cancel()
        case .cancelled:
            break
        }
    }
    var connectionLogger = logger
    connectionLogger[metadataKey: "connectionID"] = "\(UUID())"

    switch connectionType {
    case .webSocket:
        preconditionFailure("Unexpected WebSocket connection.")
    case let .http1(httpConnection):
        connectionLogger[metadataKey: "protocol"] = "http1"
        var streamCounter: UInt64 = 0
        httpConnection.newStreamHandler = { stream in
            streamCounter &+= 1
            var httpStreamLogger = connectionLogger
            httpStreamLogger[metadataKey: "streamID"] = "\(streamCounter)"
            handleHTTPStream(stream, logger: httpStreamLogger)
        }
    case let .http2(httpConnection):
        connectionLogger[metadataKey: "protocol"] = "http2"
        httpConnection.newStreamHandler = { stream in
            var httpStreamLogger = connectionLogger
            httpStreamLogger[metadataKey: "streamID"] = "\(stream.streamID)"
            handleHTTPStream(stream, logger: httpStreamLogger)
        }
    }

    connection.logger = connectionLogger
    connection.start(queue: DispatchQueue(label: "AConnectionQueue"))
}

private let fullyShutdownPromise: EventLoopPromise<Void> = eventLoopGroup.next().makePromise()
private var signalSource: DispatchSourceSignal = trap(signal: SIGINT) { [weak listener] _ in
    fullyShutdownPromise.futureResult.whenComplete { _ in
        listener?.cancel()
    }
    quiesceHelper.initiateShutdown(promise: fullyShutdownPromise)
}

dispatchGroup.enter()

listener.start(queue: DispatchQueue(label: "ListenerQueue"))

dispatchGroup.wait()
signalSource.cancel()
