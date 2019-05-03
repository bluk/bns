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
import Foundation

/// Traps a signal and performs an action.
public func trap(signal sig: Int32, handler: @escaping (Int32) -> Void) -> DispatchSourceSignal {
    let queue = DispatchQueue.global(qos: .userInitiated)
    let signalSource = DispatchSource.makeSignalSource(signal: sig, queue: queue)
    signal(sig, SIG_IGN)
    signalSource.setEventHandler(handler: {
        signalSource.cancel()
        handler(sig)
    })
    signalSource.resume()
    return signalSource
}
