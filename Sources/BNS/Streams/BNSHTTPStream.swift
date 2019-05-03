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

import Foundation
import Logging
import NIO
import NIOHTTP1

/// BNSHTTPStream represents a HTTP request/response stream.
public protocol BNSHTTPStream: BNSBaseStream {
    /// The head of the request containing the request method, URI, and headers.
    var requestHead: HTTPRequestHead? { get }

    /// Any trailing headers in the request. Must be accessed on the callback queue.
    /// If there are any trailer headers, it is set before the receive completion's
    /// boolean isComplete is true.
    var requestTrailerHeaders: HTTPHeaders? { get }

    /// If the response head was written to the underlying network layer. Must be accessed on the callback queue.
    var wasResponseHeadWritten: Bool { get }

    /// The head of the response containing the response status code and headers. It must be set before
    /// the first completed message is sent.
    var responseHead: HTTPResponseHead? { get set }

    /// The response trailer headers. If there are any to send, they must be set before the message body's
    /// final message with isComplete is sent.
    var responseTrailerHeaders: HTTPHeaders? { get set }

    /// Receives a complete message. The completion handler is only called once.
    ///
    /// - Parameters:
    ///     - completion: The completion callback to use when data is received.
    func receiveMessage(completion: @escaping (Data?, BNSStreamContentContext?, Bool, Error?) -> Void)

    /// Recieves content. The completion handler is only called once.
    ///
    /// - Parameters:
    ///     - minimumIncompleteLength: The desired minimum length before the completion callback is invoked.
    ///     - maximumLength: The maximum amount of data to invoke the completion handler with.
    ///     - completion: The completion callback to use when data is received.
    func receive(
        minimumIncompleteLength: Int,
        maximumLength: Int,
        completion: @escaping (Data?, BNSStreamContentContext?, Bool, Error?) -> Void
    )

    /// Buffers data to send.
    ///
    /// - Parameters:
    ///     - content: The data to send.
    ///     - completion: The completion callback to use when data is sent.
    func send(
        content: Data,
        completion: BNSStreamSendCompletion
    )

    /// Buffers data to send.
    ///
    /// - Parameters:
    ///     - content: The data to send.
    ///     - completion: The completion callback to use when data is sent.
    func send(
        content: IOData,
        completion: BNSStreamSendCompletion
    )

    /// Buffers data to send.
    ///
    /// - Parameters:
    ///     - content: The data to send.
    ///     - contentContext: The context for the data being sent.
    ///     - isComplete: If the data being sent represents a complete message.
    ///     - completion: The completion callback to use when data is sent.
    func send(
        content: Data,
        contentContext: BNSStreamContentContext,
        isComplete: Bool,
        completion: BNSStreamSendCompletion
    )

    /// Buffers data to send.
    ///
    /// - Parameters:
    ///     - content: The data to send.
    ///     - contentContext: The context for the data being sent.
    ///     - isComplete: If the data being sent represents a complete message.
    ///     - completion: The completion callback to use when data is sent.
    func send(
        content: IOData?,
        contentContext: BNSStreamContentContext,
        isComplete: Bool,
        completion: BNSStreamSendCompletion
    )
}

/// Default definitions for BNSHTTPStream methods.
public extension BNSHTTPStream {
    /// Buffers data to send.
    ///
    /// - Parameters:
    ///     - content: The data to send.
    ///     - completion: The completion callback to use when data is sent.
    func send(content: Data, completion: BNSStreamSendCompletion) {
        self.send(
            content: content,
            contentContext: .defaultMessage,
            isComplete: true,
            completion: completion
        )
    }

    /// Buffers data to send.
    ///
    /// - Parameters:
    ///     - content: The data to send.
    ///     - completion: The completion callback to use when data is sent.
    func send(
        content: IOData,
        completion: BNSStreamSendCompletion
    ) {
        self.send(
            content: content,
            contentContext: .defaultMessage,
            isComplete: true,
            completion: completion
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
    func send(
        content: Data,
        contentContext: BNSStreamContentContext = .defaultMessage,
        isComplete: Bool = true,
        completion: BNSStreamSendCompletion
    ) {
        var byteBuffer = self.channel.allocator.buffer(capacity: content.count)
        byteBuffer.writeBytes(content)
        let ioData = IOData.byteBuffer(byteBuffer)

        self.send(
            content: ioData,
            contentContext: contentContext,
            isComplete: isComplete,
            completion: completion
        )
    }

    // swiftlint:enable function_default_parameter_at_end
}
