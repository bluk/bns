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

internal final class BNSWebSocketConnectionTests: BNSConnectionsTests {
    func testStartThenCancel() throws {
        var didCloseChannel = false
        channel.closeFuture.whenComplete { _ in
            didCloseChannel = true
        }

        var invokedInternalStartHandler = false
        let connection = BNSWebSocketConnection(
            channel: channel,
            internalStartHandler: { _ in
                invokedInternalStartHandler = true
            },
            requestHead: HTTPRequestHead(
                version: HTTPVersion(major: 1, minor: 1),
                method: HTTPMethod.GET,
                uri: ""
            )
        )
        connection.newStreamHandler = { _ in }

        try start(connection: connection)

        XCTAssertNotNil(connection.queue)
        XCTAssertTrue(invokedInternalStartHandler)

        XCTAssertFalse(didCloseChannel)

        try self.cancel(connection: connection)

        self.waitForCallbackFlush()
        XCTAssertTrue(didCloseChannel)

        XCTAssertNil(connection.internalStartHandler)
        XCTAssertNil(connection.newStreamHandler)
    }

    func testCancelImmediately() throws {
        var didCloseChannel = false
        channel.closeFuture.whenComplete { _ in
            didCloseChannel = true
        }

        var invokedInternalStartHandler = false
        let connection = BNSHTTP1Connection(
            channel: channel,
            internalStartHandler: {
                invokedInternalStartHandler = true
            }
        )
        connection.newStreamHandler = { _ in }

        try self.cancel(connection: connection)

        self.waitForCallbackFlush()
        XCTAssertTrue(didCloseChannel)
        XCTAssertFalse(invokedInternalStartHandler)
        XCTAssertNil(connection.queue)

        XCTAssertNil(connection.internalStartHandler)
        XCTAssertNil(connection.newStreamHandler)
        XCTAssertNil(connection.shouldUpgradeToWebSocketHandler)
    }
}
