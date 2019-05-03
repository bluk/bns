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

internal protocol BNSChannelHandlerTriggerUserOutboundEventLoggable: ChannelOutboundHandler {}

internal extension BNSChannelHandlerTriggerUserOutboundEventLoggable
    where Self: BNSWithLoggableInstanceChannelHandlerLoggable {
    func triggerUserOutboundEvent(
        context: ChannelHandlerContext,
        event: Any,
        promise: EventLoopPromise<Void>?
    ) {
        self.logDebug("triggerUserOutboundEvent(): \(event)")
        context.triggerUserOutboundEvent(event, promise: promise)
    }
}

internal extension BNSChannelHandlerTriggerUserOutboundEventLoggable
    where Self: BNSOnlyLoggerChannelHandlerLoggable & BNSOnlyQueuePossiblyQueueable {
    func triggerUserOutboundEvent(
        context: ChannelHandlerContext,
        event: Any,
        promise: EventLoopPromise<Void>?
    ) {
        self.logDebug("triggerUserOutboundEvent(): \(event)")
        context.triggerUserOutboundEvent(event, promise: promise)
    }
}
