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

import NIO
import NIOHTTP1

internal protocol BNSHTTPReadableWritable: AnyObject,
    BNSReadableStream, BNSWritableStream, BNSEventLoopProtectedLoggable {
    var channel: Channel { get }
    var sendBuffer: BNSSendBuffer<Self> { get set }
    var receiveBuffer: BNSHTTPReceiveBuffer<Self> { get set }
    var requestHead: HTTPRequestHead? { get }
    var requestTrailerHeaders: HTTPHeaders? { get set }
    var wasResponseHeadWritten: Bool { get set }
    var eventLoopProtectedResponseHead: HTTPResponseHead? { get set }
    var eventLoopProtectedResponseTrailerHeaders: HTTPHeaders? { get }
}

internal extension BNSHTTPReadableWritable where Self: BNSEventLoopProtectedLoggable {
    func read(_ byteBuffer: ByteBuffer) {
        self.eventLoop.assertInEventLoop()

        self.logDebug("Read: \(byteBuffer)")

        self.receiveBuffer.add(data: byteBuffer, isComplete: false, on: self)
    }

    func requestComplete(trailerHeaders: HTTPHeaders?) {
        self.eventLoop.assertInEventLoop()

        self.withQueueIfPossible { self.requestTrailerHeaders = trailerHeaders }

        self.logDebug("Read end of request with trailer headers: \(String(describing: trailerHeaders))")

        self.receiveBuffer.add(data: nil, isComplete: true, on: self)
    }

    func wrapOutboundOut(_ content: IOData) -> HTTPServerResponsePart {
        return HTTPServerResponsePart.body(content)
    }

    func writeStarted() {
        self.eventLoop.assertInEventLoop()

        let responseHead: HTTPResponseHead
        if let temporaryResponseHead = self.eventLoopProtectedResponseHead {
            responseHead = temporaryResponseHead
        } else {
            guard let requestHead = self.requestHead else {
                preconditionFailure("Do not have request head before writing response.")
            }
            responseHead = HTTPResponseHead(version: requestHead.version, status: HTTPResponseStatus.ok)
        }

        self.logDebug("Writing responseHead: \(responseHead)")
        self.withQueueIfPossible { self.wasResponseHeadWritten = true }

        self.channel.write(HTTPServerResponsePart.head(responseHead)).whenFailure { error in
            assertionFailure("Unexpected error: \(error)")
        }
    }

    func writeFinished() {
        self.eventLoop.assertInEventLoop()

        self.logDebug(
            """
            Writing end of response with trailer headers: \
            \(String(describing: self.eventLoopProtectedResponseTrailerHeaders))
            """
        )

        self.channel.writeAndFlush(HTTPServerResponsePart.end(self.eventLoopProtectedResponseTrailerHeaders))
            .whenFailure { error in
                assertionFailure("Unexpected error: \(error)")
            }
    }
}
