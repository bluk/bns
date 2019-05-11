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
import Logging
import NIO
import NIOHTTP1
import NIOHTTPCompression
import NIOWebSocket

internal extension ChannelPipeline {
    func configureHTTP1WithError(
        context: BNSListener.InitializeChildChannelContext
    ) -> EventLoopFuture<Void> {
        let finishPipelineInitPromise: EventLoopPromise<Void>
            = context.channel.eventLoop.makePromise()
        let addHandlersFuture = context.channel.pipeline.configureHTTP1(
            context: context,
            finishPipelineInitFuture: finishPipelineInitPromise.futureResult
        )
        .flatMap { () -> EventLoopFuture<Void> in
            context.channel.pipeline.addHandler(
                NIOCloseOnErrorHandler(),
                name: BNSChannelHandlerName.nioCloseOnErrorHandler.rawValue
            )
        }

        addHandlersFuture.whenComplete { _ in
            finishPipelineInitPromise.succeed(())
        }

        return addHandlersFuture
    }

    // swiftlint:disable cyclomatic_complexity function_body_length

    private func configureHTTP1(
        context: BNSListener.InitializeChildChannelContext,
        finishPipelineInitFuture: EventLoopFuture<Void>
    ) -> EventLoopFuture<Void> {
        var handlersToRemoveOnUpgrade: [RemovableChannelHandler] = []
        handlersToRemoveOnUpgrade.reserveCapacity(8)

        // Skip this for adding to handlersToRemoveOnUpgrade since it will
        // be removed by the connection's internalStartHandler
        let connectionBufferChannelHandler = BNSHTTP1ConnectionBufferChannelHandler(
            maxBufferSizeBeforeConnectionStart:
            context.configuration.maxBufferSizeBeforeConnectionStart,
            queue: context.queue,
            logger: context.logger
        )

        let http1Connection = BNSHTTP1Connection(
            channel: context.channel,
            internalStartHandler: { [weak connectionBufferChannelHandler] in
                finishPipelineInitFuture.whenComplete { _ in
                    context.channel.eventLoop.execute {
                        connectionBufferChannelHandler?.stopBufferingAndFlush()
                    }
                }
            }
        )
        finishPipelineInitFuture.whenComplete { _ in
            context.newConnectionHandler(.http1(http1Connection))
        }

        let streamHandler = BNSHTTP1StreamChannelHandler(
            connection: http1Connection,
            handler: { [weak http1Connection] (stream: BNSHTTP1Stream) -> Void in
                guard let http1Connection = http1Connection,
                    let queue = http1Connection.queue else {
                    stream.cancel()
                    return
                }
                queue.async {
                    guard let newStreamHandler = http1Connection.newStreamHandler else {
                        stream.cancel()
                        return
                    }
                    newStreamHandler(stream)
                }
            }
        )

        let responseEncoder = HTTPResponseEncoder()

        return self.addHandler(responseEncoder, name: BNSChannelHandlerName.httpResponseEncoder.rawValue)
            .flatMap { _ -> EventLoopFuture<Void> in
                let requestDecoder = HTTPRequestDecoder(
                    leftOverBytesStrategy:
                    context.configuration.protocolSupportOptions.contains(.webSocket)
                        ? .forwardBytes : .dropBytes
                )
                let byteToMessageHandler = ByteToMessageHandler(requestDecoder)
                handlersToRemoveOnUpgrade.append(byteToMessageHandler)
                return self.addHandler(byteToMessageHandler, name: BNSChannelHandlerName.byteToMessageHandler.rawValue)
            }
            .flatMap { _ -> EventLoopFuture<Void> in
                let connectionChannelHandler = BNSHTTP1ConnectionChannelHandler(
                    connection: http1Connection
                )
                handlersToRemoveOnUpgrade.append(connectionChannelHandler)

                return self.addHandler(
                    connectionChannelHandler,
                    name: BNSChannelHandlerName.bnsHTTP1ConnectionChannelHandler.rawValue
                )
            }
            .flatMap { _ -> EventLoopFuture<Void> in
                self.addHandler(
                    connectionBufferChannelHandler,
                    name: BNSChannelHandlerName.bnsHTTP1ConnectionBufferChannelHandler.rawValue
                )
            }
            .flatMap { _ -> EventLoopFuture<Void> in
                let pipelineFuture: EventLoopFuture<Void>
                if context.configuration.featureOptions.contains(.supportsPipelining) {
                    let pipelineHandler = HTTPServerPipelineHandler()
                    handlersToRemoveOnUpgrade.append(pipelineHandler)
                    pipelineFuture = self.addHandler(
                        pipelineHandler,
                        name: BNSChannelHandlerName.httpServerPipelineHandler.rawValue
                    )
                } else {
                    pipelineFuture = self.eventLoop.makeSucceededFuture(())
                }
                return pipelineFuture
            }
            .flatMap { _ -> EventLoopFuture<Void> in
                if context.configuration.featureOptions.contains(.supportsCompression) {
                    let responseCompressor = HTTPResponseCompressor()
                    handlersToRemoveOnUpgrade.append(responseCompressor)

                    return self.addHandler(
                        responseCompressor,
                        name: BNSChannelHandlerName.httpResponseCompressor.rawValue
                    )
                }
                return self.eventLoop.makeSucceededFuture(())
            }
            .flatMap { _ -> EventLoopFuture<Void> in
                let protocolErrorHandler = HTTPServerProtocolErrorHandler()
                handlersToRemoveOnUpgrade.append(protocolErrorHandler)

                return self.addHandler(
                    protocolErrorHandler,
                    name: BNSChannelHandlerName.httpServerProtocolErrorHandler.rawValue
                )
            }
            .flatMap { _ -> EventLoopFuture<Void> in
                handlersToRemoveOnUpgrade.append(streamHandler)
                return self.eventLoop.makeSucceededFuture(())
            }
            .flatMap { _ -> EventLoopFuture<Void> in
                let upgradeFuture: EventLoopFuture<Void>
                if context.configuration.protocolSupportOptions.contains(.webSocket) {
                    let webSocketUpgrader = NIOWebSocketServerUpgrader(
                        shouldUpgrade: { [weak http1Connection] (channel: Channel, requestHead: HTTPRequestHead) in
                            let promise: EventLoopPromise<HTTPHeaders?>
                                = channel.eventLoop.makePromise()

                            guard let http1Connection = http1Connection,
                                let queue = http1Connection.queue else {
                                promise.fail(BNSConnectionError.invalidState)
                                return promise.futureResult
                            }

                            queue.async {
                                guard let shouldUpgradeToWebSocketHandler
                                    = http1Connection.shouldUpgradeToWebSocketHandler else {
                                    promise.fail(BNSConnectionError.invalidState)
                                    return
                                }
                                shouldUpgradeToWebSocketHandler(requestHead) { result in
                                    switch result {
                                    case let .success(responseHeaders):
                                        promise.succeed(responseHeaders)
                                    case let .failure(error):
                                        promise.fail(error)
                                    }
                                }
                            }
                            return promise.futureResult
                        },
                        upgradePipelineHandler: { (channel: Channel, requestHead: HTTPRequestHead) in
                            let promise: EventLoopPromise<Void> = channel.eventLoop.makePromise()
                            context.queue.async {
                                let connectionBufferChannelHandler = BNSWSConnectionBufferChannelHandler(
                                    maxBufferSizeBeforeConnectionStart:
                                    context.configuration.maxBufferSizeBeforeConnectionStart,
                                    queue: context.queue,
                                    logger: context.logger
                                )
                                var newWebSocketStream: BNSWebSocketStream?
                                // swiftlint:disable line_length
                                let webSocketConnection: BNSWebSocketConnection = BNSWebSocketConnection(
                                    channel: channel,
                                    internalStartHandler: { [weak connectionBufferChannelHandler] (webSocketConnection: BNSWebSocketConnection) in
                                        channel.eventLoop.execute {
                                            connectionBufferChannelHandler?.stopBufferingAndFlush()
                                            if let webSocketStream = newWebSocketStream {
                                                guard let queue = webSocketConnection.queue else {
                                                    webSocketStream.cancel()
                                                    return
                                                }
                                                queue.async {
                                                    guard let newStreamHandler
                                                        = webSocketConnection.newStreamHandler else {
                                                        webSocketStream.cancel()
                                                        return
                                                    }
                                                    newStreamHandler(webSocketStream)
                                                }
                                            }
                                        }
                                    },
                                    requestHead: requestHead
                                )
                                // swiftlint:enable line_length
                                let webSocketStream: BNSWebSocketStream = BNSWebSocketStream(
                                    channel: channel,
                                    connection: webSocketConnection
                                )
                                newWebSocketStream = webSocketStream
                                http1Connection.connectionUpgraded(to: webSocketConnection)

                                promise.futureResult.whenComplete { _ in
                                    context.newConnectionHandler(.webSocket(webSocketConnection))
                                }

                                channel.pipeline.addHandler(
                                    BNSWebSocketConnectionChannelHandler(
                                        connection: webSocketConnection
                                    ),
                                    name: BNSChannelHandlerName.bnsWebSocketConnectionChannelHandler.rawValue
                                )
                                .flatMap { _ in
                                    channel.pipeline.addHandler(
                                        connectionBufferChannelHandler,
                                        name: BNSChannelHandlerName.bnsWSConnectionBufferChannelHandler.rawValue
                                    )
                                }
                                .flatMap { _ in
                                    channel.pipeline.addHandler(
                                        BNSWebSocketStreamChannelHandler(stream: webSocketStream),
                                        name: BNSChannelHandlerName.bnsWebSocketStreamChannelHandler.rawValue
                                    )
                                }
                                .cascade(to: promise)
                            }
                            return promise.futureResult
                        }
                    )

                    let upgrader = HTTPServerUpgradeHandler(
                        upgraders: [webSocketUpgrader],
                        httpEncoder: responseEncoder,
                        extraHTTPHandlers: handlersToRemoveOnUpgrade,
                        upgradeCompletionHandler: { _ in }
                    )
                    upgradeFuture = self.addHandler(
                        upgrader,
                        name: BNSChannelHandlerName.httpServerUpgradeHandler.rawValue
                    )
                } else {
                    upgradeFuture = self.eventLoop.makeSucceededFuture(())
                }
                return upgradeFuture
            }
            .flatMap { _ -> EventLoopFuture<Void> in
                self.addHandler(
                    streamHandler,
                    name: BNSChannelHandlerName.bnsHTTP1StreamChannelHandler.rawValue
                )
            }
    }

    // swiftlint:enable cyclomatic_complexity function_body_length
}
