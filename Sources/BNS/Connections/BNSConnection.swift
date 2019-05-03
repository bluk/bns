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

/// BNSConnection types.
public enum BNSConnection {
    /// A HTTP 1.x connection
    case http1(BNSHTTP1Connection)
    /// A HTTP 2.x connection
    case http2(BNSHTTP2Connection)
    /// A WebSocket connection
    case webSocket(BNSWebSocketConnection)

    /// The connection as a protocol type
    public var baseConnection: BNSBaseConnection {
        switch self {
        case let .http1(connection):
            return connection
        case let .http2(connection):
            return connection
        case let .webSocket(connection):
            return connection
        }
    }

    /// The connection as a protocol type
    public var httpConnection: BNSHTTPConnection? {
        switch self {
        case let .http1(connection):
            return connection
        case let .http2(connection):
            return connection
        case .webSocket:
            return nil
        }
    }
}

/// Handles a BNSConnection.
public typealias BNSConnectionHandler = (BNSConnection) -> Void

/// BNSConnection represents a connection from a client to the service. A connection can have
/// multiple streams.
public protocol BNSBaseConnection: AnyObject {
    /// The current state of the instance. Must be accessed on the
    /// callback dispatch queue.
    var state: BNSConnectionState { get }

    /// Handler for state changes.
    var stateUpdateHandler: ((BNSConnectionState) -> Void)? { get set }

    /// The underlying Swift NIO channel.
    var channel: Channel { get }

    /// The underlying Swift NIO channel's event loop.
    var eventLoop: EventLoop { get }

    /// The queue on which all callbacks are dispatched on. Must only be accessed after connection is started.
    var queue: DispatchQueue? { get }

    /// The logger used for this connection. Must be accessed on the
    /// callback dispatch queue.
    var logger: Logger? { get set }

    /// Starts the connection.
    ///
    /// - Parameters:
    ///     - queue: The queue to use for callbacks.
    func start(queue: DispatchQueue)

    /// Cancels the connection.
    func cancel()
}
