import AgentPetCore
import SwiftUI

/// Compact daily token chart. Each complete column (including zero days and its
/// date label) is a hover target; the floating label never changes the layout.
struct PetUsageTrendView: View {
    let days: [PetCare.DayUsage]
    let accent: Color
    @State var hoveredDayID: String?

    private static let spacing: CGFloat = 5
    private static let chartHeight: CGFloat = 48

    var body: some View {
        let peak = max(days.map(\.tokens).max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Burn, last 7 days")
                    .font(.system(size: 9, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
                Text(verbatim: CareFormat.tokens(days.map(\.tokens).reduce(0, +)))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            HStack(alignment: .bottom, spacing: Self.spacing) {
                ForEach(days) { day in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(accent.opacity(day.id == hoveredDayID || day.id == days.last?.id ? 1 : 0.4))
                            .frame(height: max(3, CGFloat(day.tokens) / CGFloat(peak) * 34))
                        Text(verbatim: day.label)
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(day.id == hoveredDayID ? 0.9 : 0.35))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.chartHeight, alignment: .bottom)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { hoveredDayID = day.id }
                        else if hoveredDayID == day.id { hoveredDayID = nil }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: day.id))
                    .accessibilityValue(Text(verbatim: Self.tokenLabel(day.tokens)))
                    .accessibilityIdentifier("pet-usage-day-\(day.id)")
                }
            }
            .frame(height: Self.chartHeight, alignment: .bottom)
            .overlay(alignment: .topLeading) {
                if let index = days.firstIndex(where: { $0.id == hoveredDayID }) {
                    GeometryReader { geometry in
                        let width = min(180, geometry.size.width)
                        PetUsageDayTooltip(day: days[index], accent: accent)
                            .frame(width: width)
                            .position(x: Self.tooltipCenter(index: index, count: days.count,
                                                            chartWidth: geometry.size.width, tooltipWidth: width),
                                      y: -14)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        }
        .onDisappear { hoveredDayID = nil }
    }

    static func tokenLabel(_ tokens: Int) -> String {
        "\(CareFormat.plain(tokens)) tokens"
    }

    /// Keep both edge-day tooltips within the popover instead of clipping them.
    static func tooltipCenter(index: Int, count: Int, chartWidth: CGFloat, tooltipWidth: CGFloat) -> CGFloat {
        guard count > 0 else { return chartWidth / 2 }
        let columnWidth = max(0, (chartWidth - CGFloat(count - 1) * spacing) / CGFloat(count))
        let center = CGFloat(index) * (columnWidth + spacing) + columnWidth / 2
        let half = min(tooltipWidth, chartWidth) / 2
        return min(max(center, half), chartWidth - half)
    }
}

struct PetUsageDayTooltip: View {
    let day: PetCare.DayUsage
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: day.id)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text(verbatim: PetUsageTrendView.tokenLabel(day.tokens))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12).opacity(0.98)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
    }
}
