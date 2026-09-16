# Heirloom macOS Baseline Profile — Instruments Trace Analysis

Trace: `baseline.trace` (Time Profiler + Hangs, ~191.6s wall clock, Heirloom-macOS pid 38834,
Release build, symbolicated via embedded `Heirloom-macOS.debug.dylib`). Scenario: cold launch
with 102k assets, empty grid for 60s+, Months → All Photos → Years (15s load) → scroll → Months.

Sampling: 1ms user-callstack, on-CPU ("Running") samples only. Main thread: 16,270 samples
(16.27s on-CPU) out of 67,412 total samples across all threads.

## 1. Hangs (Hangs instrument, threshold 250ms)

13 hangs, **12.93s** total hang time, all on the Main Thread.

| # | Start | Duration | Type | Dominant main-thread activity in window |
|---|---|---|---|---|
| 1 | 00:18.738 | 461 ms | Microhang | `MacGridLoader.allRowIds` map / retain churn |
| 2 | 00:19.200 | 306 ms | Microhang | `MacCollectionGridView.Coordinator.reloadIfNeeded` flatMap |
| 3 | 00:23.481 | 351 ms | Microhang | `TimelineRow`/`MacGridSection` `==` (array equality) |
| 4 | 00:25.412 | 639 ms | Hang | `MacGridSection.==` / `TimelineRow.==` chain |
| 5 | 00:27.144 | 1.81 s | Hang | `initializeWithCopy for Asset` / `Asset.==` under AG::Compare |
| 6 | 01:27.191 | 370 ms | Microhang | `TimelineRow.initializeWithCopy` / `Coordinator.reloadIfNeeded` |
| 7 | 01:49.017 | 1.47 s | Hang | `bucketTitle` map / `TimelineRow`/`MacGridSection` `==` |
| 8 | 01:53.383 | 663 ms | Hang | `_stringCompareInternal` under `Array<A>.==` (section header cmp) |
| 9 | 02:05.909 | 827 ms | Hang | `Asset` dict lookup in `sizeForItemAt` (NSCollectionViewFlowLayout sizing pass) |
| 10 | 02:10.424 | 1.98 s | Hang | `initializeWithCopy for Asset` / `Asset.==` under AG::Compare |
| 11 | 02:24.649 | 1.30 s | Hang | `bucketTitle` map / `TimelineRow`/`MacGridSection` `==` + quickFilters filter |
| 12 | 02:38.022 | 741 ms | Hang | `TimelineRow`/`MacGridSection` `==` (array equality), ARC on dealloc |
| 13 | 02:41.583 | **2.00 s** | Severe Hang | `initializeWithCopy for Asset` / `Dictionary<>.== ` under `AG::LayoutDescriptor::Compare` (heaviest of the run) |

Every hang bottoms out in one of three patterns: (a) SwiftUI/AttributeGraph diffing an
`Equatable` `Asset`/`TimelineRow`/`MacGridSection` value, (b) `DateFormatter`/ICU
initialization in `bucketTitle`, or (c) a full-collection rebuild (`flatMap`/`filter`/`map`
over `sections`/`flatIds`/`assetsById`).

## 2. Per-thread sample totals (top 10 of ~40 threads)

| Thread | Samples | Notes |
|---|---|---|
| Main Thread (0x31a32a) | 16,270 | UI thread — see below |
| Heirloom-macOS (0x31a33d) | 15,932 | GRDB reader — 50,209-deep `MacLibraryBrowser.reload()` → GRDB `DatabaseQueue.read`/`Database.inTransaction` chain, effectively pegged for the whole 60s+ launch stall |
| Heirloom-macOS (0x31c522) | 5,732 | worker |
| Heirloom-macOS (0x31ad1f) | 4,544 | worker |
| Heirloom-macOS (0x31c508) | 4,259 | worker |
| Heirloom-macOS (0x31c086) | 4,068 | worker |
| Heirloom-macOS (0x31c1a0) | 3,865 | worker |
| Heirloom-macOS (0x31c24f) | 3,122 | worker |
| Heirloom-macOS (0x31bfe5) | 3,054 | worker |
| Heirloom-macOS (0x31bfe7) | 1,268 | worker |

## 3. Main thread — top inclusive frames (any binary, top 25)

