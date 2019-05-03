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
import NIOWebSocket

/// BNSWebSocketConnection represents a WebSocket connection.
public final class BNSWebSocketConnection: BNSBaseConnection,
    BNSInternalStateSettable,
    BNSEventLoopProtectedPossiblyQueueable,
    BNSEventLoopProtectedLoggable,
    BNSStartable,
    BNSCancellable {
    /// The current state of the instance. Must be accessed on the
    /// callback dispatch queue.
    public internal(set) var state: BNSConnectionState = .setup

    // Must be accessed within the event loop.
    internal var eventLoopProtectedState: BNSConnectionInternalState<BNSWebSocketConnection>
        = BNSConnectionInternalState<BNSWebSocketConnection>()

    /// Handler for state changes.
    public var stateUpdateHandler: ((BNSConnectionState) -> Void)? {
        didSet {
            let currentStateUpdateHandler = self.stateUpdateHandler
            guard self.eventLoop.inEventLoop else {
                self.eventLoop.execute { self.eventLoopProtectedStateUpdateHandler = currentStateUpdateHandler }
                return
            }
            self.eventLoopProtectedStateUpdateHandler = currentStateUpdateHandler
        }
    }

    internal var eventLoopProtectedStateUpdateHandler: ((BNSConnectionState) -> Void)?

    /// The underlying Swift NIO channel.
    public let channel: Channel

    /// The underlying Swift NIO channel's event loop.
    public let eventLoop: EventLoop

    /// The callback queue. Must only be accessed after connection is started.
    public internal(set) var queue: DispatchQueue?

    /// The logger used for this connection.
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

    /// Handler for new streams. Must be accessed on the callback dispatch queue.
    /// The handler should generally call the stream's start method.
    public var newStreamHandler: ((BNSWebSocketStream) -> Void)?

    internal lazy var tryReadyTransitionFromStart: () -> Void = { [weak self] in
        guard let self = self else {
            return
        }
        self.eventLoopProtectedState.transition(to: .ready, on: self)
        self.internalStartHandler?(self)
    }

    /// The request head of the original HTTP request
    public let requestHead: HTTPRequestHead

    internal var internalStartHandler: ((BNSWebSocketConnection) -> Void)?

    internal var isCancelCalled: Bool = false
    internal let shouldCallClose: (() -> Bool)? = nil
    internal lazy var afterCancelledCleanup: (() -> Void)? = { [weak self] in
        guard let self = self else {
            return
        }
        self.newStreamHandler = nil
        self.internalStartHandler = nil
    }

    internal init(
        channel: Channel,
        internalStartHandler: @escaping (BNSWebSocketConnection) -> Void,
        requestHead: HTTPRequestHead
    ) {
        self.channel = channel
        self.eventLoop = self.channel.eventLoop
        self.requestHead = requestHead
        self.internalStartHandler = internalStartHandler
    }

    /// Deinit
    deinit {
        self.eventLoopProtectedState.assertDeinit()
        self.eventLoopProtectedLogger?.trace("deinit")
    }

    /// Starts the connection.
    ///
    /// - Parameters:
    ///     - queue: The queue to use for callbacks.
    public final func start(queue: DispatchQueue) {
        self.startStartable(queue: queue)
    }

    /// Cancels the connection.
    public final func cancel() {
        self.cancelCancellable()
    }
}
