# Heirloom iOS Instruments trace summary

Process `Heirloom` (bundle `com.immich.heirloom.ios`), physical iPhone 17 Pro Max, iOS 27.0 (24A435). Two traces analyzed read-only; no repo files modified except this report.

- `ios-audit.trace` — 421.16 s, Time Profiler + Hangs + Allocations. Initial/ongoing sync of ~102k assets running throughout; Library grid (UICollectionView) mostly idle, scrolled a little.
- `ios-library.trace` — 241.16 s, Time Profiler + Hangs. Interactive session: Collections tab, album list, photo viewer (SwiftUI TabView `.page` over all ~102k row ids) from the Library grid, Years/Months/Days/All Photos switches, Square toggle, fast-scroll, date scrubber drag, Select mode, Search, Shared, Settings tabs.

Symbolication: succeeded for app code and most system frameworks without needing the DerivedData binary — both trace bundles carry embedded `symbols/stores/*.symbolsarchive` caches from the recording session, and app frames resolve to full demangled Swift names under binary `Heirloom.debug.dylib` (PhotosCore links statically into the app binary, so all app-owned code — CoreModel, LocalStore, Media, Rules, SyncEngine, ImmichAPI, Search, Editing, GRDB, Nuke — surfaces under that one binary). A minority of low-level frames (e.g. some `dyld` internals) remain raw addresses; this does not affect the app-owned tables below. The `/Users/spatel/workspace/github/projects/immich-ios-sync/native-apple/.build/DerivedData-device/Build/Products/Release-iphoneos/Heirloom-iOS.app` binary supplied for symbolication was not needed and was not used.

## Trace 1: ios-audit.trace

### ios-audit.trace: Hangs
Count: 10; total: 8.60 s; worst: 2.10 s

| # | Start (s) | Duration | Type | Heaviest app-owned main-thread frames during hang |
|---|---|---|---|---|
| 1 | 193.08 | 1.71 s | Hang | `protocol witness for UIViewControllerRepresentable.updateUIViewController(_:context:) in conformance PhotoGridView` (1489); `PhotoGridView.updateUIViewController(_:context:)` (1489); `PhotoGridViewController.render()` (1453) |
| 2 | 196.69 | 847.49 ms | Hang | `protocol witness for UIViewControllerRepresentable.updateUIViewController(_:context:) in conformance PhotoGridView` (593); `PhotoGridView.updateUIViewController(_:context:)` (593); `PhotoGridViewController.render()` (559) |
| 3 | 197.54 | 404.16 ms | Microhang | `protocol witness for UIViewControllerRepresentable.updateUIViewController(_:context:) in conformance PhotoGridView` (191); `PhotoGridView.updateUIViewController(_:context:)` (191); `PhotoGridViewController.render()` (151) |
| 4 | 197.94 | 342.48 ms | Microhang | `protocol witness for UIViewControllerRepresentable.updateUIViewController(_:context:) in conformance PhotoGridView` (157); `PhotoGridView.updateUIViewController(_:context:)` (157); `PhotoGridViewController.render()` (105) |
| 5 | 198.84 | 365.86 ms | Microhang | `protocol witness for View.body.getter in conformance LibraryView` (203); `closure #3 in closure #1 in LibraryView.body.getter` (203); `closure #2 in closure #3 in closure #1 in LibraryView.body.getter` (203) |
| 6 | 199.21 | 620.32 ms | Hang | `protocol witness for View.body.getter in conformance LibraryView` (265); `closure #3 in closure #1 in LibraryView.body.getter` (265); `closure #2 in closure #3 in closure #1 in LibraryView.body.getter` (265) |
| 7 | 235.89 | 2.10 s | Severe Hang | `protocol witness for UIViewControllerRepresentable.updateUIViewController(_:context:) in conformance PhotoGridView` (1255); `PhotoGridView.updateUIViewController(_:context:)` (1255); `PhotoGridViewController.render()` (1184) |
| 8 | 353.78 | 900.53 ms | Hang | `protocol witness for UIViewControllerRepresentable.updateUIViewController(_:context:) in conformance PhotoGridView` (535); `PhotoGridView.updateUIViewController(_:context:)` (535); `PhotoGridViewController.render()` (500) |
| 9 | 390.46 | 1.01 s | Hang | `protocol witness for View.body.getter in conformance LibraryView` (507); `closure #3 in closure #1 in LibraryView.body.getter` (507); `LibraryView.body.getter` (507) |
| 10 | 401.12 | 299.65 ms | Microhang | `protocol witness for UIViewRepresentable.updateUIView(_:context:) in conformance ZoomableImageView` (30); `ZoomableImageView.updateUIView(_:context:)` (30) |

