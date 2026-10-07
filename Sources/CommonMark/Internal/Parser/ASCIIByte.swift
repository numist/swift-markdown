/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Shared ASCII byte-classifier predicates on `UInt8`.
///
/// The parsers work over raw UTF-8 bytes, so these live on `UInt8` rather than any one parser type - `BlockParser`, the InlineParser extensions, and `EntityParser` all classify bytes and none should re-derive the ranges inline. They're `@inline(__always)` because they sit in the hot byte-scanning loops.
extension UInt8 {
    /// ASCII letter: `a`-`z` or `A`-`Z`.
    @inline(__always)
    var isASCIILetter: Bool {
        (self >= UInt8(ascii: "a") && self <= UInt8(ascii: "z"))
            || (self >= UInt8(ascii: "A") && self <= UInt8(ascii: "Z"))
    }

    /// Uppercase ASCII letter: `A`-`Z`.
    @inline(__always)
    var isUppercaseASCIILetter: Bool {
        self >= UInt8(ascii: "A") && self <= UInt8(ascii: "Z")
    }

    /// ASCII decimal digit: `0`-`9`.
    @inline(__always)
    var isASCIIDigit: Bool {
        self >= UInt8(ascii: "0") && self <= UInt8(ascii: "9")
    }

    /// Space or horizontal tab (ASCII "blank").
    @inline(__always)
    var isSpaceOrTab: Bool {
        self == UInt8(ascii: " ") || self == UInt8(ascii: "\t")
    }

    /// Space, horizontal tab, line feed, or carriage return.
    @inline(__always)
    var isSpaceTabOrNewline: Bool {
        self == UInt8(ascii: " ") || self == UInt8(ascii: "\t")
            || self == UInt8(ascii: "\n") || self == UInt8(ascii: "\r")
    }

    /// A whitespace character other than a line ending: space, tab, line tabulation (0x0B), or form
    /// feed (0x0C).
    ///
    /// It may pad a table delimiter row cell around `:?-+:?` (Tables (extension)) and must follow a task
    /// list item's checkbox (Task list items (extension)). Trimming of cell content and task list item
    /// content keeps line tabulation and form feed, so this predicate does not apply there.
    @inline(__always)
    var isExtensionScannerSpace: Bool {
        self == UInt8(ascii: " ") || self == UInt8(ascii: "\t")
            || self == 0x0B || self == 0x0C
    }

    /// A whitespace character (spec "Characters and lines"): space, tab, line feed, carriage return, line tabulation, or form feed.
    @inline(__always)
    var isASCIISpace: Bool {
        switch self {
        case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"),
             UInt8(ascii: "\r"), 0x0B, 0x0C:
            return true
        default:
            return false
        }
    }

    /// An ASCII Unicode whitespace character (spec "Characters and lines"): space, tab, line feed,
    /// carriage return, or form feed (0x0C).
    ///
    /// Classifies the characters bordering an emphasis, strikethrough or smart-quote delimiter run under
    /// the left- and right-flanking delimiter run definitions. Unlike a whitespace character, a Unicode
    /// whitespace character excludes line tabulation (0x0B), so `~<VT>~` flanks and pairs into a
    /// strikethrough while `~<FF>~` stays literal. Non-ASCII Unicode whitespace (the other `Zs` code
    /// points) is multi-byte and classified at the call site.
    @inline(__always)
    var isFlankingSpace: Bool {
        switch self {
        case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"),
             UInt8(ascii: "\r"), 0x0C:
            return true
        default:
            return false
        }
    }

    /// An ASCII punctuation character (spec "Characters and lines").
    @inline(__always)
    var isASCIIPunct: Bool {
        switch self {
        case UInt8(ascii: "!"), UInt8(ascii: "\""), UInt8(ascii: "#"),
             UInt8(ascii: "$"), UInt8(ascii: "%"), UInt8(ascii: "&"),
             UInt8(ascii: "'"), UInt8(ascii: "("), UInt8(ascii: ")"),
             UInt8(ascii: "*"), UInt8(ascii: "+"), UInt8(ascii: ","),
             UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "/"),
             UInt8(ascii: ":"), UInt8(ascii: ";"), UInt8(ascii: "<"),
             UInt8(ascii: "="), UInt8(ascii: ">"), UInt8(ascii: "?"),
             UInt8(ascii: "@"), UInt8(ascii: "["), UInt8(ascii: "\\"),
             UInt8(ascii: "]"), UInt8(ascii: "^"), UInt8(ascii: "_"),
             UInt8(ascii: "`"), UInt8(ascii: "{"), UInt8(ascii: "|"),
             UInt8(ascii: "}"), UInt8(ascii: "~"):
            return true
        default:
            return false
        }
    }
}
