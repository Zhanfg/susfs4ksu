#!/usr/bin/env python3
"""Host checks for backend discovery, boot stages and helper installation."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


class ControllerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.module = self.directory / "module"
        (self.module / "bin").mkdir(parents=True)
        shutil.copy2(ROOT / "ksu_module_susfs/controller.sh", self.module / "controller.sh")
        self.ksud = self.directory / "ksud"
        self.helper = self.module / "bin/ksu_susfs"
        self.log = self.directory / "calls"
        self.config = self.directory / "config"
        self.config.write_text("enabled=0\n")
        self.env = os.environ.copy()
        self.env.update(SUSFS_KSUD_BIN=str(self.ksud), SUSFS_CONFIG=str(self.config),
                        SUSFS_RUNTIME_DIR=str(self.directory / "runtime"), TEST_CALLS=str(self.log))
        self.env.pop("SUSFS_BIN", None)
        for prefix in ("NATIVE", "HELPER"):
            self.env.update({f"TEST_{prefix}_VERSION": "v2.3.0", f"TEST_{prefix}_VARIANT": "GKI",
                             f"TEST_{prefix}_EXIT": "0", f"TEST_{prefix}_FEATURE_EXIT": "0"})
        self.mock(self.ksud, "NATIVE")
        self.mock(self.helper, "HELPER")

    def mock(self, path: Path, kind: str) -> None:
        path.write_text(f'''#!/bin/sh
printf '%s %s\\n' {kind} "$*" >> "$TEST_CALLS"
case "$1:$2:$3" in
  susfs:show:version) printf '%s\\n' "$TEST_{kind}_VERSION"; exit "$TEST_{kind}_EXIT" ;;
  susfs:show:variant) printf '%s\\n' "$TEST_{kind}_VARIANT"; exit "$TEST_{kind}_EXIT" ;;
  susfs:show:enabled_features) echo CONFIG_KSU_SUSFS_SUS_PATH; exit "$TEST_{kind}_FEATURE_EXIT" ;;
esac
exit 0
''')
        path.chmod(0o755)

    def run_controller(self, action: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["sh", str(self.module / "controller.sh"), action],
                              env=self.env, capture_output=True, text=True)

    def test_native_preferred_and_probe_reused(self) -> None:
        result = self.run_controller("status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("backend=ksud-susfs\n", result.stdout)
        self.assertIn("compat_resukisu=yes\n", result.stdout)
        self.assertIn("version=v2.3.0\nvariant=GKI\n", result.stdout)
        self.assertEqual(self.log.read_text().splitlines(), ["NATIVE susfs show version",
                         "NATIVE susfs show variant", "NATIVE susfs show enabled_features"])

    def test_invalid_successful_native_reply_uses_private_fallback(self) -> None:
        for version in ("", "Unsupported", "v2.3", "v2:3.3.0", "v2.3.0junk", "v2.3.0-", "v2.3.0\njunk"):
            with self.subTest(version=version):
                self.env["TEST_NATIVE_VERSION"] = version
                result = self.run_controller("backend")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "reboot-susfs-v2\n")

    def test_native_variant_required_and_release_suffix_allowed(self) -> None:
        self.env["TEST_NATIVE_VARIANT"] = "Unsupported"
        self.assertEqual(self.run_controller("backend").stdout, "reboot-susfs-v2\n")
        self.env.update(TEST_NATIVE_VARIANT="NON-GKI", TEST_NATIVE_VERSION="v2.3.0-next.1")
        self.assertEqual(self.run_controller("backend").stdout, "ksud-susfs\n")
        self.env["TEST_NATIVE_EXIT"] = "1"
        self.assertEqual(self.run_controller("backend").stdout, "reboot-susfs-v2\n")

    def test_unavailable_backend_does_not_mark_stage_applied(self) -> None:
        self.env.update(TEST_NATIVE_VERSION="Unsupported", TEST_HELPER_VERSION="")
        self.assertEqual(self.run_controller("status").returncode, 127)
        self.assertEqual(self.run_controller("post-fs-data").returncode, 127)
        self.assertFalse((self.directory / "runtime/post-fs-data.done").exists())

    def test_failed_feature_query_is_reported(self) -> None:
        self.env["TEST_NATIVE_FEATURE_EXIT"] = "1"
        self.assertNotEqual(self.run_controller("status").returncode, 0)

    def test_unknown_major_does_not_claim_v2_compatibility(self) -> None:
        self.env["TEST_NATIVE_VERSION"] = "v3.0.0"
        result = self.run_controller("status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("compat_resukisu=unknown\n", result.stdout)

    def test_stages_apply_once(self) -> None:
        self.config.write_text("enabled=1\nlogging=0\nsus_path=/system/test\n"
                               "sus_path_loop=/sdcard/test\nsus_map=/system/lib64/test.so\n")
        self.assertEqual(self.run_controller("post-fs-data").returncode, 0)
        first = self.log.read_text()
        self.assertEqual(self.run_controller("post-fs-data").returncode, 0)
        self.assertEqual(self.log.read_text(), first)
        self.assertEqual(self.run_controller("boot-completed").returncode, 0)
        self.assertEqual([line for line in self.log.read_text().splitlines() if " show " not in line],
                         ["NATIVE susfs enable_log 0", "NATIVE susfs add_sus_path /system/test",
                          "NATIVE susfs add_sus_path_loop /sdcard/test",
                          "NATIVE susfs add_sus_map /system/lib64/test.so"])

    def test_installer_preserves_manager_hardlink(self) -> None:
        module = self.directory / "installed-module"
        shutil.copytree(ROOT / "ksu_module_susfs", module)
        (module / "bin").mkdir()
        manager = self.directory / "manager-daemon"
        manager.write_bytes(b"original manager daemon")
        private = module / "bin/ksu_susfs"
        os.link(manager, private)
        alias = self.directory / "manager-ksu_susfs"
        os.link(manager, alias)
        archive = self.directory / "module.zip"
        with zipfile.ZipFile(archive, "w") as output:
            output.writestr("tools/ksu_susfs_arm64", b"new private helper")
        temporary = self.directory / "installer-tmp"
        temporary.mkdir()
        env = self.env.copy()
        env.update(ARCH="arm64", MODPATH=str(module), ZIPFILE=str(archive), TMPDIR=str(temporary),
                   TEST_CUSTOMIZE=str(ROOT / "ksu_module_susfs/customize.sh"))
        script = 'ui_print() { :; }; abort() { echo "$*" >&2; exit 1; }; . "$TEST_CUSTOMIZE"'
        result = subprocess.run(["sh", "-c", script], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(private.read_bytes(), b"new private helper")
        self.assertEqual(manager.read_bytes(), b"original manager daemon")
        self.assertEqual(alias.stat().st_ino, manager.stat().st_ino)
        self.assertNotEqual(private.stat().st_ino, manager.stat().st_ino)
        self.assertTrue(os.access(private, os.X_OK))
        subprocess.run(["sh", str(ROOT / "ksu_module_susfs/uninstall.sh")], env=env, check=True)
        self.assertEqual(alias.read_bytes(), b"original manager daemon")


if __name__ == "__main__":
    unittest.main(verbosity=2)
