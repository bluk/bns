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
import NIOHTTP2

internal extension ChannelPipeline {
    // swiftlint:disable function_body_length

    func configureH2(
        context: BNSListener.InitializeChildChannelContext,
        finishPipelineInitFuture: EventLoopFuture<Void>
    ) -> EventLoopFuture<Void> {
        let connectionBufferChannelHandler = BNSHTTP2ConnectionBufferChannelHandler(
            maxBufferSizeBeforeConnectionStart:
            context.configuration.maxBufferSizeBeforeConnectionStart,
            queue: context.queue,
            logger: context.logger
        )

        let h2Connection = BNSHTTP2Connection(
            channel: context.channel,
            internalStartHandler: {
                finishPipelineInitFuture.whenComplete { _ in
                    context.channel.triggerUserOutboundEvent(BNSConnectionShouldStopInboundBufferingEvent())
                        .whenFailure { error in
                            if let channelError = error as? ChannelError {
                                switch channelError {
                                case .ioOnClosedChannel:
                                    break
                                default:
                                    assertionFailure("Unexpected error in \(error)")
                                }
                            } else {
                                assertionFailure("Unexpected error in \(error)")
                            }
                        }
                }
            }
        )
        finishPipelineInitFuture.whenComplete { _ in
            context.newConnectionHandler(.http2(h2Connection))
        }

        let connectionChannelHandler = BNSHTTP2ConnectionChannelHandler(
            connection: h2Connection
        )

        return self.addHandler(
            NIOHTTP2Handler(mode: .server, initialSettings: context.configuration.http2Settings),
            name: BNSChannelHandlerName.nioHTTP2Handler.rawValue
        )
        .flatMap { _ in
            self.addHandler(
                connectionChannelHandler,
                name: BNSChannelHandlerName.bnsHTTP2ConnectionChannelHandler.rawValue
            )
        }
        .flatMap { _ in
            self.addHandler(
                connectionBufferChannelHandler,
                name: BNSChannelHandlerName.bnsHTTP2ConnectionBufferChannelHandler.rawValue
            )
        }
        .flatMap { _ in
            // swiftlint:disable line_length

            let multiplexer = HTTP2StreamMultiplexer(
                mode: .server,
                channel: context.channel,
                inboundStreamStateInitializer: { [weak h2Connection] (streamChannel: Channel, streamID: HTTP2StreamID) in
                    guard let h2Connection = h2Connection else {
                        context.queue.async {
                            context.logger?.debug("HTTP2 Connection does not exist, so not initializing stream.")
                        }
                        return streamChannel.close()
                    }
                    let stream = BNSHTTP2Stream(
                        channel: streamChannel,
                        connection: h2Connection,
                        h2StreamID: streamID,
                        isPushRequest: false
                    )

                    let addHandlerFuture = streamChannel.pipeline
                        .addHandler(
                            HTTP2ToHTTP1ServerCodec(streamID: streamID),
                            name: BNSChannelHandlerName.http2ToHTTP1ServerCodec.rawValue
                        )
                        .flatMap { () -> EventLoopFuture<Void> in
                            streamChannel.pipeline.addHandler(
                                BNSHTTP2StreamChannelHandler(stream: stream),
                                name: BNSChannelHandlerName.bnsHTTP2StreamChannelHandler.rawValue
                            )
                        }
                        .flatMap { () -> EventLoopFuture<Void> in
                            streamChannel.pipeline.addHandler(
                                NIOCloseOnErrorHandler(),
                                name: BNSChannelHandlerName.nioCloseOnErrorHandler.rawValue
                            )
                        }

                    addHandlerFuture.whenComplete { _ in
                        guard let queue = h2Connection.queue else {
                            stream.cancel()
                            return
                        }
                        queue.async {
                            guard let newStreamHandler = h2Connection.newStreamHandler else {
                                stream.cancel()
                                return
                            }
                            newStreamHandler(stream)
                        }
                    }
                    return addHandlerFuture
                }
            )

            // swiftlint:enable line_length

            h2Connection.multiplexer = multiplexer
            return self.addHandler(
                multiplexer,
                name: BNSChannelHandlerName.http2StreamMultiplexer.rawValue
            )
        }
    }

    // swiftlint:enable function_body_length
}
