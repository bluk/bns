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

/// BNSStream types.
public enum BNSStream {
    /// A HTTP 1.x based stream
    case http1(BNSHTTP1Stream)
    /// A HTTP 2.x based stream
    case http2(BNSHTTP2Stream)
    /// A WebSocket based stream
    case webSocket(BNSWebSocketStream)

    /// The stream as a protocol type
    public var baseStream: BNSBaseStream {
        switch self {
        case let .http1(stream):
            return stream
        case let .http2(stream):
            return stream
        case let .webSocket(stream):
            return stream
        }
    }

    /// The stream as a HTTP protocol type
    public var httpStream: BNSHTTPStream? {
        switch self {
        case let .http1(stream):
            return stream
        case let .http2(stream):
            return stream
        case .webSocket:
            return nil
        }
    }
}

/// Handles a BNSStream.
public typealias BNSStreamHandler = (BNSStream) -> Void

/// BNSStream represents a streaming connection, usualy bidirectional.
public protocol BNSBaseStream: AnyObject {
    /// The current state of the instance. Must be accessed on the
    /// callback dispatch queue.
    var state: BNSStreamState { get }

    /// Handler for state changes.
    var stateUpdateHandler: ((BNSStreamState) -> Void)? { get set }

    /// The underlying Swift NIO channel.
    var channel: Channel { get }

    /// The underlying Swift NIO channel's event loop.
    var eventLoop: EventLoop { get }

    /// The queue on which all callbacks are dispatched on. Must only be accessed after stream is started.
    var queue: DispatchQueue? { get }

    /// The logger used for this stream. Must be accessed on the
    /// callback dispatch queue.
    var logger: Logger? { get set }

    /// Starts the stream.
    ///
    /// - Parameters:
    ///     - queue: The queue to use for callbacks.
    func start(queue: DispatchQueue)

    /// Cancels the stream.
    func cancel()
}
