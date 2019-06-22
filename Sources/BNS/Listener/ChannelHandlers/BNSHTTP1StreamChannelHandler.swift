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

internal final class BNSHTTP1StreamChannelHandler: ChannelInboundHandler,
    ChannelOutboundHandler,
    RemovableChannelHandler,
    BNSWithLoggableInstanceChannelHandlerLoggable {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias InboundOut = HTTPServerRequestPart
    public typealias OutboundIn = HTTPServerResponsePart
    public typealias OutboundOut = HTTPServerResponsePart

    private let connection: BNSHTTP1Connection
    private let handler: (BNSHTTP1Stream) -> Void
    private var stream: BNSHTTP1Stream?

    internal var eventLoopProtectedLoggable: BNSHTTP1Stream?

    public init(
        connection: BNSHTTP1Connection,
        handler: @escaping (BNSHTTP1Stream) -> Void
    ) {
        self.connection = connection
        self.handler = handler
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)

        defer { context.fireChannelRead(self.wrapInboundOut(reqPart)) }

        switch reqPart {
        case let .head(request):
            let stream = BNSHTTP1Stream(
                channel: context.channel,
                connection: connection,
                requestHead: request
            )
            self.stream = stream
            self.eventLoopProtectedLoggable = self.stream
            self.handler(stream)
        case let .body(requestBody):
            guard let stream = self.stream else {
                assertionFailure("Should have a stream.")
                return
            }
            stream.read(requestBody)
        case let .end(trailerHeaders):
            guard let stream = self.stream else {
                assertionFailure("Should have a stream.")
                return
            }
            stream.requestComplete(trailerHeaders: trailerHeaders)
        }
    }

    public func channelInactive(context: ChannelHandlerContext) {
        self.logTrace("channelInactive() called")
        defer { context.fireChannelInactive() }

        guard let stream = self.stream else {
            return
        }

        stream.eventLoopProtectedState.transition(to: .failed(BNSStreamError.streamReset), on: stream)
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.logDebug("errorCaught(): \(error)")

        defer { context.fireErrorCaught(error) }

        guard let stream = self.stream else {
            return
        }

        stream.eventLoopProtectedState.transition(to: .failed(error), on: stream)
    }

    public func channelReadComplete(context: ChannelHandlerContext) {
        self.logTrace("channelReadComplete() called")
        defer { context.fireChannelReadComplete() }

        context.flush()
    }

    public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        self.logDebug("userInboundEventTriggered(): \(event)")
        context.fireUserInboundEventTriggered(event)

        guard let stream = self.stream else {
            return
        }

        switch event {
        case _ as IdleStateHandler.IdleStateEvent:
            stream.eventLoopProtectedState.transition(to: .failed(BNSStreamError.idleTimeout), on: stream)
            context.close().whenFailure { error in
                context.fireErrorCaught(error)
            }
        default:
            break
        }
    }
}