### ios-audit.trace: Top 25 main-thread frames (app-owned + notable system), inclusive
Main-thread Running samples: 11224 (~11.2 s on-CPU)

| Samples | % main | Frame | Binary |
|---|---|---|---|
| 5130 | 45.7% | `protocol witness for UIViewControllerRepresentable.updateUIViewController(_:context:) in conformance PhotoGridView` | Heirloom.debug.dylib |
| 5130 | 45.7% | `PhotoGridView.updateUIViewController(_:context:)` | Heirloom.debug.dylib |
| 4625 | 41.2% | `PhotoGridViewController.render()` | Heirloom.debug.dylib |
| 2693 | 24.0% | `closure #1 in PhotoGridViewController.viewDidLoad()` | Heirloom.debug.dylib |
| 2653 | 23.6% | `PhotoGridViewController.configure(_:id:)` | Heirloom.debug.dylib |
| 2637 | 23.5% | `static ThumbHash.decode(base64:)` | Heirloom.debug.dylib |
| 2615 | 23.3% | `static ThumbHash.decode(bytes:)` | Heirloom.debug.dylib |
| 1552 | 13.8% | `protocol witness for View.body.getter in conformance LibraryView` | Heirloom.debug.dylib |
| 1552 | 13.8% | `LibraryView.body.getter` | Heirloom.debug.dylib |
| 1552 | 13.8% | `closure #1 in LibraryView.body.getter` | Heirloom.debug.dylib |
| 1550 | 13.8% | `closure #3 in closure #1 in LibraryView.body.getter` | Heirloom.debug.dylib |
| 1549 | 13.8% | `closure #2 in closure #3 in closure #1 in LibraryView.body.getter` | Heirloom.debug.dylib |
| 1549 | 13.8% | `closure #1 in closure #2 in closure #3 in closure #1 in LibraryView.body.getter` | Heirloom.debug.dylib |
| 1549 | 13.8% | `LibraryView.librarySubtitle.getter` | Heirloom.debug.dylib |
| 495 | 4.4% | `PhotoGridViewController.setSelected(_:)` | Heirloom.debug.dylib |
| 111 | 1.0% | `LibraryGridLoader.load(scope:granularity:store:)` | Heirloom.debug.dylib |
| 111 | 1.0% | `closure #5 in closure #1 in LibraryView.body.getter` | Heirloom.debug.dylib |
| 111 | 1.0% | `partial apply for closure #5 in closure #1 in LibraryView.body.getter` | Heirloom.debug.dylib |
| 111 | 1.0% | `LibraryView.reload()` | Heirloom.debug.dylib |
| 90 | 0.8% | `protocol witness for static Equatable.== infix(_:_:) in conformance Asset` | Heirloom.debug.dylib |
| 88 | 0.8% | `partial apply for thunk for @escaping @isolated(any) @callee_guaranteed @async () -> (@out A)` | Heirloom.debug.dylib |
| 88 | 0.8% | `thunk for @escaping @isolated(any) @callee_guaranteed @async () -> (@out A)` | Heirloom.debug.dylib |
| 80 | 0.7% | `AppSession.reload()` | Heirloom.debug.dylib |
| 80 | 0.7% | `partial apply for closure #1 in closure #3 in RootView.body.getter` | Heirloom.debug.dylib |
| 80 | 0.7% | `closure #1 in closure #3 in RootView.body.getter` | Heirloom.debug.dylib |

### ios-audit.trace: Top 15 background-thread app-owned frames, inclusive
Background Running samples: 75556 (~75.6 s on-CPU)

