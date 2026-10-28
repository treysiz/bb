"""Source/metadata checks only. These never substitute for Xcode or iPhone tests."""
import json
from pathlib import Path
import plistlib
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT/'ios_app'


class IOSCameraProjectTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        text = (IOS/'MiniBridgePassword.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
        cls.rows = re.findall(r'^\s*([A-F0-9]{24})\s*=\s*\{(.*)\};\s*$', text, re.M)
        cls.objects = dict(cls.rows)

    def test_new_target_graph_references_exist_without_autofill_dependency(self):
        self.assertEqual(len(self.rows), len(self.objects), 'Duplicate PBX identifiers')
        for key, body in self.rows:
            for reference in re.findall(r'\b[A-F0-9]{24}\b', body):
                self.assertIn(reference, self.objects, (key, reference))
        target = self.objects['B00000000000000000000040']
        self.assertIn('dependencies = ();', target)
        phase = self.objects['B00000000000000000000030']
        builds = re.search(r'files = \(([^)]*)\)', phase)[1].split(',')
        files = []
        for item in filter(None, builds):
            ref = re.search(r'fileRef = ([A-F0-9]{24})', self.objects[item])[1]
            path = re.search(r'path = ([^;]+)', self.objects[ref])[1].strip('"')
            self.assertTrue((IOS/path).is_file(), path)
            files.append(path)
        self.assertEqual(set(files), {'CameraApp/MiniBridgeCameraApp.swift','CameraApp/CameraBrowserModel.swift',
            'CameraCore/Sources/MiniBridgeCameraCore/ServerOrigin.swift'})

    def test_old_password_targets_and_shared_scheme_are_retained(self):
        for key in ('A00000000000000000000040','A00000000000000000000041'):
            self.assertIn(key, self.objects)
        scheme = ET.parse(IOS/'MiniBridgePassword.xcodeproj/xcshareddata/xcschemes/MiniBridge Camera.xcscheme')
        refs = scheme.findall('.//BuildableReference')
        self.assertTrue(refs)
        self.assertTrue(all(ref.attrib['BlueprintIdentifier']=='B00000000000000000000040' for ref in refs))

    def test_target_configuration_does_not_inherit_password_entitlements(self):
        for key in ('B00000000000000000000080','B00000000000000000000081'):
            body = self.objects[key]
            self.assertIn('SDKROOT = iphoneos;', body)
            self.assertIn('INFOPLIST_FILE = CameraApp/Info.plist;', body)
            self.assertNotIn('CODE_SIGN_ENTITLEMENTS', body)
            self.assertNotIn('DEVELOPMENT_TEAM', body)

    def test_metadata_has_landscape_and_no_background_or_local_sensor_claims(self):
        info = plistlib.loads((IOS/'CameraApp/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleExecutable'], '$(EXECUTABLE_NAME)')
        self.assertIn('UIInterfaceOrientationLandscapeLeft', info['UISupportedInterfaceOrientations'])
        self.assertIn('UIInterfaceOrientationLandscapeRight', info['UISupportedInterfaceOrientations'])
        for name in ('UIBackgroundModes','NSMicrophoneUsageDescription','NSCameraUsageDescription','NSAppTransportSecurity'):
            self.assertNotIn(name, info)

    def test_resources_and_app_icon_are_real_files(self):
        resource_phase = self.objects['B00000000000000000000032']
        for build in ('B00000000000000000000004','B00000000000000000000005'):
            self.assertIn(build, resource_phase)
        folder = IOS/'CameraApp/Assets.xcassets/AppIcon.appiconset'
        icon = json.loads((folder/'Contents.json').read_text())['images'][0]['filename']
        data = (folder/icon).read_bytes()
        self.assertEqual(data[:8], b'\x89PNG\r\n\x1a\n')
        self.assertEqual((int.from_bytes(data[16:20],'big'),int.from_bytes(data[20:24],'big')),(1024,1024))
        self.assertTrue((IOS/'CameraApp/BridgeLifecycle.js').is_file())


if __name__ == '__main__':unittest.main()