| Samples | % main | Frame |
|---|---|---|
| 14463 | 88.9% | `-[NSApplication run]` / runloop entry (baseline — everything nests under this) |
| 13723 | 84.3% | `-[NSApplication nextEventMatchingMask:...]` (event pump) |
| 13640 | 83.8% | `_CFRunLoopRunSpecificWithOptions` |
| 12206 | 75.0% | `AG::Graph::UpdateStack::update()` — AttributeGraph update pass |
| 12198 | 75.0% | `__CFRunLoopDoObservers` |
| 11815 | 72.6% | `Attribute.init<A>(_:)` closure (AG node creation, i.e. graph churn) |
| 10729 | 65.9% | `AG::Subgraph::update(unsigned int)` |
| 10162 | 62.5% | `GraphHost.flushTransactions()` |
| 8412 | 51.7% | `ViewGraphRootValueUpdater._updateViewGraph<A>(body:)` |
| 7315 | 45.0% | `ViewGraphRootValueUpdater.updateGraph<A>(body:)` |
| 7167–7166 | 44.0% | `NSHostingView.beginTransaction()` closures |
| 6081 | 37.4% | `UC::DriverCore::continueProcessing()` |
| 5918 | 36.4% | `CA::Transaction::commit()` / `flush()` |
| 5439 | 33.4% | `AG::LayoutDescriptor::Compare::operator()` — **value diffing of Equatable attribute inputs** |
| 5347 | 32.9% | `DynamicBody.updateValue()` |
| 5291 | 32.5% | `ViewBodyAccessor.updateBody(of:changed:)` |
| 4535 | 27.9% | `-[NSWindow layoutIfNeeded]` → `_layoutViewTree` (AppKit Auto Layout) |
| 4142 | 25.5% | `+[NSAnimationContext runAnimationGroup:]` |
| 3880 | 23.8% | `MacLibraryBrowser.body.getter` |
| 3763 | 23.1% | `NavigationSplitView.init(sidebar:detail:)` |
| 3385 | 20.8% | `UnwrapConditional.updateValue()` |
| 3366 | 20.7% | `AG::LayoutDescriptor::compare_partial(...)` |

The dominant story: `AG::LayoutDescriptor::Compare`/`compare_partial` (AttributeGraph's
Equatable-based change detection) and the AppKit layout pass together own roughly a third of
all main-thread CPU time — both driven by the size of the value types flowing through
SwiftUI's `@Observable`/`Attribute` graph.

## 4. Main thread — Heirloom/PhotosCore-owned frames, top by inclusive samples

| Samples | % main | Frame |
|---|---|---|
| 3880 | 23.8% | `MacLibraryBrowser.body.getter` |
| 3267 | 20.1% | `MacLibraryBrowser.detailView.getter` |
| 3265 | 20.1% | `MacLibraryBrowser.gridView.getter` |
| 2172 | 13.3% | `Collection.map<A,B>(_:)` (inside gridView row building) |
| 2124 | 13.1% | `MacCollectionGridView.updateNSView(_:context:)` |
| 1896 | 11.7% | `_ArrayProtocol.filter<A>(_:)` |
| 1798 | 11.1% | `MacLibraryBrowser.reload()` |
| 1673 | 10.3% | `MacGridLoader.load(...)` |
| 1658 | 10.2% | `MacGridSection.__derived_struct_equals` (`==`) |
| 1543 | 9.5% | `Asset.__derived_struct_equals` (`==`) |
| 1471 | 9.0% | `initializeWithCopy for Asset` |
| 1338 | 8.2% | `MacLibraryBrowser.body.getter` closure #7 (async reload kickoff) |
| 1208 | 7.4% | `MacLibraryBrowser.displayedSections.getter` |
| 1064 | 6.5% | `MacCollectionGridView.Coordinator.syncSelection(selectedIds:)` |
| 1057 | 6.5% | `MacCollectionGridView.Coordinator.reloadIfNeeded(sections:)` |
| 1031 | 6.3% | `MacLibraryBrowser.dateString(_:)` |
| 1029 | 6.3% | `TimelineRow.__derived_struct_equals` (`==`) |
| 862 | 5.3% | `MacGridLoader.assetsById(store:ids:)` |
| 799 | 4.9% | `Coordinator.reloadIfNeeded` closure #1 |

## 5. Main thread — self-time top (grouped)

| Group | Self samples | % main | Members |
|---|---|---|---|
| Swift ARC traffic | 2,807 | 17.3% | `swift_retain`, `swift_release`, `swift_bridgeObjectRetain/Release` (+ DYLD stubs) |
| `Date` boxing/unboxing | 1,793 | 11.0% | `getEnumTagSinglePayload for Date`, `storeEnumTagSinglePayload for Date`, `outlined init/destroy of Date?`, `type metadata accessor for Date` |
| memory ops | 1,599 | 9.8% | `_platform_memcmp`, `_platform_memmove`, `_xzm_*` allocator |
| `Asset`/`TimelineRow` copy+equality | 1,300 | 8.0% | `initializeWithCopy for Asset/TimelineRow`, `destroy for Asset/TimelineRow`, `Asset.==`, `TimelineRow.==` |

Top individual self-time leaves: `swift_retain` (988), `getEnumTagSinglePayload for Date`
(721), `swift_release` (579), `initializeWithCopy for Asset` (536), `swift_bridgeObjectRetain`
(462), `swift_bridgeObjectRelease` (440).

## 6. Non-main threads — Heirloom/PhotosCore-owned, combined top 10

| Samples | Frame |
|---|---|
| 50,209 | `MacLibraryBrowser.reload()` (background continuation) |
| 50,192 | `SerializedDatabase.execute<A>(_:)` / `DatabaseQueue.read<A>(_:)` (GRDB) |
| 50,178 | `Database.isolated<A>(readOnly:_:)` → `Database.readOnly<A>(_:)` |
| 50,134 | `Database.inSavepoint(_:)` / `Database.inTransaction(_:_:)` |

