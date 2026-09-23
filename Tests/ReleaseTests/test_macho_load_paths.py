"""The parser must distinguish otool headers from actual linked libraries."""
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
PARSER = ROOT / "scripts" / "macho-load-paths.awk"
SPARKLE = "@rpath/Sparkle.framework/Versions/B/Sparkle"
SYSTEM = "/usr/lib/libSystem.B.dylib"


def paths(output):
    result = subprocess.run(
        ["/usr/bin/awk", "-f", str(PARSER)],
        input=output, text=True, capture_output=True, check=True,
    )
    return result.stdout.splitlines()


def library(path):
    return f"\t{path} (compatibility version 1.0.0, current version 2.9.6)\n"


class MachOLoadPathTests(unittest.TestCase):
    def test_header_is_not_library(self):
        output = "/Users/test/@rpath/Sparkle.framework/BudsBar:\n" + library(SYSTEM)
        self.assertEqual(paths(output), [SYSTEM])

    def test_load_paths_include_bundle_and_system_libraries(self):
        output = "/private/tmp/Test.app/Contents/MacOS/BudsBar:\n"
        output += library(SPARKLE) + library(SYSTEM)
        self.assertEqual(paths(output), [SPARKLE, SYSTEM])

    def test_architecture_headers_are_ignored(self):
        output = "".join(
            f"/private/tmp/Test.app/BudsBar (architecture {arch}):\n"
            + library(SPARKLE)
            for arch in ("arm64", "x86_64")
        )
        self.assertEqual(paths(output), [SPARKLE, SPARKLE])

    def test_real_development_library_path_is_visible(self):
        development_library = "/Users/test/project/.build/debug/Private.dylib"
        self.assertEqual(paths(library(development_library)), [development_library])


if __name__ == "__main__":
    unittest.main()
