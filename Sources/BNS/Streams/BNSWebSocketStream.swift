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
import NIOWebSocket

/// BNSWebSocketStream represents a web socket.
public final class BNSWebSocketStream: BNSBaseStream,
    BNSStartable,
    BNSCancellable,
    BNSWritableStream,
    BNSInternalStateSettable,
    BNSEventLoopProtectedPossiblyQueueable,
    BNSEventLoopProtectedLoggable {
    typealias BNSWritableStreamDataType = WebSocketFrame

    /// The current state of the instance. Must be accessed on the
    /// callback dispatch queue.
    public internal(set) var state: BNSStreamState = .setup

    // Must be accessed within the event loop.
    internal var eventLoopProtectedState: BNSStreamInternalState<BNSWebSocketStream>
        = BNSStreamInternalState<BNSWebSocketStream>()

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

    /// The callback queue. Must only be accessed after the stream is started.
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

    /// The underlying WebSocket connection.
    public private(set) var connection: BNSWebSocketConnection

    private var sendBuffer: BNSSendBuffer<BNSWebSocketStream>
        = BNSSendBuffer<BNSWebSocketStream>()
    private var receiveBuffer: BNSWebSocketReceiveBuffer = BNSWebSocketReceiveBuffer()

    internal var isCancelCalled: Bool = false
    internal lazy var shouldCallClose: (() -> Bool)? = { [weak self] in
        guard let self = self else {
            return false
        }
        self.receiveBuffer.cancel(on: self)
        self.sendBuffer.cancel(on: self)

        return true
    }

    internal lazy var afterCancelledCleanup: (() -> Void)? = nil

    internal init(
        channel: Channel,
        connection: BNSWebSocketConnection
    ) {
        self.channel = channel
        self.eventLoop = self.channel.eventLoop
        self.connection = connection
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

    /// Receives content. Receives all of the buffered dataa.
    ///
    /// - Parameters:
    ///     - completion: The completion callback to use when data is received.
    public final func receive(
        completion: @escaping (WebSocketFrame?, BNSStreamContentContext?, Bool, Error?) -> Void
    ) {
        guard self.eventLoop.inEventLoop else {
            self.eventLoop.execute { self.receive(completion: completion) }
            return
        }
        self.receiveBuffer.receive(completion: completion, on: self)
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
        content: WebSocketFrame?,
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

    internal final func read(frame: WebSocketFrame) {
        self.channel.eventLoop.assertInEventLoop()

        self.logDebug("Read: \(frame)")

        self.receiveBuffer.add(frame: frame, on: self)
    }

    internal func wrapOutboundOut(_ content: WebSocketFrame) -> WebSocketFrame {
        return content
    }

    internal final func writeStarted() {
        // Do nothing
    }

    internal final func writeFinished() {
        self.channel.flush()
    }
}