This is a single background reader thread (0x31a33d, 15,932 samples ≈ 15.9s) spending almost
its entire budget inside one GRDB read transaction driven by `MacLibraryBrowser.reload()` —
this is the direct cause of the 60s+ empty-grid window at launch and the 15s Years-grouping
stall: the whole timeline (buckets + `assetsById` for up to 102k ids, in 400-id chunks) is
fetched serially inside `MacGridLoader.load`/`fetch`/`assetsById`.

## 7. Representative heaviest main-thread stacks

**A. Severe Hang #13 (02:41.58, 2.00s) — AttributeGraph diffing an `Asset` dictionary:**
```
_stringCompareInternal(_:_:expecting:)
protocol witness for Equatable.== in conformance Asset
static Dictionary<>.== infix(_:_:)
MacGridLoader.shouldNotifyObservers<A>(_:_:)      <- @Observable-synthesized change check
MacGridLoader.assetsById.setter
MacGridLoader.load(store:userId:destination:grouping:switcher:)
MacLibraryBrowser.reload()
closure #7 in MacLibraryBrowser.body.getter
```
`assetsById: [String: Asset]` is a plain `@Observable` stored property; every reassignment
makes the Observation runtime compare old vs. new dictionary value-by-value (102k `Asset`
structs, each `Equatable` over ~all fields including `Date`) purely to decide whether to fire
a change notification.

**B. `bucketTitle` — ICU/NSDateFormatter regeneration per bucket:**
```
icu::DateFormatSymbols::DateFormatSymbols(...)
icu::SimpleDateFormat::SimpleDateFormat(...)
-[NSDateFormatter _regenerateFormatter]
-[NSDateFormatter dateFromString:]
static MacGridLoader.bucketTitle(_:)
static MacGridLoader.bucketed(store:scope:grouping:)
MacGridLoader.load(...)
MacLibraryBrowser.reload()
```
A fresh `DateFormatter()` is created and its `dateFormat` mutated twice per call
(`MacGridView.swift:153`), and each `dateFormat` write forces ICU to reparse locale data.

## 8. Source mapping — top Heirloom-owned frames

| Frame | File:Line |
|---|---|
| `MacGridLoader` class / `assetsById`, `sections` (`@Observable` props) | `native-apple/Apps/macOS/Sources/MacGridView.swift:14-25` |
| `MacGridLoader.load(store:userId:destination:grouping:switcher:)` | `native-apple/Apps/macOS/Sources/MacGridView.swift:29-45` |
| `MacGridLoader.bucketed(store:scope:grouping:)` | `native-apple/Apps/macOS/Sources/MacGridView.swift:121-149` |
| `MacGridLoader.bucketTitle(_:)` (new `DateFormatter()` per bucket) | `native-apple/Apps/macOS/Sources/MacGridView.swift:153-161` |
| `MacGridLoader.assetsById(store:ids:)` (400-id chunked serial fetch) | `native-apple/Apps/macOS/Sources/MacGridView.swift:164-169` |
| `MacGridSection` (`Hashable`/`==` over `[TimelineRow]`) | `native-apple/Apps/macOS/Sources/MacGridView.swift:9-12` |
| `Coordinator.reloadIfNeeded(sections:)` (`flatMap` + full `!=` over ids) | `native-apple/Apps/macOS/Sources/MacGridView.swift:448-458` |
| `Coordinator.syncSelection(selectedIds:)` (filters all `flatIds` per call) | `native-apple/Apps/macOS/Sources/MacGridView.swift:475-483` |
| `Coordinator.collectionView(_:layout:sizeForItemAt:)` | `native-apple/Apps/macOS/Sources/MacGridView.swift:572-586` |
| `MacLibraryBrowser.reload()` (drives `loader.load` + album-id scan) | `native-apple/Apps/macOS/Sources/MacMainWindow.swift:612-624` |
| `MacLibraryBrowser.displayedSections` / `matchesQuickFilter(_:)` (recomputed every body eval) | `native-apple/Apps/macOS/Sources/MacMainWindow.swift:502-524` |
| `TimelineRow` (`Hashable`, used as `Array` element compared wholesale) | `native-apple/PhotosCore/Sources/CoreModel/Timeline.swift:15` |
| `Asset` (`Hashable`, ~all-field derived `==`) | `native-apple/PhotosCore/Sources/CoreModel/Asset.swift:5` |

## 9. Notes on symbolication

Full symbol names resolved directly from the trace's embedded `Heirloom-macOS.debug.dylib`
UUID (Release build ships its own debug dylib) — no external dSYM or `atos` step was needed.
A handful of AppKit/SwiftUI frames render as `<deduplicated_symbol>` or raw addresses (e.g.
`0x187d9820c`) where xctrace couldn't resolve system-framework symbols from the export; these
are consistently nested under identified AppKit auto-layout / CoreUI frames and do not affect
the owned-code findings above.
