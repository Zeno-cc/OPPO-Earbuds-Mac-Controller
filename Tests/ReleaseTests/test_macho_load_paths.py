"""Regression tests for parsing actual load paths, not otool's file headers."""
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
PARSER = ROOT / "scripts" / "macho-load-paths.awk"
SPARKLE = "@rpath/Sparkle.framework/Versions/B/Sparkle"
SYSTEM = "/usr/lib/libSystem.B.dylib"


def row(path, indent="\t", suffix=""):
    return f"{indent}{path} (compatibility version 1.0.0, current version 2.9.6){suffix}\n"


def load_paths(output):
    result = subprocess.run(
        ["/usr/bin/awk", "-f", str(PARSER)],
        input=output, text=True, capture_output=True, check=True,
    )
    return result.stdout.splitlines()


class MachOLoadPathTests(unittest.TestCase):
    def test_staging_path_is_not_a_dependency(self):
        header = "/Users/runner/project/.build-app.XYZ/OPPO Earbuds Mac Controller.app/Contents/MacOS/BudsBar:\n"
        self.assertEqual(load_paths(header + row(SPARKLE) + row(SYSTEM)), [SPARKLE, SYSTEM])

    def test_every_universal_architecture_header_is_ignored(self):
        binary = "/private/tmp/test App.app/Contents/MacOS/BudsBar"
        output = "".join(
            f"{binary} (architecture {arch}):\n" + row(SPARKLE) + row(SYSTEM)
            for arch in ("arm64", "x86_64")
        )
        self.assertEqual(load_paths(output), [SPARKLE, SYSTEM, SPARKLE, SYSTEM])

    def test_real_development_dependencies_are_not_filtered_out(self):
        for path in (
            "/Users/developer/Build Products/Private.framework/Versions/A/Private",
            "/work/project/.build/debug/Private.dylib",
            "/private/tmp/test/libPrivate.dylib",
        ):
            with self.subTest(path=path):
                self.assertEqual(load_paths("/Applications/Test.app/Test:\n" + row(path)), [path])

    def test_spaces_indentation_and_weak_link_metadata(self):
        path = "@rpath/Framework With Spaces.framework/Versions/A/Framework With Spaces"
        self.assertEqual(load_paths(row(path, "    ", " (weak)")), [path])

    def test_header_cannot_fake_sparkle_linkage(self):
        output = "/Users/test/@rpath/Sparkle.framework/Versions/B/Sparkle:\n" + row(SYSTEM)
        self.assertEqual(load_paths(output), [SYSTEM])


if __name__ == "__main__":
    unittest.main()
