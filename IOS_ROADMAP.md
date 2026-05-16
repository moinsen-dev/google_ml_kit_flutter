# iOS Feature Parity Roadmap

This document tracks the gap between Android and iOS feature support in `google_ml_kit_flutter`, and outlines the plan to close it.

**Last updated:** 2026-05-16

---

## Feature Matrix

| # | Feature | Package | Android | iOS | Status |
|---|---------|---------|:-------:|:---:|:------:|
| 1 | Barcode Scanning | `google_mlkit_barcode_scanning` | ✅ | ✅ | Done |
| 2 | Face Detection | `google_mlkit_face_detection` | ✅ | ✅ | Done |
| 3 | Text Recognition | `google_mlkit_text_recognition` | ✅ | ✅ | Done |
| 4 | Image Labeling | `google_mlkit_image_labeling` | ✅ | ✅ | Done |
| 5 | Object Detection | `google_mlkit_object_detection` | ✅ | ✅ | Done |
| 6 | Digital Ink Recognition | `google_mlkit_digital_ink_recognition` | ✅ | ✅ | Done |
| 7 | Pose Detection | `google_mlkit_pose_detection` | ✅ | ✅ | Done |
| 8 | Selfie Segmentation | `google_mlkit_selfie_segmentation` | ✅ | ✅ | Done |
| 9 | Language Identification | `google_mlkit_language_id` | ✅ | ✅ | Done |
| 10 | On-Device Translation | `google_mlkit_translation` | ✅ | ✅ | Done |
| 11 | Smart Reply | `google_mlkit_smart_reply` | ✅ | ✅ | Done |
| 12 | Entity Extraction | `google_mlkit_entity_extraction` | ✅ | ✅ | Done |
| 13 | **Subject Segmentation** | `google_mlkit_subject_segmentation` | ✅ | ✅ | **Done** — iOS 26+ via `VNGenerateForegroundInstanceMaskRequest` |
| 14 | **Document Scanner** | `google_mlkit_document_scanner` | ✅ | ✅ | **Done** — iOS 26+ via `VNDocumentCameraViewController` |
| 15 | **Face Mesh Detection** | `google_mlkit_face_mesh_detection` | ✅ | ❌ | **Open** — needs implementation |
| 16 | **GenAI Summarization** | `google_mlkit_genai_summarization` | ✅ | ❌ | **Open** — needs GenAI backend |
| 17 | **GenAI Proofreading** | `google_mlkit_genai_proofreading` | ✅ | ❌ | **Open** — needs GenAI backend |
| 18 | **GenAI Rewriting** | `google_mlkit_genai_rewriting` | ✅ | ❌ | **Open** — needs GenAI backend |
| 19 | **GenAI Image Description** | `google_mlkit_genai_image_description` | ✅ | ❌ | **Open** — needs VLM backend |
| 20 | **GenAI Speech Recognition** | `google_mlkit_genai_speech_recognition` | ✅ | ❌ | **Open** — needs STT backend |
| 21 | **GenAI Prompt** | `google_mlkit_genai_prompt` | ✅ | ❌ | **Open** — needs LLM backend |

**Current score:** 14 / 21 features have iOS parity (67%)

---

## Completed Work

### Subject Segmentation (iOS 26+)
- **Native API:** `VNGenerateForegroundInstanceMaskRequest` (Vision framework)
- **Capabilities:** Multi-subject instance masks, foreground bitmap extraction, confidence masks, per-subject bounding boxes
- **Implementation:** `packages/google_mlkit_subject_segmentation/ios/Classes/GoogleMlKitSubjectSegmentationPlugin.swift`

### Document Scanner (iOS 26+)
- **Native API:** `VNDocumentCameraViewController` (VisionKit)
- **Capabilities:** Native document scanning UI, JPEG + PDF output, page limit support
- **Implementation:** `packages/google_mlkit_document_scanner/ios/Classes/GoogleMlKitDocumentScannerPlugin.swift`

---

## Open Items

### 1. Face Mesh Detection

**Problem:** Google's ML Kit provides a 468-point dense face mesh with triangles and contours. Apple has no public API for dense face mesh on the rear camera.

**Options:**

