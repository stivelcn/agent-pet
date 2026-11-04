import Foundation

/// Estimated tokens spread over an interval (METRICS 6.3): an unmeasured response, or an in-flight request whose
/// interval runs until now (`endMs == nil`).
struct InFlightEstimate: Sendable {
    var agentId: String
    var source: SourceKind
    var startMs: Int64
    var endMs: Int64?
    var speed: Rate
}

/// A reference token speed from measured responses.
struct SpeedEstimate: Equatable, Sendable {
    var speed: Rate
}

/// Reference token speeds (METRICS 6.2) for agents.
struct SpeedReferences: Sendable {
    private struct Sums {
        var count = 0
        var output = 0.0
        var total = 0.0
        var durationMs: Int64 = 0

        mutating func add(_ response: TimedResponse) {
            count += 1
            output += response.output
            total += response.total
            durationMs += response.durationMs
        }

        var estimate: SpeedEstimate {
            let seconds = Double(durationMs) / 1000
            return SpeedEstimate(
                speed: Rate(output: output / seconds, total: total / seconds)
            )
        }
    }

    private let timed: [TimedResponse]
    private let nowMs: Int64
    private var recentByAgent: [String: SpeedEstimate] = [:]

    /// `timed` must be sorted most recent first.
    init(timed: [TimedResponse], nowMs: Int64) {
        self.timed = timed
        self.nowMs = nowMs
        var sums: [String: Sums] = [:]
        let cutoff = nowMs - SpeedEngine.recentWindowMs
        for response in timed where response.endMs >= cutoff {
            var entry = sums[response.record.agentId] ?? Sums()
            guard entry.count < SpeedEngine.recentCount else { continue }
            entry.add(response)
            sums[response.record.agentId] = entry
        }
        for (agent, entry) in sums {
            recentByAgent[agent] = entry.estimate
        }
    }

    func recent(for agentId: String) -> Rate? {
        recentByAgent[agentId]?.speed
    }

    /// The agent's recent speed, else the same-model fallback, else the same-source fallback.
    func estimate(for agent: EngineAgent) -> SpeedEstimate? {
        if let own = recentByAgent[agent.id] { return own }
        if let model = agent.model, let byModel = fallback(where: { $0.model == model }) { return byModel }
        return fallback(where: { $0.source == agent.source })
    }

    private func fallback(where matches: (ResponseRecord) -> Bool) -> SpeedEstimate? {
        let cutoff = nowMs - SpeedEngine.fallbackWindowMs
        var sums = Sums()
        for response in timed where response.endMs >= cutoff && matches(response.record) {
            sums.add(response)
            if sums.count == SpeedEngine.fallbackCount { break }
        }
        return sums.count > 0 ? sums.estimate : nil
    }
}


/// Measured plus estimated tokens inside the live window `[nowMs - W, nowMs]` (METRICS 6.3).
struct LiveWindow: Sendable {
    private(set) var total = Rate.zero
    private(set) var estimatedShare = 0.0
    private(set) var bySource: [SourceKind: Rate] = [:]
    /// The estimated part of `bySource` (unmeasured and in-flight).
    private(set) var estimatedBySource: [SourceKind: Rate] = [:]
    private(set) var byAgent: [String: Rate] = [:]
    private(set) var estimates: [InFlightEstimate] = []

    /// `latestEnds` holds the latest end of any stored response per agent; an estimate starts no earlier, so a
    /// response that is still being written is never counted twice.
    /// `measured` and `unmeasured` hold valid-interval responses that are final and unfinalized respectively.
    init(
        nowMs: Int64,
        measured measuredResponses: [TimedResponse],
        unmeasured: [TimedResponse],
        agents: [String: EngineAgent],
        latestEnds: [String: Int64],
        references: SpeedReferences
    ) {
        let windowStart = nowMs - SpeedEngine.liveWindowMs
        let seconds = Double(SpeedEngine.liveWindowMs) / 1000
        var measured = Rate.zero
        var estimated = Rate.zero
        var sourceTokens: [SourceKind: Rate] = [:]
        var estimatedSourceTokens: [SourceKind: Rate] = [:]
        var agentTokens: [String: Rate] = [:]

        for response in measuredResponses {
            let overlap = ResponseTiming.overlap(windowStart, nowMs, response.startMs, response.endMs)
            guard overlap > 0 else { continue }
            let share = Double(overlap) / Double(response.durationMs)
            let tokens = Rate(output: response.output * share, total: response.total * share)
            measured.add(tokens)
            sourceTokens[response.record.source, default: .zero].add(tokens)
            agentTokens[response.record.agentId, default: .zero].add(tokens)
        }

        func addEstimate(_ estimate: InFlightEstimate) {
            estimates.append(estimate)
            let end = estimate.endMs ?? nowMs
            let overlap = Double(ResponseTiming.overlap(windowStart, nowMs, estimate.startMs, end)) / 1000
            guard overlap > 0 else { return }
            let tokens = Rate(output: estimate.speed.output * overlap, total: estimate.speed.total * overlap)
            estimated.add(tokens)
            sourceTokens[estimate.source, default: .zero].add(tokens)
            estimatedSourceTokens[estimate.source, default: .zero].add(tokens)
            agentTokens[estimate.agentId, default: .zero].add(tokens)
        }

        for response in unmeasured {
            let record = response.record
            let agent = agents[record.agentId]
                ?? EngineAgent(id: record.agentId, source: record.source, project: "", model: record.model)
            guard let reference = references.estimate(for: agent) else { continue }
            addEstimate(InFlightEstimate(
                agentId: record.agentId, source: record.source, startMs: response.startMs, endMs: response.endMs,
                speed: reference.speed
            ))
        }

        for agent in agents.values.sorted(by: { $0.id < $1.id }) {
            guard agent.phase == .generating,
                  let inFlightStart = agent.inFlightStartMs,
                  let lastLine = agent.lastLineMs, nowMs - lastLine <= SpeedEngine.staleMs,
                  let reference = references.estimate(for: agent)
            else { continue }
            let start = max(inFlightStart, latestEnds[agent.id] ?? inFlightStart)
            addEstimate(InFlightEstimate(
                agentId: agent.id, source: agent.source, startMs: start, endMs: nil, speed: reference.speed
            ))
        }

        total = Rate(output: (measured.output + estimated.output) / seconds, total: (measured.total + estimated.total) / seconds)
        let combined = measured.output + estimated.output
        estimatedShare = combined > 0 ? estimated.output / combined : 0
        bySource = sourceTokens.mapValues { Rate(output: $0.output / seconds, total: $0.total / seconds) }
        estimatedBySource = estimatedSourceTokens.mapValues { Rate(output: $0.output / seconds, total: $0.total / seconds) }
        byAgent = agentTokens.mapValues { Rate(output: $0.output / seconds, total: $0.total / seconds) }
    }
}

extension Rate {
    mutating func add(_ other: Rate) {
        output += other.output
        total += other.total
    }
}
