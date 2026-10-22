"""Run after `flutter create` has generated ./android.
Installs our manifest, enables core-library desugaring (needed by the
notification plugin) and writes the launcher icon."""
import os, shutil, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
android = os.path.join(root, "android")

# 1. Manifest
shutil.copy(os.path.join(root, "tools", "android", "AndroidManifest.xml"),
            os.path.join(android, "app", "src", "main", "AndroidManifest.xml"))

# 2. Gradle: desugaring
for name, enable, dep in (
    ("build.gradle", "coreLibraryDesugaringEnabled true",
     "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.4'\n}\n"),
    ("build.gradle.kts", "isCoreLibraryDesugaringEnabled = true",
     '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")\n}\n'),
):
    path = os.path.join(android, "app", name)
    if not os.path.exists(path):
        continue
    s = open(path).read()
    if "oreLibraryDesugaring" not in s:
        if "compileOptions {" not in s:
            sys.exit("Could not find compileOptions in " + path)
        s = s.replace("compileOptions {", "compileOptions {\n        " + enable, 1)
        s += dep
        open(path, "w").write(s)
    print("patched", path)
    break
else:
    sys.exit("No android/app/build.gradle(.kts) found")

# 3. Launcher icon (teal rounded square, white check mark + coin)
from PIL import Image, ImageDraw
def icon(size):
    k = 4
    S = size * k
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.22), fill=(0, 137, 123, 255))
    d.ellipse([S * .14, S * .14, S * .86, S * .86], outline=(255, 255, 255, 255), width=int(S * .06))
    d.line([(S * .30, S * .52), (S * .45, S * .66), (S * .72, S * .36)],
           fill=(255, 255, 255, 255), width=int(S * .09), joint="curve")
    return im.resize((size, size), Image.LANCZOS)

for folder, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
    d = os.path.join(android, "app", "src", "main", "res", "mipmap-" + folder)
    os.makedirs(d, exist_ok=True)
    icon(px).save(os.path.join(d, "ic_launcher.png"))
print("icons written")
