# Cgame streamed-texture Safety Pool (Unreal-inspired)

The Unreal Engine texture streamer reserves a configurable MemoryMargin
for unexpected non-streaming allocations. Cgame already supports GPU
material feedback, asynchronous worker/IO threads, a memory-budgeted
mip fitter and optional adaptive prefetch. It previously allowed that
fitter to consume the entire configured streaming budget.

This adds an optional **memory safety margin** in the actual native
fitter. It is not a script-only quality estimate.

## Engine API

- set_safety_margin_percent(int): clamp to 0..25, atomic cross-thread.
- get_safety_margin_percent(): the configured reserve percentage.
- get_streaming_configured_budget_bytes(): full last-pass mip budget.
- get_streaming_safety_reserve_bytes(): last-pass reserve.
- get_streaming_budget_bytes(): actual usable mip budget after reserve.

At the engine default of **0%**, all existing fit and prefetch
decisions remain identical. When memory-budget fitting is disabled,
configured/reserved/usable gauges are all zero and unlimited fitting
remains unchanged. All arithmetic is overflow-safe even for
UINT64_MAX test budgets: division precedes multiplication, with no
floating point precision loss.

The usable budget drives BOTH adaptive speculative prefetch and the
existing heap-based, +/-5% hysteretic texture mip fitter. This does
not physically reserve VRAM, change non-streaming renderer allocations
or guarantee an FPS increase. It limits selected streamed mip bytes
to leave headroom for transient renderer allocations.

## Actual Albion After graphics presets

| Preset | Forward+ reserve | Compatibility/mobile |
| --- | ---: | ---: |
| Performance | 0% | 0% |
| Balanced | 4% | 0% |
| High | 6% | 0% |
| Ultra | 8% | 0% |

GraphicsTextureStreaming.apply already runs through the real
GraphicsQuality preset path. Stock Godot or older Cgame binaries
without the optional native API safely retain their previous behavior.

Albion After's existing Godot Performance monitor registration now
adds ConfiguredBudgetBytes and SafetyReserveBytes alongside BudgetBytes,
which now reports the usable pool. Scene teardown removes all monitors.

## Testing

- New native TextureStreaming doctests: exact MiB reserve, disabled
  budgets, limits 0..25, UINT64_MAX overflow protection.
- Albion headless: native setter/getter, fallback, tier values, budget
  gauges and reset after graphics preset changes.
- Source contract: reserve happens before prefetch and fit, is atomic,
  and actual game uses it.
- Dedicated GitHub workflow: native build, native doctests, import,
  focused game suite and full headless game regression. Source
  contracts alone do not establish runtime or compile correctness.

References:
https://dev.epicgames.com/documentation/en-us/unreal-engine/texture-streaming-metrics-in-unreal-engine
https://dev.epicgames.com/documentation/en-us/unreal-engine/texture-streaming-overview-for-unreal-engine
