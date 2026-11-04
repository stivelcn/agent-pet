import AgentPetCore
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import agentpet

@MainActor
@Suite(.serialized)
struct PetUsageTrendTests {
    @Test func tooltipShowsTheExactCountIncludingZero() {
        for tokens in [0, 54_321, 7_245_678, Int.max] {
            #expect(PetUsageTrendView.tokenLabel(tokens) == "\(CareFormat.plain(tokens)) tokens")
        }
        #expect(!PetUsageTrendView.tokenLabel(54_321).hasSuffix("k tokens"))
        #expect(!PetUsageTrendView.tokenLabel(7_245_678).hasSuffix("M tokens"))
    }

    @Test func everyDayTooltipStaysWithinTheChartEdges() {
        for width: CGFloat in [120, 272, 400] {
            let tooltipWidth = min(180, width)
            for index in 0..<7 {
                let center = PetUsageTrendView.tooltipCenter(index: index, count: 7,
                                                            chartWidth: width, tooltipWidth: tooltipWidth)
                #expect(center - tooltipWidth / 2 >= 0)
                #expect(center + tooltipWidth / 2 <= width)
            }
        }
        #expect(PetUsageTrendView.tooltipCenter(index: 0, count: 0, chartWidth: 272, tooltipWidth: 180) == 136)
    }

    @Test func hoverOverlaysRenderWithoutChangingChartSize() throws {
        // Synthetic visual fixtures only. No application preferences or real usage are touched.
        let values = [0, 125, 0, 4_500, 0, 7_245_678, 54_321]
        let days = values.enumerated().map {
            PetCare.DayUsage(id: "2026-11-0\($0.offset + 1)", label: "\($0.offset + 1)", tokens: $0.element)
        }
        var size: CGSize?
        for hovered: String? in [nil] + days.map({ Optional($0.id) }) {
            let renderer = ImageRenderer(content:
                PetUsageTrendView(days: days, accent: .cyan, hoveredDayID: hovered)
                    .padding(.top, 55).padding(14).frame(width: 300)
                    .background(Color(white: 0.18))
                    .environment(\.colorScheme, .dark))
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            let current = CGSize(width: image.width, height: image.height)
            if let size { #expect(current == size) } else { size = current }
            if let directory = ProcessInfo.processInfo.environment["AGENTPET_UI_SNAPSHOT_DIR"] {
                let folder = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let bitmap = NSBitmapImageRep(cgImage: image)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: folder.appendingPathComponent("trend-\(hovered ?? "idle").png"))
            }
        }
    }
}
