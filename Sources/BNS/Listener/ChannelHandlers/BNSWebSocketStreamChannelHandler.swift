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

import Logging
import NIO
import NIOHTTP1
import NIOWebSocket

internal final class BNSWebSocketStreamChannelHandler: ChannelInboundHandler,
    ChannelOutboundHandler,
    RemovableChannelHandler,
    BNSWithLoggableInstanceChannelHandlerLoggable,
    BNSChannelHandlerCloseLoggable,
    BNSChannelHandlerTriggerUserOutboundEventLoggable {
    public typealias InboundIn = WebSocketFrame
    public typealias InboundOut = WebSocketFrame
    public typealias OutboundIn = WebSocketFrame
    public typealias OutboundOut = WebSocketFrame

    private let stream: BNSWebSocketStream
    internal let eventLoopProtectedLoggable: BNSWebSocketStream?

    public init(
        stream: BNSWebSocketStream
    ) {
        self.stream = stream
        self.eventLoopProtectedLoggable = stream
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = self.unwrapInboundIn(data)
        defer { context.fireChannelRead(self.wrapInboundOut(frame)) }

        self.stream.read(frame: frame)
    }

    public func channelInactive(context: ChannelHandlerContext) {
        self.logTrace("channelInactive() called")
        defer { context.fireChannelInactive() }

        self.stream.eventLoopProtectedState.transition(to: .failed(BNSStreamError.streamReset), on: self.stream)
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.logDebug("errorCaught(): \(error)")
        defer { context.fireErrorCaught(error) }

        self.stream.eventLoopProtectedState.transition(to: .failed(error), on: self.stream)
    }

    public func channelReadComplete(context: ChannelHandlerContext) {
        self.logTrace("channelReadComplete() called")
        defer { context.fireChannelReadComplete() }

        context.flush()
    }

    public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        self.logDebug("userInboundEventTriggered(): \(event)")
        context.fireUserInboundEventTriggered(event)
        switch event {
        case _ as IdleStateHandler.IdleStateEvent:
            self.stream.eventLoopProtectedState.transition(to: .failed(BNSStreamError.idleTimeout), on: self.stream)
            _ = context.close()
        default:
            break
        }
    }
}
