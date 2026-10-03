import json, re, subprocess, sys, zipfile
from pathlib import Path

here = Path(__file__).parent
toc = (here / "Metails.toc").read_text(encoding="utf-8")
version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
tag = f"v{version}"
out = here / "dist"
out.mkdir(exist_ok=True)
zip_path = out / f"Metails-{version}-forever.zip"
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
    for name in ("Metails.toc", "Metails.lua", "README.md", "LICENSE"):
        z.write(here / name, f"Metails/{name}")
meta = out / "release.json"
meta.write_text(json.dumps({"releases": [{"name": "Metails", "version": tag, "filename": zip_path.name, "nolib": False,
                                          "metadata": [{"flavor": "forever", "interface": 16001}]}]}, indent=1))
notes = sys.argv[1] if len(sys.argv) > 1 else f"Metails {version}"
exists = subprocess.run(["gh", "release", "view", tag], capture_output=True).returncode == 0
if exists:
    subprocess.check_call(["gh", "release", "upload", tag, str(zip_path), str(meta), "--clobber"])
else:
    subprocess.check_call(["gh", "release", "create", tag, str(zip_path), str(meta), "--title", f"Metails {version}", "--notes", notes])
print(tag, zip_path.name)
