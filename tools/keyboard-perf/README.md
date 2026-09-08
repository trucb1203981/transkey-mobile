# Android keyboard performance checks

These tools separate physical-device component CPU timings from real installed-IME UI checks. They do not send messages, call translation APIs, or edit personal drafts.

## Component CPU benchmark

1. From `android/`, compile the current sources with `JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :app:testDebugUnitTest`.
2. From the mobile root, run `python3 tools/keyboard-perf/run.py <unique-label> --device e552d9b`.
3. Read `results/<unique-label>.jsonl`. The benchmark runs the actual compiled Kotlin classes on Android ART with the bundled dictionaries. Five warmups precede each measured group. Cold dictionary loading is recorded separately.

Timings cover whole component operations, including the entire indicated sequence for `*_run_600`. They are not per-key latency, touch-to-display latency, or release/R8 measurements. The scripts use the local Android SDK, JDK 17, and Kotlin 2.2.20 runtime paths; adjust those paths for another workstation. Test assets are copied into a unique `/data/local/tmp/transkey-keyboard-*` directory, leaving app dictionaries and preferences intact.

## Installed IME UI matrix

1. Build and install the release APK with the normal app workflow. Preserve the original APK before upgrading.
2. Unlock the device, select the TransKey IME and its Vietnamese Telex letters layout, and leave the device untouched during the run.
3. Run `python3 tools/keyboard-perf/host.py`. This installs the native, local-only `app.transkey.keyboardperf` test host.
4. Run `adb -s e552d9b shell am instrument -w -e phase <unique-label> app.transkey.keyboardperf/.KeyboardUi`.
5. Pull `/sdcard/Android/data/app.transkey.keyboardperf/files/<unique-label>` to a fresh local directory. Read `results.jsonl`, inspect the screenshots, and compare `*-gfx.txt` frame statistics. Every `passed` must be true, and the final matrix must contain 42 records. An instrumentation process exit code alone does not prove success.

The matrix types and commits in 18 input modes, checks both symbol pages and deletion in each mode, inserts/deletes emoji, jumps between emoji categories, types into a numeric field, injects a 160-key burst, and verifies held backspace stops after release. It uses real pointer events for typing. Picker rows use accessibility click because Android can report clipped row bounds behind the picker footer. Emoji category assertions wait for the target item, then retain a screenshot and IME-only accessibility tree on timeout. `-e first <mode>` resumes at a mode; `-e first extras` runs the final auxiliary checks only. Full runs restore the preferred input mode to Telex. Selecting modes through the app's picker adds them to its enabled language cycle.

The reported frame statistics describe IME rendering, not total input transport time. Mode changes and ordinary word typing are distinct from first emoji opening. Screenshot timestamps and the installed APK must correspond to the measured run.

Run Flutter analysis and release builds sequentially. Concurrent Flutter dependency preparation can rewrite GeneratedPluginRegistrant during compilation, producing a missing integration_test plugin error unrelated to the IME sources.

## Output parity

`KeyboardParity.java` compares the current compiled classes with a separately saved baseline `classes.jar` from a component benchmark. Compile it with JDK 17 and pass, in order: baseline classes JAR, current Kotlin classes directory, Kotlin standard-library JAR, dictionary asset directory, and Android SDK `android.jar`. The 2026-09-08 audit checked 34,536 output states/results without a mismatch.

## References

- [Android slow-rendering diagnostics](https://developer.android.com/topic/performance/vitals/render)
- [Android custom-view optimization](https://developer.android.com/develop/ui/views/layout/custom-views/optimizing-view)
- [GridView selection and scrolling](https://developer.android.com/reference/android/widget/GridView)

## Retained evidence

`results/baseline.jsonl` and `results/optimized-banded.jsonl` contain the paired physical-device component measurements. Other labels capture intermediate measurements; only the final installed-release matrix establishes live verification.
