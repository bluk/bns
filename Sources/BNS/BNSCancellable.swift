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

internal protocol BNSCancellable: AnyObject {
    associatedtype InternalState: BNSInternalStateTransitionable

    var channel: Channel { get }
    var eventLoop: EventLoop { get }
    var eventLoopProtectedState: InternalState { get set }
    var stateUpdateHandler: ((InternalState.StateSettable.State) -> Void)? { get set }
    var isCancelCalled: Bool { get set }
    var shouldCallClose: (() -> Bool)? { get }
    var afterCancelledCleanup: (() -> Void)? { get }
}

internal extension BNSCancellable where Self: BNSEventLoopProtectedLoggable, InternalState.StateSettable == Self {
    func cancelCancellable() {
        guard self.eventLoop.inEventLoop else {
            self.eventLoop.execute { self.cancelCancellable() }
            return
        }

        self.logTrace("cancel() called")

        guard !self.isCancelCalled else {
            self.logTrace("cancel() was already called")
            return
        }
        self.isCancelCalled = true

        let shouldClose: Bool
        if let shouldCallClose = shouldCallClose {
            shouldClose = shouldCallClose()
        } else {
            shouldClose = true
        }

        guard shouldClose else {
            self.channel.flush()
            self.eventLoopProtectedState.transition(to: .cancelled, on: self)
            self.withQueueIfPossible {
                self.stateUpdateHandler = nil
                self.afterCancelledCleanup?()
            }
            return
        }

        self.logTrace("Closing channel")

        self.channel.close().hop(to: self.eventLoop).whenComplete { _ in
            self.eventLoopProtectedState.transition(to: .cancelled, on: self)
            self.withQueueIfPossible {
                self.stateUpdateHandler = nil
                self.afterCancelledCleanup?()
            }
        }
    }
}
