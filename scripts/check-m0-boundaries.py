"""Compile positive and negative M0 API probes against the real package modules."""

from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
products = Path(subprocess.check_output(
    ["swift", "build", "--package-path", str(root / "Packages/DenViews"), "--show-bin-path"], text=True).strip())
modules = products / "Modules" if (products / "Modules").is_dir() else products
prefix = "import DenPresentationModels\nimport DenDomain\n"
cases = [
    ("read", "_ = model.boards", None),
    ("operation", "_ = model.movement", "'movement' is inaccessible due to 'private' protection level"),
    ("writer", "_ = model.state", "'state' is inaccessible due to 'private' protection level"),
    ("application", "_ = BoardMovement.self", "cannot find 'BoardMovement' in scope"),
]
with tempfile.TemporaryDirectory(prefix="den-m0-") as directory:
    for name, body, expected in cases:
        path = Path(directory) / f"{name}.swift"
        path.write_text(prefix + f"@MainActor func probe(_ model: BoardOrderProbeModel) {{ {body} }}\n")
        result = subprocess.run(
            ["xcrun", "swiftc", "-typecheck", "-swift-version", "6",
             "-target", "arm64-apple-macos26.0", "-enable-upcoming-feature", "MemberImportVisibility",
             "-I", str(modules), str(path)], capture_output=True, text=True, check=False)
        if expected is None:
            assert result.returncode == 0, result.stderr
        else:
            assert result.returncode != 0 and expected in result.stderr, result.stderr
        print(f"PASS {name}: {expected or 'public View API compiles'}")

dependencies = subprocess.check_output(
    ["swift", "package", "--package-path", str(root / "Packages/DenPresentationModels"),
     "show-dependencies", "--format", "json"], text=True)
assert "ghostty" not in dependencies.lower(), dependencies
print("PASS pure Model package graph has no Ghostty dependency")
