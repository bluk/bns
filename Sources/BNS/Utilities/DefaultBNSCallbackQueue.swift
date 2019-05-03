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

/// The default callback queue which is used when an event occurs which requires a callback
/// and the connection, stream, or listener is not started. Most commonly, this is used
/// for logging events and transitioning to the cancelled state if an instance was not started with
/// a queue. It must be a serial queue. You should only set this queue
/// when there are no BNS objects which may issue a callback (e.g. at the beginning of your program).
public var BNSDefaultCallbackQueue: DispatchQueue = DispatchQueue(label: "BNSDefaultCallbackQueue")
