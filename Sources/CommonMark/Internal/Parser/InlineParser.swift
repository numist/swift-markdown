/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

internal import BasicContainers

// `SIMD32` stands in for `InlineArray`, which requires the anyAppleOS 26 runtime.
internal struct OpenersBottom {
    private var storage: SIMD32<Int>

    internal init(fill: Int) {
        storage = SIMD32(repeating: fill)
    }

    internal subscript(_ row: Int, _ col: Int) -> Int {
        get { storage[row * 5 + col] }
        set { storage[row * 5 + col] = newValue }
    }
}

// Rescanning to the content end for every unclosed opener would make a paragraph of unclosed raw HTML quadratic.
internal struct HTMLCloserMisses {
    var comment: Range<Int> = 0..<0
    var cdata: Range<Int> = 0..<0
    var declaration: Range<Int> = 0..<0
    var processingInstruction: Range<Int> = 0..<0
}

// A scan from a run's end splits the content into the same runs as any other, so once a scan has reached the end from
// `scannedToEndFrom`, an opener ending at or past it has a closer exactly when a run of its length starts at or past its
// end.
internal struct BacktickRunsSeen {
    var scannedToEndFrom: Int?
    var latestStart = [Int: Int]()

    func rulesOutCloser(length: Int, after openEnd: Int) -> Bool {
        guard let scannedToEndFrom, scannedToEndFrom <= openEnd else {
            return false
        }
        return latestStart[length, default: -1] < openEnd
    }

    mutating func recordRun(length: Int, start: Int) {
        latestStart[length] = max(latestStart[length, default: -1], start)
    }
}

/// Inline-level Markdown parsing functions.
extension BlockParser {

    /// Parse the inline content of `parent`.
    ///
    /// On exit, `parent` has zero or more inline child nodes attached. Returns without emitting any child if `content` is empty.
    mutating func parseInline(
        content: borrowing ContentSpan,
        into parent: DocumentStorage.Index,
        preserveWhitespace: Bool = false
    ) {
        if content.isEmpty {
            return
        }
        // The delimiter and bracket stacks are scratch buffers, reused across every paragraph in the document. Reset them to empty rather than allocating per call.
        delimiters.removeSubrange(0..<delimiters.count)
        brackets.removeSubrange(0..<brackets.count)
        
        var cursor = content.startOffset
        let endOffset = content.endOffset
        var pendingTextStart = cursor
        lastDelim = nil
        lastBracket = nil
        linksFormed = 0

        // Hoisted once for the plain-text skip in the `default` case below.
        let strikethroughEnabled = storage.options.contains(.strikethrough)
        let gfmAutolinkEnabled = storage.options.contains(.gfmAutolink)
        let smartEnabled = storage.options.contains(.smart)

        htmlCloserMisses = HTMLCloserMisses()
        destinationParentheses.reset()
        attributeParentheses.reset()
        // Runs are recorded only once a scan has reached the content end.
        if backtickRunsSeen.scannedToEndFrom != nil {
            backtickRunsSeen = BacktickRunsSeen()
        }
        characterReferenceSources.removeAll(keepingCapacity: true)

        while cursor < endOffset {
            let byte = content[cursor]
            switch byte {
            case UInt8(ascii: "`"):
                cursor = handleBackticks(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "\n"):
                cursor = handleLineEnding(at: cursor, preserveWhitespace: preserveWhitespace, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "&"):
                cursor = handleCharacterReference(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "<"):
                cursor = handleAngleBracket(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "*"), UInt8(ascii: "_"):
                cursor = handleDelimRun(
                    char: byte,
                    start: cursor,
                    content: content,
                    parent: parent,
                    pendingTextStart: &pendingTextStart
                )

            case UInt8(ascii: "~"):
                if strikethroughEnabled {
                    cursor = handleDelimRun(
                        char: byte,
                        start: cursor,
                        content: content,
                        parent: parent,
                        pendingTextStart: &pendingTextStart
                    )
                } else {
                    cursor += 1
                }
                
            case UInt8(ascii: "["):
                cursor = openBracket(
                    .link,
                    length: 1,
                    at: cursor,
                    to: parent,
                    pendingTextStart: &pendingTextStart,
                    content: content
                )

            case UInt8(ascii: "!"):
                cursor = handleExclamationMark(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "^"):
                cursor = handleCaret(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "]"):
                flushPendingText(
                    start: pendingTextStart,
                    end: cursor,
                    content: content,
                    into: parent
                )
                cursor = handleCloseBracket(
                    cursor: cursor,
                    content: content,
                    parent: parent
                )
                pendingTextStart = cursor

            case UInt8(ascii: "\\"):
                cursor = handleBackslash(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: ":"), UInt8(ascii: "w"):
                cursor = handleGFMAutolinkTrigger(byte, at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "'"), UInt8(ascii: "\""):
                // Smart quotes: push a quote delimiter (resolved to curly open/close in `processEmphasis`). Without `.smart`, the byte is ordinary text.
                if smartEnabled {
                    cursor = handleQuoteDelim(
                        char: byte,
                        start: cursor,
                        content: content,
                        parent: parent,
                        pendingTextStart: &pendingTextStart
                    )
                } else {
                    cursor += 1
                }

            case UInt8(ascii: "-"):
                // Smart dashes: a run of 2+ hyphens becomes en/em dashes. A lone `-` is left in the pending-text region (identical text, fewer nodes).
                if smartEnabled {
                    cursor = handleSmartHyphen(
                        start: cursor,
                        content: content,
                        parent: parent,
                        pendingTextStart: &pendingTextStart
                    )
                } else {
                    cursor += 1
                }

            case UInt8(ascii: "."):
                // Smart ellipsis: exactly `...` becomes a single ellipsis. Other runs of dots stay in the pending-text region.
                if smartEnabled {
                    cursor = handleEllipsis(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)
                } else {
                    cursor += 1
                }

            default:
                // Plain text: SIMD-skip to the next inline-significant byte instead of stepping one byte at a time. The skipped run stays pending and is flushed when that byte emits.
                cursor = content.nextSignificant(
                    from: cursor,
                    strikethrough: strikethroughEnabled,
                    gfmAutolink: gfmAutolinkEnabled,
                    smart: smartEnabled
                )
            }
        }
        flushPendingText(
            start: pendingTextStart,
            end: endOffset,
            content: content,
            into: parent
        )
        processEmphasis(
            stackBottom: -1,
            content: content
        )
    }

    private mutating func handleBackticks(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        if let span = matchCodeSpan(
            start: cursor,
            content: content
        ) {
            emitLiteral(
                .codeInline(backtickCount: span.backtickCount),
                span.content,
                start: cursor,
                end: span.afterClose,
                to: parent,
                pendingTextStart: &pendingTextStart,
                content: content
            )
            return span.afterClose
        }
        // No matching close - skip past the run; the backticks become part of the pending text region.
        return scanBacktickRun(
            start: cursor,
            content: content
        )
    }

    private mutating func handleLineEnding(at cursor: Int, preserveWhitespace: Bool, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        let info: LineBreakInfo
        if preserveWhitespace {
            guard cursor > pendingTextStart, content[cursor - 1] == UInt8(ascii: "\\") else {
                return cursor + 1
            }
            info = LineBreakInfo(isHard: true, textEnd: cursor - 1)
        } else {
            info = classifyLineBreak(
                at: cursor,
                pendingTextStart: pendingTextStart,
                content: content
            )
        }
        return appendLineBreak(isHard: info.isHard, textEnd: info.textEnd, resumingAt: cursor + 1, content: content, parent: parent, pendingTextStart: &pendingTextStart)
    }

    private mutating func appendLineBreak(isHard: Bool, textEnd: Int, resumingAt resume: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        flushPendingText(
            start: pendingTextStart,
            end: textEnd,
            content: content,
            into: parent
        )
        let kind: MarkdownNode.Kind = isHard ? .lineBreak : .softBreak
        let breakIdx = storage.appendNode(NodeRecord(kind: kind, parent: parent))
        storage.appendChild(breakIdx, to: parent)
        pendingTextStart = resume
        return resume
    }

    private mutating func handleCharacterReference(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        // Entity matching reads one buffer, so it scans `&`'s segment; a line join ends any reference anyway.
        guard let window = content.contiguousChunk(fromVirtual: cursor, limit: content.endOffset) else {
            preconditionFailure("an `&` is never a line join, the only byte without a contiguous chunk")
        }
        guard let entity = characterReference(at: window.offset, in: window) else {
            return cursor + 1
        }
        let decoded = Self.appendUTF8Bytes(
            bytes: entity.bytes,
            count: entity.count,
            into: &storage.strings
        )
        let afterSemi = cursor + (entity.afterSemi - window.offset)
        let textIdx = emitLiteral(
            .text,
            decoded,
            start: cursor,
            end: afterSemi,
            to: parent,
            pendingTextStart: &pendingTextStart,
            content: content
        )
        if positionsEnabled {
            let source = storage.sourceRanges[textIdx]
            characterReferenceSources.append((decoded.range, source.start..<source.end))
        }
        return afterSemi
    }

    private mutating func handleAngleBracket(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        if let auto = matchAutolink(
            start: cursor,
            content: content
        ) {
            flushPendingText(
                start: pendingTextStart,
                end: cursor,
                content: content,
                into: parent
            )
            emitAutolink(
                auto: auto,
                into: parent,
                content: content
            )
            linksFormed += 1
            pendingTextStart = auto.afterClose
            return auto.afterClose
        }
        if let htmlEnd = matchInlineHTML(
            start: cursor,
            content: content
        ) {
            emitLiteral(
                .htmlInline,
                materializedChunk(start: cursor, end: htmlEnd, content: content),
                start: cursor,
                end: htmlEnd,
                to: parent,
                pendingTextStart: &pendingTextStart,
                content: content
            )
            return htmlEnd
        }
        return cursor + 1
    }

    private mutating func handleExclamationMark(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        if cursor + 1 < content.endOffset,
           content[cursor + 1] == UInt8(ascii: "[") {
            return openBracket(
                .image,
                length: 2,
                at: cursor,
                to: parent,
                pendingTextStart: &pendingTextStart,
                content: content
            )
        }
        return cursor + 1
    }

    private mutating func handleCaret(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        if storage.options.contains(.attributes),
           cursor + 1 < content.endOffset,
           content[cursor + 1] == UInt8(ascii: "[") {
            return openBracket(
                .attribute,
                length: 2,
                at: cursor,
                to: parent,
                pendingTextStart: &pendingTextStart,
                content: content
            )
        }
        return cursor + 1
    }

    private mutating func handleBackslash(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        // Backslash escape: `\<ASCII punct>` emits the punct as a single-byte text node.
        if cursor + 1 < content.endOffset {
            let next = content[cursor + 1]
            if next.isASCIIPunct {
                emitLiteral(
                    .text,
                    content.chunk(offset: cursor + 1, length: 1),
                    start: cursor,
                    end: cursor + 2,
                    to: parent,
                    pendingTextStart: &pendingTextStart,
                    content: content
                )
                return cursor + 2
            }
            // An LF forms a backslash's hard line break in `handleLineEnding`; a CR, which only inline-only content
            // parsed in place holds, forms it here, with a CRLF's LF.
            if next == UInt8(ascii: "\r"), let afterLineEnding = lineEndingEnd(at: cursor + 1, in: content) {
                return appendLineBreak(isHard: true, textEnd: cursor, resumingAt: afterLineEnding, content: content, parent: parent, pendingTextStart: &pendingTextStart)
            }
        }
        return cursor + 1
    }

    private mutating func handleGFMAutolinkTrigger(_ byte: UInt8, at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        // An open `[` or `![` suppresses the autolink even if it never closes, so `[a http://t.t` is text.
        let insideLinkOrImageBracket = lastBracket.map { brackets[$0].insideLinkOrImage } ?? false
        if storage.options.contains(.gfmAutolink),
           !insideLinkOrImageBracket,
           let auto = matchGFMAutolink(
            trigger: byte,
            cursor: cursor,
            content: content
           ) {
            flushPendingText(
                start: pendingTextStart,
                end: auto.urlStart,
                content: content,
                into: parent
            )
            emitGFMAutolink(
                auto: auto,
                into: parent,
                content: content
            )
            pendingTextStart = auto.urlEnd
            return auto.urlEnd
        }
        return cursor + 1
    }

