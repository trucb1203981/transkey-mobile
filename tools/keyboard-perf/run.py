"""Run source-level CPU benchmarks on Android ART without modifying app data.

First compile current sources with :app:testDebugUnitTest. This measures component
CPU time on the physical device, not touch-to-display latency or release R8 code.
"""
import argparse
import glob
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("label")
parser.add_argument("--device", default="e552d9b")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
sdk = Path("/opt/homebrew/share/android-commandlinetools")
java = Path("/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home")
stdlib = Path(sorted(glob.glob(str(Path.home() / ".gradle/caches/modules-2/files-2.1/org.jetbrains.kotlin/kotlin-stdlib/2.2.20/*/*.jar")))[0])
classes = repo / "build/app/tmp/kotlin-classes/debug"
work = Path(tempfile.mkdtemp(prefix="transkey-keyboard-"))
env = dict(os.environ, JAVA_HOME=str(java))
adb = [str(sdk / "platform-tools/adb"), "-s", args.device]


def run(command):
    subprocess.run([str(x) for x in command], check=True, env=env, stdout=subprocess.DEVNULL)


run([java / "bin/javac", "-source", "17", "-target", "17", "-cp", os.pathsep.join(map(str, [sdk / "platforms/android-36/android.jar", classes, stdlib])), "-d", work, Path(__file__).with_name("KeyboardPerfMain.java")])
names = ["TelexProcessor", "VniProcessor", "ChunjiinComposer", "HangulComposer", "VietWordCorrector", "PinyinHanziConverter", "KanaKanjiConverter"]
with zipfile.ZipFile(work / "classes.jar", "w") as jar:
    for name in names:
        for path in (classes / "app/transkey/mobile").glob(name + "*.class"):
            jar.write(path, path.relative_to(classes))
    for path in (work / "app").rglob("*.class"):
        jar.write(path, path.relative_to(work))
run([sdk / "build-tools/36.0.0/d8", "--min-api", "30", "--lib", sdk / "platforms/android-36/android.jar", "--output", work / "bench.zip", work / "classes.jar", stdlib])
with zipfile.ZipFile(work / "assets.apk", "w", zipfile.ZIP_STORED) as jar:
    for name in ["jadict.db", "zhdict.db"]:
        jar.write(repo / "android/app/src/main/assets" / name, "assets/" + name)
remote = "/data/local/tmp/" + work.name
run(adb + ["shell", "mkdir", "-p", remote])
for path in [work / "bench.zip", work / "assets.apk"] + [repo / "android/app/src/main/assets" / n for n in ["vn_syllables.txt", "en_words.txt"]]:
    run(adb + ["push", path, remote + "/"])
output = repo / "tools/keyboard-perf/results" / (args.label + ".jsonl")
output.parent.mkdir(exist_ok=True)
with output.open("w") as log:
    subprocess.run(adb + ["shell", "CLASSPATH=" + remote + "/bench.zip", "app_process", "/system/bin", "app.transkey.mobile.KeyboardPerfMain", remote, remote + "/assets.apk"], check=True, stdout=log, env=env)
print(output)
