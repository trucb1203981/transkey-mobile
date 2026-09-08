# Mobile quality continuation: OCR text and batch diagnosis

1. [x] Re-read prior evidence and trace the current camera batch/API contract. Verify current runtime version and device connection.
2. [x] Run bounded real-device comparisons: native crop scaling and up to three small text requests (raw OCR, checked transcription, optional neighboring context). Never export credentials or change model/provider configuration.
3. [x] Implement only evidence-supported local improvements; preserve concurrent changes. Record API changes as proposals unless separately authorized.
4. [x] Run full Flutter analysis/tests, Android release/iOS simulator builds, and physical Android verification on representative inputs. Physical iPhone acceptance remains unverified because no iPhone is connected.
5. [x] Record measured quality/cost limits, restore the regular app, remove task-owned artifacts from the device, and restore device settings.

## Baseline

Prior French gallery: 17 regions / 805 characters, restored bottom-right dialogue but two tail paragraphs remain untranslated even with French selected and a manual retry. Prior Japanese: six cards from 12 Vision fragments. Menu reading access is improved, but OCR and semantic errors remain. Current API runtime and local web HEAD both use b018f4b4e00e5a8c5836d257db9caa6aa8062ca7. The API cache omits scene/context from its key, so a context comparison must account for caching; echoes are not cached. Physical Android reconnected after the user confirmed it.

## Implementation decision

The exact OCR fragment echoed in a live HTTP 201 response (Gemini); a checked transcription translated with the same model. A bounded-context request translated too, but used GPT-5 nano, so context is not isolated as the causal variable. Native 2x/3x scaling and thresholding did not consistently improve the damaged dialogue and degraded parts of the clear-text control; no new pixel transformation will ship from this sample.

The initial experiment attached up to four neighboring paragraphs, capped at 600 UTF-16 characters, to an explicit unresolved-block retry. That experiment could add up to 150 quota characters under the current API formula. It was rejected after the actual UI check described below. The retained implementation preserves existing translations on invalid responses, suppresses duplicate retries, rejects obsolete responses, and adds localized feedback without a context payload.

## Final scope correction

The actual UI context retry returned grammatical French instead of Vietnamese. The context assumption failed a real check, so the context selector/request field/tests were removed. Ship only request-result validation, prior-result preservation, stale-response rejection, duplicate suppression, and localized feedback. Keep context and API cache/quality gates as proposals. The final gates contain 150 passing tests and one pre-existing skip; analysis passes.

## Final device result

The regular Android release verified French per-block unchanged feedback with the old translation preserved, six grouped Japanese manga cards, and a 63-row menu list with an accessible tax/allergy footer. The French result still contains a negation reversal, so semantic accuracy is not accepted. Page/settings races and network errors are covered by deterministic Dio tests, not forced physical-device scenarios. The app is back at home with Auto Detect, its prior draft, account, and clipboard preserved. Six task-owned media rows, their files, and the UI dump were removed; charging stay-awake returned to zero and the owned log capture stopped.