    private mutating func handleEllipsis(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        guard cursor + 2 < content.endOffset,
              content[cursor + 1] == UInt8(ascii: "."),
              content[cursor + 2] == UInt8(ascii: ".") else {
            return cursor + 1
        }
        emitLiteral(
            .text,
            smartConstantChunk(Self.ellipsis),
            start: cursor,
            end: cursor + 3,
            to: parent,
            pendingTextStart: &pendingTextStart,
            content: content
        )
        return cursor + 3
    }

    // MARK: - Links / images (bracket stack)

    /// Bracket-stack opener kind.
    internal enum BracketKind {
        case link
        case image
        case attribute

        var nodeKind: MarkdownNode.Kind {
            switch self {
            case .link: .link
            case .image: .image
            case .attribute: .attribute
            }
        }
    }

    /// Bracket-stack entry recording an open `[` (LINK), `![` (IMAGE), or `^[` (ATTRIBUTE - extended-attribute syntax).
    internal struct BracketRecord {
        var kind: BracketKind
        var inlText: DocumentStorage.Index
        // The opener text node's range is in source offsets, so stamping the wrapper from it would map twice.
        var virtualStart: Int
        /// Delimiter-stack index at time of push. Passed to `processEmphasis` as `stackBottom` after a successful link match so emphasis inside the link text gets resolved without leaking out.
        var delimPosition: Int
        /// `true` once any later bracket has been pushed on top of this one. Used to disqualify the shortcut-reference form for outer brackets that contain nested ones.
        var bracketAfter: Bool = false
        var insideLinkOrImage: Bool
        // A link opener can't form a link once a link or autolink formed after it, because links may not contain
        // other links (Links).
        var linksFormedBefore: Int
        var previous: Int?
    }

    private mutating func openBracket(_ kind: BracketKind, length: Int, at cursor: Int, to parent: DocumentStorage.Index, pendingTextStart: inout Int, content: borrowing ContentSpan) -> Int {
        let textIdx = emitLiteral(.text, content.chunk(offset: cursor, length: length), start: cursor, end: cursor + length, to: parent, pendingTextStart: &pendingTextStart, content: content)
        pushBracket(kind: kind, inlText: textIdx, virtualStart: cursor, delimPosition: lastDelim ?? -1)
        return cursor + length
    }

    private mutating func pushBracket(kind: BracketKind, inlText: DocumentStorage.Index, virtualStart: Int, delimPosition: Int) {
        if let lastBracket {
            brackets[lastBracket].bracketAfter = true
        }
        let prev = lastBracket
        let newIdx = brackets.count
        let insideLinkOrImage = (prev.map { brackets[$0].insideLinkOrImage } ?? false)
            || kind == .link || kind == .image
        brackets.append(BracketRecord(
            kind: kind,
            inlText: inlText,
            virtualStart: virtualStart,
            delimPosition: delimPosition,
            insideLinkOrImage: insideLinkOrImage,
            linksFormedBefore: linksFormed,
            previous: prev
        ))
        lastBracket = newIdx
    }

    private mutating func popBracket() {
        if let last = lastBracket {
            lastBracket = brackets[last].previous
        }
    }
    
    /// Process a `]` while the parent's child list contains any text/inline nodes that were emitted after the matching `[`. Returns the new cursor position.
    private mutating func handleCloseBracket(cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index) -> Int {
        let afterBracket = cursor + 1
        // No bracket open: emit `]` literal and return.
        guard let openerIdx = lastBracket else {
            emitBracketLiteral(at: cursor, end: afterBracket, content: content, parent: parent)
            return afterBracket
        }
        let openerKind = brackets[openerIdx].kind
        let openerInl = brackets[openerIdx].inlText
        let openerDelimPos = brackets[openerIdx].delimPosition
        let openerStart = brackets[openerIdx].virtualStart
        // Inactive link opener: just pop and emit `]`.
        if openerKind == .link, brackets[openerIdx].linksFormedBefore < linksFormed {
            popBracket()
            emitBracketLiteral(at: cursor, end: afterBracket, content: content, parent: parent)
            return afterBracket
        }
        let formed: (data: NodeData, end: Int)?
        let literalEnd: Int
        if openerKind == .attribute {
            let attribute = matchAttributeForm(cursor: cursor, content: content)
            formed = attribute.data.map { ($0, attribute.end) }
            literalEnd = attribute.end
        } else if let inline = matchInlineLinkForm(cursor: cursor, content: content) {
            formed = inline
            literalEnd = afterBracket
        } else if let reference = matchReferenceLinkForm(bracketTextStart: brackets[openerIdx].bracketAfter ? nil : openerStart + (openerKind == .image ? 2 : 1), cursor: cursor, content: content) {
            formed = (.link(url: storage.intern(reference.definition.destination), title: storage.intern(reference.definition.title)), reference.end)
            literalEnd = afterBracket
        } else {
            formed = nil
            literalEnd = afterBracket
        }
        if let formed {
            wrapBracketContent(openerKind.nodeKind, formed.data, openerInl: openerInl, delimPosition: openerDelimPos, start: openerStart, end: formed.end, content: content)
            popBracket()
            if openerKind == .link {
                linksFormed += 1
            }
            return formed.end
        }
        if openerKind != .attribute, emitFootnoteReferenceIfDefined(openerIdx: openerIdx, bracketStart: openerKind == .image ? openerStart + 1 : openerStart, closeBracket: cursor, content: content) {
            return afterBracket
        }
        popBracket()
        emitBracketLiteral(at: cursor, end: literalEnd, content: content, parent: parent)
        return literalEnd
    }

    @inline(__always)
    private mutating func matchInlineLinkForm(cursor: Int, content: borrowing ContentSpan) -> (data: NodeData, end: Int)? {
        let pos = cursor + 1
        // Try inline link: `(url "title")`.
        guard pos < content.endOffset, content[pos] == UInt8(ascii: "("),
              let inline = matchInlineLinkTail(afterParen: pos + 1, content: content) else {
            return nil
        }
        return (.link(url: storage.intern(inline.url), title: storage.intern(inline.title)), inline.end)
    }

    @inline(__always)
    private mutating func matchReferenceLinkForm(bracketTextStart: Int?, cursor: Int, content: borrowing ContentSpan) -> (definition: ReferenceDefinition, end: Int)? {
        let pos = cursor + 1
        // Try reference link forms: full `[label]`, collapsed `[]`, or shortcut.
        if storage.referenceMap.isEmpty {
            return nil
        }
        var key = NormalizedLabel.empty
        var afterReference = pos
        if let label = matchLabelKey(from: pos, content: content) {
            key = label.key
            // A whitespace-only `[ ]` is neither a link label nor `[]` (Links), so after a shortcut
            // reference it stays text.
            if !key.isEmpty || label.afterEnd == pos + 2 {
                afterReference = label.afterEnd
            }
        }
        // Collapsed `[]` or absent - fall back to shortcut form (the bracket text itself becomes the label) when no inner brackets were nested under this opener.
        if key.isEmpty, let textStart = bracketTextStart {
            if cursor > textStart, labelFits(linkLabelLimit, virtualRange: textStart..<cursor, in: content) {
                key = normalizeLabel(virtualRange: textStart..<cursor, in: content)
            }
        }
        guard !key.isEmpty, let definition = storage.referenceMap[key] else {
            return nil
        }
        let expansion = definition.destination.length + definition.title.length
        guard expansion <= referenceExpansionRemaining else {
            return nil
        }
        referenceExpansionRemaining -= expansion
        return (definition, afterReference)
    }

    @inline(__always)
    private mutating func matchInlineLinkTail(afterParen: Int, content: borrowing ContentSpan) -> (url: Chunk, title: Chunk, end: Int)? {
        let end = content.endOffset
        let destStart = skipWhitespace(from: afterParen, in: content)
        guard let dest = matchLinkDestination(from: destStart, end: end, in: content) else {
            return nil
        }
        let titleStart = skipWhitespace(from: dest.afterEnd, in: content)
        var titleEnd = dest.afterEnd
        var titleInterior = dest.afterEnd..<dest.afterEnd
        if titleStart > dest.afterEnd,
           let title = matchLinkTitle(from: titleStart, end: end, in: content) {
            titleInterior = title.interior
            titleEnd = title.afterEnd
        }
        let close = skipWhitespace(from: titleEnd, in: content)
        guard close < end, content[close] == UInt8(ascii: ")") else {
            return nil
        }
        return (
            unescapedChunk(dest.destination, in: content),
            unescapedTitle(titleInterior, in: content),
            close + 1
        )
    }

    private mutating func matchLabelKey(from pos: Int, content: borrowing ContentSpan) -> (key: NormalizedLabel, afterEnd: Int)? {
        let end = content.endOffset
        guard let label = matchLinkLabel(from: pos, end: end, in: content) else {
            return nil
        }
        return (label.interior.isEmpty ? .empty : normalizeLabel(virtualRange: label.interior, in: content), label.afterEnd)
    }

    /// Append a one-byte `]` text node at `cursor`. Used by the failure paths of `handleCloseBracket`.
    private mutating func emitBracketLiteral(at cursor: Int, end: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index) {
        appendInline(.text, .literal(storage.intern(content.chunk(offset: cursor, length: 1))), to: parent, start: cursor, end: end, content: content)
    }

    /// Construct the `.link` / `.image` / `.attribute` node, splice it in front of the opener's `[` text node, reparent every following sibling into it, and remove the opener's `[` text from the tree. Then resolve emphasis inside the link with the bracket's `delimPosition` as the floor.
    @inline(__always)
    private mutating func wrapBracketContent(_ kind: MarkdownNode.Kind, _ data: NodeData, openerInl: DocumentStorage.Index, delimPosition: Int, start: Int, end: Int, content: borrowing ContentSpan) {
        let wrapper = storage.appendNode(NodeRecord(kind: kind, parent: storage[openerInl].parent, data: data))
        // The link/image spans from its opening `[`/`![` to just past the closing `)` or reference label.
        stampInline(wrapper, start, end, content: content)
        storage.insertChildBefore(wrapper, before: openerInl)
        var sibling = storage[openerInl].next
        while let current = sibling {
            sibling = storage[current].next
            storage.unlinkChild(current)
            storage.appendChild(current, to: wrapper)
        }
        storage.unlinkChild(openerInl)
        processEmphasis(stackBottom: delimPosition, content: content)
    }

    // MARK: - Footnote references

    private mutating func footnoteDefinition(referencedFrom open: Int, closeBracket: Int, in content: borrowing ContentSpan) -> DocumentStorage.Index? {
        let labelStart = open + 2
        guard !storage.footnoteMap.isEmpty, labelStart < closeBracket, content[open + 1] == UInt8(ascii: "^"),
              labelFits(footnoteLabelLimit, virtualRange: labelStart..<closeBracket, in: content) else {
            return nil
        }
        return storage.footnoteMap[normalizeLabel(virtualRange: labelStart..<closeBracket, in: content)]
    }

    private mutating func emitFootnoteReferenceIfDefined(openerIdx: Int, bracketStart: Int, closeBracket: Int, content: borrowing ContentSpan) -> Bool {
        // A footnote definition's label holds no unescaped bracket, so a bracket pushed after the opener rules one out.
        // Skipping that lookup keeps nested footnote-shaped brackets linear under any label limit.
        guard storage.options.contains(.footnotes), !brackets[openerIdx].bracketAfter,
              let defIdx = footnoteDefinition(referencedFrom: bracketStart, closeBracket: closeBracket, in: content) else {
            return false
        }
        let openerInl = brackets[openerIdx].inlText
        let openerStart = brackets[openerIdx].virtualStart
        // Resolve emphasis inside the bracket first, so removing its nodes leaves no stale delimiters.
        processEmphasis(stackBottom: brackets[openerIdx].delimPosition, content: content)
        emitFootnoteReference(after: openerInl, definition: defIdx, span: bracketStart..<closeBracket + 1, content: content)
        if bracketStart > openerStart {
            storage.trimLiteral(of: openerInl, trimStart: 0, newLength: bracketStart - openerStart)
            stampInline(openerInl, openerStart, bracketStart, content: content)
        } else {
            storage.unlinkChild(openerInl)
        }
        popBracket()
        return true
    }

