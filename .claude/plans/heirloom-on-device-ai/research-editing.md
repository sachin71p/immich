# Matching Apple Photos Editing with Public Apple APIs — Research Report

Date: 2026-09-18 · Scope: iOS/iPadOS 27, macOS 27 "Golden Gate" (also iOS 26/macOS 26 "Tahoe" carry-forward features), for the Heirloom (Immich fork) native SwiftUI apps. Goal: match Apple Photos editing using **only public** Apple frameworks, with non-destructive recipes storable server-side and re-rendered on-device.

Convention: **UNVERIFIED** = could not confirm from an Apple primary source (support guide, developer docs, or WWDC session) in this research pass; treat as a hypothesis to re-check in Xcode/docs before relying on it.

---

## Part A — Apple Photos feature inventory

### A.1 One-tap / global
- **Auto Enhance** (magic-wand icon) — one-tap adjustment across exposure, color, definition.
- **Revert to Original** — discards all edits, reconstructs from the original.
- **Compare** (press-and-hold before/after) on iOS; before/after toggle on Mac.
- **Copy Edits / Paste Edits**, incl. batch-paste onto multiple selected photos.
- **Duplicate** (keep original + edited copy).

### A.2 Light / Color / B&W adjustment sliders (iOS + Mac, both under "Adjust")
Exposure, Brilliance, Highlights, Shadows, Contrast, Brightness, Black Point, Saturation, Vibrance, Warmth, Tint, Sharpness, Definition, Noise Reduction, Vignette. B&W-specific sliders (Intensity, Neutrals, Tone, Grain) appear only when a Mono/Silvertone/Noir filter or the B&W adjustment is active. [Apple Support: Edit photos and videos on iPhone](https://support.apple.com/guide/iphone/iphb08064d57/ios)

### A.3 Mac-only Adjust panel (Photos for Mac, present since Photos 3/macOS Sierra, unchanged through macOS 27)
- **Levels** — black/shadow/mid/highlight/white point, per-channel. [Apple Support](https://support.apple.com/guide/photos/apply-levels-adjustments-pht362f9034f/mac)
- **Curves** — RGB + per-channel tone curve with black/mid/white point handles. [Apple Support](https://support.apple.com/guide/photos/apply-curves-adjustments-pht7875d6b19/mac)
- **Selective Color** — hue/saturation/luminance for up to 6 color ranges. [Apple Support](https://support.apple.com/guide/photos/adjust-specific-colors-phtcafe645b6/mac)
- **White Balance** — neutral-gray or skin-tone eyedropper-driven temperature/tint. [Apple Support](https://support.apple.com/guide/photos/adjust-white-balance-pht9b1d4a744/mac)
- **Retouch** brush (spot removal / blemish). [Apple Support](https://support.apple.com/guide/photos/retouch-photos-pht5c38b77c5/7.0/mac/12.0)
- **Sharpen**, **Definition**, **Noise Reduction**, **Vignette** — same underlying sliders as iOS Adjust but exposed as discrete panels on Mac. [Apple Support](https://support.apple.com/guide/photos/reduce-noise-phta85f0d224/mac)
- **Edit with** external app / Photos editing extension (Pixelmator, Affinity, etc.).

### A.4 Filters (both platforms; 9 named looks, each with an intensity slider)
Vivid, Vivid Warm, Vivid Cool, Dramatic, Dramatic Warm, Dramatic Cool, Mono, Silvertone, Noir.

### A.5 Crop / geometry
Crop handles, **Straighten** (rotation wheel), **Vertical/Horizontal perspective** sliders, **aspect-ratio presets** (Square, 16:9, 3:2, etc.), **Flip**, **Rotate** (90°), Auto-crop suggestion as part of Auto Enhance / Straighten.

### A.6 Photographic Styles (post-capture editable)
Tone (Standard/Vibrant/Rich Contrast/Warm/Cool/Black & White presets on iPhone 15/older-generation) and, from **iPhone 16 on ("latest-generation" Photographic Styles)**, independently adjustable **Color** and separate **Tone** sliders plus a **Palette** picker with undertone control, editable after the fact in Camera or in Photos (requires the shot to have been taken in High Efficiency/HEIF with the style metadata attached). [Apple Support: Use latest generation Photographic Styles](https://support.apple.com/guide/iphone/use-latest-generation-photographic-styles-iph629d2cd37/18.0/ios/18.0)

### A.7 Portrait mode edits
- **Depth Control** (virtual f-stop / aperture) slider, adjustable after capture.
- **Change focus point** after capture by tapping a different subject.
- **Portrait Lighting**: Natural Light, Studio Light, Contour Light, Stage Light, Stage Light Mono, High-Key Light Mono — each with an intensity slider. [Apple Support: Use Portrait mode](https://support.apple.com/en-us/102398)
- **"Make a portrait"** — turning an ordinary photo into a Portrait-style image after capture, for iPhone 15/16-class devices that record a **Focus** capture (depth) in non-Portrait shooting modes.

### A.8 Live Photo edits
Choose **Key Photo**, **Loop**, **Bounce**, **Long Exposure**, **Mute** (disable audio), **Trim** the Live Photo range. [Apple Support: Take and edit Live Photos](https://support.apple.com/en-us/104966)

### A.9 Video edits
Trim, the same Adjust sliders as photos, Filters, Crop/rotate, **Slo-mo speed-ramp range** (drag range handles to change where slow motion starts/ends within a slo-mo clip), **Cinematic mode**: change focus subject/point and adjust depth-of-field (aperture) after recording, **Audio Mix** (Cinematic/spatial audio: adjust foreground/background balance with Studio/Cinematic/Frame-style rendering presets) on iPhone 16 Spatial Audio clips, playback **Speed** change.

### A.10 Clean Up (Apple Intelligence object removal)
Introduced iOS 18.1; tap-to-remove smart suggestions or brush/lasso a region; removes shadows/reflections too. Device gate: iPhone 15 Pro/Pro Max, iPhone 16 family, iPad with A17 Pro/M1+, Mac with M1+. [Apple Support: Requirements to use Clean Up](https://support.apple.com/en-us/121429)

### A.11 Markup, Retouch, Red-eye
Markup (draw, text, shapes, magnifier, signature) via the share-sheet Markup tool (PencilKit-backed). Retouch/spot-removal brush (iOS + Mac). Red-eye correction (automatic as part of Auto Enhance, or manual tap).

### A.12 RAW / HDR
- **RAW editing**: full Adjust panel plus RAW-specific behavior (works on ProRAW/RAW originals; noise reduction and sharpening operate on the raw mosaic before demosaic).
- **HDR editing/display**: iPhone HDR photos (gain-map based) display with extra headroom; editing preserves/regenerates the gain map; a **"Mute HDR"** control on Mac lets users reduce/disable the HDR effect for a particular photo. [WWDC24: Use HDR for dynamic image experiences in your app](https://developer.apple.com/videos/play/wwdc2024/10177/)

### A.13 Spatial scenes (iOS 26+)
"Spatial Scene" contextual menu action converts a single flat photo into a parallax 3D scene (foreground/background separation + subtle depth-driven motion), viewable on iPhone (motion-parallax), on Vision Pro, and as a new Lock Screen/wallpaper style. Works without Apple Intelligence, on iPhone 12 and later. [MacRumors: Turn Photos Into 3D Spatial Scenes](https://www.macrumors.com/how-to/ios-3d-lock-screen-effect-spatial-scenes/)

### A.14 iOS 27 / macOS 27 new editing features (WWDC26, June 2026) — the "big three"
Announced as part of the Photos app's largest editing upgrade in years, powered by Apple Intelligence's on-device + private-cloud-compute generative models:
1. **Clean Up (v2)** — much stronger object removal/inpainting, larger-area removal, three quality/speed tiers: **Fast**, **High Quality**, **Auto**. [AppleInsider](https://appleinsider.com/articles/26/06/09/apple-intelligence-gives-photos-in-ios-27-its-biggest-editing-upgrade-in-years)
2. **Reframe / "Spatial Reframe"** — drag to change the apparent camera position/perspective after the fact; the model generates plausible new content to preserve composition (e.g., moving a subject off a sign that was behind their head). Marketed as available in Photos on iOS 27/iPadOS 27/macOS 27.
3. **Extend** — generative outpainting: extends the image canvas beyond the original frame boundary (aspect-ratio conversion, adding surrounding scenery).
4. **Image Playground** shifts from pure generation toward **editing existing photos** — select-and-transform objects within a photo via natural-language prompts, plus first-time photorealistic generation output.

All four are **UNVERIFIED as to whether Apple exposes any of this as a public API** — see Part B §7 (Clean Up / generative fill) for the developer-facing analysis; as of this writing there is no `CleanUp`, `Reframe`, or `Extend` public framework, class, or Core Image filter. Treat Reframe/Extend as **not implementable with public APIs today**; only very approximate substitutes exist (Part B §7, §14).

---

## Part B — API mapping, per feature

### B.1 Auto Enhance
- **API:** `CIImage.autoAdjustmentFilters(options:)` (returns an array of `CIFilter` — auto red-eye, auto-enhance, auto-level). Public since iOS 5 / OS X 10.7.
- **ANE/GPU:** GPU (Core Image graph); some auto-adjustment analysis uses Vision-style saliency internally, not exposed.
- **Fidelity:** Close — Apple's own Photos Auto Enhance likely uses a superset of proprietary heuristics (aesthetics scoring, face-aware tone mapping) beyond what `autoAdjustmentFilters` exposes; expect a visibly different (usually milder) result than Apple Photos.

### B.2 Adjust sliders

| Slider | API | Notes |
|---|---|---|
| Exposure | `CIExposureAdjust` (`inputEV`) | Exact math; Photos' UI range/curve mapping is proprietary — **close**. |
| Brilliance | No direct filter | Apple's "Brilliance" is a proprietary blend of local contrast + shadow lift + highlight recovery. Approximate with a `CIHighlightShadowAdjust` + local-contrast (`CIToneCurve` or a custom local-tone-mapping kernel) combo. **Approximation**. |
| Highlights / Shadows | `CIHighlightShadowAdjust` (`inputHighlightAmount`, `inputShadowAmount`, `inputRadius`) | Close. |
| Contrast / Brightness / Saturation | `CIColorControls` (`inputContrast`, `inputBrightness`, `inputSaturation`) | Exact primitives; Photos' UI curve/scaling is proprietary — **close**. |
| Black Point | `CIToneCurve` (pin the low point) or `CIColorControls` bias | Approximation of Apple's exact curve. |
| Vibrance | `CIVibrance` (`inputAmount`) | Close — same intent (saturation boost that protects skin tones), Apple's internal tuning differs. |
| Warmth / Tint | `CITemperatureAndTint` (`inputNeutral`, `inputTargetNeutral`) | Close. |
| Sharpness | `CISharpenLuminance` (`inputSharpness`) or `CIUnsharpMask` | Close/approximate depending which Apple actually uses (unpublished). |
| Definition | No direct filter | Apple's "Definition" ≈ local-contrast/clarity. Approximate via `CIUnsharpMask` with large radius + low intensity, or a custom Metal local-contrast kernel. **Approximation**. |
| Noise Reduction | `CINoiseReduction` (`inputNoiseLevel`, `inputSharpness`) for rendered images; `CIRAWFilter.luminanceNoiseReductionAmount` / `colorNoiseReductionAmount` for RAW | Close for RAW path (same ML-based RAW 9 pipeline Apple itself uses per WWDC26 session 305 below); approximate for non-RAW JPEG/HEIC. |
| Vignette | `CIVignette` or `CIVignetteEffect` (content-aware, uses image center/radius heuristics) | Close. |

### B.3 Filters (Vivid/Dramatic/Mono/Silvertone/Noir family)
- **Reality check:** Core Image's built-in `CIPhotoEffect*` filters (`CIPhotoEffectChrome`, `CIPhotoEffectFade`, `CIPhotoEffectInstant`, `CIPhotoEffectMono`, `CIPhotoEffectNoir`, `CIPhotoEffectProcess`, `CIPhotoEffectTonal`, `CIPhotoEffectTransfer`) are a **different, older filter set** (dating to iOS 7-era "Photo Booth"-style filters) and do **not** match Apple Photos' current Vivid/Dramatic/Mono/Silvertone/Noir family by name or look, despite the coincidental overlap of "Mono"/"Noir" names.
- **Implementation path:** Apple Photos' current filters are implemented as color-grade **3D LUTs** (color cubes) applied via `CIColorCube(WithColorSpace)`, layered with the same primitive adjustments (contrast, black point, saturation) used for Adjust sliders. This is **not publicly documented as "the" implementation**, but is the standard/only practical way to reproduce a fixed color-grade look in Core Image. Build your own approximate `.cube` LUTs sampled from reference outputs (e.g., photographing a color chart, running it through Photos' filters, and diffing) and apply with `CIColorCubeWithColorSpace` (`inputCubeData`, `inputCubeDimension`, `inputColorSpace`).
- **Fidelity: Approximation.** Apple has never published the LUTs or exact per-filter parameter recipes; you can get visually close but not pixel-identical.

### B.4 Crop / Straighten / Perspective
- **Straighten:** `CIStraightenFilter` (`inputAngle`) — Core Image, iOS 5+/OS X 10.7+. Exact.
- **Perspective correction:** `CIPerspectiveCorrection` (`inputTopLeft/TopRight/BottomLeft/BottomRight`) — iOS 8+/OS X 10.10+, and the convenience `CIFilter.perspectiveCorrectionFilter(...)` on `CIFilter`. Exact for the geometric transform; Apple's UI-driven "Vertical/Horizontal" two-slider abstraction on top of the four-corner primitive is your own mapping to design — **close**.
- **Auto-crop / auto-straighten suggestion:** No single Apple "auto-crop" API; approximate by combining `VNDetectHorizonRequest` (angle) for straighten and `VNGenerateAttentionBasedSaliencyImageRequest` / the newer `VNCalculateImageAestheticsScoresRequest` (iOS 18+, powers Apple's own Memories/highlight quality scoring) for a crop-region heuristic. **Approximation** — Apple's real auto-crop/auto-straighten heuristic is not public.
- **Aspect presets / flip / rotate:** Trivial `CGAffineTransform` / crop-rect math — exact.

### B.5 Photographic Styles (post-capture)
- **Capture-time:** `AVCapturePhotoOutput` writes style metadata into the file; there is a **capture-time** smart-style pipeline (guided by `AVCaptureDevice` scene metering) but **no documented public "AVCaptureSmartStyle" symbol** was found in this pass — **UNVERIFIED**, and in any case would be capture-time only.
- **Re-editing after capture:** Apple Support explicitly says iPhone 16-class ("latest generation") Photographic Styles can be adjusted after the shot in Camera or Photos, but **no PhotoKit/Core Image API was found that lets a third-party app read or re-drive that per-shot Style metadata** (Tone/Color/Palette parameters aren't exposed via `PHContentEditingInput`, `CIRAWFilter`, or ImageIO metadata dictionaries in public docs). **Fidelity: NOT POSSIBLE publicly** to genuinely re-edit Apple's own Style metadata; you can only approximate the visual effect by building your own Tone/Color/Palette sliders on top of `CIColorControls`/`CITemperatureAndTint`/a LUT (same approach as B.3).

### B.6 Portrait mode edits
- **Depth Control (aperture) / focus point:** `CIContext.depthBlurEffectFilter(for:disparityImage:portraitEffectsMatte:hairSemanticSegmentation:orientation:options:)` — returns a ready-to-use `CIFilter` (parameters include a simulated `inputAperture` and a focus rect/point depending on overload). Two overloads exist: a legacy one (`for:disparityImage:portraitEffectsMatte:hairSemanticSegmentation:orientation:`) and a newer one adding `glassesMatte:` and `gainMap:` inputs (added to support later iPhone hardware/HDR portraits). Public since iOS 13 (method), depth/disparity + portrait-matte capture since iOS 12. **Fidelity: Close** — this is very likely the same primitive Apple's own Photos app uses for the depth-blur render; you supply the same auxiliary AVFoundation-captured depth/disparity + portrait-effects-matte (+ hair matte / glasses matte where present) that ship embedded in the HEIC/JPEG. [Apple docs: depthBlurEffectFilter](https://developer.apple.com/documentation/coreimage/cicontext/3228045-depthblureffectfilter)
- **Portrait Lighting (Studio/Contour/Stage/Stage Mono/High-Key):** **No public Core Image filter class or method was found** for these named lighting looks. Evidence: only Apple's private/internal filters implement them (community reverse-engineering projects such as `PortraitPhotos` on GitHub reference private, undocumented `CIFilter` subclasses used internally by Camera/Photos — not part of the public SDK surface). **Fidelity: NOT POSSIBLE publicly** to reproduce Apple's exact Portrait Lighting; the closest public building blocks are the portrait-effects-matte (foreground/background separation) plus your own relighting approximation using `VNGeneratePersonSegmentationRequest`/`VNGenerateForegroundInstanceMaskRequest` masks combined with custom Metal/Core Image dodge-burn/gradient-light kernels. Expect **approximation** quality at best, with real engineering effort.
- **"Make a portrait" from Focus capture (iPhone 15/16 non-Portrait-mode depth):** depends on Apple writing an `AVDepthData`/disparity auxiliary image into ordinary (non-Portrait) captures on these devices; if present in the asset's `PHContentEditingInput`/`AVCapturePhoto`, the same `depthBlurEffectFilter` path applies. **Close** if the depth auxiliary data is actually retrievable (device/capture-mode dependent — **UNVERIFIED** whether Heirloom would ever see this data for photos not shot as Portrait, since it depends on what iOS 15 write-time policy stores).

### B.7 Clean Up / object removal (generative inpainting)
- **No public Apple inpainting/object-removal API exists** for photos as of this research (iOS 27/macOS 27). There is no `CleanUp`, `VNInpaintingRequest`, or Image Playground "edit existing image region" API discovered.
- **Foreground/subject isolation building blocks (public):** `VNGenerateForegroundInstanceMaskRequest` (multi-instance salient-object masks, iOS 17+), `VNGeneratePersonSegmentationRequest` (person matte, iOS 15+), `VNGeneratePersonInstanceMaskRequest` (per-person instance masks, iOS 17+). These give you the *mask*, not the *removal/fill*.
- **Image Playground's `ImageCreator`/`ImagePlaygroundViewController`** (iOS 18.4+) can take a `sourceImage` as visual inspiration for **generating a new stylized image**, but this is generative-from-scratch-with-reference, not region-constrained inpainting of the original pixels — not a substitute for Clean Up. **NOT POSSIBLE publicly** to do true content-aware fill/inpainting with a first-party Apple API.
- **Practical path for Heirloom:** implement your own inpainting using Vision's masks (above) to select the region, then a bundled, converted Core ML model (e.g., LaMa, Apache-2.0) run via Core ML/ANE for the actual fill. This is a **custom on-device ML feature**, not an Apple API wrapper, and should be scoped/tracked separately from "public-API-only" editing parity.

### B.8 Live Photo edits
- **Editing session:** `PHLivePhotoEditingContext` with `frameProcessor` (`PHLivePhotoFrameProcessingBlock`) lets you rewrite every frame of a Live Photo (apply the same Adjust/Filter/Crop CIFilter graph you used for the still) and `saveLivePhoto(to:options:completionHandler:)` to write it back. Public, mature API (iOS 10+). **Fidelity: Exact** for applying photo-style edits consistently across all Live Photo frames.
- **Key Photo change:** exposed via `PHContentEditingOutput`/`PHAssetChangeRequest` (`PHAssetResourceType.pairedVideo`/still-image association) — **UNVERIFIED exact call**, but Apple's own `PHAssetChangeRequest` does support setting a Live Photo's still-image within its video (this is what Apple's own Camera "Live" long-press key-frame picker does); needs direct Xcode verification.
- **Loop / Bounce / Long Exposure:** `PHAsset.playbackStyle` (`PHAsset.PlaybackStyle.livePhoto`, `.videoLooping`, etc.) is **read-only** — it reports how an asset should currently play, but there is **no public setter** for third parties to flag an edited Live Photo as Loop/Bounce/Long-Exposure the way Apple's own Photos app does internally. **Fidelity: NOT POSSIBLE publicly** to set the native badge/style; however, you **can** reproduce the *visual effect* yourself — using `PHLivePhotoEditingContext`'s `frameProcessor` to read all frames and re-time/re-blend them (looping = replay forward-forward, bounce = forward-then-reverse, long-exposure = frame-average) — and export the result as your own video/Live-Photo-like asset. That is an **approximation** implemented entirely in your own code, not a native "Loop" flag.
- **Mute:** part of `PHContentEditingOutput` (`AVAsset`-level — strip/mute the audio track when writing the paired video). Exact.
- **Trim:** adjust the Live Photo's `AVAsset` time range when constructing the paired video for `PHLivePhotoEditingContext`. Exact.

### B.9 Video edits
- **Trim / crop / filters:** `AVMutableComposition` + `AVVideoComposition(asset:applyingCIFiltersWithHandler:)` (also `AVMutableVideoComposition.videoComposition(with:applyingCIFiltersWithHandler:completionHandler:)`) — applies a Core Image filter graph per-frame via `AVAsynchronousCIImageFilteringRequest`. Public, GPU-accelerated. **Exact** mechanism for applying the same Adjust/Filter recipe to video that you use for stills.
- **Slo-mo speed ramp:** `AVMutableComposition`/`AVMutableCompositionTrack.scaleTimeRange(_:toDuration:)` to remap sub-ranges to different playback durations (i.e., speed up/slow down specific ranges) — standard, public, exact mechanism, though Apple's UI-level "drag the range handles on a slo-mo clip" interaction is your own UI to build.
- **Export:** `AVAssetExportSession` (still current) or the newer async export APIs (`AVAssetExportSession.export(to:as:)`, and format/HDR-preservation configuration) introduced around iOS 18. HDR video (HLG/Dolby Vision) preservation through a filtered export requires careful `AVVideoComposition` colorspace/EDR configuration — **works, but nontrivial; treat exact HDR-video round-trip fidelity as UNVERIFIED without hands-on testing.**
- **Cinematic mode (change focus/depth after recording):** `import Cinematic` framework (iOS 17+/macOS 14+): `CNAssetInfo` (reads Cinematic-specific track info), `CNScript` (the mutable collection of focus decisions/transitions/detections — `decisions(in:)`, add/replace decisions), `CNDecision` (a decision to focus on a `CNDetection`/group at a time), `CNDetection`/`CNDetectionTrack`/`CNFixedDetectionTrack`/`CNCustomDetectionTrack` (subject tracking over time), `CNObjectTracker` (convert a tapped point/rect into a tracked detection), `CNRenderingSession` (renders the edited result), `CNImageRenderingSession` (Metal-based shallow-depth-of-field render for **still images**, not just video). **This is a first-class, fully public, Apple-maintained API** used by Photos/Final Cut/iMovie themselves — **Fidelity: Exact.** [developer.apple.com/documentation/cinematic](https://developer.apple.com/documentation/cinematic)
- **Audio Mix (spatial audio, Studio/Cinematic/Frame-style rendering) on iPhone 16 Spatial Audio clips:** also lives in the **Cinematic framework**, not raw AVFoundation: `CNAssetSpatialAudioInfo(asset:)` reads spatial-audio-capable tracks; `audioInfo.audioMix(effectIntensity:renderingStyle:)` produces a standard `AVAudioMix` (`effectIntensity: Float 0...1`, `renderingStyle: CNSpatialAudioRenderingStyle` e.g. `.cinematic`) that you attach to `AVPlayerItem.audioMix` for playback or bake in via `AVAssetWriter`/`AUAudioMix` for export. Public since **macOS/iOS 26 (Xcode 26)**, demonstrated in Apple's own "SpatialAudioCLI" sample tied to WWDC25 session 251. **Fidelity: Exact** — same primitive Apple's Photos app itself uses. [developer.apple.com/documentation/cinematic/editing-spatial-audio-with-an-audio-mix](https://developer.apple.com/documentation/cinematic/editing-spatial-audio-with-an-audio-mix)
- **Speed (simple, whole-clip):** trivial `scaleTimeRange` case above. Exact.

### B.10 Markup
- `PencilKit` (`PKCanvasView`, `PKDrawing`, `PKToolPicker`) for freehand drawing/shapes/signature, layered compositing for text/stickers via `CoreText`/SwiftUI overlays rendered into the final image. Public, mature, identical on iOS/iPadOS/macOS (Catalyst or AppKit-hosted `PKCanvasView` via `NSViewRepresentable`/`PencilKit` on macOS 12+). **Fidelity: Exact** for drawing; Apple's specific sticker/shape library and Magic-Rope selection tool would need your own equivalents.

### B.11 Retouch & Red-eye
- **Retouch (spot removal):** No single named "healing brush" filter; standard approach is `VNDetectFaceLandmarksRequest`/manual brush region + a content-aware clone/blend using `CIHeightFieldFromMask`-style techniques or a simple sampled-patch clone via `CIAffineClamp`/masking. **Approximation** — Apple's Retouch algorithm itself isn't published.
- **Red-eye:** `CIRedEyeCorrection` (`inputEyes` — array of `CIVector` centers/sizes) is part of Core Image's built-in filter set and is also what `CIImage.autoAdjustmentFilters` includes automatically when eyes are detected. **Exact** — this is genuinely the same primitive Apple Photos uses.

### B.12 macOS-only tools (additional detail)
- **Levels / Curves:** No dedicated `CILevels`/`CICurves` Apple filter; build on `CIToneCurve` (spline through up to 5 control points) for Curves, and a `CIColorControls`/`CIToneCurve` combination (mapping black/white/gamma points to a curve) for Levels. **Approximation.**
- **Selective Color (6-range HSL):** No direct filter; approximate with `CIHueSaturationValueGradient`(-derived masks) or a custom Core Image kernel (CIKernel/CIColorKernel) that masks by hue range and applies local HSL shifts. **Approximation**, meaningful engineering effort for a good match.
- **White Balance (eyedropper):** `CITemperatureAndTint` driven by a sampled neutral pixel (`inputNeutral`) — **Exact** mechanism, matches Apple's own approach (this is literally what the filter is for).
- **Sharpen / Noise Reduction / Vignette / Definition:** see B.2 table — same filters apply on Mac.
- **Retouch brush:** see B.11.
- **Edit with external app / Photo Editing Extensions:** see Part C.

### B.13 RAW editing (Apple's "RAW 9" pipeline, WWDC26)
- **API:** `CIRAWFilter` — construct via `CIRAWFilter(imageData:identifierHint:)`, `CIRAWFilter(contentsOf:)`, or from a `CVPixelBuffer` + properties. Confirmed public properties (from Apple's live docs): `baselineExposure`, `boostAmount`, `boostShadowAmount`, `colorNoiseReductionAmount`, `contrastAmount`, `decoderVersion` (`CIRAWDecoderVersion`), `detailAmount`, `exposure`, `extendedDynamicRangeAmount`, `isDraftModeEnabled`, `isGamutMappingEnabled`, `isLensCorrectionEnabled`, `linearSpaceFilter` (attach your own `CIFilter` in linear light before the rest of the RAW pipeline runs), `localToneMapAmount`, `luminanceNoiseReductionAmount`, plus (per WWDC26) `despeckleAmount`/`isDespeckleSupported`, `isHighlightRecoveryEnabled`/`isHighlightRecoverySupported`, and `portraitEffectsMatte` passthrough. Public since iOS 15/macOS 12; new/refined for **RAW 9** in iOS 27/macOS 27 (a tiled Core ML demosaic+denoise model run on the **Apple Neural Engine**) per **WWDC26 session 305, "Enhance RAW image processing with Core Image"** — same pipeline Apple's own Camera/Photos RAW path uses. [developer.apple.com/documentation/coreimage/cirawfilter](https://developer.apple.com/documentation/coreimage/cirawfilter) · [WWDC26 session 305](https://developer.apple.com/videos/play/wwdc2026/305/)
- **New in WWDC26:** `CIImageProcessorKernel`-based tiling controls for RAW-9-scale processing (precise tile-size/buffer control) so third-party apps get the same throughput/quality Apple's own apps get.
- **ANE/GPU:** ANE (ML demosaic/denoise) + GPU (rest of the Core Image graph).
- **Fidelity: Exact** — this is genuinely Apple's own production RAW pipeline exposed publicly; likely the single highest-fidelity item in this whole inventory.

### B.14 HDR editing / gain maps
- **Reading HDR:** `CIImage(contentsOf:options: [.expandToHDR: true])` decodes an Apple Gain-Map HDR (or ISO 21496-1 "Adaptive HDR") image into an HDR-valued `CIImage`; `CIImage.contentHeadroom` reports the available headroom (1.0 for SDR, up to ~8 for iPhone HDR photos). Public since iOS 17/18-era Core Image updates, refined at WWDC24 (session 10177) and WWDC23 (session 10181).
- **Tone-mapping for a given display:** `CIFilter.toneMapHeadroom()` (adapts HDR content to a target headroom, e.g., for SDR displays or lower-headroom EDR).
- **Writing HDR back out (gain map):** `CIContext.writeHEIFRepresentation(of:to:format:colorSpace:options:)` with the `.hdrGainMapImage` option (pass the edited gain image), and, new as of iOS 18/ISO 21496-1 support, `hdrGainMapAsRGB: true` to write a chromatic (RGB) rather than monochrome gain map for better HDR fidelity. Equivalent lower-level path via ImageIO: `CGImageDestinationAddImage` with an SDR base image + a `kCGImageAuxiliaryDataTypeHDRGainMap` auxiliary data dictionary (pixel buffer + format sub-dict + `CGImageMetadata`).
- **Fidelity: Exact** — this is Apple's own supported round-trip for gain-map HDR photos; the same technology iPhone Camera/Photos use.
- **"Mute HDR" per-photo UI control (Mac):** implement as a per-recipe stored `toneMapHeadroom` target/override — straightforward given the above primitives.

### B.15 Spatial scenes / spatial photo conversion
- The generative depth/parallax "Spatial Scene" **conversion** (flat photo → 3D scene) itself has **no confirmed public conversion API on iOS/macOS** — Apple Developer Forum guidance found in this research explicitly states the new `ImagePresentationComponent`/`Spatial3DImage` RealityKit APIs (WWDC24 session 10166, refined for spatial scenes) are **visionOS-only for generating/presenting**, and that assuming an equivalent iOS "convert this JPEG to a spatial scene" API would be incorrect. **Fidelity: NOT POSSIBLE publicly on iOS/macOS** to reproduce Apple's exact Spatial Scene generation; you could approximate a cheap parallax effect yourself using a Vision-derived depth/segmentation mask (foreground/background split) plus your own layered-parallax renderer (SceneKit/Metal), which would be a materially different, lower-fidelity effect. **Approximation at best, and only via custom engineering** — do not scope this as an API integration.

### B.16 Vision-based auto-crop / auto-straighten / segmentation building blocks
- `VNDetectHorizonRequest` → `VNHorizonObservation.angle` — public, exact primitive for auto-straighten (confirms the earlier prompt's "VNHorizonDetectionRequest" name was slightly off; the real symbol is `VNDetectHorizonRequest`).
- `VNGenerateAttentionBasedSaliencyImageRequest` (heat-map of likely visual attention) and `VNCalculateImageAestheticsScoresRequest` (iOS 18+, aesthetic/utility scoring — this is what backs Apple's own Memories/Photos-quality ranking) are the closest public primitives for an auto-crop heuristic; there is **no dedicated "sky segmentation" request** in the public Vision framework (**confirmed absent** — only general semantic segmentation via `VNGeneratePersonSegmentationRequest`/instance-mask requests exist for people/salient objects, not a sky-specific class).
- `VNGenerateForegroundInstanceMaskRequest` (multi-object salient instance masks, iOS 17+), `VNGeneratePersonSegmentationRequest` (single person matte, iOS 15+), `VNGeneratePersonInstanceMaskRequest` (per-person instance masks, iOS 17+) — all public, all run on ANE/GPU via the Vision framework's `VNImageRequestHandler`, useful for selective/local adjustments (e.g., "brighten just the person," or as an input to your own Clean Up/relight approximations).

### B.17 Foundation Models for natural-language edit instructions
- `import FoundationModels` (WWDC25) gives on-device access to Apple's ~3B-parameter on-device LLM via `LanguageModelSession`, with `@Generable` (declare a Swift struct the model must produce an instance of) and `@Guide` (constrain/describe individual properties in natural language, e.g., a `-1...1` range guide on an `exposure: Double` property). This is a strong, fully public fit for "make it warmer" → a `@Generable EditRecipeDelta` struct with guided properties mapped directly onto your CIFilter recipe parameters (from B.2/B.3). Public since iOS 26/macOS 26 (Xcode 26), on-device, Neural-Engine-backed. **Fidelity: N/A (mapping layer, not a visual filter)** — quality depends entirely on your own prompt/schema design, but the plumbing is solid and fully supported. [WWDC25 session 286: Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/)

---

## Part C — Integration considerations

### C.1 PhotoKit write-back (appear + revert inside Apple Photos)
- `PHContentEditingInput`/`PHContentEditingOutput` + `PHAdjustmentData` is the supported path: your extension/app receives a `PHContentEditingInput` (original pixels + any `.adjustmentData` from a *previous* edit by *your own* extension), renders the new output, and returns a `PHContentEditingOutput` carrying the rendered image/video plus a `PHAdjustmentData` (`formatIdentifier` in reverse-DNS form, a `formatVersion` string, and an opaque `data: Data` blob you define — store your **serialized recipe JSON** here, not just a version tag). Apple Photos then shows "Revert to Original" (restores the pristine original) and will re-invoke **your** extension (matched by `formatIdentifier`) if the user re-edits, handing your `PHAdjustmentData` back so you can reconstruct the exact prior state. Fully public, mature (iOS 8+/macOS 10.11+).
- **Confirmed:** Apple Photos **cannot** parse or re-render a third party's `PHAdjustmentData` itself — it only ever shows the rendered pixels for someone else's edit and offers Revert-to-Original; only the extension whose `formatIdentifier` matches can re-open/re-edit. This is expected, standard PhotoKit behavior (not new for iOS 27).
- Symmetrically, **Heirloom cannot read or reinterpret Apple's own Photos adjustment plist** (the internal `com.apple.photo` format is private/undocumented); a `PHAsset` edited in Apple Photos exposes to third parties only: the **current rendered output** (`PHContentEditingInput.fullSizeImageURL`/`displaySizeImage`, i.e., after Apple's edit is baked in) and, via `PHAssetResource` of type `.adjustmentData` / `.fullSizePhoto`/`.adjustmentBasePhoto`, the **original pristine image** if you need to re-derive from scratch. You get "the edited result" and "the original," never Apple's edit *recipe* — confirmed by the design of `PHAdjustmentData`/`PHAssetResource` and consistent across all research sources in this pass.

### C.2 Photo Editing Extensions (`PHContentEditingController`)
- A `PHContentEditingController`-conforming view controller (`startContentEditingWithInput`, `finishContentEditingWithCompletionHandler`, `canHandle(_:)`, `shouldShowCancelConfirmation`) lets Heirloom register a system-wide Photo Editing Extension so a user can invoke "Edit with Heirloom" **from inside Apple Photos** on an asset in the system Photos library, edit it with your Core Image recipe pipeline, and save back via `PHContentEditingOutput`/`PHAdjustmentData` as in C.1. Fully public (iOS 8+), Apple's own "Sample Photo Editing Extension" project is the canonical reference. This is the correct mechanism for "open Heirloom's editor from inside Apple Photos" — **not** a Photos-app plugin API, but a standard iOS/macOS app extension point, which is the only public integration surface Apple offers for this.
- Scope note: this only applies to assets that live in (or are shared into) the **system Photos library** via `PHAsset` — it is unrelated to how Heirloom edits assets that live purely in its own self-hosted library outside PhotoKit.

### C.3 Cross-platform / server-side rendering determinism
- **iOS ↔ macOS:** Both run the same Core Image / Metal stack from Apple, so a recipe expressed purely in terms of public `CIFilter`s (with fixed parameter values, explicit working color space, and explicit `CIContext` options) should render **bit-similar** (not guaranteed bit-*identical* — GPU driver/Metal shader compiler versions can differ subtly across OS versions/hardware) results on iPhone, iPad, and Mac. Pin the `CIContext`'s `workingColorSpace`, `outputColorSpace`, and disable/pin `.useSoftwareRenderer` consistently to minimize drift; treat exact numerical parity as **UNVERIFIED** without a dedicated golden-image regression suite across device families.
- **Server-side (Immich backend) rendering — this is the big gap:** Core Image, Metal, and Vision are **Apple-only**; there is **no Core Image runtime on Linux**. If the Immich server needs to render a Heirloom edit recipe (e.g., to generate a thumbnail, share-link preview, or serve a non-Apple client), it **cannot reuse the same CIFilter graph** — it needs an entirely separate implementation of the recipe's math using a Linux-capable image library such as **libvips** (via `sharp` in Node, or native `libvips`/`pyvips`), reimplementing each primitive (exposure/contrast/curves/vibrance/LUT application/crop/perspective) in that library's terms. This means:
  1. The **recipe format** (what you store server-side) must be an **abstract, versioned parameter set** (e.g., `{filter: "exposure", ev: 0.3}`, a serialized tone-curve, a LUT reference, a crop rect, etc.) — never raw `CIFilter`/`NSCoding` blobs — so it's portable to a from-scratch libvips (or WASM/whatever) renderer.
  2. Expect **visual drift, not pixel parity**, between the Apple-rendered (iOS/macOS) preview and any server-rendered (libvips) preview unless you invest heavily in matching color-management and per-primitive math (e.g., Core Image's vibrance/tone-curve formulas are not published bit-exactly). Plan the product around "close enough for a thumbnail/share preview," not "identical to the on-device edit."
  3. Filters/features with **no public math at all** (B.3 LUT-based Photos filters, B.5 Photographic Styles, B.6 Portrait Lighting, B.7 Clean Up, B.14 Spatial Scenes) can *only* ever be approximated server-side too, to the same or worse degree than on-device, since you're building your own approximation either way — there's no "more authoritative" version to fall back to off-device.

---

## Summary table

| Photos feature | Public API | OS min | Platforms | Fidelity | Notes |
|---|---|---|---|---|---|
| Auto Enhance | `CIImage.autoAdjustmentFilters(options:)` | iOS 5 / OS X 10.7 | iOS/iPadOS/macOS | Close | Apple's own heuristic is a superset. |
| Exposure | `CIExposureAdjust` | iOS 5 / OS X 10.7 | All | Close | |
| Brilliance | none direct | — | All | Approximation | Composite of shadow/highlight/local-contrast filters. |
| Highlights/Shadows | `CIHighlightShadowAdjust` | iOS 5 / OS X 10.7 | All | Close | |
| Contrast/Brightness/Saturation | `CIColorControls` | iOS 5 / OS X 10.7 | All | Close | |
| Black Point | `CIToneCurve`/`CIColorControls` | iOS 5+ | All | Approximation | |
| Vibrance | `CIVibrance` | iOS 5 / OS X 10.7 | All | Close | |
| Warmth/Tint | `CITemperatureAndTint` | iOS 5 / OS X 10.7 | All | Close | |
| Sharpness | `CISharpenLuminance`/`CIUnsharpMask` | iOS 5+ | All | Close/Approx | Apple's exact choice unpublished. |
| Definition | none direct | — | All | Approximation | Local-contrast/clarity emulation. |
| Noise Reduction (RAW) | `CIRAWFilter` noise props | iOS 15+ | All | Close | Same RAW 9 ML pipeline as Apple. |
| Noise Reduction (JPEG/HEIC) | `CINoiseReduction` | iOS 5+ | All | Approximation | |
| Vignette | `CIVignette`/`CIVignetteEffect` | iOS 5+ | All | Close | |
| Filters (Vivid/Dramatic/Mono/Silvertone/Noir) | Custom `CIColorCubeWithColorSpace` LUTs + primitives | iOS 6+ | All | Approximation | `CIPhotoEffect*` filters do NOT match these looks. |
| Straighten | `CIStraightenFilter` | iOS 5 / OS X 10.7 | All | Exact | |
| Perspective correction | `CIPerspectiveCorrection` | iOS 8 / OS X 10.10 | All | Close | Own Vertical/Horizontal UI mapping. |
| Auto-crop/straighten suggestion | `VNDetectHorizonRequest` + `VNGenerateAttentionBasedSaliencyImageRequest`/`VNCalculateImageAestheticsScoresRequest` | iOS 11–18 (varies) | All | Approximation | No public "auto-crop" API. |
| Photographic Styles re-edit | none | — | — | NOT POSSIBLE | No API reads/re-drives Apple's Style metadata. |
| Portrait depth/focus (bokeh) | `CIContext.depthBlurEffectFilter(...)` | iOS 13 (method); depth capture iOS 12+ | All | Close | Same primitive Photos likely uses. |
| Portrait Lighting (Studio/Contour/Stage/High-Key) | none public | — | — | NOT POSSIBLE | Only private/internal Apple filters implement these. |
| Live Photo frame edits | `PHLivePhotoEditingContext`/`frameProcessor` | iOS 10+ | iOS/iPadOS/macOS(Catalyst) | Exact | |
| Live Photo Loop/Bounce/Long Exposure (native flag) | none (write) | — | — | NOT POSSIBLE | `PHAsset.playbackStyle` is read-only; can reproduce visual effect yourself via frame processing. |
| Live Photo mute/trim | `PHContentEditingOutput` + `AVAsset` editing | iOS 10+ | All | Exact | |
| Video filter/adjust | `AVVideoComposition(asset:applyingCIFiltersWithHandler:)` | iOS 9+ | All | Exact | |
| Slo-mo speed ramp | `AVMutableCompositionTrack.scaleTimeRange(_:toDuration:)` | iOS 4+ | All | Exact | |
| Cinematic focus/depth edit | `import Cinematic` (`CNScript`, `CNDecision`, `CNObjectTracker`, `CNRenderingSession`) | iOS 17 / macOS 14 | iOS/iPadOS/macOS/tvOS | Exact | Same framework Photos/Final Cut use. |
| Audio Mix (spatial audio) | `Cinematic` `CNAssetSpatialAudioInfo.audioMix(effectIntensity:renderingStyle:)` → `AVAudioMix` | iOS/macOS 26 | All | Exact | WWDC25 session 251. |
| Clean Up (object removal) | none public | — | — | NOT POSSIBLE | Build your own via Vision masks + bundled Core ML inpainting model (e.g. LaMa). |
| Reframe / Extend (iOS 27) | none public | — | — | NOT POSSIBLE (UNVERIFIED) | No framework/class found; likely private generative model. |
| Markup | `PencilKit` (`PKCanvasView`) | iOS 9+ / macOS 12+ | All | Exact (drawing) | Sticker/shape library is your own. |
| Retouch (spot removal) | none direct | — | All | Approximation | |
| Red-eye correction | `CIRedEyeCorrection` | iOS 5+ | All | Exact | Also inside `autoAdjustmentFilters`. |
| Levels | `CIToneCurve`/`CIColorControls` composite | iOS 5+ | All (Mac UI) | Approximation | |
| Curves | `CIToneCurve` | iOS 5 / OS X 10.7 | All (Mac UI) | Approximation | Apple's exact spline unpublished. |
| Selective Color | Custom `CIColorKernel`/masking | — | Mac UI | Approximation | |
| White Balance (eyedropper) | `CITemperatureAndTint` | iOS 5+ | All | Exact | |
| RAW editing (RAW 9) | `CIRAWFilter` (+ `CIImageProcessorKernel` tiling, iOS 27) | iOS 15+ (RAW 9: iOS 27/macOS 27) | All | Exact | ANE demosaic+denoise. |
| HDR read/tone-map | `CIImage(options:[.expandToHDR:true])`, `contentHeadroom`, `toneMapHeadroom()` | iOS 17/18+ | All | Exact | |
| HDR gain-map write | `CIContext.writeHEIFRepresentation` (`.hdrGainMapImage`, `hdrGainMapAsRGB`) / ImageIO `kCGImageAuxiliaryDataTypeHDRGainMap` | iOS 18+ | All | Exact | |
| Spatial Scene conversion | none on iOS/macOS (`ImagePresentationComponent`/`Spatial3DImage` are visionOS-only) | — | visionOS only | NOT POSSIBLE (iOS/macOS) | Confirmed by Apple DevForum guidance. |
| Foreground/person segmentation | `VNGenerateForegroundInstanceMaskRequest`, `VNGeneratePersonSegmentationRequest`, `VNGeneratePersonInstanceMaskRequest` | iOS 15/17+ | All | Exact (as masks) | No sky-specific request exists. |
| NL edit instructions | `FoundationModels` (`@Generable`, `@Guide`, `LanguageModelSession`) | iOS/macOS 26+ | All | N/A (mapping layer) | On-device ANE-backed LLM. |
| PhotoKit write-back/revert | `PHContentEditingOutput` + `PHAdjustmentData` | iOS 8+ | All | Exact (mechanism) | Only your own extension can re-open your `PHAdjustmentData`. |
| Photo Editing Extension | `PHContentEditingController` | iOS 8+ | iOS/iPadOS/macOS(Catalyst) | Exact (mechanism) | Standard app-extension point, not a Photos plugin API. |
| Server-side (Linux) rendering | none (no Core Image on Linux) | — | Linux server | N/A | Requires a separate libvips/sharp reimplementation of every primitive; expect visual drift, not parity. |

---

## Key risks / open questions to close before committing to a design

1. **Photographic Styles, Portrait Lighting, Clean Up, Reframe/Extend, Spatial Scenes** all lack public APIs — any Heirloom feature that claims to "match" these will actually be a from-scratch approximation, some requiring bundling a third-party ML model. Scope/estimate these separately from the "wrap Apple's API" work.
2. **RAW 9, HDR gain maps, Cinematic (focus + audio mix), and depth-blur portraits** are the strongest matches — genuinely the same pipelines Apple's own apps use, fully public, ANE/GPU-accelerated. Prioritize these first for maximum fidelity-per-engineering-hour.
3. **Server-side rendering parity is structurally impossible** to make bit-identical (no Core Image on Linux); the recipe format must be designed as an abstract, versioned, cross-renderer parameter set from day one, not a serialized `CIFilter` graph.
4. A few specifics remain **UNVERIFIED** and should be confirmed hands-on in Xcode 27 before committing to an implementation: (a) whether `PHAssetChangeRequest` truly supports setting a Live Photo's key frame publicly; (b) exact HDR-video (Dolby Vision/HLG) preservation behavior through a filtered `AVAssetExportSession`; (c) whether Reframe/Extend expose *any* private-but-discoverable symbol in the iOS 27 SDK headers (worth a header-diff pass, e.g. via `class-dump`/SDK header scan, even though such symbols would be private/unsupported for App Store use).
