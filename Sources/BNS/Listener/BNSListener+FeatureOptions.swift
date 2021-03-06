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

/// Declares FeatureOptions.
public extension BNSListener {
    /// The various features to enable for the BNSListener.
    struct FeatureOptions: OptionSet {
        public let rawValue: Int

        /// Initializer with the rawValue.
        ///
        /// - Parameters:
        ///     - rawValue: The raw value which the option represents.
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// If HTTP pipelining should be supported.
        public static let supportsPipelining = FeatureOptions(rawValue: 1 << 0)
        /// If HTTP content compression should be supported.
        public static let supportsCompression = FeatureOptions(rawValue: 1 << 1)
    }
}
