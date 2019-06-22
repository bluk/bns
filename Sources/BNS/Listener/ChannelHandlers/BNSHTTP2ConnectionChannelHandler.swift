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
import NIOHTTP2

internal final class BNSHTTP2ConnectionChannelHandler: ChannelInboundHandler,
    ChannelOutboundHandler,
    RemovableChannelHandler,
    BNSWithLoggableInstanceChannelHandlerLoggable {
    public typealias InboundIn = HTTP2Frame
    public typealias InboundOut = HTTP2Frame
    public typealias OutboundIn = HTTP2Frame
    public typealias OutboundOut = HTTP2Frame

    internal let connection: BNSHTTP2Connection

    internal let eventLoopProtectedLoggable: BNSHTTP2Connection?

    public init(
        connection: BNSHTTP2Connection
    ) {
        self.connection = connection
        self.eventLoopProtectedLoggable = connection
    }

    public func channelInactive(context: ChannelHandlerContext) {
        self.logTrace("channelInactive() called")
        defer { context.fireChannelInactive() }

        self.connection.eventLoopProtectedState.transition(
            to: .failed(BNSConnectionError.connectionReset),
            on: self.connection
        )
    }

    public func channelReadComplete(context: ChannelHandlerContext) {
        self.logTrace("channelReadComplete() called")
        context.fireChannelReadComplete()

        context.flush()
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.logDebug("errorCaught(): \(error)")
        defer { context.fireErrorCaught(error) }

        self.connection.eventLoopProtectedState.transition(to: .failed(error), on: self.connection)
    }

    public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        self.logDebug("userInboundEventTriggered(): \(event)")
        context.fireUserInboundEventTriggered(event)
        switch event {
        case _ as IdleStateHandler.IdleStateEvent:
            self.connection.eventLoopProtectedState.transition(
                to: .failed(BNSConnectionError.idleTimeout),
                on: self.connection
            )
            _ = context.close()
        default:
            break
        }
    }
}
