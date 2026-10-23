import contextlib
from datetime import date
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('lookout_version', ROOT / 'scripts/version.py')
version = importlib.util.module_from_spec(spec)
spec.loader.exec_module(version)


class VersionTests(unittest.TestCase):
    def fixture(self, root, notes='- Fix configuration loading.'):
        (root / 'VERSION').write_text('1.2.3\n')
        (root / 'CHANGELOG.md').write_text(f'# Changes\n\n## [Unreleased]\n\n{notes}\n\n## [1.2.3] - 2026-10-23\n\n- Previous release.\n')

    def test_bump_resets_lower_parts_and_keeps_history(self):
        for part, expected in [('patch', '1.2.4'), ('minor', '1.3.0'), ('major', '2.0.0')]:
            with self.subTest(part=part), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                self.fixture(root)
                actual = version.bump(root, part, date(2026, 10, 24))
                self.assertEqual(actual, expected)
                value, text, headings = version.inspect(root)
                self.assertEqual(value, expected)
                self.assertIn('## [1.2.3] - 2026-10-23\n\n- Previous release.', text)
                self.assertIn(f'## [{expected}] - 2026-10-24\n\n- Fix configuration loading.', text)
                self.assertFalse(text[headings[0].end():headings[1].start()].strip())

    def test_dry_run_does_not_change_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root)
            before = {p.name: p.read_bytes() for p in root.iterdir()}
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                version.bump(root, 'patch', date(2026, 10, 24), dry_run=True)
            self.assertIn('+1.2.4', output.getvalue())
            self.assertEqual(before, {p.name: p.read_bytes() for p in root.iterdir()})

    def test_empty_notes_or_backdated_release_is_rejected(self):
        for notes, released in [('', date(2026, 10, 24)), ('- Fix.', date(2026, 10, 22))]:
            with self.subTest(notes=notes), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                self.fixture(root, notes)
                before = {p.name: p.read_bytes() for p in root.iterdir()}
                with self.assertRaises(ValueError):
                    version.bump(root, 'patch', released)
                self.assertEqual(before, {p.name: p.read_bytes() for p in root.iterdir()})

    def test_mismatch_invalid_or_duplicate_versions_are_rejected(self):
        for bad in ['2.0.0', 'v1.2.3', '01.2.3']:
            with self.subTest(value=bad), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                self.fixture(root)
                (root / 'VERSION').write_text(bad + '\n')
                with self.assertRaises(ValueError): version.inspect(root)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root)
            path = root / 'CHANGELOG.md'
            path.write_text(path.read_text() + '\n## [1.2.3] - 2026-10-22\n')
            with self.assertRaises(ValueError): version.inspect(root)


if __name__ == '__main__':
    unittest.main()