    // A footnote reference's index is 0 until the footnote pass numbers the finalized tree.
    private mutating func emitFootnoteReference(after openerInl: DocumentStorage.Index, definition defIdx: DocumentStorage.Index, span: Range<Int>, content: borrowing ContentSpan) {
        guard case .footnoteDefinition(let defLabel) = storage[defIdx].data else {
            preconditionFailure("footnoteMap holds only footnote definitions")
        }
        // Detach inner-content text nodes (the `^label` part). They aren't part of the reference's emitted text - the reference is rendered by the consumer based on its label and index.
        var sib = storage[openerInl].next
        while let sib_ = sib {
            let nextSib = storage[sib_].next
            storage.unlinkChild(sib_)
            sib = nextSib
        }
        let fnRefIdx = storage.appendNode(NodeRecord(
            kind: .footnoteReference(index: 0),
            parent: storage[openerInl].parent,
            data: .footnoteReference(label: defLabel)
        ))
        storage.insertChildAfter(fnRefIdx, after: openerInl)
        stampInline(fnRefIdx, span.lowerBound, span.upperBound, content: content)
    }

    // MARK: - Extended attributes (`^[..]`)

    private mutating func matchAttributeForm(cursor: Int, content: borrowing ContentSpan) -> (data: NodeData?, end: Int) {
        let end = content.endOffset
        let pos = cursor + 1
        // Try inline `(attrs)` form. The attribute scanner allows whitespace and balanced parens - this is *not* a link-URL scan.
        if pos < end, content[pos] == UInt8(ascii: "("),
           let scanned = matchAttributeAttributes(start: pos + 1, content: content) {
            return (.attribute(storage.intern(scanned.chunk)), scanned.afterEnd)
        }
        // Try reference form `[label]` looking up in attribute refmap.
        if storage.attributeReferenceMap.isEmpty {
            return (nil, matchLinkLabel(from: pos, end: end, in: content)?.afterEnd ?? pos)
        }
        guard let label = matchLabelKey(from: pos, content: content) else {
            return (nil, pos)
        }
        guard !label.key.isEmpty, let attributes = storage.attributeReferenceMap[label.key] else {
            return (nil, label.afterEnd)
        }
        return (.attribute(storage.intern(attributes)), label.afterEnd)
    }

    private struct AttributeAttributesMatch {
        var chunk: Chunk
        var afterEnd: Int
    }

    /// Scan the inside of an attribute form's `(…)`.
    ///
    /// Backslash before ASCII punctuation is treated as an escape (and consumed as a 2-byte unit). Differs from a link-URL scan in that whitespace is not a terminator.
    private mutating func matchAttributeAttributes(start: Int, content: borrowing ContentSpan) -> AttributeAttributesMatch? {
        let end = content.endOffset
        let maxNesting = limits.maxAttributeParenthesisNesting
        guard let close = attributeParentheses.balancedEnd(from: start, end: end, maxNesting: maxNesting, byte: { content[$0] }, terminates: { _ in false }),
              close < end else {
            return nil
        }
        return AttributeAttributesMatch(chunk: materializedChunk(start: start, end: close, content: content), afterEnd: close + 1)
    }

    // MARK: - Emphasis / strong (delimiter stack)

    /// One node in the delimiter stack - the side data structure used by CommonMark's emphasis-resolution algorithm (§6.2 + Appendix).
    ///
    /// The stack is a doubly-linked list embedded in a `UniqueArray<DelimiterRecord>` array - `previous`/`next` are array indices, `nil` means "none". When emphasis is resolved, individual records are unlinked from the list but the array itself isn't shrunk (so other indices stay valid).
    internal struct DelimiterRecord {
        var character: UInt8
        var length: Int
        var canOpen: Bool
        var canClose: Bool
        var inlText: DocumentStorage.Index
        // `insertEmph` stamps from these virtual offsets, not from the text node's literal, whose offsets already
        // point into the source or the arena.
        var virtualStart: Int
        var virtualEnd: Int
        var previous: Int?
        var next: Int?
        // An opener search follows these links rather than `previous`, because a quote pair or an unequal `~` pair
        // leaves the delimiters between them on the stack for later searches to pass.
        var previousOfCharacter: Int? = nil
        var nextOfCharacter: Int? = nil
    }

    private struct Flanking {
        var leftFlanking: Bool
        var rightFlanking: Bool
        var beforeChar: UInt8
        var beforeIsPunct: Bool
        var afterIsPunct: Bool
    }

    private func classifyFlanking(start: Int, runEnd: Int, content: borrowing ContentSpan) -> Flanking {
        let end = content.endOffset
        let contentStart = content.startOffset
        // "Before" character - treat content boundaries as a line break.
        let beforeIdx = start - 1
        let beforeChar: UInt8 = beforeIdx >= contentStart ? content[beforeIdx] : UInt8(ascii: "\n")
        let beforeScalar: Int32 = beforeIdx >= contentStart
            ? Self.flankingScalarBefore(endingAt: beforeIdx, lowerBound: contentStart, content: content)
            : 0x0A
        // "After" character - same convention at end of content.
        let afterScalar: Int32 = runEnd < end
            ? Self.flankingScalarAfter(startingAt: runEnd, content: content)
            : 0x0A
        let beforeClass = Self.characterClass(beforeScalar)
        let afterClass = Self.characterClass(afterScalar)
        let beforeIsSpace = beforeClass == .whitespace
        let beforeIsPunct = beforeClass == .punctuation
        let afterIsSpace = afterClass == .whitespace
        let afterIsPunct = afterClass == .punctuation
        let leftFlanking = !afterIsSpace && (!afterIsPunct || beforeIsSpace || beforeIsPunct)
        let rightFlanking = !beforeIsSpace && (!beforeIsPunct || afterIsSpace || afterIsPunct)
        return Flanking(
            leftFlanking: leftFlanking,
            rightFlanking: rightFlanking,
            beforeChar: beforeChar,
            beforeIsPunct: beforeIsPunct,
            afterIsPunct: afterIsPunct
        )
    }

    @inline(__always)
    private static func flankingScalarBefore(endingAt endIdx: Int, lowerBound: Int, content: borrowing ContentSpan) -> Int32 {
        let last = content[endIdx]
        if last < 0x80 { return Int32(last) }
        var lead = endIdx
        while lead > lowerBound, content[lead] & 0xC0 == 0x80 { lead -= 1 }
        return decodeUTF8Scalar(at: lead, content: content)
    }

    @inline(__always)
    private static func flankingScalarAfter(startingAt idx: Int, content: borrowing ContentSpan) -> Int32 {
        let first = content[idx]
        if first < 0x80 { return Int32(first) }
        return decodeUTF8Scalar(at: idx, content: content)
    }

    private static func decodeUTF8Scalar(at idx: Int, content: borrowing ContentSpan) -> Int32 {
        let b0 = content[idx]
        precondition(b0 >= 0xC2 && b0 <= 0xF4, "inline content is valid UTF-8, so a decoded scalar starts at a multi-byte lead byte")
        if b0 < 0xE0 {
            return (Int32(b0 & 0x1F) << 6) | Int32(content[idx + 1] & 0x3F)
        }
        if b0 < 0xF0 {
            return (Int32(b0 & 0x0F) << 12) | (Int32(content[idx + 1] & 0x3F) << 6) | Int32(content[idx + 2] & 0x3F)
        }
        return (Int32(b0 & 0x07) << 18) | (Int32(content[idx + 1] & 0x3F) << 12) | (Int32(content[idx + 2] & 0x3F) << 6) | Int32(content[idx + 3] & 0x3F)
    }

    private enum CharacterClass {
        case whitespace
        case punctuation
        case other
    }

    @inline(__always)
    private static func characterClass(_ uc: Int32) -> CharacterClass {
        if uc < 0x80 {
            let b = UInt8(uc)
            return b.isFlankingSpace ? .whitespace : b.isASCIIPunct ? .punctuation : .other
        }
        return nonASCIICharacterClass(uc)
    }

    @inline(never)
    private static func nonASCIICharacterClass(_ uc: Int32) -> CharacterClass {
        switch Unicode.Scalar(UInt32(uc))?.properties.generalCategory {
        case .spaceSeparator:
            return .whitespace
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation:
            return .punctuation
        default:
            return .other
        }
    }

    private mutating func handleDelimRun(char: UInt8, start: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        var end = content.endOffset
        if char == UInt8(ascii: "~") {
            end = start + min(end - start, max(limits.strikethroughTildeRunChunk, 1))
        }
        var runEnd = start
        while runEnd < end, content[runEnd] == char {
            runEnd += 1
        }

        let count = runEnd - start
        let flanking = classifyFlanking(start: start, runEnd: runEnd, content: content)
        let leftFlanking = flanking.leftFlanking
        let rightFlanking = flanking.rightFlanking
        let beforeIsPunct = flanking.beforeIsPunct
        let afterIsPunct = flanking.afterIsPunct
        
        let canOpen: Bool
        let canClose: Bool
        if char == UInt8(ascii: "_") {
            // Intraword `_` is rejected on whichever side has letters/digits.
            canOpen = leftFlanking && (!rightFlanking || beforeIsPunct)
            canClose = rightFlanking && (!leftFlanking || afterIsPunct)
        } else {
            canOpen = leftFlanking
            canClose = rightFlanking
        }
        // Non-flanking run: leave it as part of pending text.
        if !canOpen && !canClose {
            return runEnd
        }
        // Flush pending text up to the run start, then emit the run as text.
        let textIdx = emitLiteral(.text, content.chunk(offset: start, length: count), start: start, end: runEnd, to: parent, pendingTextStart: &pendingTextStart, content: content)
        let pushDelim: Bool
        if char == UInt8(ascii: "~") {
            let doubleTilde = storage.options.contains(.strikethroughDoubleTilde)
            pushDelim = count == 2 || (!doubleTilde && count == 1)
        } else {
            pushDelim = true
        }
        if pushDelim {
            pushDelimiter(char, length: count, canOpen: canOpen, canClose: canClose, inlText: textIdx, range: start..<runEnd)
        }
        return runEnd
    }

