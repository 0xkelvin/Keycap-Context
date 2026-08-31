// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import KeycapCore

final class KeycapCoreTests: XCTestCase {
    func testLightingProfileNormalizesPersistedValues() throws {
        let data = Data(#"""
        {
            "mode":"wave",
            "brightness":900,
            "speed":0,
            "keyColors":["not-a-color"]
        }
        """#.utf8)
        let profile = try JSONDecoder().decode(LightingProfile.self, from: data)

        XCTAssertEqual(profile.mode, .wave)
        XCTAssertEqual(profile.brightness, 100)
        XCTAssertEqual(profile.speed, 1)
        XCTAssertEqual(profile.keyColors, ["00FF20", "0070FF", "DC00FF", "FF4800"])
    }

    func testPagedInteractionResolvesVisibleChoice() {
        let request = AgentRequest(
            source: "test", kind: "question", title: "Paged",
            choices: (1...6).map { Choice(id: "c\($0)", label: "Choice \($0)") }
        )
        var interaction = RequestInteraction(request: request)

        XCTAssertEqual(interaction.pageCount, 2)
        XCTAssertEqual(interaction.goToNextPage(), .updated)
        XCTAssertEqual(interaction.visibleChoices.map(\.id), ["c5", "c6"])
        XCTAssertEqual(interaction.selectVisibleChoice(number: 2), .resolved(["c6"]))
    }

    func testMultiSelectTogglesAndSubmitsInRequestOrder() {
        let request = AgentRequest(
            source: "test", kind: "question", title: "Multiple",
            choices: (1...4).map { Choice(id: "c\($0)", label: "Choice \($0)") },
            allowsMultiple: true
        )
        var interaction = RequestInteraction(request: request)

        XCTAssertEqual(interaction.selectVisibleChoice(number: 3), .updated)
        XCTAssertEqual(interaction.selectVisibleChoice(number: 1), .updated)
        XCTAssertEqual(interaction.submit(), .resolved(["c1", "c3"]))
        XCTAssertEqual(interaction.selectVisibleChoice(number: 3), .updated)
        XCTAssertEqual(interaction.submit(), .resolved(["c1"]))
    }

    func testMultiSelectOffersSubmitControl() {
        let request = AgentRequest(
            source: "test", kind: "question", title: "Multiple",
            choices: (1...4).map { Choice(id: "c\($0)", label: "Choice \($0)") },
            allowsMultiple: true
        )
        var interaction = RequestInteraction(request: request)

        XCTAssertEqual(interaction.controls, [
            .clearSelection(enabled: false), .submitSelection(count: 0, enabled: false),
        ])
        XCTAssertEqual(interaction.selectVisibleChoice(number: 2), .updated)
        XCTAssertEqual(interaction.controls, [
            .clearSelection(enabled: true), .submitSelection(count: 1, enabled: true),
        ])
    }

    func testConfirmationOffersOnlyOneSubmitControl() {
        let request = AgentRequest(
            source: "test", kind: "permission", title: "Destructive",
            choices: (1...2).map { Choice(id: "c\($0)", label: "Choice \($0)") },
            risk: .destructive
        )
        var interaction = RequestInteraction(request: request, requiresConfirmation: true)

        XCTAssertEqual(interaction.controls, [.confirmSelection(armed: false, enabled: false)])
        XCTAssertEqual(interaction.controls.map(\.title), ["Select an option"])
        XCTAssertEqual(interaction.selectVisibleChoice(number: 1), .updated)
        XCTAssertEqual(interaction.controls, [.confirmSelection(armed: true, enabled: true)])
        XCTAssertEqual(interaction.controls.map(\.title), ["Confirm selection"])
    }

    func testPaginationControlsPrecedeSelectionControls() {
        let request = AgentRequest(
            source: "test", kind: "question", title: "Paged multi-select",
            choices: (1...6).map { Choice(id: "c\($0)", label: "Choice \($0)") },
            allowsMultiple: true
        )
        let interaction = RequestInteraction(request: request)

        XCTAssertEqual(interaction.controls, [
            .previousPage(enabled: false), .nextPage(enabled: true),
            .clearSelection(enabled: false), .submitSelection(count: 0, enabled: false),
        ])
        XCTAssertEqual(interaction.controls.map(\.isPagination), [true, true, false, false])
    }

    func testSingleChoiceRequestNeedsNoControls() {
        let request = AgentRequest(
            source: "test", kind: "question", title: "Simple",
            choices: (1...3).map { Choice(id: "c\($0)", label: "Choice \($0)") }
        )
        XCTAssertTrue(RequestInteraction(request: request).controls.isEmpty)
    }

    func testPaginatedRequestDeclinesImmediateSelection() {
        let paged = AgentRequest(
            source: "test", kind: "question", title: "Paged",
            choices: (1...6).map { Choice(id: "c\($0)", label: "Choice \($0)") }
        )
        // An immediate BUTTON DOWN would resolve choice 1 before the long press
        // that pages forward, stranding choices five and six.
        XCTAssertFalse(RequestInteraction(request: paged).acceptsImmediateSelection)

        let single = AgentRequest(
            source: "test", kind: "question", title: "Single page",
            choices: (1...4).map { Choice(id: "c\($0)", label: "Choice \($0)") }
        )
        XCTAssertTrue(RequestInteraction(request: single).acceptsImmediateSelection)
        XCTAssertFalse(
            RequestInteraction(request: single, requiresConfirmation: true)
                .acceptsImmediateSelection
        )

        let multiple = AgentRequest(
            source: "test", kind: "question", title: "Multiple",
            choices: (1...4).map { Choice(id: "c\($0)", label: "Choice \($0)") },
            allowsMultiple: true
        )
        XCTAssertFalse(RequestInteraction(request: multiple).acceptsImmediateSelection)
    }

    func testAuthorizationRequiresMatchingToken() {
        let base = ["host": "127.0.0.1:47821"]
        XCTAssertEqual(
            RequestAuthorization.evaluate(
                headers: base.merging(["authorization": "Bearer secret"]) { $1 },
                token: "secret"
            ), .allowed
        )
        XCTAssertEqual(
            RequestAuthorization.evaluate(
                headers: base.merging(["x-keycap-token": "secret"]) { $1 }, token: "secret"
            ), .allowed
        )
        XCTAssertEqual(
            RequestAuthorization.evaluate(headers: base, token: "secret"), .unauthorized
        )
        XCTAssertEqual(
            RequestAuthorization.evaluate(
                headers: base.merging(["authorization": "Bearer wrong"]) { $1 },
                token: "secret"
            ), .unauthorized
        )
        // Header names arrive in whatever case the client sent them.
        XCTAssertEqual(
            RequestAuthorization.evaluate(
                headers: ["Host": "localhost:47821", "Authorization": "bearer secret"],
                token: "secret"
            ), .allowed
        )
    }

    func testAuthorizationFailsClosedWithoutAConfiguredToken() {
        XCTAssertEqual(
            RequestAuthorization.evaluate(
                headers: ["host": "127.0.0.1:47821", "authorization": "Bearer "],
                token: ""
            ), .unauthorized
        )
    }

    func testAuthorizationRejectsBrowserOriginatedRequests() {
        // A CORS-simple POST from any page the user visits reaches the broker
        // with a loopback Host header and, if known, a valid token.
        let headers = [
            "host": "127.0.0.1:47821",
            "authorization": "Bearer secret",
            "origin": "https://evil.example",
        ]
        XCTAssertEqual(RequestAuthorization.evaluate(headers: headers, token: "secret"), .crossSite)

        // Sandboxed and local-file browser contexts serialize their origin as
        // `null`; it is still browser metadata and must not bypass the guard.
        XCTAssertEqual(
            RequestAuthorization.evaluate(
                headers: [
                    "host": "127.0.0.1:47821",
                    "authorization": "Bearer secret",
                    "origin": "null",
                ],
                token: "secret"
            ), .crossSite
        )

        XCTAssertEqual(
            RequestAuthorization.evaluate(
                headers: [
                    "host": "127.0.0.1:47821",
                    "authorization": "Bearer secret",
                    "sec-fetch-site": "cross-site",
                ],
                token: "secret"
            ), .crossSite
        )
        XCTAssertEqual(
            RequestAuthorization.evaluate(
                headers: [
                    "host": "127.0.0.1:47821",
                    "authorization": "Bearer secret",
                    "sec-fetch-site": "none",
                ],
                token: "secret"
            ), .allowed
        )
    }

    func testAuthorizationRejectsNonLoopbackHosts() {
        for host in ["keycap.example", "192.168.1.4:47821", "[2001:db8::1]:47821", ""] {
            XCTAssertEqual(
                RequestAuthorization.evaluate(
                    headers: ["host": host, "authorization": "Bearer secret"],
                    token: "secret"
                ), .untrustedHost, "\(host) must not be treated as loopback"
            )
        }
        XCTAssertEqual(
            RequestAuthorization.evaluate(
                headers: ["authorization": "Bearer secret"], token: "secret"
            ), .untrustedHost
        )
        XCTAssertTrue(RequestAuthorization.isLoopbackHost("[::1]:47821"))
    }

    func testConstantTimeComparisonMatchesEquality() {
        XCTAssertTrue(RequestAuthorization.constantTimeEquals("abc", "abc"))
        XCTAssertFalse(RequestAuthorization.constantTimeEquals("abc", "abd"))
        XCTAssertFalse(RequestAuthorization.constantTimeEquals("abc", "abcd"))
        XCTAssertFalse(RequestAuthorization.constantTimeEquals("", "a"))
        XCTAssertTrue(RequestAuthorization.constantTimeEquals("", ""))
    }

    func testOnlyDeviceRepliesProveTheLinkIsBidirectional() {
        // A half-open link still delivers button traffic. Treating that as
        // liveness lets a user keep a dead link alive by pressing keys.
        XCTAssertTrue(
            DeviceEvent.hello(version: 3, firmware: "keycap-fw", board: "xiao")
                .provesDeviceIsListening
        )
        XCTAssertFalse(DeviceEvent.button(key: 1, isDown: true, sequence: 1).provesDeviceIsListening)
        XCTAssertFalse(
            DeviceEvent.gesture(key: 1, kind: .short, sequence: 2).provesDeviceIsListening
        )
        XCTAssertFalse(DeviceEvent.error(code: "i2c-write").provesDeviceIsListening)
    }

    func testUnknownLightingModeDoesNotDiscardOtherSettings() throws {
        // A host without a newer effect must still load the rest of the file.
        let json = Data(#"""
            {"mode": "disco", "brightness": 42, "speed": 7,
             "keyColors": ["112233", "445566", "778899", "AABBCC"]}
            """#.utf8)
        let profile = try JSONDecoder().decode(LightingProfile.self, from: json)

        XCTAssertEqual(profile.mode, .rainbow)
        XCTAssertEqual(profile.brightness, 42)
        XCTAssertEqual(profile.speed, 7)
        XCTAssertEqual(profile.keyColors, ["112233", "445566", "778899", "AABBCC"])
    }

    func testAudioModesAreWireEncodedForTheDevice() {
        XCTAssertEqual(
            DeviceProtocolV2.lighting(LightingProfile(mode: .audio, brightness: 93, speed: 85)),
            "LIGHTING AUDIO 93 85 00FF20,0070FF,DC00FF,FF4800\n"
        )
        XCTAssertEqual(
            DeviceProtocolV2.lighting(LightingProfile(mode: .spectrum, brightness: 70, speed: 50)),
            "LIGHTING SPECTRUM 70 50 00FF20,0070FF,DC00FF,FF4800\n"
        )
        XCTAssertEqual(
            DeviceProtocolV2.lighting(LightingProfile(mode: .pitch, brightness: 60, speed: 40)),
            "LIGHTING PITCH 60 40 00FF20,0070FF,DC00FF,FF4800\n"
        )
        // Every audio effect must be offered in Settings.
        for mode in [LightingMode.audio, .spectrum, .pitch] {
            XCTAssertTrue(LightingMode.allCases.contains(mode), "\(mode) missing")
        }
    }

    func testParsesButton() {
        XCTAssertEqual(
            DeviceProtocolV1.parse("BUTTON 3 DOWN 42\n"),
            .button(key: 3, isDown: true, sequence: 42)
        )
        XCTAssertNil(DeviceProtocolV1.parse("BUTTON 5 DOWN 42"))
    }

    func testParsesGesture() {
        XCTAssertEqual(
            DeviceProtocolV1.parse("GESTURE 4 DOUBLE 43\n"),
            .gesture(key: 4, kind: .double, sequence: 43)
        )
        XCTAssertNil(DeviceProtocolV1.parse("GESTURE 5 SHORT 44"))
    }

    func testFormatsSemanticDeviceStatus() {
        XCTAssertEqual(DeviceProtocolV2.status(.idle), "STATUS IDLE\n")
        XCTAssertEqual(
            DeviceProtocolV2.status(.waiting(activeChoices: 3)),
            "STATUS WAITING 3\n"
        )
        XCTAssertEqual(
            DeviceProtocolV2.status(.waiting(activeChoices: 2, colorHex: "10a37f")),
            "STATUS WAITING 2 10A37F\n"
        )
    }

    func testFormatsLightingProfile() {
        let profile = LightingProfile(
            mode: .reactive, brightness: 80, speed: 65,
            keyColors: ["00ff20", "0070ff", "dc00ff", "ff4800"]
        )
        XCTAssertEqual(
            DeviceProtocolV2.lighting(profile),
            "LIGHTING REACTIVE 80 65 00FF20,0070FF,DC00FF,FF4800\n"
        )
    }

    func testFormatsFourAgentLEDStates() {
        XCTAssertEqual(
            DeviceProtocolV3.agents([.working, .waiting, .completed, .failed]),
            "AGENTS WORKING,WAITING,DONE,ERROR\n"
        )
        XCTAssertEqual(
            DeviceProtocolV3.agents([.destructive]),
            "AGENTS RISK,EMPTY,EMPTY,EMPTY\n"
        )
    }

    func testContextProfileMatchesApplicationAndProject() {
        let profile = ContextProfile(
            name: "Terminal project",
            applicationBundleIdentifier: "terminal",
            projectContains: "keycap"
        )
        XCTAssertTrue(profile.matches(
            applicationBundleIdentifier: "com.apple.Terminal",
            project: "Veea-Keycap"
        ))
        XCTAssertFalse(profile.matches(
            applicationBundleIdentifier: "com.apple.Safari",
            project: "Veea-Keycap"
        ))
    }

    @MainActor
    func testAgentConsoleAssignsSlotsAndQueuesControls() {
        let console = AgentConsole()
        XCTAssertNotNil(console.update(AgentStatusUpdate(
            session: "one", source: "Codex", state: .working
        )))
        XCTAssertNotNil(console.update(AgentStatusUpdate(
            session: "two", source: "Claude", state: .completed, preferredKey: 4
        )))

        XCTAssertEqual(console.session(forKey: 1)?.session, "one")
        XCTAssertEqual(console.session(forKey: 4)?.session, "two")
        XCTAssertTrue(console.session(forKey: 4)?.unread == true)
        XCTAssertEqual(console.enqueueControl(key: 1, action: .interrupt)?.session, "one")
        XCTAssertEqual(console.takeCommands(session: "one").map(\.action), [.interrupt])
        XCTAssertTrue(console.takeCommands(session: "one").isEmpty)
        XCTAssertTrue(console.remove(session: "two"))
        XCTAssertNil(console.session(forKey: 4))
    }

    @MainActor
    func testAgentConsoleTracksRequestRiskAndResolutionHistory() {
        let console = AgentConsole()
        let request = AgentRequest(
            id: "r1", source: "Codex", session: "s1", kind: "permission",
            title: "Delete files?", choices: [Choice(id: "allow", label: "Allow")],
            risk: .destructive
        )
        console.noteRequest(request)
        XCTAssertEqual(console.session(forKey: 1)?.state, .waiting)
        XCTAssertTrue(console.session(forKey: 1)?.destructiveApproval == true)

        console.noteResolution(
            request: request,
            resolution: .selected(AgentResponse(
                requestId: "r1", choiceId: "allow", choiceIndex: 0
            ))
        )
        XCTAssertEqual(console.session(forKey: 1)?.state, .working)
        XCTAssertFalse(console.session(forKey: 1)?.destructiveApproval ?? true)
        XCTAssertEqual(console.history.last?.kind, .selected)
    }

    func testDestructiveInteractionRequiresExplicitConfirmation() {
        let request = AgentRequest(
            source: "test", kind: "permission", title: "Delete?",
            choices: [Choice(id: "allow", label: "Allow"), Choice(id: "deny", label: "Deny")],
            risk: .destructive
        )
        var interaction = RequestInteraction(request: request, requiresConfirmation: true)

        XCTAssertEqual(interaction.selectVisibleChoice(number: 1), .updated)
        XCTAssertEqual(interaction.pendingConfirmationChoiceID, "allow")
        XCTAssertEqual(interaction.confirmVisibleChoice(number: 2), .unchanged)
        XCTAssertEqual(interaction.confirmVisibleChoice(number: 1), .resolved(["allow"]))
    }

    func testFormatsLEDs() {
        XCTAssertEqual(
            DeviceProtocolV1.leds(activeChoices: 3),
            "LEDS FFFFFF,FFFFFF,FFFFFF,000000\n"
        )
    }

    @MainActor
    func testBrokerRoutesAndQueues() {
        let broker = RequestBroker()
        var resolutions: [AgentResolution] = []
        let first = AgentRequest(
            id: "one", source: "Claude", kind: "question", title: "First?",
            choices: [Choice(id: "a", label: "A"), Choice(id: "b", label: "B")]
        )
        let second = AgentRequest(
            id: "two", source: "Codex", kind: "approval", title: "Second?",
            choices: [Choice(id: "yes", label: "Yes")]
        )

        XCTAssertTrue(broker.submit(first) { resolutions.append($0) })
        XCTAssertTrue(broker.submit(second) { resolutions.append($0) })
        XCTAssertEqual(broker.count, 2)
        XCTAssertEqual(broker.resolve(choiceNumber: 2)?.choiceId, "b")
        XCTAssertEqual(broker.active?.id, "two")
        XCTAssertEqual(
            resolutions.first,
            .selected(AgentResponse(requestId: "one", choiceId: "b", choiceIndex: 1))
        )
    }

    @MainActor
    func testBrokerCancellationAdvancesQueue() {
        let broker = RequestBroker()
        var resolution: AgentResolution?
        let first = AgentRequest(
            id: "one", source: "Claude", kind: "question", title: "First?",
            choices: [Choice(id: "a", label: "A")]
        )
        let second = AgentRequest(
            id: "two", source: "Claude", kind: "question", title: "Second?",
            choices: [Choice(id: "b", label: "B")]
        )

        XCTAssertTrue(broker.submit(first) { resolution = $0 })
        XCTAssertTrue(broker.submit(second) { _ in })
        XCTAssertEqual(broker.cancelActive()?.requestId, "one")
        XCTAssertEqual(
            resolution,
            .cancelled(AgentCancellation(requestId: "one", reason: "user"))
        )
        XCTAssertEqual(broker.active?.id, "two")
    }

    @MainActor
    func testRejectsDuplicateChoiceIDs() {
        let broker = RequestBroker()
        let request = AgentRequest(
            source: "test", kind: "question", title: "Duplicate",
            choices: [Choice(id: "x", label: "A"), Choice(id: "x", label: "B")]
        )
        XCTAssertFalse(broker.submit(request) { _ in })
    }

    @MainActor
    func testRejectsMoreThanFourChoicesWithoutTruncating() {
        let choices = (1...17).map { Choice(id: "\($0)", label: "Choice \($0)") }
        let request = AgentRequest(
            source: "test", kind: "question", title: "Too many", choices: choices
        )
        XCTAssertEqual(request.choices.count, 17)
        XCTAssertFalse(RequestBroker().submit(request) { _ in })
    }

    @MainActor
    func testAcceptsPagedChoices() {
        let choices = (1...8).map { Choice(id: "\($0)", label: "Choice \($0)") }
        let request = AgentRequest(
            source: "test", kind: "question", title: "Paged", choices: choices
        )

        XCTAssertTrue(RequestBroker().submit(request) { _ in })
    }

    @MainActor
    func testRejectsPendingAndCompletedDuplicateIDs() {
        let broker = RequestBroker()
        let request = AgentRequest(
            id: "same", source: "test", kind: "question", title: "Duplicate",
            choices: [Choice(id: "x", label: "X")]
        )

        XCTAssertEqual(broker.submitResult(request) { _ in }, .accepted)
        XCTAssertEqual(broker.submitResult(request) { _ in }, .duplicate)
        XCTAssertNotNil(broker.resolve(choiceNumber: 1))
        XCTAssertEqual(broker.submitResult(request) { _ in }, .duplicate)
    }

    @MainActor
    func testCancelsDisconnectedRequestByIDWithoutAffectingQueue() {
        let broker = RequestBroker()
        var cancelled: AgentCancellation?
        let first = AgentRequest(
            id: "one", source: "test", kind: "question", title: "First",
            choices: [Choice(id: "x", label: "X")]
        )
        let second = AgentRequest(
            id: "two", source: "test", kind: "question", title: "Second",
            choices: [Choice(id: "y", label: "Y")]
        )

        XCTAssertTrue(broker.submit(first) {
            if case .cancelled(let value) = $0 { cancelled = value }
        })
        XCTAssertTrue(broker.submit(second) { _ in })

        XCTAssertEqual(broker.cancel(requestID: "two", reason: "client-disconnected")?.reason,
                       "client-disconnected")
        XCTAssertEqual(broker.active?.id, "one")
        XCTAssertNil(cancelled)
    }

    @MainActor
    func testPausingCancelsQueueAndRejectsNewRequests() {
        let broker = RequestBroker()
        var reason: String?
        let request = AgentRequest(
            id: "one", source: "test", kind: "question", title: "First",
            choices: [Choice(id: "x", label: "X")]
        )
        XCTAssertTrue(broker.submit(request) {
            if case .cancelled(let cancellation) = $0 { reason = cancellation.reason }
        })

        broker.setPaused(true)

        XCTAssertEqual(reason, "host-paused")
        XCTAssertEqual(broker.count, 0)
        XCTAssertEqual(broker.submitResult(
            AgentRequest(id: "two", source: "test", kind: "question", title: "Second",
                         choices: [Choice(id: "y", label: "Y")])
        ) { _ in }, .paused)
    }
}
