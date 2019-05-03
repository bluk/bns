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

/// BNSHTTP1Connection represents a HTTP 1.x connection.
public final class BNSHTTP1Connection: BNSHTTPConnection,
    BNSInternalStateSettable,
    BNSEventLoopProtectedPossiblyQueueable,
    BNSEventLoopProtectedLoggable,
    BNSStartable,
    BNSCancellable,
    CustomStringConvertible,
    CustomDebugStringConvertible {
    /// The current state of the instance. Must be accessed on the
    /// callback dispatch queue.
    public internal(set) var state: BNSConnectionState = .setup

    // Must be accessed within the event loop.
    internal var eventLoopProtectedState: BNSConnectionInternalState<BNSHTTP1Connection>
        = BNSConnectionInternalState<BNSHTTP1Connection>()

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
    public var newStreamHandler: ((BNSHTTP1Stream) -> Void)?

    /// Handler to determine if the stream should be upgraded. Must be accessed on the callback dispatch queue.
    /// The handler is called with the request's head and a completion callback. If the connection should be
    /// upgraded to a web socket, then the completion callback should be sent a success Result with the
    /// upgrade response headers (if any). Otherwise, the completion callback must be called with a Result failure.
    public var shouldUpgradeToWebSocketHandler: (BNSHTTPShouldUpgradeToWebSocketHandler)?

    internal lazy var tryReadyTransitionFromStart: () -> Void = { [weak self] in
        guard let self = self else {
            return
        }
        self.eventLoopProtectedState.transition(to: .ready, on: self)
        self.internalStartHandler?()
    }

    internal var internalStartHandler: (() -> Void)?

    internal var isCancelCalled: Bool = false
    internal lazy var shouldCallClose: (() -> Bool)? = { [weak self] in
        guard let self = self else {
            return false
        }
        guard self.isConnectionUpgraded else {
            return true
        }
        self.logTrace("Connection was upgraded so only transition state")
        return false
    }

    internal lazy var afterCancelledCleanup: (() -> Void)? = { [weak self] in
        guard let self = self else {
            return
        }
        self.newStreamHandler = nil
        self.shouldUpgradeToWebSocketHandler = nil
        self.internalStartHandler = nil
    }

    private var isConnectionUpgraded: Bool = false

    internal init(
        channel: Channel,
        internalStartHandler: @escaping () -> Void
    ) {
        self.channel = channel
        self.eventLoop = self.channel.eventLoop
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

    internal final func connectionUpgraded(to connection: BNSWebSocketConnection) {
        guard self.eventLoop.inEventLoop else {
            self.eventLoop.execute { self.connectionUpgraded(to: connection) }
            return
        }

        self.logTrace("Connection was upgraded")

        self.isConnectionUpgraded = true
        self.eventLoopProtectedState.transition(
            to: .failed(BNSConnectionError.connectionUpgraded(.webSocket(connection))),
            on: self
        )
    }

    /// Cancels the connection.
    public final func cancel() {
        self.cancelCancellable()
    }

    public var description: String {
        return
            """
            BNSHTTP1Connection(\
            state: \(self.state), \
            remoteAddress: \(String(reflecting: self.channel.remoteAddress))\
            )
            """
    }

    public var debugDescription: String {
        return
            """
            BNSHTTP1Connection(\
            state: \(self.state), \
            remoteAddress: \(String(reflecting: self.channel.remoteAddress)), \
            isConnectionUpgraded: \(self.isConnectionUpgraded), \
            isCancelCalled: \(self.isCancelCalled)\
            )
            """
    }
}