| Samples | % bg | Frame | Binary |
|---|---|---|---|
| 73587 | 97.4% | `withTaskCancellationHandler<A, B>(operation:onCancel:)` | Heirloom.debug.dylib |
| 73585 | 97.4% | `SerializedDatabase.execute<A>(_:)` | Heirloom.debug.dylib |
| 73585 | 97.4% | `DatabaseQueue.read<A>(_:)` | Heirloom.debug.dylib |
| 73584 | 97.4% | `DispatchQueueActor.execute<A>(_:)` | Heirloom.debug.dylib |
| 73584 | 97.4% | `closure #1 in SerializedDatabase.execute<A>(_:)` | Heirloom.debug.dylib |
| 73584 | 97.4% | `closure #1 in closure #1 in SerializedDatabase.execute<A>(_:)` | Heirloom.debug.dylib |
| 73584 | 97.4% | `partial apply for closure #1 in closure #1 in SerializedDatabase.execute<A>(_:)` | Heirloom.debug.dylib |
| 73584 | 97.4% | `partial apply for closure #1 in SerializedDatabase.execute<A>(_:)` | Heirloom.debug.dylib |
| 73584 | 97.4% | `partial apply for closure #1 in DatabaseQueue.read<A>(_:)` | Heirloom.debug.dylib |
| 73584 | 97.4% | `Database.isolated<A>(readOnly:_:)` | Heirloom.debug.dylib |
| 73584 | 97.4% | `closure #1 in DatabaseQueue.read<A>(_:)` | Heirloom.debug.dylib |
| 73583 | 97.4% | `Database.readOnly<A>(_:)` | Heirloom.debug.dylib |
| 73582 | 97.4% | `throwingFirstError<A>(execute:finally:)` | Heirloom.debug.dylib |
| 73575 | 97.4% | `closure #1 in Database.isolated<A>(readOnly:_:)` | Heirloom.debug.dylib |
| 73575 | 97.4% | `partial apply for closure #1 in Database.isolated<A>(readOnly:_:)` | Heirloom.debug.dylib |


### ios-audit.trace: Memory (Allocations)

The Allocations instrument was armed ("Heap and VM allocations", "Identities of virtual C++ objects", freed-memory events kept) but its data lives under a `track` (`Allocations` with `detail kind="table"` children "Statistics" / "Allocations List" / etc.), not a `table` in `run/data` — `xcrun xctrace export --toc` lists no `allocations`-schema table for this trace, only `tick, life-cycle-period, ..., time-profile, ...` (35 tables, time-profile at 14, potential-hangs at 13). Every `--xpath` attempt against `/trace-toc/run[1]/data/track[@name="Allocations"]/detail[@name=...]` (tried `Statistics`, `Allocations List`, `Allocation List`, `Allocations`, `Generations`, `Call Trees`, `VM Regions`) returned an empty `<trace-query-result/>`. **Peak/persistent memory could not be extracted via `xctrace export` CLI** for this trace; would require opening the trace in the Instruments GUI (Allocations track → Statistics pane) to read memory numbers.

## Trace 2: ios-library.trace

### ios-library.trace: Hangs
Count: 10; total: 4.29 s; worst: 0.90 s

| # | Start (s) | Duration | Type | Heaviest app-owned main-thread frames during hang |
|---|---|---|---|---|
| 1 | 12.95 | 902.53 ms | Hang | `protocol witness for View.body.getter in conformance ViewerPage` (111); `ViewerPage.body.getter` (111); `closure #1 in closure #1 in closure #1 in closure #1 in ViewerView.body.getter` (87) |
| 2 | 57.50 | 307.40 ms | Microhang | `protocol witness for UIViewControllerRepresentable.updateUIViewController(_:context:) in conformance PhotoGridView` (253); `PhotoGridView.updateUIViewController(_:context:)` (253); `PhotoGridViewController.render()` (232) |
| 3 | 90.73 | 325.45 ms | Microhang | `protocol witness for UIViewControllerRepresentable.updateUIViewController(_:context:) in conformance PhotoGridView` (294); `PhotoGridView.updateUIViewController(_:context:)` (294); `PhotoGridViewController.render()` (283) |
| 4 | 120.62 | 319.80 ms | Microhang | `closure #1 in PhotoGridViewController.viewDidLoad()` (298); `PhotoGridViewController.configure(_:id:)` (286); `static ThumbHash.decode(base64:)` (276) |
| 5 | 121.05 | 347.73 ms | Microhang | `closure #1 in PhotoGridViewController.viewDidLoad()` (324); `PhotoGridViewController.configure(_:id:)` (320); `static ThumbHash.decode(base64:)` (311) |
| 6 | 121.40 | 454.48 ms | Microhang | `closure #1 in PhotoGridViewController.viewDidLoad()` (417); `PhotoGridViewController.configure(_:id:)` (373); `static ThumbHash.decode(base64:)` (370) |
| 7 | 130.91 | 554.03 ms | Hang | `static ThumbHash.decode(base64:)` (3); `static ThumbHash.decode(bytes:)` (3); `closure #1 in PhotoGridViewController.viewDidLoad()` (3) |
| 8 | 136.28 | 266.15 ms | Microhang | `__swift_instantiateConcreteTypeFromMangledNameV2` (2); `TimelineSourcesSheet._spaceToggles.init` (1); `TimelineSourcesSheet.init()` (1) |
| 9 | 182.92 | 316.54 ms | Microhang | (no owned frames resolved) |
| 10 | 197.07 | 494.34 ms | Microhang | `partial apply for closure #2 in BackupSettingsSection.body.getter` (58); `static PhotoKitBackupScanner.availableAlbums()` (58); `closure #2 in BackupSettingsSection.body.getter` (58) |

