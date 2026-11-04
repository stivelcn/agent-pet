import AppKit
import SwiftUI
import AgentPetCore

/// The pet's right-click HUD: the companion's stats plus a compact footer with
/// Settings / Quit (the same actions as the menu bar popover).
struct PetStatsView: View {
    /// The pet whose stats to show. `nil` resolves to the globally selected pet
    /// (preserves today's right-click-on-the-single-pet behaviour).
    var petID: String? = nil
    @ObservedObject private var care = PetCareController.shared
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var imagePets = ImagePetStore.shared
    @State private var hoveredAchievement: Achievement?

    private static let stageColors: [Color] = [.green, .teal, .blue, .purple, .orange]

    /// The pet id this card is showing — the passed id, else the selected pet.
    private var resolvedPetID: String? { petID ?? pet.selectedPetID }

    private var pack: ImagePetPack? {
        resolvedPetID.flatMap { imagePets.pack(id: $0) }
    }

    /// Care state of the resolved pet.
    private var careState: PetCareState { care.state(for: resolvedPetID) }
    private var level: Int { PetCare.displayLevel(forXP: careState.xp) }
    private var stageKey: String { PetCare.stageName(forLevel: PetCare.level(forXP: careState.xp)) }
    private var stageIndex: Int { PetCare.stageIndex(forLevel: PetCare.level(forXP: careState.xp)) }
    private var levelProgress: Double { PetCare.progress(forXP: careState.xp) }
    private var hunger: PetHunger { PetCare.hunger(state: careState, now: Date()) }

    private var stageColor: Color { Self.stageColors[min(stageIndex, Self.stageColors.count - 1)] }

