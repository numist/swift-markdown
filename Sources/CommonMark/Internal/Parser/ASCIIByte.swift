/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// ASCII byte classes shared by the parsers, inlined because they sit in hot scanning loops.
extension UInt8 {
    @inline(__always)
    var isASCIILetter: Bool {
        (self >= UInt8(ascii: "a") && self <= UInt8(ascii: "z"))
            || (self >= UInt8(ascii: "A") && self <= UInt8(ascii: "Z"))
    }

    @inline(__always)
    var isUppercaseASCIILetter: Bool {
        self >= UInt8(ascii: "A") && self <= UInt8(ascii: "Z")
    }

    @inline(__always)
    var isASCIIDigit: Bool {
        self >= UInt8(ascii: "0") && self <= UInt8(ascii: "9")
    }

    @inline(__always)
    var isSpaceOrTab: Bool {
        self == UInt8(ascii: " ") || self == UInt8(ascii: "\t")
    }

    @inline(__always)
    var isSpaceTabOrNewline: Bool {
        self == UInt8(ascii: " ") || self == UInt8(ascii: "\t")
            || self == UInt8(ascii: "\n") || self == UInt8(ascii: "\r")
    }

    /// A whitespace character (Characters and lines) other than a line ending.
    @inline(__always)
    var isLineWhitespace: Bool {
        self == UInt8(ascii: " ") || self == UInt8(ascii: "\t")
            || self == 0x0B || self == 0x0C
    }

    /// A whitespace character (Characters and lines).
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

    /// An ASCII Unicode whitespace character (Characters and lines), for classifying a delimiter run as
    /// left- or right-flanking. Unlike a whitespace character, it excludes line tabulation. Callers classify
    /// multi-byte Unicode whitespace themselves.
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

    /// An ASCII punctuation character (Characters and lines).
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