### ios-library.trace: Top 25 main-thread frames (app-owned + notable system), inclusive
Main-thread Running samples: 12497 (~12.5 s on-CPU)

| Samples | % main | Frame | Binary |
|---|---|---|---|
| 6767 | 54.1% | `_UIApplicationFlushCATransaction` | UIKitCore |
| 6195 | 49.6% | `-[UIView(CALayerDelegate) layoutSublayersOfLayer:]` | UIKitCore |
| 4883 | 39.1% | `-[UICollectionView _createPreparedCellForItemAtIndexPath:withLayoutAttributes:applyAttributes:isFocused:notify:]` | UIKitCore |
| 4698 | 37.6% | `closure #1 in PhotoGridViewController.viewDidLoad()` | Heirloom.debug.dylib |
| 4459 | 35.7% | `PhotoGridViewController.configure(_:id:)` | Heirloom.debug.dylib |
| 4301 | 34.4% | `static ThumbHash.decode(base64:)` | Heirloom.debug.dylib |
| 4015 | 32.1% | `__112-[UICollectionView _createPreparedCellForItemAtIndexPath:withLayoutAttributes:applyAttributes:isFocused:notify:]_block_invoke.465` | UIKitCore |
| 3989 | 31.9% | `static ThumbHash.decode(bytes:)` | Heirloom.debug.dylib |
| 3479 | 27.8% | `-[UICollectionView layoutSubviews]` | UIKitCore |
| 3422 | 27.4% | `-[UICollectionView _updateVisibleCellsNow:]` | UIKitCore |
| 3327 | 26.6% | `-[UICollectionView _createVisibleViewsForAttributes:fadeForBoundsChange:notifyLayoutForVisibleCellsPass:]` | UIKitCore |
| 3312 | 26.5% | `-[UICollectionView _createVisibleViewsForSingleCategoryAttributes:limitCreation:fadeForBoundsChange:]` | UIKitCore |
| 2191 | 17.5% | `@objc _UIHostingView.layoutSubviews()` | SwiftUI |
| 2191 | 17.5% | `_UIHostingView.layoutSubviews()` | SwiftUI |
| 2164 | 17.3% | `closure #1 in closure #1 in _UIHostingView.beginTransaction()` | SwiftUI |
| 2128 | 17.0% | `protocol witness for UIViewControllerRepresentable.updateUIViewController(_:context:) in conformance PhotoGridView` | Heirloom.debug.dylib |
| 2128 | 17.0% | `PhotoGridView.updateUIViewController(_:context:)` | Heirloom.debug.dylib |
| 1769 | 14.2% | `PhotoGridViewController.render()` | Heirloom.debug.dylib |
| 1255 | 10.0% | `-[UICollectionView _setCollectionViewLayout:animated:isInteractive:completion:animator:]` | UIKitCore |
| 1255 | 10.0% | `-[UICollectionView setCollectionViewLayout:animated:]` | UIKitCore |
| 878 | 7.0% | `__88-[UICollectionView _setCollectionViewLayout:animated:isInteractive:completion:animator:]_block_invoke_3` | UIKitCore |
| 877 | 7.0% | `__88-[UICollectionView _setCollectionViewLayout:animated:isInteractive:completion:animator:]_block_invoke_4` | UIKitCore |
| 746 | 6.0% | `-[UICollectionView _updateCycleIdleUntil:]` | UIKitCore |
| 739 | 5.9% | `-[UICollectionView _updatePrefetchedCells:]` | UIKitCore |
| 725 | 5.8% | `-[UICollectionView _prefetchItemsForPrefetchingContext:]` | UIKitCore |

