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

import XCTest

@testable import BNS
import NIO
import NIOHTTP1

internal class BNSConnectionsTests: XCTestCase {
    internal var channel: EmbeddedChannel!
    internal var queue: DispatchQueue!

    override func setUp() {
        super.setUp()

        channel = EmbeddedChannel()
        queue = DispatchQueue(label: "TestQueue")
        BNSDefaultCallbackQueue = queue
    }

    internal func waitForCallbackFlush() {
        channel.embeddedEventLoop.run()

        let group = DispatchGroup()
        group.enter()
        queue.async {
            group.leave()
        }
        group.wait()
    }

    internal func start(connection: BNSBaseConnection) throws {
        XCTAssertNil(connection.queue)
        var sawPreparingState = false
        var sawReadyState = false
        let sawReadyExpectation = self.expectation(description: "Saw Ready State")
        connection.stateUpdateHandler = { state in
            switch state {
            case .preparing:
                XCTAssertTrue(!sawReadyState && !sawPreparingState)
                sawPreparingState = true
            case .ready:
                XCTAssertTrue(!sawReadyState && sawPreparingState)
                sawReadyState = true
                sawReadyExpectation.fulfill()
            default:
                XCTFail("Should not see state: \(state)")
            }
        }
        connection.start(queue: queue)

        self.wait(for: [sawReadyExpectation], timeout: 1)

        XCTAssertTrue(sawPreparingState)
        XCTAssertTrue(sawReadyState)
        XCTAssertNotNil(connection.queue)

        guard case .ready = connection.state else {
            XCTFail("Unexpected state.")
            return
        }
    }

    func cancel(connection: BNSBaseConnection) throws {
        var sawCancelledState = false
        let sawCancelledExpectation = self.expectation(description: "Saw Cancelled State")

        queue.async {
            connection.stateUpdateHandler = { state in
                switch state {
                case .cancelled:
                    sawCancelledState = true
                    sawCancelledExpectation.fulfill()
                default:
                    XCTFail("Should not see any other state.")
                }
            }
        }

        self.waitForCallbackFlush()
        connection.cancel()

        self.wait(for: [sawCancelledExpectation], timeout: 1)

        guard case .cancelled = connection.state else {
            XCTFail("Unexpected state.")
            return
        }

        XCTAssertTrue(sawCancelledState)

        self.waitForCallbackFlush()
        XCTAssertNil(connection.stateUpdateHandler)
    }
}
