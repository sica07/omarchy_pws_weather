import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('private_store', ROOT / 'helpers/secrets.py')
store = importlib.util.module_from_spec(spec)
spec.loader.exec_module(store)


class SecretsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name)
        self.env = patch.dict(os.environ, {'HOME': str(self.home)})
        self.env.start()
        self.folder = self.home / '.local/share/omarchy_pws_weather'

    def tearDown(self):
        self.env.stop()
        self.temp.cleanup()

    def load(self, **legacy):
        return store.handle({'action': 'load', 'legacy': legacy})['secrets']

    def test_migration_and_permissions(self):
        old = os.umask(0)
        try:
            self.assertEqual(self.load(apiKey='weather-test', meteoblueApiKey='meteo-test'),
                             {'apiKey': 'weather-test', 'meteoblueApiKey': 'meteo-test'})
        finally:
            os.umask(old)
        self.assertEqual(stat.S_IMODE(self.folder.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((self.folder / 'secrets.json').stat().st_mode), 0o600)
        self.assertEqual(self.load(apiKey='stale')['apiKey'], 'weather-test')

    def test_explicit_empty_value_wins_over_legacy(self):
        self.load(apiKey='old')
        store.handle({'action': 'save', 'secrets': {'apiKey': '', 'meteoblueApiKey': ''}})
        self.assertEqual(self.load(apiKey='old')['apiKey'], '')

    def test_failed_replace_preserves_previous_keys(self):
        self.load(apiKey='old')
        with patch.object(store.os, 'replace', side_effect=OSError('disk failure')):
            with self.assertRaises(OSError):
                store.handle({'action': 'save', 'secrets': {'apiKey': 'new', 'meteoblueApiKey': ''}})
        self.assertEqual(self.load()['apiKey'], 'old')
        self.assertFalse(list(self.folder.glob('.secrets-*')))

    def test_corrupt_store_is_not_overwritten(self):
        self.load()
        path = self.folder / 'secrets.json'
        path.write_text('broken')
        with self.assertRaises(ValueError):
            self.load(apiKey='new')
        self.assertEqual(path.read_text(), 'broken')

    def test_symlink_is_rejected(self):
        self.folder.mkdir(parents=True)
        other = self.home / 'other'
        other.write_text('{}')
        (self.folder / 'secrets.json').symlink_to(other)
        with self.assertRaises(OSError):
            self.load(apiKey='test')
        self.assertEqual(other.read_text(), '{}')

    def test_hardlink_is_rejected(self):
        self.folder.mkdir(parents=True)
        other = self.home / 'other'
        other.write_text('{}')
        os.link(other, self.folder / 'secrets.json')
        with self.assertRaises(ValueError):
            self.load()

    def test_cli_migration(self):
        result = subprocess.run(['python3', str(ROOT / 'helpers/secrets.py')],
                                input=json.dumps({'action': 'load', 'legacy': {'apiKey': 'test-key'}}),
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout)['secrets']['apiKey'], 'test-key')
        self.assertEqual(result.stderr, '')

    def test_cli_failure_does_not_echo_secret(self):
        result = subprocess.run(['python3', str(ROOT / 'helpers/secrets.py')],
                                input='{"secrets":"DO-NOT-ECHO"}', text=True, capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout), {'ok': False})
        self.assertNotIn('DO-NOT-ECHO', result.stdout + result.stderr)

    def test_curl_secret_not_in_process_arguments(self):
        # Keep curl waiting for stdin while inspecting Linux's actual argv.
        process = subprocess.Popen(['curl', '-q', '-sS', '--config', '-'],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            cmdline = Path(f'/proc/{process.pid}/cmdline').read_bytes()
            self.assertNotIn(b'DUMMY-SECRET', cmdline)
            self.assertIn(b'--config', cmdline)
            # Local file fixture requires neither a real key nor network access.
            fixture = self.home / 'DUMMY-SECRET'
            fixture.write_text('OK')
            out, err = process.communicate(('url = ' + json.dumps(fixture.as_uri()) + '\n').encode(), timeout=5)
            self.assertEqual(process.returncode, 0, err)
            self.assertEqual(out, b'OK')
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


if __name__ == '__main__':
    unittest.main()
