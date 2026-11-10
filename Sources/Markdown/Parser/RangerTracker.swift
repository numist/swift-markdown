/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Collects the narrowest range that covers the source ranges added during parsing.
struct RangeTracker {
    /// The narrowest range that covers all ranges seen so far.
    private(set) var totalRange: SourceRange

    /// Create a range tracker with a starting total range.
    ///
    /// - parameter totalRange: the narrowest range that covers all ranges seen so far.
    init(totalRange: SourceRange) {
        self.totalRange = totalRange
    }

    /// Widen ``totalRange`` to cover `range`.
    ///
    /// - parameter range: An optional ``SourceRange``. This is `nil` for
    ///   elements that have no source range, such as soft and hard line breaks.
    mutating func add(_ range: SourceRange?) {
        if let range = range {
            totalRange.widen(toFit: range)
        }
    }
}
