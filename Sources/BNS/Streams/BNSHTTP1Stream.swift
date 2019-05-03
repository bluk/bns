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

/// BNSHTTP1Stream is a HTTP 1.x stream.
public final class BNSHTTP1Stream: BNSHTTPStream,
    BNSStartable,
    BNSCancellable,
    BNSReadableStream,
    BNSWritableStream,
    BNSInternalStateSettable,
    BNSEventLoopProtectedPossiblyQueueable,
    BNSEventLoopProtectedLoggable,
    BNSHTTPReadableWritable {
    /// The current state of the instance. Must be accessed on the
    /// callback dispatch queue.
    public internal(set) var state: BNSStreamState = .setup

    // Must be accessed within the event loop.
    internal var eventLoopProtectedState: BNSStreamInternalState<BNSHTTP1Stream>
        = BNSStreamInternalState<BNSHTTP1Stream>()

    /// Handler for state changes.
    public var stateUpdateHandler: ((BNSStreamState) -> Void)? {
        didSet {
            let currentStateUpdateHandler = self.stateUpdateHandler
            guard self.eventLoop.inEventLoop else {
                self.eventLoop.execute { self.eventLoopProtectedStateUpdateHandler = currentStateUpdateHandler }
                return
            }
            self.eventLoopProtectedStateUpdateHandler = currentStateUpdateHandler
        }
    }

    internal var eventLoopProtectedStateUpdateHandler: ((BNSStreamState) -> Void)?

    /// The underlying Swift NIO channel.
    public let channel: Channel

    /// The underlying Swift NIO channel's event loop.
    public let eventLoop: EventLoop

    /// The callback queue.
    public internal(set) var queue: DispatchQueue?

    /// The logger used for this stream.
    public var logger: Logger? {
        didSet {
            let currentLogger = self.logger
            guard eventLoop.inEventLoop else {
                eventLoop.execute { self.eventLoopProtectedLogger = currentLogger }
                return
            }
            self.eventLoopProtectedLogger = currentLogger
        }
    }

    internal var eventLoopProtectedLogger: Logger?

    internal lazy var tryReadyTransitionFromStart: () -> Void = { [weak self] in
        guard let self = self else {
            return
        }
        self.eventLoopProtectedState.transition(to: .ready, on: self)
        self.receiveBuffer.process(on: self)
        self.sendBuffer.process(on: self)
    }

    /// The connection which the stream originated from.
    public private(set) var connection: BNSHTTP1Connection

    /// The head of the response containing the response status code and headers. It must be set before
    /// the first completed message is sent.
    public var responseHead: HTTPResponseHead? {
        didSet {
            let currentResponseHead = self.responseHead
            guard self.eventLoop.inEventLoop else {
                self.eventLoop.execute { self.eventLoopProtectedResponseHead = currentResponseHead }
                return
            }
            self.eventLoopProtectedResponseHead = currentResponseHead
        }
    }

    internal var eventLoopProtectedResponseHead: HTTPResponseHead?

    /// If the response head was written to the underlying network layer. Must be accessed on the callback queue.
    public internal(set) var wasResponseHeadWritten: Bool = false

    /// The response trailer headers. If there are any to send, they must be set before the message body's
    /// final message with isComplete is sent.
    public var responseTrailerHeaders: HTTPHeaders? {
        didSet {
            let currentResponseTrailerHeaders = self.responseTrailerHeaders
            guard self.eventLoop.inEventLoop else {
                self.eventLoop.execute {
                    self.eventLoopProtectedResponseTrailerHeaders = currentResponseTrailerHeaders
                }
                return
            }
            self.eventLoopProtectedResponseTrailerHeaders = currentResponseTrailerHeaders
        }
    }

    internal var eventLoopProtectedResponseTrailerHeaders: HTTPHeaders?

    internal var sendBuffer: BNSSendBuffer<BNSHTTP1Stream>
        = BNSSendBuffer<BNSHTTP1Stream>()
    internal var receiveBuffer: BNSHTTPReceiveBuffer<BNSHTTP1Stream>
        = BNSHTTPReceiveBuffer<BNSHTTP1Stream>()

    internal var isCancelCalled: Bool = false
    internal lazy var shouldCallClose: (() -> Bool)? = { [weak self] in
        guard let self = self else {
            return false
        }
        self.receiveBuffer.cancel(on: self)
        self.sendBuffer.cancel(on: self)

        guard self.requestHead?.isKeepAlive ?? false else {
            return true
        }
        self.logTrace("Request was a keepAlive or unknown, so only transition state")
        return false
    }

    internal lazy var afterCancelledCleanup: (() -> Void)? = nil

    /// The head of the request containing the request method, URI, and headers.
    public private(set) var requestHead: HTTPRequestHead?
    /// Any trailing headers in the request. Must be accessed on the callback queue.
    public internal(set) var requestTrailerHeaders: HTTPHeaders?

    internal init(
        channel: Channel,
        connection: BNSHTTP1Connection,
        requestHead: HTTPRequestHead
    ) {
        self.channel = channel
        self.eventLoop = self.channel.eventLoop
        self.connection = connection
        self.requestHead = requestHead

        self.responseHead = HTTPResponseHead(version: requestHead.version, status: .ok)
    }

    /// Deinit
    deinit {
        self.eventLoopProtectedState.assertDeinit()
        self.eventLoopProtectedLogger?.trace("deinit")
    }

    /// Starts the stream.
    ///
    /// - Parameters:
    ///     - queue: The queue to use for callbacks.
    public final func start(queue: DispatchQueue) {
        self.startStartable(queue: queue)
    }

    /// Cancels the stream.
    public final func cancel() {
        self.cancelCancellable()
    }

    /// Receives a complete message. The completion handler is only called once.
    ///
    /// - Parameters:
    ///     - completion: The completion callback to use when data is received.
    public final func receiveMessage(completion: @escaping (Data?, BNSStreamContentContext?, Bool, Error?) -> Void) {
        guard self.eventLoop.inEventLoop else {
            self.eventLoop.execute { self.receiveMessage(completion: completion) }
            return
        }
        self.receiveBuffer.receive(
            minimumIncompleteLength: 0,
            maximumLength: -1,
            completion: completion,
            waitForComplete: true,
            on: self
        )
    }

    /// Recieves content. The completion handler is only called once.
    ///
    /// - Parameters:
    ///     - minimumIncompleteLength: The desired minimum length before the completion callback is invoked.
    ///     - maximumLength: The maximum amount of data to invoke the completion handler with.
    ///     - completion: The completion callback to use when data is received.
    public final func receive(
        minimumIncompleteLength: Int,
        maximumLength: Int,
        completion: @escaping (Data?, BNSStreamContentContext?, Bool, Error?) -> Void
    ) {
        guard self.eventLoop.inEventLoop else {
            self.eventLoop.execute {
                self.receive(
                    minimumIncompleteLength: minimumIncompleteLength,
                    maximumLength: maximumLength,
                    completion: completion
                )
            }
            return
        }
        self.receiveBuffer.receive(
            minimumIncompleteLength: minimumIncompleteLength,
            maximumLength: maximumLength,
            completion: completion,
            waitForComplete: false,
            on: self
        )
    }

    // swiftlint:disable function_default_parameter_at_end

    /// Buffers data to send.
    ///
    /// - Parameters:
    ///     - content: The data to send.
    ///     - contentContext: The context for the data being sent.
    ///     - isComplete: If the data being sent represents a complete message.
    ///     - completion: The completion callback to use when data is sent.
    public final func send(
        content: IOData?,
        contentContext: BNSStreamContentContext = .defaultMessage,
        isComplete: Bool = true,
        completion: BNSStreamSendCompletion
    ) {
        guard self.eventLoop.inEventLoop else {
            self.eventLoop.execute {
                self.send(
                    content: content,
                    contentContext: contentContext,
                    isComplete: isComplete,
                    completion: completion
                )
            }
            return
        }
        self.sendBuffer.send(
            content: content,
            contentContext: contentContext,
            isComplete: isComplete,
            completion: completion,
            on: self
        )
    }

    // swiftlint:enable function_default_parameter_at_end
}
