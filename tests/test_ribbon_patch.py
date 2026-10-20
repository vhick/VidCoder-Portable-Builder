"""Tiny Windows-independent tests for the safety of the Fluent.Ribbon patch."""
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

PATCH = Path(__file__).resolve().parents[1] / "scripts" / "patch-fluent-ribbon.py"
spec = spec_from_file_location("patch_fluent_ribbon", PATCH)
module = module_from_spec(spec)
spec.loader.exec_module(module)


class RibbonPatchTests(unittest.TestCase):
    def process(self, contents: str):
        with TemporaryDirectory() as temp:
            path = Path(temp) / "MainWindow.xaml"
            path.write_text(contents, encoding="utf-8")
            hits = module.process(path, check=False)
            output = path.read_text(encoding="utf-8")
            if hits:
                self.assertEqual(hits, module.process(path, check=True))
            return hits, output

    def test_default_state_is_disabled(self):
        hits, output = self.process('''<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:fluent="urn:fluent-ribbon"><fluent:Ribbon x:Name="Home" /></Window>''')
        self.assertEqual(1, hits)
        self.assertIn('AutomaticStateManagement="False"', output)
        self.assertIn('x:Name="Home"', output)

    def test_explicit_true_changes_to_false(self):
        hits, output = self.process('''<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
 xmlns:f="urn:fluent-ribbon"><f:Ribbon AutomaticStateManagement='True' /></Window>''')
        self.assertEqual(1, hits)
        self.assertIn("AutomaticStateManagement='False'", output)
        self.assertNotIn("Management='True'", output)

    def test_unrelated_namespace_and_comments_untouched(self):
        hits, output = self.process('''<Window xmlns:unrelated="urn:other" xmlns:f="urn:fluent-ribbon">
        <!-- <f:Ribbon AutomaticStateManagement="True"/> -->
        <unrelated:Ribbon/><f:Ribbon /></Window>''')
        self.assertEqual(1, hits)
        self.assertIn('<!-- <f:Ribbon AutomaticStateManagement="True"/> -->', output)
        self.assertIn('<unrelated:Ribbon/>', output)

    def test_no_fluent_controls_does_not_modify(self):
        contents = '<Window xmlns:other="urn:other"><other:Ribbon /></Window>'
        hits, output = self.process(contents)
        self.assertEqual(0, hits)
        self.assertEqual(contents, output)


if __name__ == '__main__':
    unittest.main()