| Option | Approach | Pros | Cons |
|--------|----------|------|------|
| A | `VNDetectFaceLandmarksRequest` (~52 landmarks) | Works on all cameras, simple implementation | Not a mesh — just sparse landmarks. Doesn't match the 468-point Dart API |
| B | ARKit `ARFaceAnchor` dense mesh | True dense mesh | Requires TrueDepth camera (front-facing only). No rear camera support |
| C | **MediaPipe Face Mesh → Core ML** | True 468-point mesh, any camera | Requires model conversion (~10 MB download). Most complex implementation |

**Recommendation:** Option C for true parity, or Option A as a pragmatic fallback.

---

### 2. GenAI Speech Recognition

**Problem:** Android uses AICore for context-aware speech transcription. Apple has no GenAI speech API.

**Options:**

| Option | Approach | Pros | Cons |
|--------|----------|------|------|
| A | `SFSpeechRecognizer` (Speech framework) | Native, on-device, simple | Basic STT only — no GenAI context awareness |
| B | **Whisper.cpp + FFI** | High-quality transcription, open-source | ~150–500 MB model. Requires Rust/FFI bridge |

**Recommendation:** Option A as MVP, then Option B for quality parity.

---

### 3–7. GenAI Text + Image Features

These five features share the same fundamental problem: **Apple Intelligence Writing Tools are UI-only**. There is no programmatic API for summarization, proofreading, rewriting, image description, or general prompt inference.

#### Path A: On-Device Models (True Parity)

Convert small open-source models to Core ML or run via MLX Swift:

| Feature | Model | Size | Min Device |
|---------|-------|------|------------|
| Summarization / Proofreading / Rewriting / Prompt | **Phi-3 mini** (3.8B) or **Llama 3.2 1B** | 1–4 GB | iPhone 15 Pro, M-series iPad |
| Image Description | **Moondream 2** (1.6B) or **LLaVA-Phi-3** | 1–3 GB | iPhone 15 Pro, M-series iPad |

**Pros:** Fully on-device, private, offline, matches Android AICore architecture
**Cons:** Large downloads, slower inference, high-end device requirement, complex model pipeline

#### Path B: Remote API Bridge (Fastest)

Route all GenAI calls to an external API (OpenAI, Anthropic, Gemini, or self-hosted).

**Pros:** Best quality, no downloads, works on all iOS 26+ devices, fast to implement
**Cons:** Requires internet, not on-device, costs money, architectural mismatch with Android

#### Path C: Skip / Partial

Only implement features where Apple has a native fallback:
- Speech Recognition → `SFSpeechRecognizer`
- Image Description → `VNClassifyImageRequest` (labels only, not sentences — very limited)
- Text features → not implementable without external model or API

---

## Architecture Decision Needed

Before proceeding with the open items, we need to decide on the **GenAI backend strategy**:

1. **On-Device (Core ML / MLX)** — True parity, but heavy engineering
2. **Remote API Bridge** — Fastest path, but requires network + API keys
3. **Hybrid** — On-device where possible (Speech = Whisper, Vision = Moondream), remote for text
4. **Skip GenAI** — Focus only on Face Mesh + Speech, leave text GenAI for future Apple APIs

This decision affects all 5 GenAI packages and determines the implementation approach for each.

---

## Suggested Implementation Order

### Phase 1: Quick Wins (Low Effort, High Value)
1. **Face Mesh Detection** — Option A (52 landmarks) or Option C (MediaPipe Core ML)
2. **Speech Recognition** — Option A (`SFSpeechRecognizer`)

### Phase 2: GenAI Backend (Depends on architecture decision)
3. Choose GenAI path (On-Device / Remote / Hybrid)
4. Implement shared GenAI inference layer (Core ML model loader or API client)
5. Implement Summarization
6. Implement Proofreading
7. Implement Rewriting
8. Implement Image Description
9. Implement Prompt

### Phase 3: Polish
10. Update root README feature matrix
11. Add iOS-specific Dart analysis tests
12. Verify SwiftLint on all new iOS code

---

## Notes

- **Minimum iOS version:** 26.0 (globally bumped from 15.5 to support Vision framework features)
- **Apple's iOS version scheme:** Apple skipped from iOS 16 to iOS 26 to align version numbers with calendar years
- **Device requirements for on-device LLMs:** iPhone 15 Pro / Pro Max, any M-series iPad, or newer
