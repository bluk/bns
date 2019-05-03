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

import NIO
import XCTest

@testable import BNS

internal class BNSConnectionInternalStateTests: XCTestCase {
    var connection: BNSHTTP1Connection!

    override func setUp() {
        super.setUp()
        connection = BNSHTTP1Connection(
            channel: EmbeddedChannel(),
            internalStartHandler: {}
        )
    }

    func testNormalTransition() {
        var internalState = BNSConnectionInternalState<BNSHTTP1Connection>()

        guard case .setup = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }

        internalState.transition(to: .preparing, on: connection)

        guard case .preparing = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }

        internalState.transition(to: .ready, on: connection)

        guard case .ready = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }

        internalState.transition(to: .cancelled, on: connection)

        guard case .cancelled = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }
    }

    func testImmediateCancelled() {
        var internalState = BNSConnectionInternalState<BNSHTTP1Connection>()

        guard case .setup = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }

        internalState.transition(to: .cancelled, on: connection)

        guard case .cancelled = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }
    }

    func testImmediateFailed() {
        var internalState = BNSConnectionInternalState<BNSHTTP1Connection>()

        guard case .setup = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }

        internalState.transition(to: .failed(BNSConnectionError.invalidState), on: connection)

        guard case .failed = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }
    }

    // swiftlint:disable cyclomatic_complexity

    func testMultipleFailureTransitions() {
        var internalState = BNSConnectionInternalState<BNSHTTP1Connection>()

        guard case .setup = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }

        internalState.transition(to: .failed(BNSConnectionError.invalidState), on: connection)

        guard case let .failed(firstError) = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }

        switch firstError {
        case let connectionError as BNSConnectionError:
            switch connectionError {
            case .invalidState:
                break
            default:
                XCTFail("Incorrect error: \(firstError)")
            }
        default:
            XCTFail("Incorrect error: \(firstError)")
        }

        internalState.transition(to: .failed(BNSConnectionError.connectionReset), on: connection)

        guard case let .failed(secondError) = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }

        switch secondError {
        case let connectionError as BNSConnectionError:
            switch connectionError {
            case .connectionReset:
                break
            default:
                XCTFail("Incorrect error: \(secondError)")
            }
        default:
            XCTFail("Incorrect error: \(secondError)")
        }
    }

    // swiftlint:enable cyclomatic_complexity

    func testConnectionResetAfterCancelled() {
        var internalState = BNSConnectionInternalState<BNSHTTP1Connection>()

        guard case .setup = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }

        internalState.transition(to: .cancelled, on: connection)

        guard case .cancelled = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }

        internalState.transition(to: .failed(BNSConnectionError.connectionReset), on: connection)

        guard case .cancelled = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }
    }

    func testIdleTimeoutAfterCancelled() {
        var internalState = BNSConnectionInternalState<BNSHTTP1Connection>()

        guard case .setup = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }

        internalState.transition(to: .cancelled, on: connection)

        guard case .cancelled = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }

        internalState.transition(to: .failed(BNSConnectionError.idleTimeout), on: connection)

        guard case .cancelled = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }
    }

    func testIOErrorAfterCancelled() {
        var internalState = BNSConnectionInternalState<BNSHTTP1Connection>()

        guard case .setup = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }

        internalState.transition(to: .cancelled, on: connection)

        guard case .cancelled = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }

        internalState.transition(to: .failed(IOError(errnoCode: 1, reason: "Test")), on: connection)

        guard case .cancelled = internalState.state else {
            XCTFail("Incorrect state: \(internalState)")
            return
        }
    }
}