    var body: some View {
        let state = careState
        VStack(alignment: .leading, spacing: 12) {
            header(state)
            xpBlock(state)
            achievementBlock
            statGrid(state)
            trendBlock(state)
            AgentUsageRows(limit: 3)
            if let last = state.lastFedAt {
                HStack {
                    Text("Last fed").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Text(verbatim: last.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                }
            }
            footer
        }
        .padding(14)
        .frame(width: 300)
        .background(.regularMaterial)
        .environment(\.colorScheme, .dark)
        .textSelection(.enabled)
        .noFocusRing()
    }

    // MARK: - Footer (Settings / Quit)

    private var footer: some View {
        VStack(spacing: 8) {
            Divider().overlay(Color.white.opacity(0.08))
            HStack {
                footButton(icon: "gearshape", label: "Settings") {
                    PetWindowController.shared.closeStatsPopover()
                    SettingsWindowController.shared.show()
                }
                Spacer()
                footButton(icon: "power", label: "Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private func footButton(icon: String, label: String, badge: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                    if badge {
                        Circle().fill(Color.orange).frame(width: 5, height: 5).offset(x: 3, y: -3)
                    }
                }
                Text(NSLocalizedString(label, comment: "Pet menu action"))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header

    private func header(_ state: PetCareState) -> some View {
        HStack(spacing: 10) {
            Group {
                if let frame = pack?.clip(0).first {
                    Image(nsImage: frame).resizable().interpolation(.none).scaledToFit().padding(4)
                } else {
                    Image(systemName: "pawprint.fill").foregroundStyle(.secondary)
                }
            }
            .frame(width: 46, height: 46)
            .background(RoundedRectangle(cornerRadius: 10).fill(stageColor.opacity(0.14)))

            VStack(alignment: .leading, spacing: 3) {
                Text(imagePets.displayName(for: resolvedPetID))
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                HStack(spacing: 6) {
                    Text(verbatim: "等级 \(level)")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(stageColor)
                    StageBadge(stageIndex: stageIndex, size: 16)
                    Text(NSLocalizedString(stageKey, comment: "stage"))
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(stageColor.opacity(0.2)))
                        .foregroundStyle(stageColor)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(CareFormat.hunger(hunger))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                ProgressView(value: fullness)
                    .tint(fullness > 0.5 ? .green : (fullness > 0.25 ? .orange : .red))
                    .controlSize(.small)
                    .frame(width: 64)
            }
        }
    }

    // MARK: - XP

    private func xpBlock(_ state: PetCareState) -> some View {
        let (inLevel, span) = PetCare.xpWithinLevel(forXP: state.xp)
        return VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: levelProgress).tint(stageColor).controlSize(.small)
            HStack {
                Text(verbatim: "\(CareFormat.plain(inLevel)) / \(CareFormat.plain(span)) 经验")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                Spacer()
                Text(verbatim: "\(Int((levelProgress * 100).rounded()))%")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(stageColor)
            }
            Text(String(format: NSLocalizedString("≈ %@ tokens to Lv %d", comment: ""),
                        CareFormat.tokens(PetCare.tokensToNextLevel(state: state)), level + 1))
                .font(.system(size: 10, weight: .medium)).foregroundStyle(stageColor.opacity(0.9))
        }
    }

    // MARK: - Achievements

    private var achievementBlock: some View {
        let unlocked = care.achievements
        let total = Achievement.allCases.count
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Achievements")
                    .font(.system(size: 9, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
                Text(verbatim: "\(unlocked.count) / \(total)")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
            }
            HStack(spacing: 2) {
                ForEach(Achievement.allCases, id: \.self) { a in
                    let symbol = PetCare.achievementSymbol(a)
                    let isUnlocked = unlocked.contains(a)
                    Image(systemName: symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(isUnlocked ? stageColor : Color.white.opacity(0.15))
                        // Distribute evenly across the card width so 14 badges
                        // never overflow the fixed 300pt popover (the overflow
                        // clipped the whole HUD's left edge).
                        .frame(maxWidth: .infinity, minHeight: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(hoveredAchievement == a ? Color.white.opacity(0.08) : .clear)
                        )
                        .help(PetCare.achievementDisplayName(a))
                        .onHover { inside in
                            hoveredAchievement = inside ? a : (hoveredAchievement == a ? nil : hoveredAchievement)
                        }
                }
            }
            .frame(maxWidth: .infinity)
            achievementHint(unlocked: unlocked)
        }
    }

    /// A single line under the badge row: hovering a badge shows its name, how to
    /// unlock it, and whether it's done. Reliable in the floating HUD where the
    /// system `.help` tooltip can be slow or suppressed.
    @ViewBuilder private func achievementHint(unlocked: Set<Achievement>) -> some View {
        HStack(spacing: 5) {
            if let a = hoveredAchievement {
                let done = unlocked.contains(a)
                Image(systemName: done ? "checkmark.circle.fill" : "lock.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(done ? stageColor : .white.opacity(0.35))
                Text(PetCare.achievementDisplayName(a))
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                Text(verbatim: "·").font(.system(size: 9)).foregroundStyle(.white.opacity(0.3))
                Text(PetCare.achievementDescription(a))
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            } else {
                Text("Hover a badge to see how to unlock it")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.3))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 12)
    }

    // MARK: - Stat grid

    private func statGrid(_ state: PetCareState) -> some View {
        let cells: [(String, String, String)] = [
            (NSLocalizedString("Today", comment: ""), CareFormat.tokens(state.tokensToday),
             mealText(state.mealsToday)),
            (NSLocalizedString("Streak", comment: ""), streakValue(state),
             NSLocalizedString("days fed", comment: "")),
            (NSLocalizedString("Lifetime", comment: ""), CareFormat.tokens(state.totalTokens),
             NSLocalizedString("tokens eaten", comment: "")),
            (NSLocalizedString("Sessions", comment: ""), "\(state.totalMeals)",
             NSLocalizedString("completed", comment: "")),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(cells, id: \.0) { cell in
                VStack(alignment: .leading, spacing: 1) {
                    Text(cell.0.uppercased())
                        .font(.system(size: 8, weight: .semibold)).tracking(0.8)
                        .foregroundStyle(.white.opacity(0.35))
                    Text(verbatim: cell.1)
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    Text(verbatim: cell.2)
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            }
        }
    }

    // MARK: - 7-day trend

    private func trendBlock(_ state: PetCareState) -> some View {
        PetUsageTrendView(days: PetCare.recentDays(state: state, now: Date()), accent: stageColor)
            .zIndex(1)
    }

    // MARK: - Derived

    /// Continuous fullness 0…1 (48h since the last feeding → empty).
    private var fullness: Double {
        guard let last = careState.lastFedAt else { return 0.5 }
        let hours = Date().timeIntervalSince(last) / 3600
        return max(0, min(1, 1 - hours / 48))
    }

    private func mealText(_ meals: Int) -> String {
        meals == 1
            ? NSLocalizedString("1 meal", comment: "")
            : String(format: NSLocalizedString("%d meals", comment: ""), meals)
    }

    private func streakValue(_ s: PetCareState) -> String {
        "\(s.streakDays)"
    }
}