    /// Resolve emphasis pairs. Walks forward from the first delimiter above `stackBottom` (use `-1` to process the entire stack). For each closer, looks back for the most recent compatible opener and pairs them via `insertEmph`.
    private mutating func processEmphasis(stackBottom: Int, content: borrowing ContentSpan) {
        var openersBottom = OpenersBottom(fill: stackBottom)
        // Find the earliest (smallest-index) delimiter strictly above stackBottom.
        var closer: Int? = nil
        var laterOfCharacter = SIMD8<Int>(repeating: -1)
        var walker = lastDelim
        while let w = walker, w > stackBottom {
            let wCharIdx = charIndex(for: delimiters[w].character)
            let later = laterOfCharacter[wCharIdx]
            if later >= 0 {
                delimiters[later].previousOfCharacter = w
                delimiters[w].nextOfCharacter = later
            }
            laterOfCharacter[wCharIdx] = w
            closer = w
            walker = delimiters[w].previous
        }
        while let c = closer {
            if !delimiters[c].canClose {
                closer = delimiters[c].next
                continue
            }
            let closerChar = delimiters[c].character
            let charIdx = charIndex(for: closerChar)
            // Rules 9 and 10 can reject an opener for a closer that can open and accept it for one that can't, so
            // the two kinds of closer keep separate `openersBottom` rows.
            let bottomRow = (delimiters[c].canOpen ? 3 : 0) + delimiters[c].length % 3
            // Look backward for first matching opener.
            var opener = delimiters[c].previousOfCharacter
            var openerFound = false
            while let o = opener, o > stackBottom,
                  o >= openersBottom[bottomRow, charIdx] {
                if delimiters[o].canOpen {
                    let cl = delimiters[c]
                    let op = delimiters[o]
                    // `~` takes this test too, with no length match: `insertEmph` discards an unequal pair, so a `~`
                    // closer pairs only with the nearest `~` opener that passes.
                    if !(cl.canOpen || op.canClose)
                        || cl.length % 3 == 0
                        || (op.length + cl.length) % 3 != 0 {
                        openerFound = true
                        break
                    }
                }
                opener = delimiters[o].previousOfCharacter
            }
            let oldCloser = c
            if closerChar == UInt8(ascii: "'") || closerChar == UInt8(ascii: "\"") {
                // Smart quote: the closer is already the right (closing) curly form - `handleQuoteDelim` sets `'`→rightSingleQuote and a `"` closer (which by definition `canClose`)→rightDoubleQuote at creation, so re-interning it here would only move its segment to the pool's end and make `consolidateTextNodes` merge it with its neighbours (e.g. the apostrophe in `it's`) by copying segments instead of widening in place. Only the opener needs its glyph flipped.
                let single = closerChar == UInt8(ascii: "'")
                let next = delimiters[c].next
                if openerFound, let opener {
                    setSmartLiteral(
                        of: delimiters[opener].inlText,
                        single ? Self.leftSingleQuote : Self.leftDoubleQuote
                    )
                    removeDelim(opener)
                    removeDelim(oldCloser)
                }
                closer = next
            } else if openerFound, let opener {
                closer = insertEmph(
                    opener: opener,
                    closer: c,
                    content: content
                )
            } else {
                closer = delimiters[c].next
            }
            if !openerFound {
                openersBottom[bottomRow, charIdx] = oldCloser
                if !delimiters[oldCloser].canOpen {
                    removeDelim(oldCloser)
                }
            }
        }
        // Free remaining delimiters above stackBottom.
        while let last = lastDelim, last > stackBottom {
            removeDelim(last)
        }
    }

    private func charIndex(for c: UInt8) -> Int {
        switch c {
        case UInt8(ascii: "_"): return 1
        case UInt8(ascii: "~"): return 2
        case UInt8(ascii: "'"): return 3
        case UInt8(ascii: "\""): return 4
        default: return 0
        }
    }

    private mutating func insertEmph(opener: Int, closer: Int, content: borrowing ContentSpan) -> Int? {
        let openerInl = delimiters[opener].inlText
        let closerInl = delimiters[closer].inlText
        let openerChar = delimiters[opener].character
        // A record's `length` keeps the full run length, which rules 9 and 10 sum, so the delimiters still unused are
        // counted from the text literals.
        var openerNumChars = literalLength(of: openerInl)
        var closerNumChars = literalLength(of: closerInl)
        let useDelims: Int
        let kind: MarkdownNode.Kind
        if openerChar == UInt8(ascii: "~") {
            if openerNumChars != closerNumChars {
                let next = delimiters[closer].next
                removeDelim(closer)
                removeDelim(opener)
                return next
            }
            // Consume the entire run from each side.
            useDelims = openerNumChars
            kind = .strikethrough
        } else {
            useDelims = (closerNumChars >= 2 && openerNumChars >= 2) ? 2 : 1
            kind = useDelims == 1 ? .emphasis : .strong
        }
        openerNumChars -= useDelims
        closerNumChars -= useDelims
        // Trim `useDelims` chars off the END of the opener literal.
        storage.trimLiteral(of: openerInl, trimStart: 0, newLength: openerNumChars)
        // Trim `useDelims` chars off the START of the closer literal.
        storage.trimLiteral(of: closerInl, trimStart: useDelims, newLength: closerNumChars)
        // Free intervening delimiters (their inl_text nodes survive - they become children of the new emph/strong).
        if let previous = delimiters[closer].previous, previous != opener {
            removeDelims(after: opener, through: previous)
        }
        // Build the wrapping node and reparent siblings.
        let parentIdx = storage[openerInl].parent
        let emphIdx = storage.appendNode(NodeRecord(kind: kind, parent: parentIdx))
        // Stamp the source range spanning the consumed delimiters on both ends.
        let start = delimiters[opener].virtualEnd - useDelims
        let end = delimiters[closer].virtualStart + useDelims
        stampInline(emphIdx, start, end, content: content)
        stampInline(openerInl, delimiters[opener].virtualStart, start, content: content)
        stampInline(closerInl, end, delimiters[closer].virtualEnd, content: content)
        delimiters[opener].virtualEnd = start
        delimiters[closer].virtualStart = end
        var sibling = storage[openerInl].next
        while let sibling_ = sibling, sibling_ != closerInl {
            let nextSibling = storage[sibling_].next
            storage.unlinkChild(sibling_)
            storage.appendChild(sibling_, to: emphIdx)
            sibling = nextSibling
        }
        storage.insertChildAfter(emphIdx, after: openerInl)
        var resultCloser: Int? = closer
        if openerNumChars == 0 {
            storage.unlinkChild(openerInl)
            removeDelim(opener)
        }
        if closerNumChars == 0 {
            storage.unlinkChild(closerInl)
            let next = delimiters[closer].next
            removeDelim(closer)
            resultCloser = next
        }
        return resultCloser
    }

    private mutating func removeDelims(after first: Int, through last: Int) {
        var d: Int? = last
        while let dd = d, dd != first {
            let prev = delimiters[dd].previous
            removeDelim(dd)
            d = prev
        }
    }

    private mutating func removeDelim(_ idx: Int) {
        let prev = delimiters[idx].previous
        let next = delimiters[idx].next
        if let prev {
            delimiters[prev].next = next
        }
        if let next {
            delimiters[next].previous = prev
        }
        if idx == lastDelim {
            lastDelim = prev
        }
        let previousOfCharacter = delimiters[idx].previousOfCharacter
        let nextOfCharacter = delimiters[idx].nextOfCharacter
        if let previousOfCharacter {
            delimiters[previousOfCharacter].nextOfCharacter = nextOfCharacter
        }
        if let nextOfCharacter {
            delimiters[nextOfCharacter].previousOfCharacter = previousOfCharacter
        }
    }

    private func literalLength(of nodeIdx: DocumentStorage.Index) -> Int {
        guard case .literal(let ref) = storage[nodeIdx].data else {
            preconditionFailure("a delimiter run's text node holds a literal")
        }
        return ref.totalLength
    }

    // MARK: - Smart punctuation

    static let leftSingleQuote: Unicode.Scalar = "\u{2018}"
    static let rightSingleQuote: Unicode.Scalar = "\u{2019}"
    static let leftDoubleQuote: Unicode.Scalar = "\u{201C}"
    static let rightDoubleQuote: Unicode.Scalar = "\u{201D}"
    static let enDash: Unicode.Scalar = "\u{2013}"
    static let emDash: Unicode.Scalar = "\u{2014}"
    static let ellipsis: Unicode.Scalar = "\u{2026}"

    private mutating func appendToArena(_ s: String) {
        for b in s.utf8 {
            storage.strings.append(b)
        }
    }

    /// Append a constant UTF-8 byte sequence into the string arena.
    private mutating func appendSmartConstant(_ glyph: Unicode.Scalar) {
        UTF8.encode(glyph) { storage.strings.append($0) }
    }

    private mutating func smartConstantChunk(_ glyph: Unicode.Scalar) -> Chunk {
        let offset = storage.strings.count
        appendSmartConstant(glyph)
        return arenaChunk(from: offset)
    }

    /// Replace a text node's literal with a constant smart-punctuation glyph.
    private mutating func setSmartLiteral(of nodeIdx: DocumentStorage.Index, _ glyph: Unicode.Scalar) {
        let ref = storage.intern(smartConstantChunk(glyph))
        storage[nodeIdx].data = .literal(ref)
    }

    /// Handle a run of `-` under `.smart`. A run of two or more hyphens is decomposed into en/em dashes. A lone hyphen is left in the pending-text region. Returns the offset just past the run.
    private mutating func handleSmartHyphen(start: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        let end = content.endOffset
        var runEnd = start
        while runEnd < end,
              content[runEnd] == UInt8(ascii: "-") {
            runEnd += 1
        }
        let numHyphens = runEnd - start
        if numHyphens < 2 {
            // Lone hyphen: leave it in pending text (identical output, no extra node).
            return runEnd
        }
        var enCount = 0
        var emCount = 0
        if numHyphens % 3 == 0 {
            emCount = numHyphens / 3
        } else if numHyphens % 2 == 0 {
            enCount = numHyphens / 2
        } else if numHyphens % 3 == 2 {
            enCount = 1
            emCount = (numHyphens - 2) / 3
        } else {
            enCount = 2
            emCount = (numHyphens - 4) / 3
        }
        let offset = storage.strings.count
        for _ in 0..<emCount {
            appendSmartConstant(Self.emDash)
        }
        for _ in 0..<enCount {
            appendSmartConstant(Self.enDash)
        }
        let chunk = arenaChunk(from: offset)
        emitLiteral(.text, chunk, start: start, end: runEnd, to: parent, pendingTextStart: &pendingTextStart, content: content)
        return runEnd
    }

    /// Handle a `'` or `"` under `.smart`. Emits a text node carrying the initial curly form and, if the quote can open or close, pushes a delimiter so `processEmphasis` can resolve the open/close pairing.
    ///
    /// Returns the offset just past the quote.
    private mutating func handleQuoteDelim(char: UInt8, start: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        // Quotes are limited to a single delimiter character (unlike `*`/`_`/`~` runs).
        let runEnd = start + 1
        let flanking = classifyFlanking(start: start, runEnd: runEnd, content: content)
        let leftFlanking = flanking.leftFlanking
        let rightFlanking = flanking.rightFlanking
        let beforeChar = flanking.beforeChar
        // Quote-specific flanking rules.
        let canOpen = leftFlanking && !rightFlanking && beforeChar != UInt8(ascii: "]") && beforeChar != UInt8(ascii: ")")
        let canClose = rightFlanking
        // Initial curly form: `'` is always a right single quote (apostrophe); `"` is a closing quote when it can close, otherwise an opening quote.
        let literal: Unicode.Scalar
        if char == UInt8(ascii: "'") {
            literal = Self.rightSingleQuote
        } else {
            literal = canClose ? Self.rightDoubleQuote : Self.leftDoubleQuote
        }
        let textIdx = emitLiteral(.text, smartConstantChunk(literal), start: start, end: runEnd, to: parent, pendingTextStart: &pendingTextStart, content: content)
        if canOpen || canClose {
            // The curly glyph is 3 UTF-8 bytes; recording that as the delimiter length makes the rule-of-three opener check (`length % 3 == 0`) always admit a quote pairing.
            pushDelimiter(char, length: 3, canOpen: canOpen, canClose: canClose, inlText: textIdx, range: start..<runEnd)
        }
        return runEnd
    }

    private mutating func pushDelimiter(_ char: UInt8, length: Int, canOpen: Bool, canClose: Bool, inlText: DocumentStorage.Index, range: Range<Int>) {
        let prev = lastDelim
        let newIdx = delimiters.count
        delimiters.append(DelimiterRecord(
            character: char,
            length: length,
            canOpen: canOpen,
            canClose: canClose,
            inlText: inlText,
            virtualStart: range.lowerBound,
            virtualEnd: range.upperBound,
            previous: prev,
            next: nil
        ))
        if let prev {
            delimiters[prev].next = newIdx
        }
        lastDelim = newIdx
    }

    // MARK: - Code spans

    private struct CodeSpanMatch {
        var content: Chunk      // the code-span literal (with one-space-each-side trimmed if applicable)
        var afterClose: Int     // offset just past the closing backtick run
        var backtickCount: Int  // number of backticks in the opening/closing run
    }

