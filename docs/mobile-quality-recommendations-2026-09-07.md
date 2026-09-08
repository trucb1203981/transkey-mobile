# Mobile quality and repeat-use recommendations

## Implemented locally

Android OCR now prepares images outside the UI isolate, normalizes EXIF rotation before resizing, and maps recognized regions back to the upright source with independent horizontal/vertical scales. ML Kit, preprocessing passes, and DBNet use one working coordinate system; scratch images are released on success and failure.

Adaptive thresholding now uses the shorter image axis to select its local window, preserving output under 90-degree rotations. A typed integral buffer provides predictable four-byte storage per cell for normal OCR sizes, with a wider fallback for unusually large inputs. Two low-contrast rotation regressions fail against the previous algorithm and pass against the updated version; dark/bright strokes under uneven lighting and uniform-background controls also pass.

Gallery import keeps menu/document/manga images up to 2560 pixels and other dense/default scenes up to 2048. Android OCR uses 2048 for menu/document/screenshot and 2560 for manga. The existing vision upload caps remain unchanged. More pixels can increase local processing time and memory; device measurements and a bounded gallery batch remain necessary.

Camera translation reuse now requires exact content after whitespace normalization. Punctuation, currency, signs, case, CJK characters, numbers, and negation are preserved. This removes false reuse at the cost of extra requests when OCR changes its reading; the actual cost delta needs production cache-hit measurements.

Automatic history trimming retains favorites as well as locked entries. Users can still explicitly remove saved content. A very large collection of saved entries remains stored in SharedPreferences; a future SQLite migration should be considered based on measured load times, with account isolation and a reversible migration.

The gallery handoff now removes the live preview for one rendered frame before disposing its controller. Previously, opening the picker produced `CameraException(Disposed CameraController, buildPreview() was called on a disposed CameraController.)` on the physical Android device. Background teardown is suppressed while the picker owns the transition, so it cannot schedule a camera restart into the gallery.

## API findings and proposed fixes

These findings come from current source, not live authenticated production requests. This task changed no API code or provider configuration, and pre-existing web edits were preserved.

| Priority | Evidence and consequence | Proposed action | Cost impact |
| --- | --- | --- | --- |
| P1 | `prompts/features/translate-batch.ts:50-68` deliberately drops non-dish fragments, including allergen legends. A synthetic menu's separate "Contains peanuts" line remained untranslated; the real Japanese menu's combined allergy footer did translate. The omission is observed, but the precise production route was not captured. | Preserve ingredient, allergen, dietary, quantity, and ordering-condition notes with their associated item. Add semantic checks for required notes and negation; separate source prices from translated names. Evaluate both text-batch and vision prompts on the same images. | Prompt/schema work first; no blanket model upgrade. Slightly longer output is possible. |
| P1 | `translate.controller.ts:1272` keys Google Vision OCR cache by image bytes, but `google-vision.service.ts:459` scales cached boxes to caller-supplied original dimensions. Repeating identical uploaded bytes with different original dimensions replays coordinates from the first request. | Cache boxes in uploaded-image or normalized coordinates, then transform for every response. An interim key must include original dimensions and a geometry version. Test identical image bytes at two target sizes. | No model upgrade. Normalized storage preserves cache reuse. |
| P1 | `canUse()` checks counters before the external OCR call; `recordUsage()` is scheduled afterward. Concurrent gallery calls can all pass the same remaining budget. | Reserve one unit atomically before dispatch, reconcile only confirmed outcomes, and deduplicate identical in-flight image requests. Test simultaneous requests at the final remaining unit. | Protects the free-tier ceiling and avoids duplicate OCR spending. |
| P2 | `translate.service.ts:3563` notes that aborted hedge losers are not included in accumulated cost. This leaves a gap between successful-response telemetry and potentially billable provider work. | Track attempts, hedge launches, returned usage, and unresolved aborted usage separately; reconcile against provider billing. Do not infer that an HTTP abort cancels provider billing. | Better budget visibility; defer hedge tuning until actual tail latency and charges are known. |
| P2 | `getCachedBlocks()` has no age condition; 30-day cleanup occurs probabilistically on writes. Reads can continue serving older entries when writes stop. | Enforce TTL and OCR/prompt version on reads. Prefer normalized geometry and exact source keys. | Small increase in legitimate refresh calls. |

