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
import NIO
import NIOWebSocket

private struct ReceiveHandler {
    let completion: (WebSocketFrame?, BNSStreamContentContext?, Bool, Error?) -> Void
}

internal struct BNSWebSocketReceiveBuffer {
    private var receiveHandlers: CircularBuffer<ReceiveHandler> = CircularBuffer<ReceiveHandler>(initialCapacity: 8)
    private var receiveBuffer: CircularBuffer<WebSocketFrame> = CircularBuffer<WebSocketFrame>(initialCapacity: 8)

    internal mutating func receive(
        completion: @escaping (WebSocketFrame?, BNSStreamContentContext?, Bool, Error?) -> Void,
        on stream: BNSWebSocketStream
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

        self.receiveHandlers.append(ReceiveHandler(completion: completion))

        self.process(on: stream)
    }

    internal mutating func add(frame: WebSocketFrame, on stream: BNSWebSocketStream) {
        stream.eventLoop.assertInEventLoop()

        self.receiveBuffer.append(frame)

        self.process(on: stream)
    }

    internal mutating func process(on stream: BNSWebSocketStream) {
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
            guard let frame = self.receiveBuffer.popFirst() else {
                return
            }
            self.receiveHandlers.removeFirst()

            queue.async { handler.completion(frame, nil, false, nil) }
        }
    }

    internal mutating func cancel(on stream: BNSWebSocketStream) {
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
