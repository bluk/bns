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

internal final class BNSHTTP1ConnectionTests: BNSConnectionsTests {
    func testStartThenCancel() throws {
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
        connection.shouldUpgradeToWebSocketHandler = { _, completion in
            completion(Result<HTTPHeaders, Error>.failure(BNSConnectionError.invalidState))
        }

        try start(connection: connection)

        XCTAssertNotNil(connection.queue)
        XCTAssertTrue(invokedInternalStartHandler)

        self.waitForCallbackFlush()
        XCTAssertFalse(didCloseChannel)

        try self.cancel(connection: connection)

        self.waitForCallbackFlush()
        XCTAssertTrue(didCloseChannel)

        XCTAssertNil(connection.internalStartHandler)
        XCTAssertNil(connection.newStreamHandler)
        XCTAssertNil(connection.shouldUpgradeToWebSocketHandler)
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
        connection.shouldUpgradeToWebSocketHandler = { _, completion in
            completion(Result<HTTPHeaders, Error>.failure(BNSConnectionError.invalidState))
        }

        try self.cancel(connection: connection)

        self.waitForCallbackFlush()
        XCTAssertTrue(didCloseChannel)
        XCTAssertFalse(invokedInternalStartHandler)
        XCTAssertNil(connection.queue)

        XCTAssertNil(connection.internalStartHandler)
        XCTAssertNil(connection.newStreamHandler)
        XCTAssertNil(connection.shouldUpgradeToWebSocketHandler)
    }

    // swiftlint:disable function_body_length

    func testStartThenConnectionUpgradedThenCancelled() throws {
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
        connection.shouldUpgradeToWebSocketHandler = { _, completion in
            completion(Result<HTTPHeaders, Error>.failure(BNSConnectionError.invalidState))
        }
        try start(connection: connection)

        XCTAssertNotNil(connection.queue)
        XCTAssertTrue(invokedInternalStartHandler)

        let webSocketConnection = BNSWebSocketConnection(
            channel: channel,
            internalStartHandler: { _ in },
            requestHead: HTTPRequestHead(
                version: HTTPVersion(major: 1, minor: 1),
                method: HTTPMethod.GET,
                uri: ""
            )
        )

        var sawFailedState = false
        let sawFailedExpectation = self.expectation(description: "Saw Failed State")

        queue.async {
            connection.stateUpdateHandler = { state in
                switch state {
                case .failed:
                    sawFailedState = true
                    sawFailedExpectation.fulfill()
                default:
                    XCTFail("Should not see any other state.")
                }
            }
        }

        queue.async {
            connection.connectionUpgraded(to: webSocketConnection)
        }

        self.wait(for: [sawFailedExpectation], timeout: 1)
        XCTAssertTrue(sawFailedState)
        guard case let .failed(error) = connection.state else {
            XCTFail("Unexpected state.")
            return
        }

        switch error {
        case let connectionError as BNSConnectionError:
            switch connectionError {
            case let .connectionUpgraded(connectionInUpgraded):
                switch connectionInUpgraded {
                case let .webSocket(newWebSocketConnection):
                    XCTAssertEqual(ObjectIdentifier(webSocketConnection), ObjectIdentifier(newWebSocketConnection))
                default:
                    XCTFail("Unexpected object in error: \(connectionInUpgraded)")
                }
            default:
                XCTFail("Unexpected error: \(error)")
            }
        default:
            XCTFail("Unexpected error: \(error)")
        }

        try self.cancel(connection: connection)

        self.waitForCallbackFlush()
        XCTAssertFalse(didCloseChannel)

        XCTAssertNil(connection.internalStartHandler)
        XCTAssertNil(connection.newStreamHandler)
        XCTAssertNil(connection.shouldUpgradeToWebSocketHandler)
    }

    // swiftlint:enable function_body_length
}