    /// Match a code span starting at `start` (which must point at a backtick).
    private mutating func matchCodeSpan(start: Int, content: borrowing ContentSpan) -> CodeSpanMatch? {
        let end = content.endOffset
        let openEnd = scanBacktickRun(start: start, content: content)
        let runLength = openEnd - start
        if runLength > limits.maxCodeSpanOpeningBackticks {
            return nil
        }
        // Rescanning for every unmatched opener would make a paragraph of distinct-length runs quadratic.
        if backtickRunsSeen.rulesOutCloser(length: runLength, after: openEnd) {
            return nil
        }

        // Find a matching same-length backtick run after `openEnd`.
        var i = openEnd
        while i < end {
            let b = content[i]
            if b == UInt8(ascii: "`") {
                let closeEnd = scanBacktickRun(start: i, content: content)
                let closeLength = closeEnd - i
                if closeLength == runLength {
                    return CodeSpanMatch(content: codeSpanContent(start: openEnd, end: i, content: content), afterClose: closeEnd, backtickCount: runLength)
                }
                i = closeEnd
                continue
            }
            i += 1
        }
        backtickRunsSeen.scannedToEndFrom = openEnd
        var k = openEnd
        while k < end {
            guard content[k] == UInt8(ascii: "`") else {
                k += 1
                continue
            }
            let runEnd = scanBacktickRun(start: k, content: content)
            backtickRunsSeen.recordRun(length: runEnd - k, start: k)
            k = runEnd
        }
        return nil
    }

    /// Scan `start..<end` for the run of backticks beginning at `start`. Returns the offset just past the last consecutive backtick.
    private func scanBacktickRun(start: Int, content: borrowing ContentSpan) -> Int {
        let end = content.endOffset
        var i = start
        while i < end, content[i] == UInt8(ascii: "`") {
            i += 1
        }
        return i
    }

    private mutating func codeSpanContent(start: Int, end: Int, content: borrowing ContentSpan) -> Chunk {
        if let contiguous = content.contiguousChunk(fromVirtual: start, limit: end), contiguous.length == end - start {
            // Line endings are written as `\n` before they become spaces, so that a CRLF becomes one space.
            if contentHoldsCR, let copy = lineFeedCopy(of: contiguous) {
                return trimSingleSpaces(spacingLineEndings(copy))
            }
            var holdsLineEnding = false
            for i in contiguous.range where readByte(at: i, in: contiguous) == UInt8(ascii: "\n") {
                holdsLineEnding = true
                break
            }
            if !holdsLineEnding {
                return trimSingleSpaces(contiguous)
            }
        }
        let outOffset = storage.strings.count
        for k in start..<end {
            let b = content[k]
            storage.strings.append(b == UInt8(ascii: "\n") ? UInt8(ascii: " ") : b)
        }
        return trimSingleSpaces(arenaChunk(from: outOffset))
    }

    // Rewrites `chunk`'s bytes in place, so `chunk` must be an arena copy, never the source.
    private mutating func spacingLineEndings(_ chunk: Chunk) -> Chunk {
        for k in chunk.range where storage.strings[k] == UInt8(ascii: "\n") {
            storage.strings[k] = UInt8(ascii: " ")
        }
        return chunk
    }

    /// Apply CommonMark's "code-span single-space-strip" rule.
    ///
    /// If the content is non-empty, begins with a space, ends with a space, and contains at least one non-space byte, strip exactly one space from each end.
    private func trimSingleSpaces(_ chunk: Chunk) -> Chunk {
        let start = chunk.offset
        let end = chunk.range.upperBound
        if start < end,
           readByte(at: start, in: chunk) == UInt8(ascii: " "),
           readByte(at: end - 1, in: chunk) == UInt8(ascii: " ") {
            // Verify there's at least one non-space byte strictly between the two enclosing spaces. For 1- and 2-byte runs there are no inner bytes, so the strip rule doesn't apply.
            let innerStart = start + 1
            let innerEnd = end - 1
            var hasNonSpace = false
            if innerStart < innerEnd {
                for j in innerStart..<innerEnd {
                    let b = readByte(at: j, in: chunk)
                    if b != UInt8(ascii: " ") {
                        hasNonSpace = true
                        break
                    }
                }
            }
            if hasNonSpace {
                return chunk.extracting(1..<(chunk.length - 1))
            }
        }
        return chunk
    }

    // MARK: - Line breaks

    private struct LineBreakInfo {
        var isHard: Bool
        var textEnd: Int  // exclusive end of the pending-text region (excludes the marker bytes)
    }

    /// Decide whether the `\n` at `newlineOffset` is a soft or hard line break. CommonMark 0.31 §6.6 / §6.7:
    /// - Hard if a `\` immediately precedes the newline (with at least one byte in the pending-text region).
    /// - Hard if 2+ spaces immediately precede the newline.
    /// - Soft otherwise.
    /// Returns the kind plus the offset at which to truncate pending text (excluding the marker bytes - backslash or trailing spaces).
    private func classifyLineBreak(at newlineOffset: Int, pendingTextStart: Int, content: borrowing ContentSpan) -> LineBreakInfo {
        // Backslash hard break.
        if newlineOffset > pendingTextStart {
            let prev = content[newlineOffset - 1]
            if prev == UInt8(ascii: "\\") {
                return LineBreakInfo(isHard: true, textEnd: newlineOffset - 1)
            }
        }
        // A line tabulation or form feed before the line ending stays text (`a\f\t  \n` keeps `a\f`).
        var textEnd = newlineOffset
        var spacesBeforeLineEnding = 0
        var inSpaceRun = true
        while textEnd > pendingTextStart {
            let prev = content[textEnd - 1]
            if prev == UInt8(ascii: " ") {
                if inSpaceRun { spacesBeforeLineEnding += 1 }
            } else if prev == UInt8(ascii: "\t") {
                inSpaceRun = false
            } else {
                break
            }
            textEnd -= 1
        }
        return LineBreakInfo(isHard: spacesBeforeLineEnding >= 2, textEnd: textEnd)
    }

    // MARK: - Autolinks

    private struct AutolinkMatch {
        var interior: Range<Int>  // bytes between `<` and `>` (the visible text)
        var afterClose: Int       // offset just past the closing `>`
        var isEmail: Bool
    }

    /// Try to match an autolink starting at `start` (which points at `<`). CommonMark 0.31 §6.4. URI form first, email form as fallback.
    private func matchAutolink(start: Int, content: borrowing ContentSpan) -> AutolinkMatch? {
        if let uri = matchURIAutolink(start: start, content: content) {
            return uri
        }
        return matchEmailAutolink(start: start, content: content)
    }

    /// URI autolink: `<scheme:rest>` where scheme is `[A-Za-z][A-Za-z0-9+.-]{1,31}` and rest contains no `<`, `>`, ASCII whitespace, or ASCII control characters.
    private func matchURIAutolink(start: Int, content: borrowing ContentSpan) -> AutolinkMatch? {
        let end = content.endOffset
        var i = start + 1
        if i >= end {
            return nil
        }
        let first = content[i]
        if !first.isASCIILetter {
            return nil
        }
        i += 1
        var schemeChars = 1
        while i < end, schemeChars < 32 {
            let b = content[i]
            let ok = b.isASCIILetter
                || b.isASCIIDigit
                || b == UInt8(ascii: "+")
                || b == UInt8(ascii: ".")
                || b == UInt8(ascii: "-")
            if !ok {
                break
            }
            i += 1
            schemeChars += 1
        }
        // Need at least 2-char scheme and a `:`.
        if schemeChars < 2 || i >= end {
            return nil
        }
        if content[i] != UInt8(ascii: ":") {
            return nil
        }
        i += 1
        // Scan body until `>`.
        let bodyStart = start + 1
        while i < end {
            let b = content[i]
            if b == UInt8(ascii: ">") {
                return AutolinkMatch(
                    interior: bodyStart..<i,
                    afterClose: i + 1,
                    isEmail: false
                )
            }
            if b == UInt8(ascii: "<") || b == UInt8(ascii: " ") || b < 0x20 || b == 0x7F {
                return nil
            }
            i += 1
        }
        return nil
    }

    /// Email autolink: `<local@domain>` with `local` from a generous punctuation set and `domain` made of dot-separated labels.
    private func matchEmailAutolink(start: Int, content: borrowing ContentSpan) -> AutolinkMatch? {
        let end = content.endOffset
        var i = start + 1
        let bodyStart = i
        // Local part: 1+ local-allowed chars, no `@`.
        var localChars = 0
        while i < end {
            let b = content[i]
            if b == UInt8(ascii: "@") {
                break
            }
            if !isEmailLocalChar(b) {
                return nil
            }
            i += 1
            localChars += 1
        }
        if localChars == 0 || i >= end {
            return nil
        }
        i += 1
        // Domain: 1+ labels separated by `.`. Each label: letter/digit, optional letters/digits/hyphens, ending with letter/digit. Up to 63 chars per label.
        var labelStart = i
        while true {
            if i >= end {
                return nil
            }
            let b = content[i]
            if b == UInt8(ascii: ">") || b == UInt8(ascii: ".") {
                let labelLength = i - labelStart
                if labelLength == 0 || labelLength > 63
                    || content[labelStart] == UInt8(ascii: "-") || content[i - 1] == UInt8(ascii: "-") {
                    return nil
                }
                if b == UInt8(ascii: ">") {
                    break
                }
                labelStart = i + 1
            } else if !(b.isASCIILetter || b.isASCIIDigit || b == UInt8(ascii: "-")) {
                // Stopping at the first byte no domain holds keeps an unclosed `<local@` from scanning the block.
                return nil
            }
            i += 1
        }
        return AutolinkMatch(
            interior: bodyStart..<i,
            afterClose: i + 1,
            isEmail: true
        )
    }

    private func isEmailLocalChar(_ b: UInt8) -> Bool {
        if b.isASCIILetter || b.isASCIIDigit {
            return true
        }
        switch b {
        case UInt8(ascii: "."), UInt8(ascii: "!"), UInt8(ascii: "#"), UInt8(ascii: "$"),
             UInt8(ascii: "%"), UInt8(ascii: "&"), UInt8(ascii: "'"), UInt8(ascii: "*"),
             UInt8(ascii: "+"), UInt8(ascii: "/"), UInt8(ascii: "="), UInt8(ascii: "?"),
             UInt8(ascii: "^"), UInt8(ascii: "_"), UInt8(ascii: "`"), UInt8(ascii: "{"),
             UInt8(ascii: "|"), UInt8(ascii: "}"), UInt8(ascii: "~"), UInt8(ascii: "-"):
            return true
        default:
            return false
        }
    }

    private func isGFMEmailLocalChar(_ b: UInt8) -> Bool {
        if b.isASCIILetter || b.isASCIIDigit {
            return true
        }
        switch b {
        case UInt8(ascii: "."), UInt8(ascii: "+"), UInt8(ascii: "-"), UInt8(ascii: "_"):
            return true
        default:
            return false
        }
    }

    /// Emit a `.link` node + a single `.text` child for an autolink match.
    ///
    /// For email forms, the URL gets a `mailto:` prefix and is materialized into the string arena.
    private mutating func emitAutolink(auto: AutolinkMatch, into parent: DocumentStorage.Index, content: borrowing ContentSpan) {
        let textChunk = unescapedChunk(
            content.chunk(offset: auto.interior.lowerBound, length: auto.interior.count),
            backslashEscapes: false
        )
        let urlChunk = auto.isEmail
            ? materializeAutolinkURL(prefix: "mailto:", start: auto.interior.lowerBound, end: auto.interior.upperBound, content: content)
            : textChunk
        let urlRef = storage.intern(urlChunk)
        let textRef = storage.intern(textChunk)
        // The link spans the whole `<…>`; the text child spans just the interior visible bytes.
        let linkIdx = appendInline(.link, .link(url: urlRef, title: .empty), to: parent, start: auto.interior.lowerBound - 1, end: auto.afterClose, content: content)
        appendInline(.text, .literal(textRef), to: linkIdx, start: auto.interior.lowerBound, end: auto.interior.upperBound, content: content)
    }

    // MARK: - Raw inline HTML

