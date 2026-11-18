"""Generate only the bindings needed by the engine adapter; the kernel is standalone."""
import json
import sys
from pathlib import Path

cpp, destination = [Path(arg).resolve() for arg in sys.argv[1:3]]
sys.path.insert(0, str(cpp))
import build_profile
import binding_generator

destination.mkdir(parents=True, exist_ok=True)
# The upstream generator removes only destination/gen. Refuse an ambiguous target.
expected = Path(__file__).resolve().parents[2] / "dist" / "godot" / "native-build"
if destination != expected:
    raise ValueError("Expected the dedicated dist/godot/native-build directory")
profile = destination / "profile.json"
profile.write_text(json.dumps({
    "enabled_classes": ["RefCounted", "OS", "RandomNumberGenerator", "Texture2D", "RenderingServer", "Node2D"],
}), encoding="utf-8")
api = cpp / "gdextension" / "extension_api-4-7.json"
trimmed = destination / "extension_api.json"
trimmed.write_text(json.dumps(build_profile.generate_trimmed_api(str(api), str(profile))), encoding="utf-8")
binding_generator.generate_bindings(str(trimmed), str(cpp / "gdextension" / "gdextension_interface.json"), False, output_dir=str(destination))
