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

internal protocol BNSStartable: AnyObject {
    associatedtype InternalState: BNSInternalStateTransitionable

    var eventLoop: EventLoop { get }
    var eventLoopProtectedState: InternalState { get set }
    var isCancelCalled: Bool { get set }
    var queue: DispatchQueue? { get set }
    var tryReadyTransitionFromStart: () -> Void { get }
}

internal extension BNSStartable where Self: BNSEventLoopProtectedLoggable, InternalState.StateSettable == Self {
    func startStartable(queue: DispatchQueue) {
        guard self.eventLoop.inEventLoop else {
            self.eventLoop.execute { self.startStartable(queue: queue) }
            return
        }

        guard !self.isCancelCalled else {
            assertionFailure("Should not call start() after calling cancel().")
            return
        }

        // guard self.queue == nil else {
        //     assertionFailure("Should not call start() twice.")
        //     return
        // }
        self.queue = queue

        self.logTrace("start(queue:) called")

        self.eventLoopProtectedState.assertStart(file: #file, line: #line)

        self.eventLoopProtectedState.transition(to: .preparing, on: self)
        self.tryReadyTransitionFromStart()
    }
}