## Model and image algorithm strategy

1. Keep native OCR first for supported scripts. Preserve legible pixels before introducing a more expensive model. Google's guidance recommends at least about 16x16 pixels per character, with little added benefit beyond 24x24. This supports a scene-aware cap rather than one aggressive cap for every image. [ML Kit input guidance](https://developers.google.com/ml-kit/vision/text-recognition/v2/android#input-image-guidelines).
2. Keep the existing cheap vision tier for difficult images, with escalation only after a quality failure. Evaluate script leakage, omitted regions, changed numbers, reading order, and translation adequacy separately. A long or high-confidence OCR string is not evidence of semantic correctness.
3. Evaluate dense-image tiling or selective region crops before enlarging DBNet's global input. Keep fixed-size detector tiles bounded and deduplicate overlaps; benchmark against small glyphs and neighboring manga bubbles. This is a proposal, not a verified accuracy improvement.
4. Evaluate adaptive contrast/threshold passes on a labeled set of faded menus, glare, dark backgrounds, and small text. Do not enable extra passes globally based on synthetic success alone. Compare clean-image latency and recall to avoid slowing ordinary scans.
5. Do not switch all traffic to a larger model. Build a representative set of at least 150 consented or synthetic/public test images across supported scripts, rotations, menus, documents, signs, and comics. Measure character error rate, correct translated regions, box overlap, p50/p95 latency, peak memory, cache hits, fallback rate, and billed cost per successful scan.

## Initial real-image device observations

Four user-provided files from `/Users/trucnguyen/Desktop/Record` were copied unchanged into a task-only Android photo folder and selected through the real system picker in the release app. Originals were not edited or added to Git. Menus used the menu scene; both comics used the manga scene; source was Auto and target Vietnamese. This is a four-image diagnostic sample, not an accuracy benchmark.

| Source relative to Record | Device observation | Follow-up |
| --- | --- | --- |
| `japan menu/2025_menu_kohoku_all_page-0001-1-scaled.jpg` (1808x2560) | Many small labels translate and prices remain visible, but some labels are semantically unreliable and long cards overlap nearby rows or extend below the photo. The allergy footer is translated on this sample. | Label dish names, modifiers, prices, and notes separately. Use a compact row list when full translated text cannot fit; retain a tap-through full translation instead of silently truncating it. |
| `korean menu/491585727_1313302746887325_8485083602324437630_n.jpg` (1440x1440) | The actual text is Japanese despite the folder name. Both menu pages complete, but examples such as the bottom-center garbled dish label remain unsuitable for ordering. | Classify from image/script evidence, not folder names. Compare source OCR against a checked transcription before attributing errors to the translation model. |
| `Manga/Screenshot_2026-06-02-19-19-18-444_com.android.chrome.jpg` (1080x2400) | Native preflight yielded 30 characters, then Vision returned 12 blocks in 6638ms. Vietnamese output is visible, but one right-side speech bubble is fragmented into several cards and the name near the lower bubble is displaced. | Evaluate bubble-level grouping, vertical right-to-left reading order, and box alignment even after Vision succeeds. Increasing model cost alone is not established as a fix. |
| `comic/img169.jpg` (1078x1600) | The native route accepted 6 blocks / 713 characters without a full-page vision call. Several dialogue regions are merged across panels, translated cards obscure art, and a bottom-right dialogue remains uncovered. | Gate native acceptance on region coverage and panel boundaries as well as character count. Test a bounded crop fallback for invalid regions and evaluate Latin-script auto selection; the current auto manga hint defaults to Japanese. |

Those initial results led to the region and overlay continuation below. The acceptance target remains: preserve verified dialogue/items, keep source and translated geometry associated, avoid automatic card overlap, and provide complete readable text when the photo has insufficient space. Semantic accuracy and coverage still need separate evaluation.

## Implemented region and overlay continuation

Native OCR dedup now requires matching content and overlapping source boxes; it preserves a complete selected read instead of combining text with another read's smaller box. Latin crops retain independent paragraph positions. A controlled Android probe changed the French page from 6 baseline blocks to 13 independent regions; this is a geometry diagnostic, not a labeled accuracy score.

