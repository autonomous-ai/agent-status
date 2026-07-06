import SwiftUI
import XCTest
@testable import AgentStatus

/// Headless render of the aggregate menu-bar label (`AggregateMenuBarLabel`) in
/// every `AggregateActivity` state, stacked into /tmp/menubar-snapshots/
/// agg-all-{dark,light}.png for eyeball review. Built from synthetic snapshots,
/// so no personal info.
@MainActor
final class AggregateLabelSnapshotRenderTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let outDir = URL(fileURLWithPath: "/tmp/menubar-snapshots", isDirectory: true)

    func testRenderAggregateLabelStates() throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let cases: [(String, AggregateActivity)] = [
            ("empty",          .make(from: [], now: t0)),
            ("idle (5)",       .make(from: (1...5).map { idle($0) }, now: t0)),
            ("working single", .make(from: [busy("Bash", "xcodebuild -scheme AgentStatus test", -95, 1)], now: t0)),
            ("working + idle", .make(from: [busy("Bash", "npm run build", -95, 1)] + (2...5).map { idle($0) }, now: t0)),
            ("working multi",  .make(from: [busy("Bash", "npm run build", -40, 1, updated: -20),
                                            busy("Read", "queue.ts", -15, 2, updated: -2),
                                            busy("Agent", "audit retry paths", -9, 3, updated: -30)], now: t0)),
            ("waiting",        .make(from: [waiting("Bash", "rm -rf build", 1)], now: t0)),
            ("waiting + fleet", .make(from: [waiting("Bash", "rm -rf build", 1),
                                             busy("Read", "x", -5, 2), busy("Edit", "y", -5, 3)], now: t0)),
            ("needs you (2)",  .make(from: [waiting("Bash", "x", 1), errored(2)], now: t0)),
            ("error",          .make(from: [errored(1)], now: t0)),
        ]

        try renderStrip(cases, scheme: .dark, bg: Color(red: 0.11, green: 0.12, blue: 0.14), name: "agg-all-dark")
        try renderStrip(cases, scheme: .light, bg: Color(red: 0.86, green: 0.87, blue: 0.89), name: "agg-all-light")
    }

    private func renderStrip(_ cases: [(String, AggregateActivity)], scheme: ColorScheme,
                             bg: Color, name: String) throws {
        let strip = VStack(alignment: .leading, spacing: 10) {
            ForEach(cases, id: \.0) { label, activity in
                HStack(spacing: 14) {
                    Text(label)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(scheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                        .frame(width: 110, alignment: .leading)
                    AggregateMenuBarLabel(activity: activity)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(20)
        .frame(width: 460, alignment: .leading)
        .background(bg)
        .environment(\.colorScheme, scheme)

        let renderer = ImageRenderer(content: strip)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return XCTFail("no image for \(name)") }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("PNG encode failed for \(name)")
        }
        try png.write(to: outDir.appendingPathComponent("\(name).png"))
        XCTAssertGreaterThan(png.count, 2_000)
    }

    // MARK: - Synthetic snapshots

    private func snap(_ status: SessionStatus, pid: Int32, updated: TimeInterval,
                      enriched: EnrichedSession) -> SessionSnapshot {
        SessionSnapshot(
            id: "demo:\(pid)", providerId: "demo", pid: pid, sessionId: "\(pid)",
            cwd: URL(fileURLWithPath: "/tmp"), startedAt: t0.addingTimeInterval(-3_600),
            updatedAt: t0.addingTimeInterval(updated), status: status, waitingFor: nil,
            version: nil, kind: "interactive", entrypoint: "cli", isAlive: true, enriched: enriched
        )
    }

    private func idle(_ pid: Int32) -> SessionSnapshot {
        snap(.idle, pid: pid, updated: -600, enriched: .empty)
    }

    private func busy(_ tool: String, _ preview: String, _ startedAgo: TimeInterval,
                      _ pid: Int32, updated: TimeInterval = -5) -> SessionSnapshot {
        var e = EnrichedSession.empty
        e.activeTools = [ActiveTool(id: "t\(pid)", name: tool, preview: preview,
                                    startedAt: t0.addingTimeInterval(startedAgo))]
        return snap(.busy, pid: pid, updated: updated, enriched: e)
    }

    private func waiting(_ tool: String, _ preview: String, _ pid: Int32) -> SessionSnapshot {
        var e = EnrichedSession.empty
        e.activeTools = [ActiveTool(id: "q\(pid)", name: tool, preview: preview,
                                    startedAt: t0.addingTimeInterval(-20))]
        return snap(.waiting, pid: pid, updated: -20, enriched: e)
    }

    private func errored(_ pid: Int32) -> SessionSnapshot {
        var e = EnrichedSession.empty
        let failed = ActiveTool(id: "e\(pid)", name: "Bash", preview: "python x.py",
                                startedAt: t0.addingTimeInterval(-60))
        e.recentTools = [CompletedTool(completing: failed, isError: true, at: t0.addingTimeInterval(-50))]
        return snap(.error, pid: pid, updated: -50, enriched: e)
    }
}
