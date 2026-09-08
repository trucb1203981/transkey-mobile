---
date: 2026-09-08
type: fix
status: verified
---

# Repair native OCR on menu and comic images

## Request and evidence

The user requested OCR fixes after physical iPhone verification. The dense Japanese menu displays 4 pieces, but the source OCR reads 14 before translation. French comic regions also merge across panels. Existing source images remain under /Users/trucnguyen/Desktop/Record. Preserve all prior mobile changes and user data. No API/model upgrade or deployment is authorized by this implementation scope.

## Plan

1. [x] Capture baseline native reads and compare bounded local region variants on the actual image.
2. [x] Implement only a measured improvement with conservative replacement rules and source-coordinate preservation.
3. [x] Run regression checks on multiple menu/comic inputs and clean quantity controls.
4. [x] Build/install the normal iPhone app, verify visible results, restore user state, and record limits.

## Verification boundary

Host Apple Vision experiments are diagnostic only. Final acceptance requires the connected physical iPhone, including its older recognition implementation. No number will be rewritten from a text-only guess.

## Root cause and measured implementation

The Japanese menu's full-page recognizer confuses the opening bracket before 4 with a leading 1. Two small padded ROI reads on the physical iPhone independently produce the correct quantity, but with a Japanese corner bracket paired with a square bracket. The initial acceptance guard rejected that punctuation variant and correctly kept the old result. Recognizing equivalent square/corner-bracket shapes in the comparison resolves this rejection; the replacement text and digits still come from both native reads.

`ocr_quantity_repair.dart` plans at most four suspect labels and two ROI views per label. It excludes balanced labels, prices, multi-number lines, vertical/large/invalid regions, and keeps regions within the upright image. Both reads must contain one aligned line, agree after punctuation normalization, and preserve the dish/unit text except one recovered/missing character. Missing, conflicting, extra, foreign, or failed reads retain the original. The displayed rectangle and confidence are preserved. There is no rule mapping 14 to 4; a true bracketed 14 remains 14.

A separate physical control exposed the broad automatic-language configuration reading `CHICKEN [14 pcs]` as `CHICKEN [14 pcsl`. The same native model with automatic language selection reads the punctuation correctly. A bounded extra page read now runs only for automatic source mode, exclusively Latin text of sufficient length, and a malformed quantity label. It is accepted only if dimensions, ordered numbers, and name letters agree, allowing the measured closing-bracket l/I confusion after a quantity unit. It does not change explicit language choices or run on ordinary clear pages, CJK pages, or mixed-script pages.

## Diagnostic evidence

Task directory pointer: `/tmp/transkey-ocr-repair-workdir.txt`. `device-results.json` records the initial failed diagnostic pass, including two menus and the clean 4/14/24 control. Its bare baseline call intentionally lacked the app's broad language list and is not an identical-config baseline. `roi-language-results.json` then isolates language configuration and six ROI paddings on the physical device, plus French and Japanese comic controls.

The first two broad-language ROI views returned `唐揚げ「4個］` in agreement. Their source-area ratios were 0.888/0.982 and overlap coverage was 0.931/0.886, passing the geometry guard. The wider sixth view also saw an extra neighboring line and would be rejected. Automatic language selection on these tiny Japanese crops was worse, so CJK ROI language behavior remains unchanged.

French broad/automatic full-page diagnostics returned 46/44 lines and 649/669 characters, with some different errors. The Japanese manga remained weak under both whole-page configurations. Neither comparison establishes a general comic accuracy improvement, and neither justifies switching all OCR to automatic language detection. This fix does not change manga region grouping.

Analysis is clean; 170 unit/widget tests pass with one pre-existing skip. Final normal iOS build/sign/install passes, with 129.2MB app and 73.8s Xcode stage. Native diagnostic targets are temporary, use no translation API, and are replaced by `lib/main.dart` for final installation. The final gallery acceptance is recorded below.


## Final installed acceptance

The normal final target on iPhone X / iOS 16.7.16 processed a two-image gallery batch. The dense Japanese menu retained 85 items and its selected source now reads `唐揚げ「4個]`, with the explanation correctly describing four pieces. The separate clean control reading list shows both source and Vietnamese translation preserving 4, 14, and 24. Evidence: `/tmp/transkey-ocr-four-detail.png`, `/tmp/transkey-ocr-clean-result.png`, and `/tmp/transkey-ocr-clean-list.png`. Opening the menu detail triggered one ordinary explanation API call; the OCR repair itself adds no provider requests.

Final device logs recorded the quantity check repairing one label in 1855ms and the Latin check accepting the control in 3145ms. Full-page reads took 7504ms and 8966ms while both pages were processed concurrently. This establishes an accuracy correction on these inputs, not a speed improvement. Extra native work is bounded and restricted to suspect labels. No model upgrade or API deployment was made.

Final gates: analysis clean; 170 tests passed with one pre-existing skip; iOS release build, strict code-sign verification, install, and visible gallery acceptance passed; Android release APK build passed (95.9MB). Android was disconnected and was not physically retested this turn. The final installed target is `lib/main.dart`, packaged under the task directory's `final-guard/`.

Source Auto, target English, scene Auto, and the user's existing draft were restored. Eight task-owned diagnostic files were removed from the app container. Original Record images and other user files were preserved. French panel grouping, general manga accuracy, untranslated menu notes, prolonged thermal/battery behavior, and retention improvements remain outside this verified correction. No commit was created.

The two task-created Photos copies (03:38 menu and 03:39 quantity control) were removed after checking their contents and timestamps; Recently Deleted was not emptied. The task Safari tab was closed, task-owned WDA/USB/logging processes and the fixture server were stopped, and the normal app was left open.
