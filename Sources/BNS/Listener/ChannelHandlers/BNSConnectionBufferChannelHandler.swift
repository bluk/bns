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
import NIOHTTP2
import NIOWebSocket

internal enum BufferedEvent {
    case active
    case inactive
    case readData(NIOAny)
    case readComplete
    case writabilityChanged
    case userInboundEventTriggered(Any)
    case errorCaught(Error)
}

internal final class BNSHTTP1ConnectionBufferChannelHandler: BNSConnectionBufferChannelHandler,
    ChannelInboundHandler,
    ChannelOutboundHandler,
    RemovableChannelHandler,
    BNSOnlyQueuePossiblyQueueable,
    BNSOnlyLoggerChannelHandlerLoggable {
    typealias InboundIn = HTTPServerRequestPart
    typealias InboundOut = HTTPServerRequestPart
    typealias OutboundIn = Never
    typealias OutboundOut = Never

    let logger: Logger?
    let queue: DispatchQueue?
    var isBuffering = true
    var hasRemovedHandler = false

    var bufferedEvents: [BufferedEvent]
    var context: ChannelHandlerContext?
    var eventLoop: EventLoop?
    var totalBytesBuffered: Int = 0
    var maxBufferSizeBeforeConnectionStart: Int?

    init(
        maxBufferSizeBeforeConnectionStart: Int?,
        queue: DispatchQueue,
        logger: Logger? = nil
    ) {
        self.maxBufferSizeBeforeConnectionStart = maxBufferSizeBeforeConnectionStart
        self.queue = queue

        if let logger = logger {
            var loggerWithMetadata = logger
            loggerWithMetadata[metadataKey: "handler"] = "\(type(of: self))"
            self.logger = loggerWithMetadata
        } else {
            self.logger = nil
        }
        self.bufferedEvents = []
        self.bufferedEvents.reserveCapacity(16)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if let maxBufferSizeBeforeConnectionStart = self.maxBufferSizeBeforeConnectionStart {
            let requestPart = self.unwrapInboundIn(data)
            switch requestPart {
            case let .body(bodyBytes):
                self.totalBytesBuffered += bodyBytes.readableBytes
                if totalBytesBuffered > maxBufferSizeBeforeConnectionStart {
                    context.close().whenFailure { error in
                        context.fireErrorCaught(error)
                    }
                    return
                }
            default:
                break
            }
        }

        self.bufferedEvents.append(.readData(data))
        self.tryToFlushBuffer(context: context)
    }
}

internal final class BNSHTTP2ConnectionBufferChannelHandler: BNSConnectionBufferChannelHandler,
    ChannelInboundHandler,
    ChannelOutboundHandler,
    RemovableChannelHandler,
    BNSOnlyQueuePossiblyQueueable,
    BNSOnlyLoggerChannelHandlerLoggable {
    typealias InboundIn = HTTP2Frame
    typealias InboundOut = HTTP2Frame
    typealias OutboundIn = Never
    typealias OutboundOut = Never

    let logger: Logger?
    let queue: DispatchQueue?
    var isBuffering = true
    var hasRemovedHandler = false

    var bufferedEvents: [BufferedEvent]
    var context: ChannelHandlerContext?
    var eventLoop: EventLoop?
    var totalBytesBuffered: Int = 0
    var maxBufferSizeBeforeConnectionStart: Int?

    init(
        maxBufferSizeBeforeConnectionStart: Int?,
        queue: DispatchQueue,
        logger: Logger? = nil
    ) {
        self.maxBufferSizeBeforeConnectionStart = maxBufferSizeBeforeConnectionStart
        self.queue = queue

        if let logger = logger {
            var loggerWithMetadata = logger
            loggerWithMetadata[metadataKey: "handler"] = "\(type(of: self))"
            self.logger = loggerWithMetadata
        } else {
            self.logger = nil
        }
        self.bufferedEvents = []
        self.bufferedEvents.reserveCapacity(16)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if let maxBufferSizeBeforeConnectionStart = self.maxBufferSizeBeforeConnectionStart {
            let http2Frame = self.unwrapInboundIn(data)
            switch http2Frame.payload {
            case let .data(frameData):
                self.totalBytesBuffered += frameData.data.readableBytes
                if totalBytesBuffered > maxBufferSizeBeforeConnectionStart {
                    context.close().whenFailure { error in
                        context.fireErrorCaught(error)
                    }
                    return
                }
            default:
                break
            }
        }

        self.bufferedEvents.append(.readData(data))
        self.tryToFlushBuffer(context: context)
    }
}

