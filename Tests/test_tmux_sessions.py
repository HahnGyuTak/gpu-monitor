import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch, Mock, mock_open

path = Path(__file__).resolve().parents[1] / "Sources/GPUMonitor/Resources/tmux_sessions.py"
spec = importlib.util.spec_from_file_location("tmux_sessions", path)
t = importlib.util.module_from_spec(spec)
spec.loader.exec_module(t)


def process(pid=10, parent=1, **changes):
    return dict(dict(pid=pid, parent=parent, name="bash", state="S", pgrp=pid,
                     tty=123, foreground=pid, start="100"), **changes)


def pane(**changes):
    return dict(dict(pid=10, dead=False, pipe=False, tty="/dev/pts/1"), **changes)


def row(session="$0", name="idle", attached=0, pane_id="%0", pid=10, dead=0):
    return "\t".join(map(str, [1, session, 123456, name, attached, "@0", pane_id, pid, "bash", dead, "/dev/pts/1", 0]))


class SessionChecks(unittest.TestCase):
    def setUp(self):
        self.stat = patch.object(t.os, "stat", return_value=SimpleNamespace(st_rdev=123)).start()
        self.addCleanup(patch.stopall)

    def check(self, ps, **changes):
        return t.pane_blocker(pane(**changes), ps, shell_check=lambda _: True)

    def test_idle_interactive_shell(self):
        self.assertIsNone(self.check({10: process()}))

    def test_background_and_helpers_block_deletion(self):
        for name in ("python", "sleep", "tee", "tail", "bash"):
            with self.subTest(name=name):
                self.assertIsNotNone(self.check({10: process(), 11: process(11, 10, name=name)}))

    def test_reparented_tty_process(self):
        self.assertIsNotNone(self.check({10: process(), 11: process(11, 1)}))

    def test_unrelated_process_is_not_a_blocker(self):
        self.assertIsNone(self.check({10: process(), 11: process(11, 1, tty=999)}))

    def test_running_shell_and_missing_root_are_blocked(self):
        self.assertIsNotNone(self.check({10: process(state="R")}))
        self.assertIsNotNone(self.check({}))

    def test_dead_pane_and_reused_pid(self):
        self.stat.side_effect = FileNotFoundError()
        self.assertIsNone(self.check({}, dead=True))
        self.assertIsNotNone(self.check({10: process()}, dead=True))

    def test_pipe_and_unknown_foreground_block(self):
        self.assertIsNotNone(self.check({10: process()}, pipe=True))
        self.assertIsNotNone(self.check({10: process(foreground=22)}))

    def test_tty_permission_denied(self):
        self.stat.side_effect = PermissionError()
        self.assertIsNotNone(self.check({10: process()}))

    def test_script_shell_is_not_idle(self):
        with patch("builtins.open", mock_open(read_data=b"bash\0-c\0read foo\0")), patch.object(t.os, "readlink", return_value="/usr/bin/bash"):
            self.assertFalse(t.interactive_shell(10))
        with patch("builtins.open", mock_open(read_data=b"bash\0--noprofile\0--norc\0")), patch.object(t.os, "readlink", return_value="/usr/bin/bash"):
            self.assertTrue(t.interactive_shell(10))

    def test_unreadable_process_scan_fails_closed(self):
        with patch.object(t.os, "listdir", return_value=["10"]), patch("builtins.open", side_effect=PermissionError()):
            with self.assertRaises(t.SessionCheckError):
                t.strict_processes()

    def inventory(self, output, ps=None, blocker=None):
        if ps is None:
            ps = {1: process(1, 0, tty=0), 10: process(), 11: process(11, 1, tty=124)}
        with patch.object(t, "tmux_command", return_value=output), patch.object(t, "strict_processes", return_value=ps), patch.object(t, "pane_blocker", side_effect=blocker or (lambda *_: None)), patch("builtins.open", mock_open(read_data="boot-id")):
            return t.inspect_tmux_sessions()

    def test_attached_clients_block(self):
        self.assertFalse(self.inventory(row(attached=1))[0]["canDelete"])

    def test_all_panes_are_checked(self):
        def blocker(p, _):
            return "busy" if p["pid"] == 11 else None
        item = self.inventory(row() + "\n" + row(pane_id="%1", pid=11), blocker=blocker)[0]
        self.assertEqual(item["paneIDs"], ["%0", "%1"])
        self.assertFalse(item["canDelete"])

    def test_shared_window_is_blocked(self):
        items = self.inventory(row() + "\n" + row(session="$1", name="linked"))
        self.assertTrue(all(not item["canDelete"] for item in items))

    def test_identity_changes_invalidate_token(self):
        original = self.inventory(row())[0]["token"]
        for changed in (row(name="renamed"), row(pane_id="%2"), row().replace("123456", "123457")):
            self.assertNotEqual(original, self.inventory(changed)[0]["token"])
        ps = {1: process(1, 0, tty=0), 10: process(start="new-start")}
        self.assertNotEqual(original, self.inventory(row(), ps)[0]["token"])

    def test_incomplete_tmux_metadata_is_rejected(self):
        with self.assertRaises(t.SessionCheckError):
            self.inventory("incomplete")


class DeletionChecks(unittest.TestCase):
    def setUp(self):
        self.item = dict(id="$4", name="test; literal name", token="a" * 64, canDelete=True,
                         reason="idle", paneIDs=["%7"], serverPID=123, created=456)
        self.command = Mock(return_value="")

    def delete(self, inventories, request=None):
        return t.delete_empty_session(request or self.item, inspect=Mock(side_effect=inventories), command=self.command)

    def test_verified_delete_uses_exact_id_only(self):
        result = self.delete([[self.item], [self.item]])
        self.assertTrue(result["deleted"])
        args = self.command.call_args.args[0]
        self.assertEqual(args[:4], ["if-shell", "-F", "-t", "$4"])
        self.assertEqual(args[5], "kill-session -t '$4'")
        self.assertIn("session_attached", args[4])
        self.assertNotIn(self.item["name"], " ".join(args))

    def test_work_starting_between_checks_is_blocked(self):
        busy = dict(self.item, canDelete=False, reason="new job")
        self.assertFalse(self.delete([[self.item], [busy]])["deleted"])
        self.command.assert_not_called()

    def test_replaced_session_and_disappearing_session_are_blocked(self):
        for items in ([dict(self.item, token="b" * 64)], []):
            self.assertFalse(self.delete([[self.item], items])["deleted"])
        self.command.assert_not_called()

    def test_remote_recheck_blocks_stale_eligibility(self):
        self.assertFalse(self.delete([[dict(self.item, canDelete=False)]])["deleted"])
        self.command.assert_not_called()

    def test_malformed_target_never_executes(self):
        for target in ("idle", "$1;kill-server", "-a", ""):
            self.assertFalse(self.delete([], dict(self.item, id=target))["deleted"])
        self.command.assert_not_called()

    def test_last_moment_attachment_is_reported(self):
        self.command.return_value = "GPU_MONITOR_DELETE_BLOCKED\n"
        self.assertFalse(self.delete([[self.item], [self.item]])["deleted"])

    def test_inspection_failure_never_deletes(self):
        self.assertFalse(self.delete(t.SessionCheckError("permission denied"))["deleted"])
        self.command.assert_not_called()


if __name__ == "__main__":
    unittest.main()
