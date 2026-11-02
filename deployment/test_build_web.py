"""Regression for first-run Flutter bootstrap metadata on hosted builds."""
import unittest
import json
import os
import tempfile
from pathlib import Path
from unittest.mock import patch
import build_web
from build_web import machine_sdk_version


class PublicConfigTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        (root/'deployment').mkdir()
        self.saved = dict(FIREBASE_API_KEY='fixture-key', FIREBASE_PROJECT_ID='fixture-project',
                          FIREBASE_SENDER_ID='123', FIREBASE_WEB_APP_ID='fixture-web-app')
        self.path = root/'deployment'/'firebase-web.public.json'
        self.path.write_text(json.dumps(self.saved), encoding='utf-8')
        self.root_patch = patch.object(build_web, 'ROOT', root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)

    def test_saved_public_config_enables_hosted_build_without_extra_environment(self):
        with patch.dict(os.environ, {}, clear=True):
            _, public = build_web.config()
        self.assertEqual(public, self.saved)

    def test_complete_host_override_replaces_saved_project(self):
        override = {key: 'other-'+value for key, value in self.saved.items()}
        with patch.dict(os.environ, override, clear=True):
            _, public = build_web.config()
        self.assertEqual(public, override)

    def test_partial_host_override_rejected_instead_of_mixing_projects(self):
        with patch.dict(os.environ, {'FIREBASE_PROJECT_ID': 'other-project'}, clear=True):
            with self.assertRaisesRegex(ValueError, 'Partial Firebase'):
                build_web.config()

    def test_unknown_keys_in_public_file_are_rejected(self):
        self.path.write_text(json.dumps({**self.saved, 'SERVER_SECRET': 'fixture'}), encoding='utf-8')
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, 'Invalid public Firebase'):
                build_web.config()

class SdkVersionTests(unittest.TestCase):
    def test_clean_machine_output(self):
        self.assertEqual(machine_sdk_version('{"frameworkVersion":"3.41.9"}')['frameworkVersion'], '3.41.9')

    def test_first_run_progress_and_ansi_before_metadata(self):
        output = '\x1b[32mDownloading packages...\nGot dependencies.\n{"frameworkVersion":"3.41.9","frameworkRevision":"fixture"}\n'
        self.assertEqual(machine_sdk_version(output)['frameworkRevision'], 'fixture')

    def test_unrecognized_metadata_fails_clearly(self):
        with self.assertRaisesRegex(ValueError, 'SDK version'):
            machine_sdk_version('setup failed {not json} {"unexpected":true}')

if __name__ == '__main__':
    unittest.main()