    /// Match raw inline HTML starting at `start` (which points at `<`). Returns the offset just past the closing `>`, or `nil` if the bytes do not form one of the six accepted patterns:
    ///
    /// - open tag: `<name attrs… />` / `<name>`
    /// - close tag: `</name>`
    /// - comment: `<!--…-->` (and the empty forms `<!-->` / `<!--->`)
    /// - processing instruction: `<?…?>`
    /// - declaration: `<!NAME …>`
    /// - CDATA section: `<![CDATA[…]]>`
    ///
    /// CommonMark 0.31 §6.6.
    private mutating func matchInlineHTML(start: Int, content: borrowing ContentSpan) -> Int? {
        let end = content.endOffset
        let after = start + 1
        if after >= end {
            return nil
        }
        let c = content[after]
        switch c {
        case UInt8(ascii: "!"):
            return matchHTMLBangForm(start: start, content: content)
        case UInt8(ascii: "?"):
            return Self.matchHTMLOpenerToCloser("<?", "?>", start: start, content: content, misses: &htmlCloserMisses.processingInstruction)
        case UInt8(ascii: "/"):
            return matchHTMLTag(nameStart: start + 2, isClosing: true, content: content)
        default:
            return matchHTMLTag(nameStart: after, isClosing: false, content: content)
        }
    }

    private func matchHTMLTag(nameStart: Int, isClosing: Bool, content: borrowing ContentSpan) -> Int? {
        let end = content.endOffset
        guard let nameEnd = htmlTagNameEnd(from: nameStart, end: end, byte: { content[$0] }) else {
            return nil
        }
        return htmlTagEnd(afterName: nameEnd, isClosing: isClosing, end: end) { content[$0] }
    }

    /// Dispatch `<!`-prefixed HTML forms: comment, CDATA, declaration.
    private mutating func matchHTMLBangForm(start: Int, content: borrowing ContentSpan) -> Int? {
        let end = content.endOffset
        // start[0] == '<', start[1] == '!' guaranteed by caller.
        let i = start + 2
        if i >= end {
            return nil
        }
        let next = content[i]
        if next == UInt8(ascii: "-") {
            return matchHTMLComment(start: start, content: content)
        }
        if next == UInt8(ascii: "[") {
            return Self.matchHTMLOpenerToCloser("<![CDATA[", "]]>", start: start, content: content, misses: &htmlCloserMisses.cdata)
        }
        return matchHTMLDeclaration(start: start, content: content)
    }

    /// Match `<!--…-->`. Accepts the empty forms `<!-->` and `<!--->` per HTML5, then scans for the first `-->` terminator.
    private mutating func matchHTMLComment(start: Int, content: borrowing ContentSpan) -> Int? {
        let end = content.endOffset
        // Need at least `<!--`.
        if start + 4 > end {
            return nil
        }
        if content[start + 2] != UInt8(ascii: "-") || content[start + 3] != UInt8(ascii: "-") {
            return nil
        }
        let bodyStart = start + 4
        // <!-->
        if bodyStart < end, content[bodyStart] == UInt8(ascii: ">") {
            return bodyStart + 1
        }
        // <!--->
        if bodyStart + 1 < end, content[bodyStart] == UInt8(ascii: "-"), content[bodyStart + 1] == UInt8(ascii: ">") {
            return bodyStart + 2
        }
        return Self.scanRawHTMLCloser("-->", from: bodyStart, content: content, misses: &htmlCloserMisses.comment)
    }

    /// Match `<!NAME …>` where NAME is `[A-Z]+`, followed by at least one spacechar, any non-`>` chars, then `>`.
    private mutating func matchHTMLDeclaration(start: Int, content: borrowing ContentSpan) -> Int? {
        let end = content.endOffset
        var i = start + 2
        var nameLen = 0
        while i < end {
            let b = content[i]
            if b.isUppercaseASCIILetter {
                nameLen += 1
                i += 1
            } else {
                break
            }
        }
        if nameLen == 0 {
            return nil
        }
        let afterSpaces = skipWhitespace(from: i, in: content)
        if afterSpaces == i {
            return nil
        }
        return Self.scanRawHTMLCloser(">", from: afterSpaces, content: content, misses: &htmlCloserMisses.declaration)
    }

    private static func matchHTMLOpenerToCloser(_ opener: String, _ closer: String, start: Int, content: borrowing ContentSpan, misses: inout Range<Int>) -> Int? {
        let end = content.endOffset
        let openerLength = opener.utf8.count
        if start + openerLength > end {
            return nil
        }
        if !bytesEqual(at: start, target: opener.utf8, content: content) {
            return nil
        }
        return scanRawHTMLCloser(closer, from: start + openerLength, content: content, misses: &misses)
    }

    // A scan that fails from `start` fails from every later start too, which sees a subset of the same bytes and the
    // same content end.
    private static func scanRawHTMLCloser(
        _ closer: String, from start: Int, content: borrowing ContentSpan, misses: inout Range<Int>
    ) -> Int? {
        let end = content.endOffset
        if misses.contains(start) {
            return nil
        }
        let width = closer.utf8.count
        var i = start
        while i + width <= end {
            if bytesEqual(at: i, target: closer.utf8, content: content) {
                return i + width
            }
            i += 1
        }
        misses = start..<Int.max
        return nil
    }

    // MARK: - GFM extended autolinks

    /// Result of a GFM bare-URL / email match.
    private struct GFMAutolinkMatch {
        var urlStart: Int
        var urlEnd: Int
        var destinationPrefix: String
    }

    /// Dispatch a GFM autolink trial based on the trigger byte. Returns nil if no autolink starts at / contains `cursor`.
    private mutating func matchGFMAutolink(trigger: UInt8, cursor: Int, content: borrowing ContentSpan) -> GFMAutolinkMatch? {
        if trigger == UInt8(ascii: ":") {
            return matchGFMSchemeAutolink(
                colon: cursor, content: content
            )
        }
        precondition(trigger == UInt8(ascii: "w"), "a GFM autolink trial is dispatched only on `:` or `w`")
        return matchGFMWWWAutolink(
            start: cursor, content: content
        )
    }

    /// `:`-triggered: looks back for `http`/`https`/`ftp`, then forward for `//` and a URL body.
    private mutating func matchGFMSchemeAutolink(colon: Int, content: borrowing ContentSpan) -> GFMAutolinkMatch? {
        let end = content.endOffset
        let contentStart = content.startOffset
        if colon + 3 >= end {
            return nil
        }
        if content[colon + 1] != UInt8(ascii: "/") || content[colon + 2] != UInt8(ascii: "/") {
            return nil
        }
        guard let schemeStart = matchSchemeBackward(colon: colon, content: content) else {
            return nil
        }
        // The scheme is the whole run of ASCII letters before `://`, so a letter before `http` makes the scheme
        // something else (`xhttp://a.b` is text). Any other character may precede it.
        if schemeStart > contentStart, content[schemeStart - 1].isASCIILetter {
            return nil
        }
        guard schemeURLDomainAccepted(afterSlashes: colon + 3, content: content) else {
            return nil
        }
        let urlEnd = scanGFMURLBody(start: colon + 3, content: content)
        let trimmedEnd = trimTrailingPunctuation(urlStart: schemeStart, urlEnd: urlEnd, content: content)
        return GFMAutolinkMatch(
            urlStart: schemeStart,
            urlEnd: trimmedEnd,
            destinationPrefix: ""
        )
    }

    /// Find the start position of `http`, `https`, or `ftp` ending just before `colon`. Returns the scheme's first-byte offset, or nil.
    private mutating func matchSchemeBackward(colon: Int, content: borrowing ContentSpan) -> Int? {
        let contentStart = content.startOffset
        if colon - 5 >= contentStart,
           Self.bytesEqual(at: colon - 5, target: Self.httpsScheme, content: content, ignoringASCIICase: true) {
            return colon - 5
        }
        if colon - 4 >= contentStart,
           Self.bytesEqual(at: colon - 4, target: Self.httpScheme, content: content, ignoringASCIICase: true) {
            return colon - 4
        }
        if colon - 3 >= contentStart,
           Self.bytesEqual(at: colon - 3, target: Self.ftpScheme, content: content, ignoringASCIICase: true) {
            return colon - 3
        }
        return nil
    }

    /// `w`-triggered: matches `www.` followed by a URL body.
    private mutating func matchGFMWWWAutolink(start: Int, content: borrowing ContentSpan) -> GFMAutolinkMatch? {
        let end = content.endOffset
        let contentStart = content.startOffset
        if start > contentStart {
            let pre = content[start - 1]
            if !isValidWWWPreceding(pre) {
                return nil
            }
        }
        if start + 4 > end {
            return nil
        }
        if !Self.bytesEqual(at: start, target: Self.wwwPrefix, content: content) {
            return nil
        }
        guard domainAccepted(base: start, requirePeriod: true, content: content) else {
            return nil
        }
        let urlEnd = scanGFMURLBody(start: start + 4, content: content)
        let trimmedEnd = trimTrailingPunctuation(
            urlStart: start, urlEnd: urlEnd,
            content: content
        )
        return GFMAutolinkMatch(urlStart: start, urlEnd: trimmedEnd, destinationPrefix: "http://")
    }

    private func matchEmailScheme(_ scheme: String, colon: Int, localBound: Int, content: borrowing ContentSpan) -> Int? {
        let len = scheme.utf8.count
        let schemeStart = colon + 1 - len
        if schemeStart < localBound {
            return nil
        }
        if !Self.bytesEqual(at: schemeStart, target: scheme.utf8, content: content) {
            return nil
        }
        if schemeStart == localBound {
            return len
        }
        let prev = content[schemeStart - 1]
        if prev.isASCIILetter || prev.isASCIIDigit {
            return nil
        }
        return len
    }

    /// `@`-triggered: scans backward for the email local part and forward for the domain.
    private mutating func matchGFMEmailAutolink(at: Int, localBound: Int, content: borrowing ContentSpan, resumeAt: inout Int) -> GFMAutolinkMatch? {
        let end = content.endOffset
        // A restart at a second `@` keeps the folded scheme and any period already scanned, so `a@b.c@d` links `b.c@d`.
        var atSign = at
        var schemeFolded = false
        var isXmpp = false
        var hasPeriodBeforeAlphanumeric = false
        while true {
            var localStart = atSign
            while localStart > localBound {
                let b = content[localStart - 1]
                if isGFMEmailLocalChar(b) {
                    localStart -= 1
                    continue
                }
                if b == UInt8(ascii: ":") {
                    if let len = matchEmailScheme("mailto:", colon: localStart - 1, localBound: localBound, content: content) {
                        schemeFolded = true
                        localStart -= len
                        continue
                    }
                    if let len = matchEmailScheme("xmpp:", colon: localStart - 1, localBound: localBound, content: content) {
                        schemeFolded = true
                        isXmpp = true
                        localStart -= len
                        continue
                    }
                }
                break
            }
            // A folded scheme counts as a local part, so `mailto:@a.b` is accepted.
            if localStart == atSign {
                resumeAt = atSign + 1
                return nil
            }
            var i = atSign + 1
            var sawSecondAt = false
            while i < end {
                let b = content[i]
                if b.isASCIILetter || b.isASCIIDigit || b == UInt8(ascii: "-") || b == UInt8(ascii: "_") {
                    i += 1
                } else if b == UInt8(ascii: "."), i + 1 < end, content[i + 1].isASCIILetter || content[i + 1].isASCIIDigit {
                    hasPeriodBeforeAlphanumeric = true
                    i += 1
                } else if b == UInt8(ascii: "/"), isXmpp {
                    i += 1
                } else {
                    sawSecondAt = b == UInt8(ascii: "@")
                    break
                }
            }
            if sawSecondAt {
                atSign = i
                continue
            }
            // Every `@` before `i` is settled, so resuming at `i` keeps the pass linear on `@`-dense input.
            resumeAt = i
            guard i > atSign + 1, hasPeriodBeforeAlphanumeric, content[i - 1].isASCIILetter else {
                return nil
            }
            return GFMAutolinkMatch(urlStart: localStart, urlEnd: i, destinationPrefix: schemeFolded ? "" : "mailto:")
        }
    }

