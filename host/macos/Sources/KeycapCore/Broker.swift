// SPDX-License-Identifier: Apache-2.0
import Foundation

@MainActor
public final class RequestBroker {
    public typealias Completion = (AgentResolution) -> Void

    private struct Pending {
        let request: AgentRequest
        let completion: Completion
        var timeoutTask: Task<Void, Never>?
    }

    private var pending: [Pending] = []
    private var completedRequestIDs: [String] = []
    private var completedRequestIDSet: Set<String> = []
    private let completedRequestLimit = 256
    private let maximumQueueDepth = 64
    public var onChange: ((AgentRequest?, Int) -> Void)?
    public var active: AgentRequest? { pending.first?.request }
    public var count: Int { pending.count }
    public private(set) var isPaused = false

    public init() {}

    @discardableResult
    public func submit(_ request: AgentRequest, completion: @escaping Completion) -> Bool {
        submitResult(request, completion: completion) == .accepted
    }

    @discardableResult
    public func submitResult(
        _ request: AgentRequest,
        completion: @escaping Completion
    ) -> SubmissionResult {
        guard !isPaused else { return .paused }
        guard pending.count < maximumQueueDepth else { return .full }
        guard isValid(request) else { return .invalid }
        guard !pending.contains(where: { $0.request.id == request.id }),
              !completedRequestIDSet.contains(request.id) else {
            return .duplicate
        }

        pending.append(Pending(request: request, completion: completion, timeoutTask: nil))
        if let timeout = request.timeoutSeconds, timeout > 0 {
            let requestID = request.id
            pending[pending.count - 1].timeoutTask = Task { @MainActor [weak self] in
                let nanoseconds = UInt64(min(timeout, 86_400) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                _ = self?.cancel(requestID: requestID, reason: "timeout")
            }
        }
        notify()
        return .accepted
    }

    @discardableResult
    public func resolve(choiceNumber: Int) -> AgentResponse? {
        guard let current = pending.first,
              current.request.choices.indices.contains(choiceNumber - 1) else {
            return nil
        }

        return resolve(choiceIDs: [current.request.choices[choiceNumber - 1].id])
    }

    @discardableResult
    public func resolve(choiceIDs: [String]) -> AgentResponse? {
        guard let current = pending.first, !choiceIDs.isEmpty,
              (current.request.allowsMultiple == true || choiceIDs.count == 1),
              Set(choiceIDs).count == choiceIDs.count else {
            return nil
        }

        let indices = choiceIDs.compactMap { choiceID in
            current.request.choices.firstIndex(where: { $0.id == choiceID })
        }
        guard indices.count == choiceIDs.count else { return nil }

        let choiceIndex = indices[0]
        let choice = current.request.choices[choiceIndex]
        let response = AgentResponse(
            requestId: current.request.id,
            choiceId: choice.id,
            choiceIndex: choiceIndex,
            choiceIds: choiceIDs
        )
        pending.removeFirst()
        current.timeoutTask?.cancel()
        rememberCompleted(current.request.id)
        current.completion(.selected(response))
        notify()
        return response
    }

    @discardableResult
    public func cancelActive(reason: String? = "user") -> AgentCancellation? {
        guard let requestID = active?.id else { return nil }
        return cancel(requestID: requestID, reason: reason)
    }

    @discardableResult
    public func cancel(requestID: String, reason: String? = nil) -> AgentCancellation? {
        guard let index = pending.firstIndex(where: { $0.request.id == requestID }) else {
            return nil
        }
        let current = pending.remove(at: index)
        current.timeoutTask?.cancel()
        rememberCompleted(current.request.id)
        let cancellation = AgentCancellation(requestId: current.request.id, reason: reason)
        current.completion(.cancelled(cancellation))
        notify()
        return cancellation
    }

    @discardableResult
    public func cancel(session: String, reason: String? = nil) -> Int {
        let requestIDs = pending.compactMap { pending in
            pending.request.session == session ? pending.request.id : nil
        }
        requestIDs.forEach { _ = cancel(requestID: $0, reason: reason) }
        return requestIDs.count
    }

    public func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if paused {
            let requestIDs = pending.map(\.request.id)
            requestIDs.forEach { _ = cancel(requestID: $0, reason: "host-paused") }
        } else {
            notify()
        }
    }

    private func isValid(_ request: AgentRequest) -> Bool {
        !request.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        request.title.utf8.count <= 4_096 &&
        (request.detail?.utf8.count ?? 0) <= 65_536 &&
        (1...16).contains(request.choices.count) &&
        Set(request.choices.map(\.id)).count == request.choices.count &&
        request.choices.allSatisfy {
            !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && $0.id.utf8.count <= 256 && $0.label.utf8.count <= 4_096
            && ($0.description?.utf8.count ?? 0) <= 16_384
        } &&
        (request.progress.map { $0.total > 0 && (1...$0.total).contains($0.current) } ?? true) &&
        (request.timeoutSeconds.map { $0.isFinite && $0 > 0 } ?? true) &&
        (request.accentColor.map {
            $0.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
        } ?? true)
    }

    private func rememberCompleted(_ requestID: String) {
        completedRequestIDs.append(requestID)
        completedRequestIDSet.insert(requestID)
        if completedRequestIDs.count > completedRequestLimit {
            let expired = completedRequestIDs.removeFirst()
            completedRequestIDSet.remove(expired)
        }
    }

    private func notify() {
        onChange?(active, pending.count)
    }
}

public enum SubmissionResult: Equatable, Sendable {
    case accepted
    case invalid
    case duplicate
    case paused
    case full
}
