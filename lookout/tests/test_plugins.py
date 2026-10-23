import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/plugins.py'
spec = importlib.util.spec_from_file_location('lookout_plugins', SCRIPT)
plugins = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plugins)


class PluginBuildTests(unittest.TestCase):
    def test_enable_disable_removes_only_generated_plugin_assets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            personal = root / 'agent/.env'
            personal.parent.mkdir(parents=True)
            personal.write_text('KEEP=private\n')
            plugins.build(['odoo', 'nginx'], root)
            dashboards = root / 'server/generated/dashboards'
            rules = root / 'server/generated/loki-rules/fake'
            pipeline = root / 'agent/generated/log-pipeline.alloy'
            metadata = json.loads((root / 'agent/generated/.lookout-generated').read_text())
            self.assertEqual(metadata['version'], (plugins.ROOT / 'VERSION').read_text().strip())
            self.assertTrue((dashboards / 'odoo-logs.json').exists())
            self.assertTrue((dashboards / 'nginx.json').exists())
            self.assertTrue((rules / 'nginx.yml').exists())
            text = pipeline.read_text()
            self.assertLess(text.index('// Plugin: odoo'), text.index('// 統一 level'))
            self.assertEqual(text.count('loki.process "containers"'), 1)
            plugins.build(['nginx'], root)
            self.assertFalse((dashboards / 'odoo-logs.json').exists())
            self.assertNotIn('// Plugin: odoo', pipeline.read_text())
            self.assertTrue((dashboards / 'nginx.json').exists())
            plugins.build([], root)
            self.assertFalse((dashboards / 'nginx.json').exists())
            self.assertFalse((rules / 'nginx.yml').exists())
            self.assertTrue((rules / 'apps.yml').exists())
            self.assertTrue((dashboards / 'home.json').exists())
            self.assertNotIn('// Plugin:', pipeline.read_text())
            self.assertEqual(personal.read_text(), 'KEEP=private\n')

    def test_same_selection_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.assertTrue(plugins.build(['odoo'], root))
            pipeline = root / 'agent/generated/log-pipeline.alloy'
            before = pipeline.stat().st_mtime_ns
            self.assertFalse(plugins.build(['odoo'], root))
            self.assertEqual(pipeline.stat().st_mtime_ns, before)

    def test_invalid_selection_preserves_previous_build(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            plugins.build(['odoo'], root)
            pipeline = root / 'agent/generated/log-pipeline.alloy'
            before = pipeline.read_text()
            for names in [['unknown'], ['../nginx'], ['nginx', 'nginx']]:
                with self.assertRaises(ValueError):
                    plugins.build(names, root)
            self.assertEqual(pipeline.read_text(), before)

    def test_refuses_to_replace_an_unmanaged_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            directory = root / 'server/generated'
            directory.mkdir(parents=True)
            personal = directory / 'my-file'
            personal.write_text('keep')
            with self.assertRaises(ValueError):
                plugins.build([], root)
            self.assertEqual(personal.read_text(), 'keep')


if __name__ == '__main__':
    unittest.main()
