"""Synthetic bundle fixtures only; never manufacture a real deliverable from them."""
import importlib.util
import json
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('ios_ipa',ROOT/'scripts/package_ios_camera_ipa.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)


class IOSCameraIPATests(unittest.TestCase):
    def setUp(self):
        (ROOT/'firmware/build').mkdir(parents=True,exist_ok=True)
        self.temp=tempfile.TemporaryDirectory(prefix='ios-ipa-synthetic-',dir=ROOT/'firmware/build')
        self.root=Path(self.temp.name).resolve()
        assert self.root.is_relative_to((ROOT/'firmware/build').resolve())
        self.app=self.root/'Synthetic.app';self.app.mkdir()
        self.info={'CFBundleSupportedPlatforms':['iPhoneOS'],'CFBundleExecutable':'Synthetic',
            'CFBundleIdentifier':'test.synthetic.camera','CFBundleShortVersionString':'0.0.0',
            'CFBundleVersion':'0','MinimumOSVersion':'16.0'}
        self.write_info();self.write_binary(2)
        self.output=self.root/'UNSIGNED-test.ipa'

    def tearDown(self):self.temp.cleanup()
    def write_info(self):
        (self.app/'Info.plist').write_bytes(plistlib.dumps(self.info))
    def write_binary(self, platform):
        header=struct.pack('<IiiIIIII',0xFEEDFACF,0x0100000C,0,2,1,24,0,0)
        command=struct.pack('<IIIIII',0x32,24,platform,16<<16,26<<16,0)
        (self.app/'Synthetic').write_bytes(header+command+b'SYNTHETIC_FIXTURE_NOT_AN_APP')

    def test_layout_hashes_executable_mode_and_uninstallable_label(self):
        report=module.package(self.app,self.output)
        self.assertFalse(report['install_ready']);self.assertFalse(report['testflight_ready'])
        self.assertFalse(report['signed_by_this_script'])
        self.assertEqual(report['device_binary']['platform'],'iPhoneOS')
        with zipfile.ZipFile(self.output) as archive:
            self.assertEqual(set(archive.namelist()),{'Payload/Synthetic.app/Info.plist','Payload/Synthetic.app/Synthetic'})
            self.assertEqual(archive.getinfo('Payload/Synthetic.app/Synthetic').external_attr>>16 & 0o777,0o755)
        self.assertEqual(json.loads(self.output.with_suffix('.json').read_text())['sha256'],report['sha256'])

    def test_arm64_simulator_cannot_be_mislabeled_as_device(self):
        self.write_binary(7)
        with self.assertRaises(ValueError):module.package(self.app,self.output)
        self.assertFalse(self.output.exists())

    def test_simulator_bundle_metadata_is_rejected(self):
        self.info['CFBundleSupportedPlatforms']=['iPhoneSimulator'];self.write_info()
        with self.assertRaises(ValueError):module.package(self.app,self.output)

    def test_invalid_binary_and_executable_escape_are_rejected(self):
        (self.app/'Synthetic').write_bytes(b'not a compiler output')
        with self.assertRaises(ValueError):module.package(self.app,self.output)
        for name in ('../Synthetic','..\\Synthetic','..',''):
            self.info['CFBundleExecutable']=name;self.write_info()
            with self.assertRaises(ValueError):module.package(self.app,self.output)

    def test_signing_material_is_not_exported(self):
        for name in ('certificate.p12','embedded.mobileprovision','private.key'):
            file=self.app/name;file.write_bytes(b'SYNTHETIC_NOT_A_CREDENTIAL')
            with self.assertRaises(ValueError):module.package(self.app,self.output)
            file.unlink()


if __name__=='__main__':unittest.main()