### ios-library.trace: Top 15 background-thread app-owned frames, inclusive
Background Running samples: 212542 (~212.5 s on-CPU)

| Samples | % bg | Frame | Binary |
|---|---|---|---|
| 200354 | 94.3% | `withTaskCancellationHandler<A, B>(operation:onCancel:)` | Heirloom.debug.dylib |
| 200349 | 94.3% | `SerializedDatabase.execute<A>(_:)` | Heirloom.debug.dylib |
| 200347 | 94.3% | `partial apply for closure #1 in SerializedDatabase.execute<A>(_:)` | Heirloom.debug.dylib |
| 200347 | 94.3% | `DatabaseQueue.read<A>(_:)` | Heirloom.debug.dylib |
| 200347 | 94.3% | `closure #1 in SerializedDatabase.execute<A>(_:)` | Heirloom.debug.dylib |
| 200346 | 94.3% | `closure #1 in closure #1 in SerializedDatabase.execute<A>(_:)` | Heirloom.debug.dylib |
| 200346 | 94.3% | `partial apply for closure #1 in closure #1 in SerializedDatabase.execute<A>(_:)` | Heirloom.debug.dylib |
| 200346 | 94.3% | `DispatchQueueActor.execute<A>(_:)` | Heirloom.debug.dylib |
| 200329 | 94.3% | `closure #1 in DatabaseQueue.read<A>(_:)` | Heirloom.debug.dylib |
| 200329 | 94.3% | `partial apply for closure #1 in DatabaseQueue.read<A>(_:)` | Heirloom.debug.dylib |
| 200329 | 94.3% | `Database.isolated<A>(readOnly:_:)` | Heirloom.debug.dylib |
| 200327 | 94.3% | `Database.readOnly<A>(_:)` | Heirloom.debug.dylib |
| 200316 | 94.2% | `throwingFirstError<A>(execute:finally:)` | Heirloom.debug.dylib |
| 200295 | 94.2% | `Database.inTransaction(_:_:)` | Heirloom.debug.dylib |
| 200293 | 94.2% | `closure #1 in Database.isolated<A>(readOnly:_:)` | Heirloom.debug.dylib |

## What stands out

### ios-audit.trace
- 45.7% of main-thread Running samples are inside `PhotoGridView.updateUIViewController(_:context:)` → `PhotoGridViewController.render()`, even though the grid was mostly idle — the ongoing 102k-asset sync is repeatedly triggering full grid re-renders on the main thread.
- `ThumbHash.decode(base64:)`/`decode(bytes:)` account for ~23.5% of main-thread inclusive samples, called from `PhotoGridViewController.configure(_:id:)` — per-cell placeholder decoding runs on the main thread during cell configuration.
- 9 of 10 hangs (all but the last, a `ZoomableImageView` microhang) are dominated by the same two call paths: `PhotoGridView`/`PhotoGridViewController.render()` (hangs 1,2,3,4,7,8) and `LibraryView.body.getter` closures (hangs 5,6,9) — grid render and library-subtitle computation are the two hang sources during sync.
- Background CPU is almost entirely GRDB reads: 97.4% of all background Running samples (≈75.6 s thread-aggregate over the 420 s trace) sit inside `SerializedDatabase.execute`/`DatabaseQueue.read`, i.e. essentially all background work during the sync is database reads, not networking or image decode.
- Allocations/memory data was armed for this trace but is not exportable via `xctrace export` CLI (see Memory section) — no peak/persistent RSS figure available from this analysis.

