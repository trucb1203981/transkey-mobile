---
date: 2026-09-08
type: fix
status: complete-with-verification-limits
---

# Preserve camera results during failed or obsolete retries

## Root cause and live diagnosis

The raw French OCR fragment returned unchanged in a real HTTP 201 response. The current API logged one script leak in one block but accepted that result: its minimum leak threshold is one, so a one-block retry can be entirely untranslated and still report success. A checked transcription translated with the same Gemini model. A request with neighboring context also translated, but a different model won the provider race, so the experiment does not isolate context as the cause. Current local API HEAD and deployed runtime both match b018f4b4e00e5a8c5836d257db9caa6aa8062ca7; no backend or provider configuration was changed.

The camera's old per-block retry called a batch helper that falls back to source text on errors. It then overwrote the previous translation unconditionally. It checked only index bounds after awaiting the API, so a response could also overwrite the same index on another photo or after language/scene changes.

## Native comparison and rejected transformation

Eight real Android ML Kit reads compared two French crops at 1x, 2x, 3x, and 2x with adaptive threshold. Damaged dialogue mean line confidence was 0.571 / 0.536 / 0.600 / 0.469, with different recognition errors in every variant. Clear-control confidence was 0.703 / 0.695 / 0.690 / 0.615; scaling lost letters and thresholding introduced errors. Confidence is not an accuracy score. The comparison did not support shipping another universal image transformation, so this pass changes no pixel algorithm.

## Shipped changes

- One explicit per-block retry carrying the selected language and scene, with no new context payload or semantic retry loop.
- Empty, malformed, uncertain-marker, echoed, unchanged, and network-error responses leave the previous translation intact.
- Ignore obsolete requests/responses after page, content, language, or scene changes; suppress duplicate in-flight retries of the same block.
- Add unchanged/failure feedback in all 14 app locales.
- Add 13 deterministic regressions for request contract, valid replacement, old-result preservation, malformed/echo/uncertain/network cases, and delayed obsolete responses.

## Rejected context experiment

A temporary implementation selected four neighboring paragraphs, capped at 600 UTF-16 characters. On the actual production UI it changed the problematic dialogue into grammatical French, still the wrong target language. This disproved the assumption that neighboring context reliably solves the translation issue. The unstick facts file `/tmp/unstick-camera-source-echo.md` records the checks. The context selector, request field, and associated tests were removed before the final build. Context remains an API evaluation proposal, not a shipped mobile feature.

## Gates

Full Flutter analysis passes. Full suite: 150 passed, one pre-existing smoke test skipped. Android release build passes (95.9MB). iOS simulator build passes; native ML Kit dependencies exclude arm64 simulator support, so this is x86_64 compilation, not physical iPhone camera acceptance. Final production Android UI checks passed for the state/access behavior described below. Gates after removing the experiment are in the safe log files listed below.

## Cost evidence and limits

The three diagnostic text requests recorded API telemetry costs of 0.0003706 USD (raw, Gemini, 2255ms device round trip), 0.0003739 USD (checked transcription, Gemini, 921ms), and 0.0007974 USD (context, GPT-5 nano, 6763ms). Total recorded cost was 0.0015419 USD. These are returned telemetry values, not reconciled billing; unreported cancelled hedge work can add cost. No model price claim or general speed/quality benchmark is made.

The final retry sends the existing single source fragment only. It adds no context quota, semantic retry loop, or Vision upload. Existing API transport retries and provider races remain in place. Contextual recovery and wrong-target-language validation need a controlled backend evaluation before rollout.

## API proposals

1. Separate an unresolved ordinary sentence from legitimate unchanged names/codes and from transport success. Report a per-block quality status for a one-block echo. Do not blindly lower the threshold and trigger every expensive provider on every proper name.
2. The shared cache key currently contains source language, target language, and text, but no scene/context/prompt version. Explicit mobile force-refresh only bypassed the local cache. Add a bounded authenticated refresh contract; key scene/version and bypass or fingerprint contextual requests. Verify repeated text across menu/manga, different contexts, and parallel requests before rollout.
3. Menu prompts explicitly drop allergen legends and non-dish notes. Preserve allergen, ingredient, quantity, negation, and ordering-condition information as typed notes. Evaluate prompt/schema changes with checked menu transcriptions before changing the model tier. The mobile reading list preserves omitted source rows but cannot supply their missing translation.

## Evidence

- /tmp/transkey-quality-comparison.json: sanitized native/API comparison, no credentials.
- /tmp/transkey-compare-device.log: task-owned Flutter log capture, separated by PID.
- /tmp/transkey-retry-safe-{analyze,suite,android,ios}.log: final gates.
- /tmp/transkey-retry-safe-runtime.log: final production PID 22829 Flutter-only capture, 48 lines with zero Exception/ERROR/RenderFlex/overflowed/DioError markers. This is not a full native crash or performance audit.
- /tmp/transkey-retry-safe-unchanged.png: French retry preserved its previous result and showed localized unchanged feedback.
- /tmp/transkey-retry-safe-japanese-result.png: six readable grouped Japanese manga cards.
- /tmp/transkey-retry-safe-menu-list.png and /tmp/transkey-retry-safe-menu-footer-final.png: 63-row menu list, original-only entries, and complete tax/allergy footer.
- docs/mobile-quality-plan-2026-09-08.md: execution plan and decision boundaries.

## Device verification and cleanup

The regular production target replaced the temporary diagnostic target and was checked on the connected Android device:

- French gallery: 17 blocks / 805 characters, one native paragraph recovered, no Vision request. A manual block retry returned the existing translation and displayed the new unchanged snackbar without replacing that result. Tail paragraphs translated in this run, but the bottom-left sentence reversed the source negation ("JE NE POSSEDE PLUS DE X1" became an assertion of having more X1). Provider/cache variability prevents attributing semantic improvement to this mobile change.
- Japanese gallery: weak native text triggered the existing Vision fallback; 12 fragments became six cards with three bounded text repairs. The logged Vision stage was 9530ms in this one run, not a general latency benchmark.
- Dense Japanese menu: the list showed 63 entries, kept original-only rows visible, and scrolled to the complete translated tax/allergy footer. Some food labels remain incorrect; list visibility is not semantic acceptance.
- Obsolete-page/settings responses and network-error retention passed deterministic tests. No physical network outage or page-switch race was forced.

One menu control initially selected a task-created screenshot because Android indexed screenshots written to shared storage, changing picker order. That run was excluded. The correct source was then selected using a fresh picker screenshot; subsequent screenshots streamed directly to the host.

The app is back at home with Auto Detect, its prior draft, account, clipboard, and the user's floating Telegram UI preserved. Six verified task-owned MediaStore rows and their files were deleted, along with the empty fixture directory and UI dump. The original charging stay-awake setting (0) was restored and the exact owned log capture stopped. User source images remain unchanged. No commit, push, deployment, or publication was requested. Physical iOS behavior and retention effects remain unverified.
