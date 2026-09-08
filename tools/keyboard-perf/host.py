"""Build and install a local-only native host for real keyboard UI checks."""
from pathlib import Path
import os
import subprocess
import tempfile
import zipfile

source = Path(__file__).parent
sdk = Path("/opt/homebrew/share/android-commandlinetools")
java = Path("/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home")
work = Path(tempfile.mkdtemp(prefix="transkey-keyboard-host-"))
env = dict(os.environ, JAVA_HOME=str(java))


def run(args):
    subprocess.run([str(v) for v in args], check=True, env=env, stdout=subprocess.DEVNULL)


run([java / "bin/javac", "-cp", sdk / "platforms/android-36/android.jar", "-d", work, source / "KeyboardHost.java", source / "KeyboardUi.java"])
run([sdk / "build-tools/36.0.0/d8", "--min-api", "30", "--lib", sdk / "platforms/android-36/android.jar", "--output", work, *work.rglob("*.class")])
run([sdk / "build-tools/36.0.0/aapt2", "link", "-I", sdk / "platforms/android-36/android.jar", "--manifest", source / "host-manifest.xml", "-o", work / "host.apk"])
with zipfile.ZipFile(work / "host.apk", "a") as archive:
    archive.write(work / "classes.dex", "classes.dex")
run([sdk / "build-tools/36.0.0/apksigner", "sign", "--ks", Path.home() / ".android/debug.keystore", "--ks-pass", "pass:android", "--key-pass", "pass:android", work / "host.apk"])
run([sdk / "platform-tools/adb", "-s", "e552d9b", "install", "-r", work / "host.apk"])
run([sdk / "platform-tools/adb", "-s", "e552d9b", "shell", "am", "start", "-n", "app.transkey.keyboardperf/.KeyboardHost"])
print(work / "host.apk")
