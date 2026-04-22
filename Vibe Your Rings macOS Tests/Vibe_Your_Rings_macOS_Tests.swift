//
//  Vibe_Your_Rings_macOS_Tests.swift
//  Vibe Your Rings macOS Tests
//
//  Two tiers of coverage:
//  - Tier 1 (snapshot): renders UsagePopoverView in representative states
//    over a range of desktop backgrounds, so visual drift from any future
//    UI edit is caught against committed baselines.
//  - Tier 2 (unit): exercises pure business logic — JSON parsing, error
//    classification, header application — without network or keychain.
//
//  Conventions:
//  - All tests use fixed (non-`Date()`) timestamps so snapshots are
//    deterministic across runs and machines.
//  - SwiftUI views are snapshotted by wrapping in `NSHostingView` so we
//    get an explicit NSView to hand to SnapshotTesting's `.image` strategy
//    (the bare `View` form is ambiguous across library overloads).
//

import XCTest
import SwiftUI
import AppKit
import SnapshotTesting
@testable import Vibe_Your_Rings

// MARK: - Fixtures

/// Anchored to a fixed point in time so snapshot output is bit-stable —
/// relative-date text like "Updated just now" would otherwise change every
/// run and cause spurious diffs.
private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

private func makeUsageData(
    session: Double = 0.40,
    sonnet: Double = 0.25,
    allModels: Double = 0.55,
    error: String? = nil,
    needsLogin: Bool = false
) -> UsageData {
    UsageData(
        sessionUtilization: session * 100,
        sessionResetsAt: fixedNow.addingTimeInterval(2 * 3600),
        sonnetWeeklyUtilization: sonnet * 100,
        sonnetWeeklyResetsAt: fixedNow.addingTimeInterval(3 * 86400),
        allModelsWeeklyUtilization: allModels * 100,
        allModelsWeeklyResetsAt: fixedNow.addingTimeInterval(4 * 86400),
        lastRefreshed: fixedNow,
        error: error,
        needsLogin: needsLogin
    )
}

/// Wraps a SwiftUI view in an NSHostingView sized to `size`, ready to hand
/// to `assertSnapshot(of:as: .image)`.
private func hosted<V: View>(_ view: V, size: CGSize) -> NSView {
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(origin: .zero, size: size)
    return host
}

// MARK: - Tier 2: pure-logic unit tests

final class UsageServiceLogicTests: XCTestCase {

    // MARK: parseUsageResponse

    func testParseUsageResponse_extractsAllThreeWindows() throws {
        let json = """
        {
          "five_hour":         { "utilization": 42.5, "resets_at": "2026-04-22T12:00:00.000Z" },
          "seven_day":         { "utilization": 17.3, "resets_at": "2026-04-28T00:00:00.000Z" },
          "seven_day_sonnet":  { "utilization": 88.1, "resets_at": "2026-04-28T00:00:00.000Z" }
        }
        """.data(using: .utf8)!

        let result = UsageService.shared.parseUsageResponse(json)

        XCTAssertEqual(result.sessionUtilization, 42.5, accuracy: 0.001)
        XCTAssertEqual(result.allModelsWeeklyUtilization, 17.3, accuracy: 0.001)
        XCTAssertEqual(result.sonnetWeeklyUtilization, 88.1, accuracy: 0.001)
        XCTAssertNotNil(result.sessionResetsAt)
        XCTAssertNotNil(result.lastRefreshed)
        XCTAssertNil(result.error)
    }

    func testParseUsageResponse_missingKeys_yieldsZerosNotError() throws {
        // Claude's API sometimes omits a window entirely (e.g. early in a
        // new billing period). Parser should treat absent blocks as 0% used,
        // never as a failure.
        let json = "{ \"five_hour\": { \"utilization\": 10.0 } }".data(using: .utf8)!

        let result = UsageService.shared.parseUsageResponse(json)

        XCTAssertEqual(result.sessionUtilization, 10.0, accuracy: 0.001)
        XCTAssertEqual(result.sonnetWeeklyUtilization, 0)
        XCTAssertEqual(result.allModelsWeeklyUtilization, 0)
        XCTAssertNil(result.error)
    }

    func testParseUsageResponse_malformedJSON_returnsErrorUsage() throws {
        let result = UsageService.shared.parseUsageResponse(Data("not json".utf8))

        XCTAssertNotNil(result.error)
        XCTAssertEqual(result.sessionUtilization, 0)
    }

    // MARK: Pro vs Max tier detection

    func testParseUsageResponse_maxTier_hasSonnetApplicable() throws {
        // Max tier: `seven_day_sonnet` block is present (even at 0%).
        let json = """
        {
          "five_hour":        { "utilization": 10.0 },
          "seven_day":        { "utilization": 5.0 },
          "seven_day_sonnet": { "utilization": 0.0 }
        }
        """.data(using: .utf8)!

        let result = UsageService.shared.parseUsageResponse(json)
        XCTAssertTrue(result.sonnetWeeklyApplicable,
            "Presence of seven_day_sonnet implies a Max subscription.")
    }

    func testParseUsageResponse_proTier_marksSonnetNotApplicable() throws {
        // Pro tier: the API omits `seven_day_sonnet` entirely.
        let json = """
        {
          "five_hour": { "utilization": 30.0 },
          "seven_day": { "utilization": 12.0 }
        }
        """.data(using: .utf8)!

        let result = UsageService.shared.parseUsageResponse(json)
        XCTAssertFalse(result.sonnetWeeklyApplicable,
            "Absent seven_day_sonnet is the signal for a Pro subscription.")
        // And the utilisation falls back to 0 so existing consumers that
        // read the Double field (widget, complication) don't crash.
        XCTAssertEqual(result.sonnetWeeklyUtilization, 0)
    }

