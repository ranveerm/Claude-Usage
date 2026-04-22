//
//  Vibe_Your_Rings_iOSTests.swift
//  Vibe Your Rings iOS Tests
//
//  Two tiers of coverage for the iOS target:
//  - Tier 1 (snapshot): deterministic screenshots of ConcentricCirclesView
//    at varied usage/time progress combinations. The rings are the app's
//    single most visually load-bearing element, and any regression here
//    ripples through every surface (app, widget, complication).
//  - Tier 2 (unit): same pure-logic coverage as the macOS suite. Mirrored
//    rather than shared because Shared/*.swift files are compiled into
//    both app modules; we want each platform's module to be independently
//    green in CI.
//
//  SwiftUI views are snapshotted via UIHostingController so SnapshotTesting
//  sees a concrete UIView (the bare `View` form is overload-ambiguous).
//

import XCTest
import SwiftUI
import UIKit
import SnapshotTesting
@testable import Vibe_Your_Rings_iOS

/// Wraps a SwiftUI view in a UIHostingController sized to `size`, ready
/// to hand to `assertSnapshot(of:as: .image)`.
private func hosted<V: View>(_ view: V, size: CGSize) -> UIView {
    let host = UIHostingController(rootView: view)
    host.view.frame = CGRect(origin: .zero, size: size)
    host.view.backgroundColor = .clear
    return host.view
}

// MARK: - Tier 2: pure-logic unit tests

final class UsageLogicTests_iOS: XCTestCase {

    func testParseUsageResponse_happyPath() throws {
        let json = """
        {
          "five_hour":        { "utilization": 55.0, "resets_at": "2026-04-22T12:00:00.000Z" },
          "seven_day":        { "utilization": 22.0 },
          "seven_day_sonnet": { "utilization": 77.5 }
        }
        """.data(using: .utf8)!

        let result = UsageService.shared.parseUsageResponse(json)

        XCTAssertEqual(result.sessionUtilization, 55.0, accuracy: 0.001)
        XCTAssertEqual(result.allModelsWeeklyUtilization, 22.0, accuracy: 0.001)
        XCTAssertEqual(result.sonnetWeeklyUtilization, 77.5, accuracy: 0.001)
        XCTAssertNotNil(result.lastRefreshed)
    }

    func testParseUsageResponse_emptyObject_yieldsZeros() throws {
        let result = UsageService.shared.parseUsageResponse(Data("{}".utf8))
        XCTAssertEqual(result.sessionUtilization, 0)
        XCTAssertEqual(result.sonnetWeeklyUtilization, 0)
        XCTAssertEqual(result.allModelsWeeklyUtilization, 0)
        XCTAssertNil(result.error)
    }

    func testIsCloudflareError_matches() {
        XCTAssertTrue(UsageService.isCloudflareError("Just a moment"))
        XCTAssertTrue(UsageService.isCloudflareError("x-cf-ray: foo"))
        XCTAssertFalse(UsageService.isCloudflareError("unrelated timeout"))
    }

    func testApplyHeaders_cookieShape() {
        var req = URLRequest(url: URL(string: "https://claude.ai")!)
        UsageService.applyHeaders(to: &req, sessionKey: "A", cfClearance: "B")
        XCTAssertEqual(req.value(forHTTPHeaderField: "cookie"), "sessionKey=A; cf_clearance=B")
    }

    func testUsageData_roundtripsAllFields() throws {
        let original = UsageData(
            sessionUtilization: 33,
            sessionResetsAt: Date(timeIntervalSince1970: 1_700_000_000),
            sonnetWeeklyUtilization: 44,
            sonnetWeeklyResetsAt: Date(timeIntervalSince1970: 1_700_500_000),
            allModelsWeeklyUtilization: 55,
            allModelsWeeklyResetsAt: Date(timeIntervalSince1970: 1_701_000_000),
            lastRefreshed: Date(timeIntervalSince1970: 1_699_900_000),
            error: nil,
            needsLogin: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UsageData.self, from: data)
        XCTAssertEqual(decoded.sessionUtilization, 33)
        XCTAssertEqual(decoded.sonnetWeeklyUtilization, 44)
        XCTAssertEqual(decoded.allModelsWeeklyUtilization, 55)
    }
}

// MARK: - Tier 1: snapshot tests

final class RingSnapshotTests: XCTestCase {

    /// Flip to `true` locally to regenerate baselines. Never commit enabled.
    /// Prefer the `/accept-snapshots` command.
    override func invokeTest() {
        // isRecording = true  // <- do not commit this line uncommented
        super.invokeTest()
    }

    // MARK: Representative ring states

    func testRings_empty() {
        assertSnapshot(of: ringsView(CircleRendererInput(
            sessionProgress: 0, sonnetProgress: 0, allModelsProgress: 0
        )), as: .image)
    }

    func testRings_low() {
        assertSnapshot(of: ringsView(CircleRendererInput(
            sessionProgress: 0.10, sonnetProgress: 0.15, allModelsProgress: 0.20
        )), as: .image)
    }

    func testRings_balanced() {
        // Usage and time roughly in sync — the faded "time" arc should peek
        // just past the solid "usage" arc on all three rings.
        assertSnapshot(of: ringsView(CircleRendererInput(
            sessionProgress:       0.40,
            sonnetProgress:        0.35,
            allModelsProgress:     0.50,
            sessionTimeProgress:   0.45,
            sonnetTimeProgress:    0.40,
            allModelsTimeProgress: 0.55
        )), as: .image)
    }

    func testRings_overshoot() {
        // Usage has outrun time — tests the curved cut where the solid arc
        // wraps around the time arc. Historically fragile.
        assertSnapshot(of: ringsView(CircleRendererInput(
            sessionProgress:       0.85,
            sonnetProgress:        0.70,
            allModelsProgress:     0.90,
            sessionTimeProgress:   0.40,
            sonnetTimeProgress:    0.30,
            allModelsTimeProgress: 0.50
        )), as: .image)
    }

    func testRings_full() {
        assertSnapshot(of: ringsView(CircleRendererInput(
            sessionProgress: 1.0, sonnetProgress: 1.0, allModelsProgress: 1.0,
            sessionTimeProgress: 1.0, sonnetTimeProgress: 1.0, allModelsTimeProgress: 1.0
        )), as: .image)
    }

    // MARK: Helper

    private func ringsView(_ input: CircleRendererInput) -> UIView {
        let view = ConcentricCirclesView(input: input)
            .frame(width: 200, height: 200)
            .padding(10)
            .background(Color(white: 0.08))
        return hosted(view, size: CGSize(width: 220, height: 220))
    }
}
