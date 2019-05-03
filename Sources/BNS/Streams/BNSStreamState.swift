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

/// The state of the stream.
public enum BNSStreamState {
    /// Initial state prior to start
    case setup
    /// When the stream is being established
    case preparing
    /// When the stream is able to send and receive data
    case ready
    /// When an error occurred
    case failed(Error)
    /// When the stream is invalidated
    case cancelled

    // swiftlint:disable cyclomatic_complexity

    internal func transition(to newState: BNSStreamState) -> BNSStreamState {
        switch self {
        case .setup:
            switch newState {
            case .setup:
                assertionFailure("Invalid transition from \(self) to \(newState)")
            case .preparing, .ready, .failed, .cancelled:
                return newState
            }
        case .preparing:
            switch newState {
            case .setup, .preparing:
                assertionFailure("Invalid transition from \(self) to \(newState)")
            case .ready, .failed, .cancelled:
                return newState
            }
        case .ready:
            switch newState {
            case .setup, .preparing, .ready:
                assertionFailure("Invalid transition from \(self) to \(newState)")
            case .failed, .cancelled:
                return newState
            }
        case .failed:
            switch newState {
            case .setup, .preparing, .ready:
                assertionFailure("Invalid transition from \(self) to \(newState)")
            case .failed, .cancelled:
                return newState
            }
        case .cancelled:
            assertionFailure("Invalid transition from \(self) to \(newState)")
        }

        return self
    }

    // swiftlint:enable cyclomatic_complexity
}