    /// Emit a `.link` node + a single `.text` child for a GFM autolink match.
    private mutating func emitGFMAutolink(auto: GFMAutolinkMatch, into parent: DocumentStorage.Index, content: borrowing ContentSpan) {
        let textChunk = content.chunk(
            offset: auto.urlStart,
            length: auto.urlEnd - auto.urlStart
        )
        let urlChunk = auto.destinationPrefix.isEmpty
            ? textChunk
            : materializeAutolinkURL(prefix: auto.destinationPrefix, start: auto.urlStart, end: auto.urlEnd, content: content)
        let urlRef = storage.intern(urlChunk)
        let textRef = storage.intern(textChunk)
        let linkIdx = appendInline(.link, .link(url: urlRef, title: .empty), to: parent, start: auto.urlStart, end: auto.urlEnd, content: content)
        appendInline(.text, .literal(textRef), to: linkIdx, start: auto.urlStart, end: auto.urlEnd, content: content)
    }

    /// Append `prefix` + the content bytes of `start..<end` into `storage.strings`, returning a chunk pointing at the appended region.
    ///
    /// The bytes are read from `content` (the scratch/source view, independent of `storage.strings`) so the read region doesn't alias the buffer being appended to.
    private mutating func materializeAutolinkURL(prefix: String, start: Int, end: Int, content: borrowing ContentSpan) -> Chunk {
        let offset = storage.strings.count
        appendToArena(prefix)
        for j in start..<end {
            storage.strings.append(content[j])
        }
        return arenaChunk(from: offset)
    }

    private func scanGFMURLBody(
        start: Int,
        content: borrowing ContentSpan
    ) -> Int {
        let end = content.endOffset
        var i = start
        while i < end {
            let b = content[i]
            if b.isSpaceTabOrLineEnding || b == UInt8(ascii: "<") {
                break
            }
            i += 1
        }
        return i
    }

    /// Peel trailing `.,?:!*_~` and unmatched trailing `)` per the GFM autolink trim rules.
    private func trimTrailingPunctuation(urlStart: Int, urlEnd: Int, content: borrowing ContentSpan) -> Int {
        var opening = 0
        var closing = 0
        for j in urlStart..<urlEnd {
            switch content[j] {
            case UInt8(ascii: "("): opening += 1
            case UInt8(ascii: ")"): closing += 1
            default: break
            }
        }

        var i = urlEnd
        trim: while i > urlStart {
            switch content[i - 1] {
            case UInt8(ascii: ")"):
                if closing <= opening {
                    break trim
                }
                closing -= 1
                i -= 1
            case UInt8(ascii: "?"), UInt8(ascii: "!"), UInt8(ascii: "."), UInt8(ascii: ","),
                 UInt8(ascii: ":"), UInt8(ascii: "*"), UInt8(ascii: "_"), UInt8(ascii: "~"),
                 UInt8(ascii: "'"), UInt8(ascii: "\""):
                i -= 1
            case UInt8(ascii: ";"):
                // GFM rule: a trailing `&entity;`-like sequence is treated as separate text.
                var entityStart = i - 2
                while entityStart > urlStart, content[entityStart].isASCIILetter {
                    entityStart -= 1
                }
                if entityStart < i - 2, content[entityStart] == UInt8(ascii: "&") {
                    i = entityStart
                } else {
                    i -= 1
                }
            default:
                break trim
            }
        }
        return i
    }

    // The scan never examines the content's last byte, a backslash makes it examine the next character
    // instead, and more than ten periods lift the underscore rule. `ExtendedAutolinkDomainScanTests` pins each of these
    // departures from the spec's prose.
    private mutating func domainAccepted(base: Int, requirePeriod: Bool, content: borrowing ContentSpan) -> Bool {
        let end = content.endOffset
        let size = end - base
        var periods = 0
        var underscoresInPreviousSegment = 0
        var underscoresInLastSegment = 0
        var i = 1
        while i < size - 1 {
            if content[base + i] == UInt8(ascii: "\\"), i < size - 2 {
                i += 1
            }
            let b = content[base + i]
            if b == UInt8(ascii: "_") {
                underscoresInLastSegment += 1
            } else if b == UInt8(ascii: ".") {
                underscoresInPreviousSegment = underscoresInLastSegment
                underscoresInLastSegment = 0
                periods += 1
            } else if !isHostByte(b) && b != UInt8(ascii: "-") {
                break
            }
            i += 1
        }
        if (underscoresInPreviousSegment > 0 || underscoresInLastSegment > 0) && periods <= 10 {
            return false
        }
        return !requirePeriod || periods > 0
    }

    private mutating func schemeURLDomainAccepted(afterSlashes: Int, content: borrowing ContentSpan) -> Bool {
        let first = content[afterSlashes]
        if first < 0x80 {
            if !isHostByte(first) {
                return false
            }
        } else {
            let scalar = Self.decodeUTF8Scalar(at: afterSlashes, content: content)
            if Self.characterClass(scalar) != .other {
                return false
            }
        }
        return domainAccepted(base: afterSlashes, requirePeriod: false, content: content)
    }

    private func isHostByte(_ b: UInt8) -> Bool {
        b < 0x80 && !b.isASCIIPunct && (b == 0x0B || !b.isWhitespaceCharacter)
    }

    /// Only space, tab, line endings, `*`, `_`, `~`, `(` count as valid boundaries; everything else (including `<`) disqualifies the autolink so it can't trigger inside an angle-bracket autolink that failed validation.
    private func isValidWWWPreceding(_ b: UInt8) -> Bool {
        if b.isSpaceTabOrLineEnding {
            return true
        }
        switch b {
        case UInt8(ascii: "*"), UInt8(ascii: "_"), UInt8(ascii: "~"), UInt8(ascii: "("):
            return true
        default:
            return false
        }
    }

    private static let httpsScheme = Array("https".utf8)
    private static let httpScheme = Array("http".utf8)
    private static let ftpScheme = Array("ftp".utf8)
    private static let wwwPrefix = Array("www.".utf8)

    // With `ignoringASCIICase`, `target` must hold only ASCII letters, since the case mask also pairs other bytes, such
    // as `:` with 0x1A.
    private static func bytesEqual(at start: Int, target: some Collection<UInt8>, content: borrowing ContentSpan, ignoringASCIICase: Bool = false) -> Bool {
        let mask: UInt8 = ignoringASCIICase ? 0x20 : 0
        for (k, targetByte) in target.enumerated() {
            if (content[start + k] | mask) != (targetByte | mask) {
                return false
            }
        }
        return true
    }

    /// Append a flat UTF-8 byte array to `out` and return a chunk pointing at the appended region.
    private static func appendUTF8Bytes(bytes: Bytes8, count: Int, into out: inout UniqueArray<UInt8>) -> Chunk {
        let offset = out.count
        for i in 0..<count {
            out.append(bytes[i])
        }
        return Chunk(offset: offset, length: count, inSource: false)
    }

    // MARK: - Helpers

    /// Emit a `.text` node spanning `start..<end` if non-empty.
    private mutating func flushPendingText(start: Int, end: Int, content: borrowing ContentSpan, into parent: DocumentStorage.Index) {
        if end <= start {
            return
        }
        // Every line join is a line break, which flushes the run, so a run lies within one segment.
        guard let chunk = content.contiguousChunk(fromVirtual: start, limit: end), chunk.length == end - start else {
            preconditionFailure("a text run lies within one segment")
        }
        appendInline(.text, .literal(storage.intern(chunk)), to: parent, start: start, end: end, content: content)
    }

    @discardableResult
    private mutating func appendInline(_ kind: MarkdownNode.Kind, _ data: NodeData?, to parent: DocumentStorage.Index, start: Int, end: Int, content: borrowing ContentSpan) -> DocumentStorage.Index {
        let idx = storage.appendNode(NodeRecord(kind: kind, parent: parent, data: data))
        storage.appendChild(idx, to: parent)
        stampInline(idx, start, end, content: content)
        return idx
    }

    @discardableResult
    private mutating func emitLiteral(_ kind: MarkdownNode.Kind, _ chunk: Chunk, start: Int, end: Int, to parent: DocumentStorage.Index, pendingTextStart: inout Int, content: borrowing ContentSpan) -> DocumentStorage.Index {
        flushPendingText(start: pendingTextStart, end: start, content: content, into: parent)
        pendingTextStart = end
        return appendInline(kind, .literal(storage.intern(chunk)), to: parent, start: start, end: end, content: content)
    }

    mutating func materializedChunk(start: Int, end: Int, content: borrowing ContentSpan) -> Chunk {
        if let contiguous = content.contiguousChunk(fromVirtual: start, limit: end),
           contiguous.length == end - start {
            if contentHoldsCR, let copy = lineFeedCopy(of: contiguous) {
                return copy
            }
            return contiguous
        }
        let outOffset = storage.strings.count
        for k in start..<end {
            storage.strings.append(content[k])
        }
        return arenaChunk(from: outOffset)
    }

    /// Stamp `node`'s source range from *virtual* content offsets, resolving each through `content.sourceOffset(ofVirtual:)`.
    ///
    /// `end` is *exclusive* (one past the last byte), so the last content byte `end - 1` is resolved and incremented; this also maps an `end` that lands on the synthetic line-join newline back to just past the preceding source byte.
    @inline(__always)
    mutating func stampInline(_ node: DocumentStorage.Index, _ start: Int, _ end: Int, content: borrowing ContentSpan) {
        guard positionsEnabled, end > start else {
            return
        }
        storage.setSourceStart(node, lineEndingStart(content.sourceOffset(ofVirtual: start)))
        storage.setSourceEnd(node, content.sourceOffset(ofVirtual: end - 1) + 1)
    }

    /// Merge runs of adjacent `.text` children into single nodes, descending into containers.
    ///
    /// Smart-punctuation / entity substitutions emit their replacement as a separate text node (e.g. `"Markdown"` + `"’"` + `"s "`). The merged node's content is the concatenation of the runs' segments.
    mutating func consolidateTextNodes(_ root: DocumentStorage.Index) {
        var parent = root
        var child = storage[root].firstChild
        while true {
            guard let current = child else {
                guard storage.ascend(from: &parent, resumingAt: &child, within: root) else {
                    return
                }
                continue
            }
            if storage[current].kind.isText {
                // Absorb all immediately-following text siblings into `current`.
                while let next = storage[current].next, storage[next].kind.isText {
                    mergeTextNode(next, into: current)
                }
            } else {
                parent = current
                child = storage[current].firstChild
                continue
            }
            child = storage[current].next
        }
    }

    // Runs after the email autolink pass, which finds an address's source range through the text's source segments.
    mutating func writeLineEndingsAsLineFeeds(inTextOf root: DocumentStorage.Index) {
        var parent = root
        var child = storage[root].firstChild
        while true {
            guard let current = child else {
                guard storage.ascend(from: &parent, resumingAt: &child, within: root) else {
                    return
                }
                continue
            }
            guard storage[current].kind.isText else {
                parent = current
                child = storage[current].firstChild
                continue
            }
            guard case .literal(let ref) = storage[current].data else {
                preconditionFailure("a text node holds a literal")
            }
            if sourceSegmentsHoldCR(ref) {
                let offset = storage.strings.count
                for i in 0..<ref.count {
                    let chunk = storage.segments[ref.first + i].chunk
                    if chunk.inSource {
                        appendWritingLineEndingsAsLineFeeds(chunk.range)
                    } else {
                        // A CR decoded from a character reference is text, not a line ending. The arena can't be read
                        // through a span while it grows, so its bytes are copied one at a time.
                        for k in chunk.range {
                            storage.strings.append(storage.strings[k])
                        }
                    }
                }
                storage[current].data = .literal(storage.intern(arenaChunk(from: offset)))
            }
            child = storage[current].next
        }
    }

    private func sourceSegmentsHoldCR(_ ref: ContentRef) -> Bool {
        for i in 0..<ref.count {
            let chunk = storage.segments[ref.first + i].chunk
            if chunk.inSource, firstCR(in: chunk.range) < chunk.range.upperBound {
                return true
            }
        }
        return false
    }

