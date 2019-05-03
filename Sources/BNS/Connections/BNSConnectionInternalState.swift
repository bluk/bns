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

internal struct BNSConnectionInternalState<StateSettable: BNSInternalStateSettable>: BNSInternalStateTransitionable,
    CustomStringConvertible,
    CustomDebugStringConvertible
    where StateSettable.State == BNSConnectionState {
    internal var state: BNSInternalState = .setup

    // swiftlint:disable multiline_arguments

    @inlinable
    internal func assertStart(file: StaticString = #file, line: UInt = #line) {
        assert({ () -> Bool in
            switch self.state {
            case .setup:
                return true
            case .preparing, .ready, .failed, .cancelled:
                return false
            }
        }(), "start() called from an invalid state: \(self.state)", file: file, line: line)
    }

    @inlinable
    internal func assertDeinit(file: StaticString = #file, line: UInt = #line) {
        assert({ () -> Bool in
            switch self.state {
            case .cancelled, .setup:
                return true
            case .preparing, .ready, .failed:
                return false
            }
        }(), "deinit in an invalid state: \(self.state)", file: file, line: line)
    }

    // swiftlint:enable multiline_arguments

    // swiftlint:disable function_body_length cyclomatic_complexity

    internal mutating func transition(to newState: BNSInternalState, on connection: StateSettable) {
        connection.eventLoop.assertInEventLoop()

        switch state {
        case .setup:
            switch newState {
            case .setup:
                preconditionFailure("Invalid transition from \(self.state) to \(newState)")
            case .preparing, .ready, .failed, .cancelled:
                break
            }
        case .preparing:
            switch newState {
            case .setup, .preparing:
                preconditionFailure("Invalid transition from \(self.state) to \(newState)")
            case .ready, .failed, .cancelled:
                break
            }
        case .ready:
            switch newState {
            case .setup, .preparing, .ready:
                preconditionFailure("Invalid transition from \(self.state) to \(newState)")
            case .failed, .cancelled:
                break
            }
        case .failed:
            switch newState {
            case .setup:
                preconditionFailure("Invalid transition from \(self.state) to \(newState)")
            case .preparing, .ready:
                // Could have failed before the connection was ready, so do not perform transition.
                return
            case .failed, .cancelled:
                break
            }
        case .cancelled:
            switch newState {
            case .setup, .cancelled:
                preconditionFailure("Invalid transition from \(self.state) to \(newState)")
            case .preparing, .ready:
                // Could have cancelled after starting but before the connection was ready,
                // so do not perform transition.
                return
            case let .failed(error):
                switch error {
                case let connectionError as BNSConnectionError:
                    switch connectionError {
                    case .connectionReset:
                        return
                    case .idleTimeout:
                        return
                    case .connectionUpgraded:
                        assertionFailure("Invalid transition from \(self.state) to \(newState)")
                    case .invalidState:
                        assertionFailure("Invalid transition from \(self.state) to \(newState)")
                    }
                case is IOError:
                    return
                default:
                    assertionFailure("Invalid transition from \(self.state) to \(newState)")
                }
                return
            }
        }

        self.state = newState

        let updateHandler = connection.eventLoopProtectedStateUpdateHandler

        connection.withQueueIfPossible {
            let connectionState: BNSConnectionState
            switch newState {
            case .setup:
                connectionState = BNSConnectionState.setup
            case .preparing:
                connectionState = BNSConnectionState.preparing
            case .ready:
                connectionState = BNSConnectionState.ready
            case let .failed(error):
                connectionState = BNSConnectionState.failed(error)
            case .cancelled:
                connectionState = BNSConnectionState.cancelled
            }
            connection.state = connectionState
            updateHandler?(connectionState)
        }
    }

    // swiftlint:enable function_body_length cyclomatic_complexity

    var description: String {
        return "\(self.state)"
    }

    var debugDescription: String {
        return "BNSConnectionInternalState(\(self.state))"
    }
}
