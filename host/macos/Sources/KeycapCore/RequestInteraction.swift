// SPDX-License-Identifier: Apache-2.0
import Foundation

public struct RequestInteraction: Equatable, Sendable {
    public let request: AgentRequest
    public let pageSize: Int
    public let requiresConfirmation: Bool
    public private(set) var pageIndex = 0
    public private(set) var selectedChoiceIDs: Set<String> = []
    public private(set) var pendingConfirmationChoiceID: String?

    public init(request: AgentRequest, pageSize: Int = 4, requiresConfirmation: Bool = false) {
        self.request = request
        self.pageSize = max(pageSize, 1)
        self.requiresConfirmation = requiresConfirmation
    }

    public var pageCount: Int {
        max(1, Int(ceil(Double(request.choices.count) / Double(pageSize))))
    }

    public var visibleChoices: ArraySlice<Choice> {
        let start = min(pageIndex * pageSize, request.choices.count)
        let end = min(start + pageSize, request.choices.count)
        return request.choices[start..<end]
    }

    public var canGoPrevious: Bool { pageIndex > 0 }
    public var canGoNext: Bool { pageIndex + 1 < pageCount }
    public var allowsMultiple: Bool { request.allowsMultiple == true }
    public var canSubmit: Bool {
        allowsMultiple ? !selectedChoiceIDs.isEmpty : pendingConfirmationChoiceID != nil
    }

    /// Whether a bare key press may resolve the request without waiting for the
    /// debounced gesture.
    ///
    /// Paginated requests must decline: the host resolves an immediate press on
    /// `BUTTON … DOWN`, which would consume the long press that pages between
    /// choices and strand every option after the fourth.
    public var acceptsImmediateSelection: Bool {
        !allowsMultiple && !requiresConfirmation && pageCount == 1
    }

    /// The controls the overlay must offer for the current state, ordered as
    /// they are laid out: pagination first, then the trailing selection group.
    public var controls: [InteractionControl] {
        var controls: [InteractionControl] = []
        if pageCount > 1 {
            controls.append(.previousPage(enabled: canGoPrevious))
            controls.append(.nextPage(enabled: canGoNext))
        }
        if allowsMultiple {
            controls.append(.clearSelection(enabled: !selectedChoiceIDs.isEmpty))
            controls.append(.submitSelection(
                count: selectedChoiceIDs.count, enabled: canSubmit
            ))
        } else if requiresConfirmation {
            controls.append(.confirmSelection(
                armed: pendingConfirmationChoiceID != nil, enabled: canSubmit
            ))
        }
        return controls
    }

    @discardableResult
    public mutating func selectVisibleChoice(number: Int) -> InteractionOutcome {
        let localIndex = number - 1
        guard visibleChoices.indices.contains(pageIndex * pageSize + localIndex) else {
            return .unchanged
        }
        let choice = request.choices[pageIndex * pageSize + localIndex]
        if allowsMultiple {
            if selectedChoiceIDs.contains(choice.id) {
                selectedChoiceIDs.remove(choice.id)
            } else {
                selectedChoiceIDs.insert(choice.id)
            }
            return .updated
        }
        if requiresConfirmation {
            pendingConfirmationChoiceID = choice.id
            return .updated
        }
        return .resolved([choice.id])
    }

    @discardableResult
    public mutating func goToPreviousPage() -> InteractionOutcome {
        guard canGoPrevious else { return .unchanged }
        pageIndex -= 1
        return .updated
    }

    @discardableResult
    public mutating func goToNextPage() -> InteractionOutcome {
        guard canGoNext else { return .unchanged }
        pageIndex += 1
        return .updated
    }

    @discardableResult
    public mutating func clearSelection() -> InteractionOutcome {
        guard !selectedChoiceIDs.isEmpty else { return .unchanged }
        selectedChoiceIDs.removeAll()
        return .updated
    }

    public func submit() -> InteractionOutcome {
        guard canSubmit else { return .unchanged }
        if allowsMultiple {
            let ordered = request.choices.compactMap {
                selectedChoiceIDs.contains($0.id) ? $0.id : nil
            }
            return .resolved(ordered)
        }
        return .resolved([pendingConfirmationChoiceID!])
    }

    /// Short instructions for the gestures nobody would otherwise discover.
    ///
    /// A short press selects, and people find that immediately. Submitting a
    /// multi-select, clearing it, paging, and confirming a destructive choice
    /// all need a long or double press that nothing on screen mentions, which
    /// is how a working overlay comes to look like one that cannot be
    /// finished. At most two are returned so the status line stays readable.
    ///
    /// The gestures are configurable, so the hints are derived from the
    /// mapping in force rather than assumed: a remapped long press earns no
    /// hint instead of a wrong one.
    public func gestureHints(longPress: String, doublePress: String) -> [String] {
        var hints: [String] = []
        let contextual = longPress == "contextual"

        if requiresConfirmation {
            if contextual, let choiceID = pendingConfirmationChoiceID,
               let index = request.choices.firstIndex(where: { $0.id == choiceID }) {
                hints.append("HOLD KEY \(index % pageSize + 1) TO CONFIRM")
            }
            return hints
        }

        if allowsMultiple && contextual {
            hints.append("HOLD KEY 4 TO SUBMIT")
            if !selectedChoiceIDs.isEmpty {
                hints.append("HOLD KEY 2 TO CLEAR")
            }
        }

        if pageCount > 1 && hints.count < 2 {
            if doublePress == "navigate" {
                hints.append("DOUBLE-PRESS 1 OR 4 TO PAGE")
            } else if contextual && !allowsMultiple {
                // A multi-select long press on key 4 submits, so it cannot also
                // page forward; only the double press can.
                hints.append("HOLD KEY 1 OR 4 TO PAGE")
            }
        }
        return hints
    }

    public func confirmVisibleChoice(number: Int) -> InteractionOutcome {
        let index = pageIndex * pageSize + number - 1
        guard request.choices.indices.contains(index),
              request.choices[index].id == pendingConfirmationChoiceID else { return .unchanged }
        return .resolved([request.choices[index].id])
    }
}

public enum InteractionOutcome: Equatable, Sendable {
    case unchanged
    case updated
    case resolved([String])
}

public enum InteractionControl: Equatable, Sendable {
    case previousPage(enabled: Bool)
    case nextPage(enabled: Bool)
    case clearSelection(enabled: Bool)
    case submitSelection(count: Int, enabled: Bool)
    case confirmSelection(armed: Bool, enabled: Bool)

    /// Pagination sits on the leading edge; everything else is pushed right.
    public var isPagination: Bool {
        switch self {
        case .previousPage, .nextPage: return true
        case .clearSelection, .submitSelection, .confirmSelection: return false
        }
    }

    public var isEnabled: Bool {
        switch self {
        case .previousPage(let enabled), .nextPage(let enabled),
             .clearSelection(let enabled), .submitSelection(_, let enabled),
             .confirmSelection(_, let enabled):
            return enabled
        }
    }

    public var title: String {
        switch self {
        case .previousPage: return "Previous"
        case .nextPage: return "Next"
        case .clearSelection: return "Clear"
        case .submitSelection(let count, _): return "Submit \(count)"
        case .confirmSelection(let armed, _):
            return armed ? "Confirm selection" : "Select an option"
        }
    }

    public var isEmphasized: Bool {
        switch self {
        case .submitSelection, .confirmSelection: return true
        case .previousPage, .nextPage, .clearSelection: return false
        }
    }
}