### ios-library.trace
- Main-thread time is dominated by UIKit collection-view machinery, not the SwiftUI viewer: `_UIApplicationFlushCATransaction` (54.1%), `-[UIView layoutSublayersOfLayer:]` (49.6%), `_createPreparedCellForItemAtIndexPath:...` (39.1%) outweigh `_UIHostingView.layoutSubviews`/`beginTransaction` (17.3-17.5%).
- `PhotoGridViewController.configure(_:id:)` (35.7%) and `ThumbHash.decode(base64:/bytes:)` (34.4%/31.9%) are still top-6 main-thread frames during an interactive session with fast-scroll, matching the audit trace — thumbhash decode-on-main is a recurring cost independent of sync activity.
- 7 of 10 hangs are Microhangs (250-550 ms) tied to grid cell configure/render (`PhotoGridViewController.configure/render`, `ThumbHash.decode`); the worst hang (0.90 s, at t=12.95 s, opening the photo viewer) is inside `ViewerPage.body.getter`/`ViewerView.body.getter` closures.
- Background CPU is, again, almost entirely GRDB reads: 94.3% of background Running samples (≈212.5 s thread-aggregate over the 240 s trace) sit inside `SerializedDatabase.execute`/`DatabaseQueue.read` — DB read pressure is not sync-specific, it dominates background CPU during ordinary UI navigation too.
- `UICollectionViewCompositionalLayout`/`_UICollectionCompositionalLayoutSolver` frames appear under the grid re-layout paths (Square toggle, Years/Months/Days/All Photos switches) but individually stay below the top-25 cutoff, sitting behind the cell-creation and CATransaction-flush costs.

## Appendix: exact commands run

```
xcrun xctrace export --input ios-audit.trace --toc
xcrun xctrace export --input ios-library.trace --toc

# hangs (table 13 in both traces)
xcrun xctrace export --input ios-audit.trace   --xpath '/trace-toc/run[1]/data/table[13]' --output hangs-audit.xml
xcrun xctrace export --input ios-library.trace --xpath '/trace-toc/run[1]/data/table[13]' --output hangs-library.xml

# time-profile (table 14 in both traces)
xcrun xctrace export --input ios-audit.trace   --xpath '/trace-toc/run[1]/data/table[14]' --output tp-audit.xml
xcrun xctrace export --input ios-library.trace --xpath '/trace-toc/run[1]/data/table[14]' --output tp-library.xml

# allocations track — all attempts returned an empty <trace-query-result/>
xcrun xctrace export --input ios-audit.trace --xpath '/trace-toc/run[1]/data/track[@name="Allocations"]/detail[@name="Statistics"]'       --output alloc_try.xml
xcrun xctrace export --input ios-audit.trace --xpath '/trace-toc/run[1]/data/track[@name="Allocations"]/detail[@name="Allocations List"]' --output alloc_try.xml
xcrun xctrace export --input ios-audit.trace --xpath '/trace-toc/run[1]/data/track[@name="Allocations"]/detail[@name="Generations"]'       --output alloc_try.xml
xcrun xctrace export --input ios-audit.trace --xpath '/trace-toc/run[1]/data/track[@name="Allocations"]/detail[@name="Call Trees"]'        --output alloc_try.xml
xcrun xctrace export --input ios-audit.trace --xpath '/trace-toc/run[1]/data/track[@name="Allocations"]/detail[@name="VM Regions"]'        --output alloc_try.xml

# analysis (adapted from scripts/heirloom-perf/summarize.py; copy lives in
# /private/tmp/claude-501/heirloom-ios-perf/analyze.py, not committed to the repo)
python3 analyze.py hangs-audit.xml   tp-audit.xml   "ios-audit.trace"   > report-audit.md
python3 analyze.py hangs-library.xml tp-library.xml "ios-library.trace" > report-library.md
```

`analyze.py` streams the `time-profile` XML with `xml.etree.ElementTree.iterparse`, resolves the export's id/ref string de-duplication (thread, thread-state, tagged-backtrace, frame, binary all dedup via `id`/`ref`), and for each `Running`-state sample: counts main vs background thread inclusive frame credit (one credit per unique frame per sample) filtered to binaries whose name contains "heirloom" (app-owned; covers PhotosCore since it's statically linked) or frame names matching notable SwiftUI/UIKit layout tokens (`UICollectionViewCompositionalLayout`, `HostingView`, `AttributeGraph`, `TabView`, `Paging`, `UIPageViewController`, `CATransaction`, `UICollectionView`); and, for main-thread samples whose `sample-time` falls inside a hang's `[start, start+duration]` window, accumulates per-hang app-owned frame counts for the hang table's "heaviest frames" column.
