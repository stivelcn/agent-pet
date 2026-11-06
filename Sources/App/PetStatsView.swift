import AppKit
import SwiftUI
import AgentPetCore

/// The pet's right-click HUD: the companion's stats plus a compact footer with
/// Settings / Quit (the same actions as the menu bar popover).
struct PetStatsView: View {
    /// The pet whose stats to show. `nil` resolves to the globally selected pet
    /// (preserves today's right-click-on-the-single-pet behaviour).
    var windowKey: String = PetWindowPlanner.defaultKey
    var petID: String? = nil
    var maximumHeight: CGFloat? = nil
    @ObservedObject var sleep: PetSleepController = .shared
    @ObservedObject var care = PetCareController.shared
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var imagePets = ImagePetStore.shared
    @ObservedObject var relay = PetRelayController.shared
    @State private var hoveredAchievement: Achievement?
    @State var detailsExpanded = false


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

    private var stageColor: Color { PetMenuPalette.accent }

    var body: some View {
        ViewThatFits(in: .vertical) {
            menuContents.fixedSize(horizontal: false, vertical: true)
            ScrollView { menuContents }
        }
        .frame(width: 340)
        .frame(maxHeight: maximumHeight ?? max(360, (NSScreen.main?.visibleFrame.height ?? 800) - 60))
        .background(PetMenuPalette.background)
        .environment(\.colorScheme, .dark)
        .noFocusRing()
    }

    @ViewBuilder private var menuContents: some View {
        let state = careState
        VStack(alignment: .leading, spacing: 14) {
            header(state)
            xpBlock(state)
            statGrid(state)
            details
            if let last = state.lastFedAt {
                Text(InterfaceText.format("Last fed") + " · " + last.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10)).foregroundStyle(PetMenuPalette.secondary)
            }
            actions
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    private var details: some View {
        VStack(spacing: 8) {
            Button {
                detailsExpanded.toggle()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "star").font(.system(size: 16))
                    Text(InterfaceText.format("Achievements and usage"))
                        .font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 4)
                    Text(verbatim: "\(care.achievements.count) / \(Achievement.allCases.count)")
                        .font(.system(size: 11)).foregroundStyle(PetMenuPalette.secondary)
                    Image(systemName: detailsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(PetMenuPalette.primary)
            .accessibilityIdentifier("pet-menu-details")
            .accessibilityValue(InterfaceText.format(detailsExpanded ? "Expanded" : "Collapsed"))
            if detailsExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        achievementBlock
                        trendBlock(careState)
                        AgentUsageRows(limit: 3)
                    }
                    .padding(10)
                }
                .frame(height: 160)
                .background(RoundedRectangle(cornerRadius: 10).fill(PetMenuPalette.surface))
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                PetWindowController.shared.closeStatsPopover()
                PetWindowController.shared.showMessageComposer(forKey: windowKey)
            } label: {
                Label(InterfaceText.format("Send a pet message"), systemImage: "envelope.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PetMenuButtonStyle(prominent: true))
            .accessibilityIdentifier("pet-menu-message")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date.timeIntervalSince1970 + relay.serverOffset
                let active = relay.mailbox.pendingTogether != nil
                    || relay.togetherSession?.isPending(at: now) == true
                    || relay.togetherSession?.isActive(at: now) == true
                if windowKey == PetWindowPlanner.defaultKey, relay.pair != nil, active {
                    sleepButton
                    PetTogetherControls(relay: relay, compact: true)
                } else {
                    HStack(spacing: 7) {
                        sleepButton
                        if windowKey == PetWindowPlanner.defaultKey, relay.pair != nil {
                            inviteButton("Go visiting", icon: "door.left.hand.open", mode: .visit)
                            inviteButton("Work together", icon: "person.2", mode: .work)
                        }
                    }
                    if windowKey == PetWindowPlanner.defaultKey, relay.pair != nil, !relay.supportsTogether {
                        Label(InterfaceText.format("Both friends need to update for visits and work"), systemImage: "info.circle")
                            .font(.system(size: 9)).foregroundStyle(PetMenuPalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var sleepButton: some View {
        Button {
            PetWindowController.shared.closeStatsPopover()
            if sleep.isSleeping { sleep.wakeUp() } else { sleep.goToSleep() }
        } label: {
            Label(InterfaceText.format(sleep.isSleeping ? "Wake up" : "Back to the nest to sleep"),
                  systemImage: sleep.isSleeping ? "sun.max" : "moon.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PetMenuButtonStyle())
        .accessibilityIdentifier(sleep.isSleeping ? "pet-wake-up" : "pet-go-to-sleep")
    }

    private func inviteButton(_ title: String, icon: String, mode: PetTogetherMode) -> some View {
        Button { Task { await relay.inviteTogether(mode) } } label: {
            Label(InterfaceText.format(title), systemImage: icon).frame(maxWidth: .infinity)
        }
        .buttonStyle(PetMenuButtonStyle())
        .disabled(!relay.supportsTogether || relay.isBusy)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 9) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
            HStack {
                footButton(icon: "gearshape", label: "Settings") {
                    PetWindowController.shared.closeStatsPopover()
                    SettingsWindowController.shared.show()
                }
                Spacer()
                footButton(icon: "power", label: "Quit") { NSApplication.shared.terminate(nil) }
            }
        }
    }

    private func footButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(InterfaceText.format(label), systemImage: icon)
                .font(.system(size: 11, weight: .medium)).padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .foregroundStyle(PetMenuPalette.secondary)
    }

    // MARK: - Header

    private func header(_ state: PetCareState) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Group {
                if let frame = pack?.clip(0).first {
                    Image(nsImage: frame).resizable().interpolation(.high).scaledToFit().padding(5)
                } else {
                    Image(systemName: "pawprint.fill").foregroundStyle(PetMenuPalette.secondary)
                }
            }
            .frame(width: 60, height: 60)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.18, green: 0.20, blue: 0.26)))
            VStack(alignment: .leading, spacing: 7) {
                Text(imagePets.displayName(for: resolvedPetID))
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(PetMenuPalette.primary)
                    .lineLimit(1).truncationMode(.middle)
                HStack(spacing: 5) {
                    Text(verbatim: "Lv.\(level)")
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .background(Capsule().fill(PetMenuPalette.accent.opacity(0.12)))
                    Text(InterfaceText.format(stageKey)).lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .background(Capsule().fill(PetMenuPalette.accent.opacity(0.12)))
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(PetMenuPalette.accent)
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Circle().fill(hunger == .full ? Color.green : Color.orange).frame(width: 5, height: 5)
                Text(CareFormat.hunger(hunger)).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(PetMenuPalette.primary)
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(Capsule().fill(PetMenuPalette.surface))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
            .fixedSize()
        }
    }

    private func xpBlock(_ state: PetCareState) -> some View {
        let (inLevel, span) = PetCare.xpWithinLevel(forXP: state.xp)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(InterfaceText.format("Growth progress")).foregroundStyle(PetMenuPalette.primary)
                Spacer()
                Text(verbatim: "\(Int((levelProgress * 100).rounded()))%")
                    .fontWeight(.semibold).foregroundStyle(PetMenuPalette.accent)
            }
            .font(.system(size: 11))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(PetMenuPalette.accent).frame(width: geometry.size.width * levelProgress)
                }
            }
            .frame(height: 5)
            HStack {
                Text(InterfaceText.format("%@ / %@ XP", CareFormat.plain(inLevel), CareFormat.plain(span)))
                Spacer()
                Text(verbatim: "Lv.\(level + 1)")
            }
            .font(.system(size: 10)).foregroundStyle(PetMenuPalette.secondary)
            Text(InterfaceText.format("Eat %@ tokens to level up", CareFormat.tokens(PetCare.tokensToNextLevel(state: state))))
                .font(.system(size: 10)).foregroundStyle(PetMenuPalette.secondary)
        }
    }

    // MARK: - Achievements

    private var achievementBlock: some View {
        let unlocked = care.achievements
        let total = Achievement.allCases.count
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
            Text(InterfaceText.format("Achievements"))
                    .font(.system(size: 9, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(PetMenuPalette.secondary)
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
                Text(InterfaceText.format("Hover a badge to see how to unlock it"))
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.3))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 12)
    }

    // MARK: - Stat grid

    private func statGrid(_ state: PetCareState) -> some View {
        let cells: [(String, String, String)] = [
            (InterfaceText.format("Today consumed"), CareFormat.tokens(state.tokensToday),
             mealText(state.mealsToday)),
            (InterfaceText.format("Companion streak"), streakValue(state),
             NSLocalizedString("days fed", comment: "")),
            (InterfaceText.format("Lifetime consumed"), CareFormat.tokens(state.totalTokens),
             NSLocalizedString("tokens eaten", comment: "")),
            (InterfaceText.format("Completed sessions"), "\(state.totalMeals)",
             NSLocalizedString("completed", comment: "")),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(cells, id: \.0) { cell in
                VStack(alignment: .leading, spacing: 1) {
                    Text(cell.0.uppercased())
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PetMenuPalette.secondary)
                    Text(verbatim: cell.1)
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                        .font(.system(size: 21, weight: .semibold)).foregroundStyle(.white)
                    Text(verbatim: cell.2)
                        .font(.system(size: 9)).foregroundStyle(PetMenuPalette.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 11).fill(PetMenuPalette.surface))
            }
        }
    }

    // MARK: - 7-day trend

    private func trendBlock(_ state: PetCareState) -> some View {
        PetUsageTrendView(days: PetCare.recentDays(state: state, now: Date()), accent: PetMenuPalette.accent)
            .zIndex(1)
    }

    private func mealText(_ meals: Int) -> String {
        meals == 1
            ? NSLocalizedString("1 meal", comment: "")
            : String(format: NSLocalizedString("%d meals", comment: ""), meals)
    }

    private func streakValue(_ s: PetCareState) -> String {
        InterfaceText.format("%d days", s.streakDays)
    }
}

