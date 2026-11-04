# Third-party sources and notices

This macOS version integrates EmberCat's notch flame renderer/editor and live output-speed engine
inside AgentPet. No EmberCat menu-bar pet artwork, Makima, Dock companion, paw trails, second status
item, Sparkle updater, or upstream application entry point is included.

## AgentPet

The original AgentPet MIT copyright and license are retained in `LICENSE`. That root license must not
be represented as covering third-party flame files whose upstream licensing has not been established.

## EmberCat flame sources

- Upstream: https://github.com/johann15910358798-lab/EmberCat.git
- Version: `v0.6.15`, commit prefix `f4b0e15f8ad2` (the installed version inspected on 2026-11-03).
- Copied source: `Sources/App/EmberCat/Notch*.swift`.
- Local adaptations: preferences use AgentPet's isolated suite; native preview closure participates in
  shared application activation ownership. Standalone preview-app/export tooling was omitted; the
  user-facing native editor and all six appearance controls are retained.
- EmberCat is acknowledged as a publicly available source project. At the inspected revision, the
  upstream root did not include a project-wide LICENSE covering these Swift files. This repository
  preserves their provenance and does not assign them the AgentPet or Agent Speed MIT license.
- The CC0 notice under upstream `Sources/EmberCat/Resources/NotchFlame/LICENSE.txt` applies to its
  flame image sequences, not to the Swift renderer/editor code copied here. Those image sequences
  are not included in this integration. Attribution alone is not a substitute for license terms;
  downstream redistributors should confirm the applicable terms with the EmberCat project.

## Agent Speed and zstd

`Vendor/AgentSpeedCore` is a **trimmed source subset**, not a complete or unmodified upstream tree.
The 2026-11-03 cleanup retained 88 of the original 151 Swift files; the contents of retained files were
not changed by that cleanup. Source provenance is recorded in `Vendor/AGENT-SPEED-UPSTREAM.md`.
Agent Speed's MIT license is retained in `Vendor/AGENT-SPEED-LICENSE`.

Only `LiveMonitor` / `SpeedStore` are started. Shared reporting facts/ledger and day aggregation
types remain because the real-time engine references them. On 2026-11-04, local modifications removed
the six pricing files and monetary metrics from the engine (82 Swift files remain); token/timing
metrics and all required source adapters are retained. Traffic sampling, profile/report upload,
network pricing/exchange synchronization, standalone history database services and update clients were
removed. All required local log-source adapters remain.

`Vendor/CZstd` remains the decompression dependency, with its license and original vendoring notes
preserved in that directory. Packaging includes these notices and all three retained license texts.