The gallery manga Vision path groups fragments in detected balloons, conservatively joins nearby vertical CJK fragments, and corrects coordinates from unique exact native text anchors. The captured 13-fragment fixture yields 6 groups. A fresh final Android API response yielded 12 fragments and also became 6 visible cards, with 3 newly grouped dialogues eligible for text repair. The right-hand dialogue became one card and the lower name appeared inside its balloon. Grouping preserves API order and is not a general proof of Japanese reading order. Direct-shutter Vision grouping parity remains a follow-up.

Automatic translated cards now fit source-centered cells within the photo. Long text shows an ellipsis; the existing tap action opens the complete translation and source. The final Japanese comic, French comic, and dense Japanese menu were checked through the real gallery and visually inspected. Full-text tap recovery passed on comic and menu samples. Menu labels remain semantically unreliable and many require taps; French OCR still omits or misreads some dialogue. These are open quality issues, not fixed by card bounds.

Geometry and layout add no provider calls. Only newly grouped manga dialogue can add text requests, using the existing 15-item batch limit and captured language/scene cache keys. The final Japanese page's 3 repair candidates fit one small text batch; no second image upload or higher-priced model was enabled. Request failures keep previously translated fragments. Added text requests can increase both user quota consumption and provider spending; actual billing and latency distributions were not measured.

The next continuation below addresses native page script, uncovered paragraph recovery, menu reading-list access, and the missing source-language request field. Further work should measure semantic quality before changing provider selection. The source-level API findings above remain proposals and should be rechecked against concurrent backend work before implementation.

Local screenshots are recorded in the flow log. Synthetic menu pages differing only in price (15 versus 19) also completed through gallery, OCR, translation, and page navigation with distinct source prices retained.

## Illustrative model costs

Prices checked on 2026-09-07 for standard paid Gemini Developer API usage. Actual configured provider, token counts, thinking, retries, hedges, caching, tax, and infrastructure can change the bill. The example assumes 1,500 input tokens and 500 output tokens per vision request; it is not a measured image token count.

| Route | Published rate | Example cost for 1,000 requests |
| --- | --- | --- |
| Gemini 2.5 Flash-Lite | USD 0.10/M input, 0.40/M output | USD 0.35 |
| Gemini 2.5 Flash | USD 0.30/M input, 2.50/M output | USD 1.70 |
| Google Cloud Vision document OCR | First 1,000 units/month free, then USD 1.50/1,000 in the next tier | USD 1.50 after the free tier, plus text translation |

