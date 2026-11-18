/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark

// The String accessors are built on the always-available `node.stringContent` projection, so they compile (and the assertions that use them run) on every deployment target. These live in the test target only - they are not part of the shipping API.
extension MarkdownNode {

    borrowing func literal() -> String? {
        switch stringContent {
        case .text(let s): return s
        case .codeBlock(_, let body): return body
        case .htmlBlock(let body): return body
        default: return nil
        }
    }

    borrowing func url() -> String? {
        if case .link(let url, _) = stringContent { return url }
        return nil
    }

    borrowing func title() -> String? {
        if case .link(_, let title) = stringContent { return title }
        return nil
    }

    borrowing func attributes() -> String? {
        if case .attribute(let a) = stringContent { return a }
        return nil
    }

    borrowing func codeBlockInfoString() -> String? {
        if case .codeBlock(let info, _) = stringContent { return info }
        return nil
    }

    borrowing func footnoteLabel() -> String? {
        if case .footnote(let label) = stringContent { return label }
        return nil
    }
}