    // MARK: isCloudflareError

    func testIsCloudflareError_detectsKnownMarkers() {
        XCTAssertTrue(UsageService.isCloudflareError("Just a moment…"))
        XCTAssertTrue(UsageService.isCloudflareError("cf-ray: abc123"))
        XCTAssertTrue(UsageService.isCloudflareError("HTTP 403 returned by proxy"))
    }

    func testIsCloudflareError_rejectsOrdinaryErrors() {
        XCTAssertFalse(UsageService.isCloudflareError("The request timed out"))
        XCTAssertFalse(UsageService.isCloudflareError("Session expired"))
        XCTAssertFalse(UsageService.isCloudflareError(""))
    }

    // MARK: applyHeaders

    func testApplyHeaders_buildsCookieFromBothTokens() {
        var request = URLRequest(url: URL(string: "https://claude.ai")!)
        UsageService.applyHeaders(to: &request, sessionKey: "sk_abc", cfClearance: "cf_xyz")

        let cookie = request.value(forHTTPHeaderField: "cookie") ?? ""
        XCTAssertTrue(cookie.contains("sessionKey=sk_abc"))
        XCTAssertTrue(cookie.contains("cf_clearance=cf_xyz"))
    }

    func testApplyHeaders_omitsCfClearanceWhenEmpty() {
        var request = URLRequest(url: URL(string: "https://claude.ai")!)
        UsageService.applyHeaders(to: &request, sessionKey: "sk_abc", cfClearance: "")

        let cookie = request.value(forHTTPHeaderField: "cookie") ?? ""
        XCTAssertEqual(cookie, "sessionKey=sk_abc")
        XCTAssertFalse(cookie.contains("cf_clearance"))
    }

    // MARK: UsageData Codable

    func testUsageData_codableRoundtrip() throws {
        let original = makeUsageData()
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UsageData.self, from: encoded)

        XCTAssertEqual(decoded.sessionUtilization, original.sessionUtilization)
        XCTAssertEqual(decoded.sonnetWeeklyUtilization, original.sonnetWeeklyUtilization)
        XCTAssertEqual(decoded.allModelsWeeklyUtilization, original.allModelsWeeklyUtilization)
        XCTAssertEqual(decoded.needsLogin, original.needsLogin)
    }
}

// MARK: - Tier 1: snapshot tests

final class PopoverSnapshotTests: XCTestCase {

    /// Flip to `true` locally to regenerate every baseline in this suite.
    /// Never commit with this enabled. The `/accept-snapshots` command
    /// wraps this flow so you don't have to edit source.
    override func invokeTest() {
        // isRecording = true  // <- do not commit this line uncommented
        super.invokeTest()
    }

    // MARK: Typical usage

    func testPopover_normalState() {
        assertSnapshot(of: hosted(makePopover(state: .normal),
                                  size: CGSize(width: 320, height: 160)),
                       as: .image)
    }

    func testPopover_nearLimit() {
        assertSnapshot(of: hosted(makePopover(state: .nearLimit),
                                  size: CGSize(width: 320, height: 160)),
                       as: .image)
    }

    func testPopover_empty() {
        assertSnapshot(of: hosted(makePopover(state: .empty),
                                  size: CGSize(width: 320, height: 160)),
                       as: .image)
    }

    // Pro tier: Sonnet weekly metric isn't available. The middle ring
    // should render grey and the "Sonnet Weekly" list row should read "N/A"
    // in a dimmed style rather than "0%".
    func testPopover_proTier() {
        var data = makeUsageData()
        data.sonnetWeeklyUtilization = 0
        data.sonnetWeeklyResetsAt = nil
        data.sonnetWeeklyApplicable = false
        let view = UsagePopoverView(
            usageData: data,
            isConfigured: true,
            onRefresh: {},
            onLogin: {}
        )
        assertSnapshot(of: hosted(view, size: CGSize(width: 320, height: 160)),
                       as: .image)
    }

    // MARK: Edge states

    func testPopover_signedOut() {
        let data = makeUsageData(needsLogin: true)
        let view = UsagePopoverView(
            usageData: data,
            isConfigured: false,
            onRefresh: {},
            onLogin: {}
        )
        assertSnapshot(of: hosted(view, size: CGSize(width: 320, height: 220)),
                       as: .image)
    }

    func testPopover_error() {
        let data = makeUsageData(error: "Network unreachable")
        let view = UsagePopoverView(
            usageData: data,
            isConfigured: true,
            onRefresh: {},
            onLogin: {}
        )
        assertSnapshot(of: hosted(view, size: CGSize(width: 320, height: 220)),
                       as: .image)
    }

    // MARK: Backgrounds (re the .regularMaterial fix)

    func testPopover_onYellowDesktop() {
        assertSnapshot(of: hosted(popoverOver(.yellow),
                                  size: CGSize(width: 360, height: 200)),
                       as: .image)
    }

    func testPopover_onDarkDesktop() {
        assertSnapshot(of: hosted(popoverOver(Color(white: 0.12)),
                                  size: CGSize(width: 360, height: 200)),
                       as: .image)
    }

    // MARK: Helpers

    private enum State { case normal, nearLimit, empty }

    private func makePopover(state: State) -> some View {
        let data: UsageData = {
            switch state {
            case .normal:    return makeUsageData()
            case .nearLimit: return makeUsageData(session: 0.95, sonnet: 0.88, allModels: 0.92)
            case .empty:     return makeUsageData(session: 0, sonnet: 0, allModels: 0)
            }
        }()
        return UsagePopoverView(
            usageData: data,
            isConfigured: true,
            onRefresh: {},
            onLogin: {}
        )
    }

    private func popoverOver(_ colour: Color) -> some View {
        ZStack {
            colour
            makePopover(state: .normal)
        }
    }
}
