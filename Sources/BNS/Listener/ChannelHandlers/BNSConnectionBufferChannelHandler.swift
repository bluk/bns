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
    RemovableChannelHandler,
    BNSOnlyQueuePossiblyQueueable,
    BNSOnlyLoggerChannelHandlerLoggable {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias InboundOut = HTTPServerRequestPart

    internal let logger: Logger?
    internal let queue: DispatchQueue?
    internal var isBuffering = true
    internal var hasRemovedHandler = false

    internal var bufferedEvents: [BufferedEvent]
    internal var context: ChannelHandlerContext?
    internal var eventLoop: EventLoop?
    internal var totalBytesBuffered: Int = 0
    internal var maxBufferSizeBeforeConnectionStart: Int?

    public init(
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
                    _ = context.close()
                    return
                }
            default:
                break
            }
        }

        self.bufferedEvents.append(.readData(data))
        checkIfStillBuffering(context: context)
    }
}

internal final class BNSHTTP2ConnectionBufferChannelHandler: BNSConnectionBufferChannelHandler,
    ChannelInboundHandler,
    RemovableChannelHandler,
    BNSOnlyQueuePossiblyQueueable,
    BNSOnlyLoggerChannelHandlerLoggable {
    public typealias InboundIn = HTTP2Frame
    public typealias InboundOut = HTTP2Frame

    internal let logger: Logger?
    internal let queue: DispatchQueue?
    internal var isBuffering = true
    internal var hasRemovedHandler = false

    internal var bufferedEvents: [BufferedEvent]
    internal var context: ChannelHandlerContext?
    internal var eventLoop: EventLoop?
    internal var totalBytesBuffered: Int = 0
    internal var maxBufferSizeBeforeConnectionStart: Int?

    public init(
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
                    _ = context.close()
                    return
                }
            default:
                break
            }
        }

        self.bufferedEvents.append(.readData(data))
        checkIfStillBuffering(context: context)
    }
}

internal final class BNSWSConnectionBufferChannelHandler: BNSConnectionBufferChannelHandler,
    ChannelInboundHandler,
    RemovableChannelHandler,
    BNSOnlyQueuePossiblyQueueable,
    BNSOnlyLoggerChannelHandlerLoggable {
    public typealias InboundIn = WebSocketFrame
    public typealias InboundOut = WebSocketFrame

    internal let logger: Logger?
    internal let queue: DispatchQueue?
    internal var isBuffering = true
    internal var hasRemovedHandler = false

    internal var bufferedEvents: [BufferedEvent]
    internal var context: ChannelHandlerContext?
    internal var eventLoop: EventLoop?
    internal var totalBytesBuffered: Int = 0
    internal var maxBufferSizeBeforeConnectionStart: Int?

    public init(
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
                _ = context.close()
                return
            }
        }

        self.bufferedEvents.append(.readData(data))
        checkIfStillBuffering(context: context)
    }
}

internal protocol BNSConnectionBufferChannelHandler: ChannelInboundHandler,
    RemovableChannelHandler {
    var isBuffering: Bool { get set }
    var hasRemovedHandler: Bool { get set }
    var totalBytesBuffered: Int { get set }
    var maxBufferSizeBeforeConnectionStart: Int? { get }

    var bufferedEvents: [BufferedEvent] { get set }
    var context: ChannelHandlerContext? { get set }
    var eventLoop: EventLoop? { get set }
}

internal extension BNSConnectionBufferChannelHandler
    where Self: BNSOnlyLoggerChannelHandlerLoggable & BNSOnlyQueuePossiblyQueueable {
    func stopBufferingAndFlush() {
        self.logTrace("Stop buffering and flush")
        self.isBuffering = false
        tryToFlushBuffer()
    }

    func checkIfStillBuffering(context: ChannelHandlerContext) {
        self.logTrace("Checking if still buffering")
        self.context = context
        self.eventLoop = context.channel.eventLoop
        tryToFlushBuffer()
    }

    // swiftlint:disable cyclomatic_complexity

    func tryToFlushBuffer() {
        self.logTrace("Trying to flush buffer")
        guard !self.isBuffering else {
            self.logTrace("Still buffering so returning")
            return
        }

        guard let context = self.context,
            let eventLoop = self.eventLoop else {
            self.logTrace("Don't have the context or event loop yet, so returning")
            return
        }

        eventLoop.assertInEventLoop()

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
        _ = context.pipeline.removeHandler(self)
    }

    // swiftlint:enable cyclomatic_complexity

    func channelRegistered(context: ChannelHandlerContext) {
        context.fireChannelRegistered()
        checkIfStillBuffering(context: context)
    }

    func channelUnregistered(context: ChannelHandlerContext) {
        self.context = nil
        self.eventLoop = nil
        context.fireChannelUnregistered()
        checkIfStillBuffering(context: context)
    }

    func channelActive(context: ChannelHandlerContext) {
        self.bufferedEvents.append(.active)
        checkIfStillBuffering(context: context)
    }

    func channelInactive(context: ChannelHandlerContext) {
        self.bufferedEvents.append(.inactive)
        checkIfStillBuffering(context: context)
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        self.bufferedEvents.append(.readComplete)
        checkIfStillBuffering(context: context)
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        self.bufferedEvents.append(.writabilityChanged)
        checkIfStillBuffering(context: context)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        self.bufferedEvents.append(.userInboundEventTriggered(event))
        checkIfStillBuffering(context: context)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.bufferedEvents.append(.errorCaught(error))
        checkIfStillBuffering(context: context)
    }
}
