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

private struct ReceiveHandler {
    let minimumIncompleteLength: Int
    let maximumLength: Int
    let completion: (Data?, BNSStreamContentContext?, Bool, Error?) -> Void
    let waitForComplete: Bool
}

internal protocol BNSReadableStream: BNSEventLoopProtectedPossiblyQueueable {
    associatedtype Stream: BNSInternalStateSettable where Stream.State == BNSStreamState

    var eventLoopProtectedState: BNSStreamInternalState<Stream> { get }
    var isCancelCalled: Bool { get set }
}

internal struct BNSHTTPReceiveBuffer<Stream: BNSReadableStream> {
    private var receiveHandlers: CircularBuffer<ReceiveHandler> = CircularBuffer<ReceiveHandler>(initialCapacity: 4)
    private var receiveBuffer: CircularBuffer<ByteBuffer> = CircularBuffer<ByteBuffer>(initialCapacity: 8)
    private var isComplete: Bool = false
    internal var totalByteCount = 0
    internal var currentByteOffset = 0

    internal mutating func receive(
        minimumIncompleteLength: Int,
        maximumLength: Int,
        completion: @escaping (Data?, BNSStreamContentContext?, Bool, Error?) -> Void,
        waitForComplete: Bool,
        on stream: Stream
    ) {
        stream.eventLoop.assertInEventLoop()

        guard !stream.isCancelCalled else {
            stream.withQueueIfPossible { completion(nil, nil, false, BNSStreamError.invalidState) }
            return
        }

        switch stream.eventLoopProtectedState.state {
        case .setup, .preparing, .ready:
            break
        case .failed, .cancelled:
            stream.withQueueIfPossible { completion(nil, nil, false, BNSStreamError.invalidState) }
            return
        }

        self.receiveHandlers.append(
            ReceiveHandler(
                minimumIncompleteLength: minimumIncompleteLength,
                maximumLength: maximumLength,
                completion: completion,
                waitForComplete: waitForComplete
            )
        )

        self.process(on: stream)
    }

    internal mutating func add(data: ByteBuffer?, isComplete: Bool, on stream: Stream) {
        stream.eventLoop.assertInEventLoop()

        assert(!self.isComplete, "Data being added even though it was supposedly completed.")
        if let data = data {
            totalByteCount += data.readableBytes
            self.receiveBuffer.append(data)
        }

        if isComplete {
            self.isComplete = true
        }

        self.process(on: stream)
    }

    internal mutating func process(on stream: Stream) {
        stream.eventLoop.assertInEventLoop()

        switch stream.eventLoopProtectedState.state {
        case .ready:
            break
        case .setup, .preparing, .failed, .cancelled:
            return
        }

        guard let queue = stream.queue else {
            preconditionFailure("Queue should not be nil.")
        }

        while let handler = self.receiveHandlers.first {
            guard totalByteCount > handler.minimumIncompleteLength || self.isComplete else {
                return
            }

            if handler.waitForComplete {
                guard self.isComplete else {
                    return
                }
            }

            var bytesLeftToRead = handler.maximumLength > 0
                ? min(handler.maximumLength, totalByteCount) : totalByteCount
            var data = Data()
            data.reserveCapacity(bytesLeftToRead)

            while bytesLeftToRead > 0,
                var byteBuffer = self.receiveBuffer.popFirst() {
                let lengthInByteBufferToRead = min(byteBuffer.readableBytes, bytesLeftToRead)
                guard let readBytes = byteBuffer.readBytes(length: lengthInByteBufferToRead) else {
                    preconditionFailure("Did not read the expected number of bytes in the buffer.")
                }
                data.append(contentsOf: readBytes)
                bytesLeftToRead -= lengthInByteBufferToRead
                if byteBuffer.readableBytes != 0 {
                    self.receiveBuffer.prepend(byteBuffer)
                }
            }

            assert(bytesLeftToRead == 0, "Did not read the expected number of bytes.")

            self.receiveHandlers.removeFirst()

            let isComplete = self.isComplete
            let isEmpty = self.receiveBuffer.isEmpty

            queue.async {
                handler.completion(data, nil, isComplete && isEmpty, nil)
            }
        }
    }

    internal mutating func cancel(on stream: Stream) {
        stream.eventLoop.assertInEventLoop()

        self.receiveBuffer.removeAll()

        self.receiveHandlers.forEach { receiveHandler in
            stream.withQueueIfPossible {
                receiveHandler.completion(nil, nil, false, BNSStreamError.invalidState)
            }
        }

        self.receiveHandlers.removeAll()
    }
}
