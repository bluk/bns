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

/// Context about the content being sent or received.
public class BNSStreamContentContext {
    /// If this is the final content in either direction.
    public let isFinal: Bool

    /// Designated initializer.
    public init(
        isFinal: Bool
    ) {
        self.isFinal = isFinal
    }

    /// The default message content context. The isFinal is set to false.
    public static let defaultMessage: BNSStreamContentContext = BNSStreamContentContext(isFinal: false)

    /// The final message content context. The isFinal is set to true.
    public static let finalMessage: BNSStreamContentContext = BNSStreamContentContext(isFinal: true)
}