    private mutating func appendSegments(of ref: ContentRef) {
        // Each segment is read into a local before appending, so the read access ends before the mutating append - no aliasing of the growing `segments` pool.
        for i in 0..<ref.count {
            let seg = storage.segments[ref.first + i]
            storage.segments.append(seg)
        }
    }

    /// Merge `source` into the preceding text node `dest`, unlinking `source`.
    ///
    /// When the two runs are pool-contiguous (the common case for adjacent text) this just widens `dest`'s `ContentRef` - no new segments.
    private mutating func mergeTextNode(_ source: DocumentStorage.Index, into dest: DocumentStorage.Index) {
        guard case .literal(let destRef) = storage[dest].data,
              case .literal(let srcRef) = storage[source].data else {
            preconditionFailure("a text node holds a literal")
        }
        // A destination ending the pool grows by copies of the source's segments alone, since re-copying it per
        // sibling would make a long run quadratic.
        let isContiguous = destRef.first + destRef.count == srcRef.first
        let endsPool = destRef.first + destRef.count == storage.segments.count
        let first = isContiguous || endsPool ? destRef.first : storage.segments.count
        if !isContiguous {
            if !endsPool {
                appendSegments(of: destRef)
            }
            appendSegments(of: srcRef)
        }
        storage[dest].data = .literal(ContentRef(
            first: first,
            count: destRef.count + srcRef.count,
            totalLength: destRef.totalLength + srcRef.totalLength
        ))
        if positionsEnabled {
            let a = storage.sourceRanges[dest]
            let b = storage.sourceRanges[source]
            precondition(a.start >= 0 && b.start >= 0, "with `.sourcePosition`, every text node is stamped before it consolidates")
            storage.sourceRanges[dest] = DocumentStorage.SourceByteRange(
                start: a.start,
                end: b.end
            )
        }
        storage.unlinkChild(source)
    }

    // This runs after emphasis resolution, so a `_` or `*` beside an email is resolved before the email's boundaries are.
    mutating func gfmEmailAutolinkPass(_ root: DocumentStorage.Index, image: ContentImage?) {
        var parent = root
        var child = storage[root].firstChild
        while true {
            guard let current = child else {
                guard storage.ascend(from: &parent, resumingAt: &child, within: root) else {
                    return
                }
                continue
            }
            // Taken before the split, so resuming here skips the nodes the split inserts.
            let next = storage[current].next
            switch storage[current].kind {
            case .text:
                splitEmailsInTextNode(current, parent: parent, image: image)
            case .link:
                // Links may not contain other links (Links).
                break
            default:
                parent = current
                child = storage[current].firstChild
                continue
            }
            child = next
        }
    }

    // A text run takes its side of the node's range instead of mapping its bytes, because a run that isn't all source
    // bytes, such as a smart quote, can't be mapped.
    private mutating func splitEmailsInTextNode(_ node: DocumentStorage.Index, parent: DocumentStorage.Index, image: ContentImage?) {
        guard case .literal(let ref) = storage[node].data else {
            preconditionFailure("a text node holds a literal")
        }
        // Checking first spares a text node without an `@` the copy below.
        if !contentRefContains(ref, byte: UInt8(ascii: "@")) {
            return
        }
        // `content` borrows the source or `scratch`, never the arena, which the storage mutations below grow.
        // Content of several segments is joined in `scratch` too, so it is read as one span.
        let firstChunk = storage.segments[ref.first].chunk
        let inPlace = ref.count == 1 && firstChunk.inSource
        var copy = UniqueArray<UInt8>()
        if !inPlace {
            materialize(ref, into: &copy)
        }
        let scratch = copy
        let content = inPlace
            ? ContentSpan(span: sourceBytes.extracting(firstChunk.range), base: firstChunk.offset, inSource: true)
            : ContentSpan(span: scratch.span, base: 0, inSource: false)
        let origin = content.startOffset
        let total = content.endOffset

        var current = node
        var segStart = origin
        var localBound = origin
        var carve = ContentRefCarvePosition()
        var didSplit = false
        var i = origin
        var resumeAt = origin
        // Read before the first split shortens `node`'s range.
        let nodeEnd = positionsEnabled ? storage.sourceRanges[node].end : -1
        while i < total {
            guard content[i] == UInt8(ascii: "@") else {
                i += 1
                continue
            }
            guard let auto = matchGFMEmailAutolink(
                at: i, localBound: localBound, content: content, resumeAt: &resumeAt
            ) else {
                // Moving `localBound` too keeps a `+` or `.` that ended the domain from pulling the abandoned
                // candidate into the next local part.
                localBound = resumeAt
                i = resumeAt
                continue
            }
            let beforeRef = subContentRef(of: ref, from: segStart - origin, to: auto.urlStart - origin, resumingAt: &carve)
            storage[current].data = .literal(beforeRef)
            let emailRef = subContentRef(of: ref, from: auto.urlStart - origin, to: auto.urlEnd - origin, resumingAt: &carve)
            let email = positionsEnabled ? sourceSpan(of: emailRef, image: image) : nil
            if let email {
                let currentStart = storage.sourceRanges[current].start
                precondition(currentStart >= 0, "a text run is placed before an address splits it")
                storage.setSourceStart(current, min(currentStart, email.start))
                storage.setSourceEnd(current, email.start)
            }

            // A URL is read as one span, so a destination of several segments is joined in the arena.
            let urlRef = auto.destinationPrefix.isEmpty && emailRef.count == 1
                ? emailRef
                : materializeURL(prefix: auto.destinationPrefix, for: emailRef)
            let linkIdx = storage.appendNode(NodeRecord(
                kind: .link, parent: parent, data: .link(url: urlRef, title: .empty)))
            let childIdx = storage.appendNode(NodeRecord(
                kind: .text, parent: linkIdx, data: .literal(emailRef)))
            storage.appendChild(childIdx, to: linkIdx)
            storage.insertChildAfter(linkIdx, after: current)
            if let email {
                for idx in [linkIdx, childIdx] {
                    storage.setSourceStart(idx, email.start)
                    storage.setSourceEnd(idx, email.end)
                }
            }

            // The tail's content is carved once its end is known, since carving the whole tail per address would
            // re-copy a long run's segments each time.
            let tailIdx = storage.appendNode(NodeRecord(
                kind: .text, parent: parent, data: .literal(.empty)))
            storage.insertChildAfter(tailIdx, after: linkIdx)
            if let email {
                storage.setSourceStart(tailIdx, email.end)
                storage.setSourceEnd(tailIdx, max(nodeEnd, email.end))
            }

            if beforeRef.totalLength == 0 {
                storage.unlinkChild(current)
            }
            current = tailIdx
            segStart = auto.urlEnd
            localBound = auto.urlEnd
            i = auto.urlEnd
            didSplit = true
        }
        if didSplit {
            let afterRef = subContentRef(of: ref, from: segStart - origin, to: total - origin, resumingAt: &carve)
            storage[current].data = .literal(afterRef)
            if afterRef.totalLength == 0 {
                storage.unlinkChild(current)
            }
        }
    }

    private func contentRefContains(_ ref: ContentRef, byte target: UInt8) -> Bool {
        for s in 0..<ref.count {
            let chunk = storage.segments[ref.first + s].chunk
            // Every text node is scanned, so the source or arena buffer is chosen once per segment rather than per byte.
            let bytes = (chunk.inSource ? sourceBytes : storage.strings.span).extracting(chunk.range)
            for k in 0..<bytes.count where bytes[k] == target { return true }
        }
        return false
    }

    private func materialize(_ ref: ContentRef, into out: inout UniqueArray<UInt8>) {
        for s in 0..<ref.count {
            let chunk = storage.segments[ref.first + s].chunk
            for k in chunk.range { out.append(readByte(at: k, in: chunk)) }
        }
    }

    private struct ContentRefCarvePosition {
        var segment = 0
        var start = 0
    }

    // Resuming from `position`, a left-to-right series of carves visits each segment of `ref` a bounded number of
    // times in total.
    private mutating func subContentRef(of ref: ContentRef, from lo: Int, to hi: Int, resumingAt position: inout ContentRefCarvePosition) -> ContentRef {
        if hi <= lo {
            return .empty
        }
        precondition(position.start <= lo, "a carve starts at or after the segment it resumes from")
        let refFirst = ref.first
        let refCount = ref.count
        let newFirst = storage.segments.count
        var count = 0
        var total = 0
        var v = position.start
        for s in position.segment..<refCount {
            let seg = storage.segments[refFirst + s]
            let segLen = seg.length
            let segStart = v
            if segStart >= hi {
                break
            }
            position = ContentRefCarvePosition(segment: s, start: segStart)
            v += segLen
            let pieceLo = max(lo, segStart)
            let pieceHi = min(hi, v)
            if pieceHi <= pieceLo {
                continue
            }
            let localOffset = pieceLo - segStart
            let pieceLen = pieceHi - pieceLo
            storage.segments.append(Segment(
                offset: seg.offset + localOffset,
                length: pieceLen,
                inSource: seg.inSource
            ))
            count += 1
            total += pieceLen
        }
        precondition(count > 0, "a non-empty sub-range of a text node overlaps at least one of its segments")
        return ContentRef(first: newFirst, count: count, totalLength: total)
    }

    // The bytes go through a local buffer because they may be in the arena, which the copy grows.
    private mutating func materializeURL(prefix: String, for emailRef: ContentRef) -> ContentRef {
        var buf = UniqueArray<UInt8>()
        for b in prefix.utf8 {
            buf.append(b)
        }
        materialize(emailRef, into: &buf)
        let offset = storage.strings.count
        for k in 0..<buf.count {
            storage.strings.append(buf[k])
        }
        return storage.intern(Chunk(offset: offset, length: buf.count, inSource: false))
    }

    private mutating func sourceSpan(of ref: ContentRef, image: ContentImage?) -> (start: Int, end: Int) {
        precondition(ref.count > 0 && ref.totalLength > 0, "an email address holds at least one byte")
        let firstSeg = storage.segments[ref.first]
        let lastSeg = storage.segments[ref.first + ref.count - 1]
        let first = escapeSource(endingAt: sourceRange(of: firstSeg, local: 0, image: image))
        let last = sourceRange(of: lastSeg, local: lastSeg.length - 1, image: image)
        return (first.lowerBound, last.upperBound)
    }

    // Backslashes before `bytes` pair off from the first (Backslash escapes), so an odd run ends in an
    // escape's backslash.
    private func escapeSource(endingAt bytes: Range<Int>) -> Range<Int> {
        guard sourceBytes[bytes.lowerBound].isASCIIPunct else {
            return bytes
        }
        var runStart = bytes.lowerBound
        while runStart > 0 && sourceBytes[runStart - 1] == UInt8(ascii: "\\") {
            runStart -= 1
        }
        return (bytes.lowerBound - runStart) % 2 == 1 ? (bytes.lowerBound - 1)..<bytes.upperBound : bytes
    }

    // Arena text that is neither imaged nor a decoded character reference is smart punctuation, which no address holds.
    private func sourceRange(of seg: Segment, local: Int, image: ContentImage?) -> Range<Int> {
        if seg.inSource {
            let offset = seg.offset + local
            return offset..<(offset + 1)
        }
        let arena = seg.offset + local
        if let offset = image?.sourceOffset(ofArenaByte: arena) {
            return offset..<(offset + 1)
        }
        return characterReferenceSource(ofArenaByte: arena)
    }

    private func characterReferenceSource(ofArenaByte offset: Int) -> Range<Int> {
        var lo = 0
        var hi = characterReferenceSources.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if characterReferenceSources[mid].arena.upperBound > offset {
                hi = mid
            } else {
                lo = mid + 1
            }
        }
        precondition(lo < characterReferenceSources.count && characterReferenceSources[lo].arena.contains(offset), "an address's arena byte outside the leaf's content comes from a character reference")
        return characterReferenceSources[lo].source
    }
}
