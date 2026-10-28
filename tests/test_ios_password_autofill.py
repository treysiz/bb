import plistlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class IOSPasswordAutofillSourceTests(unittest.TestCase):
    def test_host_app_and_extension_metadata_are_valid(self):
        app = plistlib.loads((ROOT / "ios_app/App/Info.plist").read_bytes())
        extension = plistlib.loads((ROOT / "ios_app/PasswordCredentialProvider/Info.plist").read_bytes())
        entitlements = plistlib.loads((ROOT / "ios_app/PasswordCredentialProvider/MiniBridgePassword.entitlements").read_bytes())
        self.assertEqual(app["CFBundleIdentifier"], "$(PRODUCT_BUNDLE_IDENTIFIER)")
        self.assertEqual(extension["NSExtension"]["NSExtensionPointIdentifier"],
                         "com.apple.authentication-services-credential-provider-ui")
        self.assertTrue(extension["NSExtension"]["NSExtensionAttributes"]["ASCredentialProviderExtensionCapabilities"]["SupportsSavePasswordCredentials"])
        self.assertTrue(entitlements["com.apple.developer.authentication-services.autofill-credential-provider"])

    def test_project_builds_and_embeds_both_targets(self):
        project = (ROOT / "ios_app/MiniBridgePassword.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        self.assertIn('productType = "com.apple.product-type.application"', project)
        self.assertIn('productType = "com.apple.product-type.app-extension"', project)
        self.assertIn('name = "Embed App Extensions"', project)
        self.assertIn("CodeSignOnCopy", project)
        self.assertIn("App/MiniBridgePassword.entitlements", project)
        self.assertIn("PasswordCredentialProvider/MiniBridgePassword.entitlements", project)

    def test_save_path_requires_an_explicit_system_save_action(self):
        source = (ROOT / "ios_app/PasswordCredentialProvider/CredentialProviderViewController.swift").read_text(encoding="utf-8")
        self.assertIn("prepareInterface(for savePasswordRequest: ASSavePasswordRequest)", source)
        self.assertIn("completeSavePasswordRequest", source)
        self.assertIn("cancelRequest(withError: ASExtensionError(.userCanceled))", source)
        self.assertIn("save(site:", source)

    def test_credentials_are_encrypted_with_the_shared_vault_format(self):
        source = (ROOT / "ios_app/Shared/VaultRepository.swift").read_text(encoding="utf-8")
        self.assertIn("CCPBKDFAlgorithm(kCCPBKDF2)", source)
        self.assertIn("CCPRFHmacAlgSHA256", source)
        self.assertIn("600_000", source)
        self.assertIn("AES.GCM.seal", source)
        self.assertIn("authenticating: Data(id.utf8)", source)
        self.assertIn('"type": "pair"', source)
        self.assertIn('"type": "put"', source)

    def test_fill_matching_is_scoped_to_exact_host_or_app_identifier(self):
        source = (ROOT / "ios_app/Shared/VaultRepository.swift").read_text(encoding="utf-8")
        self.assertIn("caseInsensitiveCompare(identifier) == .orderedSame", source)


if __name__ == "__main__":
    unittest.main()
