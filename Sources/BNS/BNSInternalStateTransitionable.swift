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

internal protocol BNSInternalStateTransitionable {
    associatedtype StateSettable: BNSInternalStateSettable

    func assertStart(file: StaticString, line: UInt)
    func assertDeinit(file: StaticString, line: UInt)
    mutating func transition(to newState: BNSInternalState, on connection: StateSettable)
}

internal enum BNSInternalState {
    case setup
    case preparing
    case ready
    case failed(Error)
    case cancelled
}