A sequential Flash-Lite route with 10% additionally escalated to Flash would cost about USD 0.52 per 1,000 requests under those assumptions. This is an estimate, not a production saving. [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing), [Cloud Vision pricing](https://cloud.google.com/vision/pricing).

## Returning-user experience

Reliability improvements are implemented; increased retention has not been demonstrated. Evaluate the following product changes separately from model spending:

- Make the user's last successful task and saved phrases easy to resume from home, while retaining current camera/keyboard entry points. Preserve an unfinished draft per account and expire it predictably; do not silently restore another account's content.
- Show progress and a recoverable retry for slow scans, retaining the selected photo and successful pages. A retry should target failed regions or pages, with a clear indication when it uses an additional paid route.
- Explain the next action for weak images: crop to the text, move closer, reduce glare, or select the source language. Do not ask the user to understand provider names or OCR thresholds.
- Measure first successful translation, capture-to-usable-result time, failed/repeated scans, saved-item revisits, and D1/D7/D30 return rates by platform and scene. Compare cohorts after release; do not treat test passes as evidence of retention.

## Verification limits

Final Flutter analysis and 128 unit/widget tests pass; one pre-existing smoke test is skipped. Three tests are from concurrent metadata work and are not attributed to this task. New regression coverage includes exact cache behavior, favorites after 500 entries, EXIF transforms, independent resize scales, concurrent scratch-file ownership, cleanup after a native OCR error, and adaptive-threshold rotation/lighting behavior.

The initial image-preparation pass verified three Android native OCR reference cases, including original-coordinate assertions; the continuation additionally verified native paragraph geometry and three real gallery inputs. Single-run OCR times: large menu 2661ms, multi-pass rotated document 11456ms, small sign 252ms. The release test reports the Dart binding result, not instrumentation success. Android release and iOS simulator builds pass; the normal Android app was installed in place with user data preserved. Four real image results were inspected initially, followed by the three-image region/overlay checks described above. No iPhone is connected. An iOS build cannot establish real camera, thermal, battery, photo-picker, or Apple Vision behavior on a physical iPhone. No production model comparison or retention cohort study was performed.

## Continuation: page evidence and source recovery

A controlled Android whole-page comparison on the French comic produced 13 Latin blocks / 809 characters, versus 15 Japanese-script blocks / 793 characters. The Japanese recognizer introduced seven CJK glyphs into the French text. The Japanese manga and dense Japanese menu provided negative controls: Latin output was much weaker than Japanese output. The new page selector requires substantial Latin evidence and no more than 3% competing CJK characters before selecting Latin for crops. This is a heuristic, not a calibrated language classifier. Mixed-script pages with a very small minority language still need a broader labeled evaluation.

Native whole-page paragraphs can now fill uncovered Latin dialogue regions. Recovery checks the union of existing source rectangles, excludes weak/short/panel-sized candidates, and retains each recovered paragraph's own coordinates. The controlled final auto-script probe returned 15 French blocks, including the previously missing bottom-right dialogue, with no CJK leakage. The Japanese native control retained four blocks. One cold local run took 4445ms for French and 4170ms for Japanese; these are not p95 measurements or evidence of a speedup. Auto-script detection adds two native whole-page reads on this path, while an explicit Latin-language hint adds one. Recovered text can consume extra translation quota even though this recovery adds no Vision upload.

The menu result now has a labeled List action. The reading sheet preserves source-only entries that the server omitted, marks them as original text, and supports complete selectable text. Copy-all includes these notes too. This preserves visibility of allergen and ordering notes; it does not turn an untranslated note into a reliable translation. Widget verification includes a narrow display at 1.7 system text scale.

All five camera text-batch request paths now send the selected sourceLang, matching the language already used by the camera cache. Previously, a user could pin French in the UI while the batch API still received no source-language hint. Auto remains auto; this change adds no requests or automatic retries. The existing API also supports contextTexts, but charges for that input. Bounded neighboring context and source-echo checks should be evaluated on the tail chunks before enabling them. Current evidence does not establish that missing context is the cause of every untranslated fragment.

Final device evidence for this continuation: the French gallery returned 17 blocks / 805 characters with its missing bottom-right dialogue restored, but that dialogue and another tail paragraph still echoed French after explicit language selection. One manual retry did not resolve it. The Japanese control remained six grouped cards. The dense menu list opened 63 entries, preserved original-only rows, and displayed the complete tax/allergy footer after scrolling. This confirms access and coverage behavior, not semantic correctness. Full analysis, 137 tests (one pre-existing skip), Android release, and iOS simulator builds pass. Physical iOS and retention effects are unverified.

For the source-echo issue, first capture sanitized per-chunk input/output and the selected provider with request IDs. Compare native OCR text to a checked transcription, then evaluate one bounded neighboring-context request against the same model. Measure corrected fragments, changed numbers/names, latency, and billed tokens. Only escalate failed regions to a larger model after this comparison establishes a benefit. Keep explicit user retry available; do not silently loop over the entire page.

## September 8: retry safety and verified API limits

A live raw-OCR request confirmed that the French source echo originates in the API response (HTTP 201), not the mobile renderer. The API accepted one leaked block out of one because the minimum leak allowance is one. A checked transcription translated correctly with the same Gemini model. Neighboring context helped in one diagnostic call with a different race winner, but an actual UI trial returned grammatical French instead of Vietnamese. The context experiment was removed from the final mobile build.

The shipped per-block retry now retains prior results on empty/echo/uncertain/malformed/network-error output, ignores obsolete responses after page/settings changes, suppresses duplicate pending requests, and gives unchanged/failure feedback in all 14 locales. It adds no context quota or automatic semantic retries. These are state and recovery improvements; they do not claim to solve OCR semantics or wrong-language model output.

Prioritize three API changes before any model upgrade: meaningful per-block unresolved/wrong-target status, a bounded refresh contract with cache keys respecting scene/context/prompt version, and preservation of menu allergen/ordering notes. Compare noisy OCR and checked transcriptions under a fixed provider configuration to isolate prompt/context improvements. The existing shared cache can return the old translation on an explicit retry, and a contextual result can be reused in another scene because those factors are absent from its key.

Eight local crop experiments did not justify enabling extra scaling/thresholding globally. The raw/checked/context diagnostic calls recorded 0.0015419 USD in total API cost telemetry; actual billing may include unreported cancelled race work. See `.Codex/flows/2026-09-08-camera-retry-context.md` for final behavior, evidence, and verification limits.

Final September 8 verification: analysis passes, 150 tests pass with one pre-existing skip, and Android release/iOS simulator builds pass. The installed normal Android target preserved the old French translation on an unchanged retry, showed six Japanese dialogue cards, and opened a 63-row menu list through the tax/allergy footer. The French result still reversed a negation, and some menu food labels remain incorrect. Evaluate negation and dish identity alongside target language, numbers, names, and note coverage before accepting an API/model change. Physical iPhone behavior and any improvement in D1/D7/D30 return rates remain unverified.

## September 8: physical iPhone continuation

This checkpoint supersedes the earlier physical-iPhone verification gaps, within the limits below. The normal signed release was installed in place on iPhone X / iOS 16.7.16, preserving user data. The user resolved device Internet validation and restored Camera entitlement. No account purchase or entitlement override was performed by this task.

The real device exposed a clipped camera settings button at 375 logical pixels. The flexible language pair and responsive secondary toolbar row now keep the full settings control accessible. Settings and Help both open on the installed final build; the sharpness hint clears the extra row. Seven widget regressions cover control bounds/taps at widths 320/375/430 and text scales 1/2. The existing AssistiveTouch bubble partially covers Help on this device; its exposed edge works, and the user's bubble position was preserved.

The French/Japanese comic batch completed with page navigation and full-text details. One explicit Japanese block retry successfully replaced the selected result. The French sample retained its X1 negation in this run but still merged text across panels and split the bottom-right sentence. Japanese produced seven visible cards, including an extra sound-effect card compared with the Android run. These observations do not establish semantic correctness or general reading-order accuracy.

The final build processed the dense Japanese menu through Apple Vision: 113 native lines in 3857ms and 85 retained menu items. The 85-item reading list preserved original-only entries and exposed the complete tax/allergy footer. Both footer notes remained Japanese in this run. The quantity printed as 4 was already misread as 14 in source OCR, and the Vietnamese translation retained that erroneous 14. This is direct evidence to prioritize OCR quality for bracketed quantities, separately from the API's failure to translate recognized notes. More items than Android's 63 is not evidence of higher accuracy.

Next evaluate bounded local region re-reads for suspect quantities and panel-aware grouping with checked transcripts on both platforms. Measure corrected characters/regions, false corrections on clean input, latency, and native memory before enabling additional passes. Keep the API note-preservation and unresolved-status proposals above. The observed OCR error does not justify switching all translation requests to a more expensive model. The toolbar change itself introduces no provider requests or model cost.

Final gates: analysis clean, 157 unit/widget tests passed with one pre-existing skip, physical iOS release build/sign/install passed, and shared Android release build passed. Comic/retry/cancel checks used the first physical build; menu/toolbar/retake checks used the final toolbar revision with unchanged OCR/retry code. Android was not reinstalled for this toolbar-only revision. The final source differs from the installed build only by removal of an obsolete comment.

Source Auto, target English, scene Auto, and the user's draft were restored/preserved. The one temporary menu copy and task Safari tab were removed; original photos and Record files were preserved, and task-owned device tools were stopped. No API/model deployment or production release was made. Controlled shutter capture, prolonged battery/thermal behavior, physical large-text settings, offline recovery, and D1/D7/D30 retention remain unverified. Full evidence: `.Codex/flows/2026-09-08-iphone-image-quality.md`.


## September 8: verified iPhone quantity recognition repair

This checkpoint supersedes the prior unresolved 4-to-14 observation. Two bounded, aligned native region reads now agree before replacing a malformed menu quantity. The installed iPhone release reads the tested chicken label as four pieces, while a separate visible reading-list control preserves genuine 4, 14, and 24 quantities. A restricted Latin-only native check also recovers the bracket in `pcs]`; it requires unchanged ordered numbers and name letters. Conflicting or missing evidence retains the original read.

The change introduces no provider requests or model upgrade. Additional native checks took 1855ms and 3145ms during a concurrent two-image batch on iPhone X, so this is an accuracy improvement with local processing cost, not a speed claim. Analysis, 170 tests (one existing skip), Android release build, and physical iOS build/sign/install/gallery checks passed. Android was not physically retested for this iOS-specific path. French panel grouping and API note/translation issues remain unresolved. Evidence and implementation limits: `.Codex/flows/2026-09-08-native-ocr-repair.md`.


## September 8: dialogue boundary correction awaiting final UI acceptance

Physical diagnostic OCR confirmed a 992px-wide French crop combining three independent passages. The Vision winner now preserves horizontal paragraph positions on Latin pages, using individual line geometry. Recorded physical coordinates pass regressions for three separate groups, with no text substitution. The CJK path is unchanged. Full analysis, 176 tests (one existing skip), Android release build, and normal iOS release build/sign/install pass.

The normal app's final gallery acceptance is pending because automated Camera taps are currently interpreted as long presses. A manual Camera tap was requested from the user to isolate input behavior. Do not treat static/fixture success as completed UI verification. No extra recognition request or model upgrade is introduced, but translation chunk overhead may vary with the changed block granularity. Full state: `.Codex/flows/2026-09-08-dialogue-boundaries.md`.


## September 8: targeted dialogue fix verified in the normal iPhone app

This supersedes the pending gallery check above. A three-photo Comic batch completed. The original French page's left dialogue, Spirou caption, and refusal balloon are now independently positioned and open with separate source/translation text. The Japanese control retains seven cards and full dialogue details. Page navigation and retake work. No code changed after the previously passing analysis, 176 tests, and Android/iOS builds.

An additional French cafe page still contains fragmented utterances and noise cards. The original page also retains isolated noise and some split sentences elsewhere. General comic OCR accuracy remains incomplete; there is no paired baseline to classify every issue on the additional page as a regression. Next prioritize image-supported fragment assembly and noise discrimination, preserving meaningful short utterances. The targeted fix adds no recognition pass or model upgrade; overall translation chunk overhead remains input-dependent. Full evidence: `.Codex/flows/2026-09-08-dialogue-boundaries.md`.


## September 8: French cafe reconciliation, Android accepted

The additional French cafe page now passes targeted physical Xiaomi acceptance on revision r4: redundant embedded glyph cards are removed, coffee and exact-response lines are assembled, MAIS OUI is recovered, and LA SEULE SOLUTION appears once. Native output has 15 cards. These are structural OCR improvements; stylized-character errors and translation semantics remain imperfect.

The implementation uses existing crop/page recognition, geometric speech shapes, and independent native evidence. It adds no recognition pass, provider call, or model upgrade. Translation cost still depends on the resulting text/chunks. Full analysis is clean and 190 Flutter tests pass with one existing skip. Normal Android/iOS builds pass, and normal iOS r4 is installed. Final iPhone gallery acceptance is waiting for the device's XCTest passcode prompt; do not treat recorded native fixtures as final installed-app proof. Full evidence: `.Codex/flows/2026-09-08-french-fragments.md`.


## September 8: final iPhone cafe acceptance

This supersedes the pending XCTest checkpoint. Normal installed r4 passes the targeted cafe structural checks on iPhone: coffee, exact-response, solution, and bottom four-row dialogue have complete grouped source sheets; the mirrored-sign MAZ and trailing G2 artifacts are gone, and the solution card appears once. The original French page retains three independent passages. The Japanese control renders and opens its dialogue; eight overlays were visible this run, so exact-count parity with the earlier seven-card note is not claimed.

Character accuracy is still incomplete: iPhone reads MAIS OU instead of MAIS OUI, producing an incorrect meaning; Android reads that phrase correctly. Other stylized-letter errors and isolated noise on img169 remain. Keep release wording scoped to better dialogue grouping and targeted noise removal. No provider/model upgrade or added recognition pass was needed. Full evidence and the 190-test gate: `.Codex/flows/2026-09-08-french-fragments.md`.