/// Scoped to the pet menu; settings and message bubbles retain their own themes.
enum PetMenuPalette {
    static let background = Color(red: 0.11, green: 0.12, blue: 0.15)
    static let surface = Color(red: 0.15, green: 0.16, blue: 0.20)
    static let primary = Color(red: 0.95, green: 0.95, blue: 0.97)
    static let secondary = Color(red: 0.66, green: 0.67, blue: 0.73)
    static let accent = Color(red: 0.67, green: 0.59, blue: 0.96)
}

struct PetMenuButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        PetMenuButtonBody(configuration: configuration, prominent: prominent)
    }
}

private struct PetMenuButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(.system(size: prominent ? 13 : 10, weight: .medium))
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(prominent ? PetMenuPalette.background : PetMenuPalette.primary)
            .padding(.horizontal, prominent ? 12 : 7)
            .frame(minHeight: prominent ? 36 : 29)
            .background(RoundedRectangle(cornerRadius: prominent ? 10 : 8)
                .fill(prominent ? PetMenuPalette.accent : PetMenuPalette.surface))
            .overlay(RoundedRectangle(cornerRadius: prominent ? 10 : 8)
                .fill(Color.white.opacity(hovered && isEnabled ? 0.07 : 0)))
            .overlay(RoundedRectangle(cornerRadius: prominent ? 10 : 8)
                .strokeBorder(Color.white.opacity(prominent ? 0.12 : 0.09)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.42)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onHover { hovered = $0 }
    }
}