internal final class BNSWSConnectionBufferChannelHandler: BNSConnectionBufferChannelHandler,
    ChannelInboundHandler,
    ChannelOutboundHandler,
    RemovableChannelHandler,
    BNSOnlyQueuePossiblyQueueable,
    BNSOnlyLoggerChannelHandlerLoggable {
    typealias InboundIn = WebSocketFrame
    typealias InboundOut = WebSocketFrame
    typealias OutboundIn = Never
    typealias OutboundOut = Never

    let logger: Logger?
    let queue: DispatchQueue?
    var isBuffering = true
    var hasRemovedHandler = false

    var bufferedEvents: [BufferedEvent]
    var context: ChannelHandlerContext?
    var eventLoop: EventLoop?
    var totalBytesBuffered: Int = 0
    var maxBufferSizeBeforeConnectionStart: Int?

    init(
        maxBufferSizeBeforeConnectionStart: Int?,
        queue: DispatchQueue,
        logger: Logger? = nil
    ) {
        self.maxBufferSizeBeforeConnectionStart = maxBufferSizeBeforeConnectionStart
        self.queue = queue

        if let logger = logger {
            var loggerWithMetadata = logger
            loggerWithMetadata[metadataKey: "handler"] = "\(type(of: self))"
            self.logger = loggerWithMetadata
        } else {
            self.logger = nil
        }
        self.bufferedEvents = []
        self.bufferedEvents.reserveCapacity(16)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if let maxBufferSizeBeforeConnectionStart = self.maxBufferSizeBeforeConnectionStart {
            let webSocketFrame = self.unwrapInboundIn(data)
            self.totalBytesBuffered += webSocketFrame.length

            if totalBytesBuffered > maxBufferSizeBeforeConnectionStart {
                context.close().whenFailure { error in
                    context.fireErrorCaught(error)
                }
                return
            }
        }

        self.bufferedEvents.append(.readData(data))
        self.tryToFlushBuffer(context: context)
    }
}

internal protocol BNSConnectionBufferChannelHandler: ChannelInboundHandler,
    ChannelOutboundHandler,
    RemovableChannelHandler {
    var isBuffering: Bool { get set }
    var hasRemovedHandler: Bool { get set }
    var totalBytesBuffered: Int { get set }
    var maxBufferSizeBeforeConnectionStart: Int? { get }

    var bufferedEvents: [BufferedEvent] { get set }
}

internal struct BNSConnectionShouldStopInboundBufferingEvent {}

internal extension BNSConnectionBufferChannelHandler
    where Self: BNSOnlyLoggerChannelHandlerLoggable & BNSOnlyQueuePossiblyQueueable {
    func triggerUserOutboundEvent(context: ChannelHandlerContext, event: Any, promise: EventLoopPromise<Void>?) {
        defer { context.triggerUserOutboundEvent(event, promise: promise) }

        if event is BNSConnectionShouldStopInboundBufferingEvent {
            self.logTrace("Stop buffering and flush")
            self.isBuffering = false
            self.tryToFlushBuffer(context: context)
        }
    }

    // swiftlint:disable cyclomatic_complexity

    func tryToFlushBuffer(context: ChannelHandlerContext) {
        self.logTrace("Trying to flush buffer")
        guard !self.isBuffering else {
            self.logTrace("Still buffering so returning")
            return
        }

        for event in self.bufferedEvents {
            switch event {
            case .active:
                context.fireChannelActive()
            case .inactive:
                context.fireChannelInactive()
            case let .readData(data):
                let reqPart = self.unwrapInboundIn(data)
                context.fireChannelRead(NIOAny(reqPart))
            case .readComplete:
                context.fireChannelReadComplete()
            case .writabilityChanged:
                context.fireChannelWritabilityChanged()
            case let .userInboundEventTriggered(event):
                context.fireUserInboundEventTriggered(event)
            case let .errorCaught(error):
                context.fireErrorCaught(error)
            }
        }

        self.bufferedEvents.removeAll()

        guard !self.hasRemovedHandler else {
            return
        }
        self.hasRemovedHandler = true
        context.pipeline.removeHandler(self).whenFailure { error in
            switch error {
            case let pipelineError as ChannelPipelineError:
                switch pipelineError {
                case .notFound:
                    break
                default:
                    assertionFailure("Unexpected error: \(error)")
                }
            default:
                assertionFailure("Unexpected error: \(error)")
            }
        }
    }

    // swiftlint:enable cyclomatic_complexity

    func channelRegistered(context: ChannelHandlerContext) {
        context.fireChannelRegistered()
        self.tryToFlushBuffer(context: context)
    }

    func channelUnregistered(context: ChannelHandlerContext) {
        context.fireChannelUnregistered()
        self.tryToFlushBuffer(context: context)
    }

    func channelActive(context: ChannelHandlerContext) {
        self.bufferedEvents.append(.active)
        self.tryToFlushBuffer(context: context)
    }

    func channelInactive(context: ChannelHandlerContext) {
        self.bufferedEvents.append(.inactive)
        self.tryToFlushBuffer(context: context)
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        self.bufferedEvents.append(.readComplete)
        self.tryToFlushBuffer(context: context)
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        self.bufferedEvents.append(.writabilityChanged)
        self.tryToFlushBuffer(context: context)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        self.bufferedEvents.append(.userInboundEventTriggered(event))
        self.tryToFlushBuffer(context: context)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.bufferedEvents.append(.errorCaught(error))
        self.tryToFlushBuffer(context: context)
    }
}
