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
import NIO

private struct SendHandler<DataType> {
    let content: DataType?
    let contentContext: BNSStreamContentContext
    let isComplete: Bool
    let completion: BNSStreamSendCompletion
}

internal protocol BNSWritableStream: BNSEventLoopProtectedPossiblyQueueable {
    associatedtype StateSettable: BNSInternalStateSettable where StateSettable.State == BNSStreamState
    associatedtype BNSWritableStreamDataType
    associatedtype OutboundOut

    var channel: Channel { get }
    var eventLoopProtectedState: BNSStreamInternalState<StateSettable> { get }
    var isCancelCalled: Bool { get }

    func writeStarted()
    func write(content: BNSWritableStreamDataType?, shouldFlush: Bool) -> EventLoopFuture<Void>
    func wrapOutboundOut(_ content: BNSWritableStreamDataType) -> OutboundOut
    func writeFinished()
}

internal extension BNSWritableStream where Self: BNSEventLoopProtectedLoggable {
    func write(content: BNSWritableStreamDataType?, shouldFlush: Bool) -> EventLoopFuture<Void> {
        let promise: EventLoopPromise<Void> = self.channel.eventLoop.makePromise()
        guard self.eventLoop.inEventLoop else {
            self.eventLoop.execute {
                self.write(content: content, shouldFlush: shouldFlush).cascade(to: promise)
            }
            return promise.futureResult
        }

        guard let content = content else {
            if shouldFlush {
                self.logDebug("Flushing with no content")
                self.channel.flush()
            } else {
                assertionFailure("Write with no content and no intention to flush")
            }
            promise.succeed(())
            return promise.futureResult
        }

        if shouldFlush {
            self.logDebug("Writing and flushing: \(content)")
            self.channel.writeAndFlush(self.wrapOutboundOut(content))
                .cascade(to: promise)
        } else {
            self.logDebug("Writing: \(content)")
            self.channel.write(self.wrapOutboundOut(content)).cascade(to: promise)
        }

        return promise.futureResult
    }
}

internal struct BNSSendBuffer<Stream: BNSWritableStream & BNSEventLoopProtectedLoggable> {
    private var sendHandlers: CircularBuffer<SendHandler<Stream.BNSWritableStreamDataType>>
        = CircularBuffer<SendHandler<Stream.BNSWritableStreamDataType>>(initialCapacity: 4)
    private var hasWritten: Bool = false

    internal mutating func send(
        content: Stream.BNSWritableStreamDataType?,
        contentContext: BNSStreamContentContext,
        isComplete: Bool,
        completion: BNSStreamSendCompletion,
        on stream: Stream
    ) {
        stream.eventLoop.assertInEventLoop()

        guard !stream.isCancelCalled else {
            switch completion {
            case .idempotent:
                break
            case let .contentProcessed(callback):
                stream.withQueueIfPossible { callback(BNSStreamError.invalidState) }
            }
            return
        }

        switch stream.eventLoopProtectedState.state {
        case .ready:
            self.processHandler(
                content: content,
                contentContext: contentContext,
                isComplete: isComplete,
                completion: completion,
                stream: stream
            )
            return
        case .setup, .preparing:
            break
        case .failed, .cancelled:
            switch completion {
            case .idempotent:
                break
            case let .contentProcessed(callback):
                stream.withQueueIfPossible { callback(BNSStreamError.invalidState) }
            }
            return
        }

        self.sendHandlers.append(
            SendHandler(
                content: content,
                contentContext: contentContext,
                isComplete: isComplete,
                completion: completion
            )
        )

        self.process(on: stream)
    }

    internal mutating func process(on stream: Stream) {
        stream.eventLoop.assertInEventLoop()

        stream.logTrace("Processing send buffer")
        defer { stream.logTrace("Finished processing send buffer") }

        let completedContextHandlers = self.sendHandlers.filter { $0.isComplete }
        self.sendHandlers.removeAll(where: { $0.isComplete })

        for handler in completedContextHandlers {
            self.processHandler(
                content: handler.content,
                contentContext: handler.contentContext,
                isComplete: handler.isComplete,
                completion: handler.completion,
                stream: stream
            )
        }
    }

    internal mutating func processHandler(
        content: Stream.BNSWritableStreamDataType?,
        contentContext: BNSStreamContentContext,
        isComplete: Bool,
        completion: BNSStreamSendCompletion,
        stream: Stream
    ) {
        stream.eventLoop.assertInEventLoop()

        guard isComplete else {
            self.sendHandlers.append(
                SendHandler(
                    content: content,
                    contentContext: contentContext,
                    isComplete: isComplete,
                    completion: completion
                )
            )
            return
        }

        let currentContext = ObjectIdentifier(contentContext)

        let handlers = self.sendHandlers.filter { ObjectIdentifier($0.contentContext) == currentContext }

        for handler in handlers {
            writeHandler(
                content: handler.content,
                contentContext: handler.contentContext,
                isComplete: handler.isComplete,
                completion: handler.completion,
                stream: stream
            )
        }

        writeHandler(
            content: content,
            contentContext: contentContext,
            isComplete: isComplete,
            completion: completion,
            stream: stream
        )
        self.sendHandlers.removeAll(where: { ObjectIdentifier($0.contentContext) == currentContext })
    }

    internal mutating func writeHandler(
        content: Stream.BNSWritableStreamDataType?,
        contentContext: BNSStreamContentContext,
        isComplete: Bool,
        completion: BNSStreamSendCompletion,
        stream: Stream
    ) {
        stream.eventLoop.assertInEventLoop()

        guard let queue = stream.queue else {
            preconditionFailure("Queue should not be nil.")
        }

        if !self.hasWritten {
            stream.writeStarted()
            self.hasWritten = true
        }

        let writeFuture: EventLoopFuture<Void>
        if let content = content {
            writeFuture = stream.write(content: content, shouldFlush: isComplete && !contentContext.isFinal)
        } else if isComplete {
            writeFuture = stream.write(content: nil, shouldFlush: true)
        } else {
            assertionFailure("Invalid sendHandler. No content and it is not signaling the content is complete.")
            return
        }

        writeFuture.whenComplete { result in
            switch completion {
            case let .contentProcessed(completion):
                switch result {
                case .success:
                    queue.async { completion(nil) }
                case let .failure(error):
                    queue.async { completion(error) }
                }
            case .idempotent:
                break
            }
        }

        if isComplete, contentContext.isFinal {
            stream.writeFinished()
        }
    }

    internal mutating func cancel(on stream: Stream) {
        stream.eventLoop.assertInEventLoop()

        self.sendHandlers.forEach { handler in
            switch handler.completion {
            case let .contentProcessed(completion):
                stream.withQueueIfPossible { completion(BNSStreamError.invalidState) }
            case .idempotent:
                break
            }
        }

        self.sendHandlers.removeAll()
    }
}
