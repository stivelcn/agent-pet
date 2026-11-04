# Agent Speed source provenance

- Upstream: https://github.com/zoefix/agent-speed
- Inspected Agent Speed commit recorded at initial vendoring: `a94a67fcc78e5d8eea5f82d8d5e737bccf994e2c`.
- Local integration source: the Agent Speed sources carried by EmberCat `v0.6.15`
  (EmberCat commit prefix `f4b0e15f8ad2`), integrated on 2026-11-03.
- Agent Speed MIT copyright and license: `AGENT-SPEED-LICENSE`.
- zstd provenance and BSD license: `CZstd/VENDOR.md` and `CZstd/LICENSE`.

## Local subset

This directory is no longer a full upstream source copy. On 2026-11-03 the merged macOS app retained
88 of 151 `AgentSpeedCore` Swift files, based on the `LiveMonitor`, `SpeedStore` and snapshot dependency
graph, followed by clean compilation and regression testing. Retained Swift file contents and the
CZstd implementation were not edited during this cleanup.

Removed capabilities: traffic monitoring, network price/exchange synchronization, profile/report upload,
update clients, standalone history persistence/analysis, unused currency/formatting and demo helpers.

The subset still contains all required local source adapters, engine/IO/parsers, plus shared types under
`History` and `Reporting` referenced by the real-time engine. Their presence does not enable
an upload service. AgentPet starts only `LiveMonitor` / `SpeedStore` through its EmberCat bridge.

## Token-only metrics (2026-11-04)

The local subset now contains 82 Swift files. Removed the six `Pricing` files (including embedded
model prices and exchange rates), the unused price-decimal conversion helper, and monetary fields/calculations
in snapshots, records, live windows, day aggregates and report ledgers. Local reporting identifies models from validated transcript ids
rather than a pricing table. Token counting, timing, source adapters and speed estimates remain.
These are intentional local modifications; the retained Swift sources are no longer unmodified.

Future upstream updates must re-evaluate dependencies instead of copying removed feature trees back
wholesale. Keep this note, the license files and the root `THIRD_PARTY_NOTICES.md` synchronized.
