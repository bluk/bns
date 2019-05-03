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

/// Declares State.
public extension BNSListener {
    /// The state of the listener
    enum State {
        /// The instance is created but not started.
        case setup
        /// The instance is started but not ready to process requests.
        case waiting
        /// The instance is able to process requests.
        case ready
        /// The instance has failed and may stop serving requests.
        case failed(Error)
        /// The instance has been stopped and will not process requests.
        case cancelled
    }

    internal struct InternalState {
        private var state: State = .setup

        // swiftlint:disable multiline_arguments

        @inlinable
        internal func assertStart(file: StaticString = #file, line: UInt = #line) {
            assert({ () -> Bool in
                switch self.state {
                case .setup:
                    return true
                case .waiting, .ready, .failed, .cancelled:
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
                case .waiting, .ready, .failed:
                    return false
                }
            }(), "deinit in an invalid state: \(self.state)", file: file, line: line)
        }

        // swiftlint:enable multiline_arguments

        // swiftlint:disable function_body_length cyclomatic_complexity

        internal mutating func transition(to newState: State, on listener: BNSListener) {
            switch state {
            case .setup:
                switch newState {
                case .setup:
                    preconditionFailure("Invalid transition from \(self.state) to \(newState)")
                case .waiting, .ready, .failed, .cancelled:
                    break
                }
            case .waiting:
                switch newState {
                case .setup, .waiting:
                    preconditionFailure("Invalid transition from \(self.state) to \(newState)")
                case .ready, .failed, .cancelled:
                    break
                }
            case .ready:
                switch newState {
                case .setup, .waiting, .ready:
                    preconditionFailure("Invalid transition from \(self.state) to \(newState)")
                case .failed, .cancelled:
                    break
                }
            case .failed:
                switch newState {
                case .setup:
                    preconditionFailure("Invalid transition from \(self.state) to \(newState)")
                case .waiting, .ready:
                    // Could have failed before the connection was ready, so do not perform transition.
                    return
                case .failed, .cancelled:
                    break
                }
            case .cancelled:
                switch newState {
                case .setup, .cancelled:
                    preconditionFailure("Invalid transition from \(self.state) to \(newState)")
                case .waiting, .ready:
                    // Could have cancelled after starting but before the connection was ready,
                    // so do not perform transition.
                    return
                case let .failed(error):
                    switch error {
                    case let listenerError as BNSListenerError:
                        switch listenerError {
                        case .invalidState, .invalidTLSConfig, .unsupportedProtocol:
                            assertionFailure("Invalid transition from \(self.state) to \(newState)")
                        }
                    default:
                        assertionFailure("Invalid transition from \(self.state) to \(newState)")
                    }
                    return
                }
            }

            self.state = newState
            listener.state = newState
            listener.stateUpdateHandler?(newState)
        }
    }

    // swiftlint:enable function_body_length cyclomatic_complexity
}
