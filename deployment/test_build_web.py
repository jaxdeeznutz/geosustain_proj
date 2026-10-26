"""Regression for first-run Flutter bootstrap metadata on hosted builds."""
import unittest
from build_web import machine_sdk_version

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
