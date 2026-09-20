import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / "Sources/GPUMonitor/Resources/collector.py"
spec = importlib.util.spec_from_file_location("collector", path)
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)


class ProgressTests(unittest.TestCase):
    def test_tqdm_eta(self):
        p = c.parse_progress("exp_042: 63%|██████▎   | 6300/10000 [2:23:00<1:24:00, 1.36s/it]")
        self.assertEqual(p["step"], 6300)
        self.assertAlmostEqual(p["fraction"], .63)
        self.assertEqual(p["etaSeconds"], 5040)
        self.assertEqual(p["label"], "exp_042")

    def test_glued_and_truncated_tmux_bars(self):
        text = "eval: 99%|████| 5171/5215 [50:35<00eval: 99%|████| 5172/5215 [50:35<00"
        p = c.parse_progress(text)
        self.assertEqual(p["step"], 5172)
        self.assertIsNone(p["etaSeconds"])

    def test_no_eta_from_next_bar(self):
        p = c.parse_progress("train: 10%|x| 1/10 [00:01<?\nval: 20%|xx| 2/10 [00:01<00:04, 2it/s]")
        self.assertEqual(p["step"], 2)
        self.assertEqual(p["etaSeconds"], 4)

    def test_ignore_nvidia_smi_and_unlabelled_ratios(self):
        self.assertIsNone(c.parse_progress("| 41% 33C P3 50W / 280W | 1MiB / 24576MiB | 0% Default |\n2026/09/17"))

    def test_epoch_scope(self):
        p = c.parse_progress("Epoch 3/5")
        self.assertEqual(p["scope"], "epoch")
        self.assertAlmostEqual(p["fraction"], .6)

    def test_invalid_counts(self):
        self.assertIsNone(c.parse_progress("step 20/10"))
        self.assertIsNone(c.parse_progress("step 0/0"))

    def test_carriage_return_and_ansi(self):
        p = c.parse_progress("\x1b[31mstep 1/10\x1b[0m\rstep 2/10")
        self.assertEqual(p["step"], 2)

    def test_thousands(self):
        p = c.parse_progress("Step 1,200/2,000 ETA 00:15")
        self.assertEqual(p["total"], 2000)
        self.assertEqual(p["etaSeconds"], 15)

    def test_exit_marker_not_echo_command(self):
        events = c.parse_events("echo GPU_MONITOR_EXIT run=abc code=0\nGPU_MONITOR_EXIT run=abc code=0")
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["exitCode"], 0)

    def test_oom_and_completion_are_separate(self):
        self.assertEqual(c.parse_events("torch.OutOfMemoryError: CUDA out of memory")[0]["kind"], "oom")
        self.assertEqual(c.parse_events("Training completed")[0]["kind"], "completionHint")
        self.assertEqual(c.parse_events("100%|████| 10/10 [00:01<00:00, 1it/s]"), [])

    def test_process_tree(self):
        ps = {1: {"pid": 1, "parent": 0}, 2: {"pid": 2, "parent": 1}, 3: {"pid": 3, "parent": 2}, 4: {"pid": 4, "parent": 0}}
        self.assertEqual([p["pid"] for p in c.descendants(1, ps)], [2, 3])

    def test_host_to_container_gpu_pid(self):
        ps = {22: {'start': '500'}}
        self.assertEqual(c.map_gpu_pid(50000, ps, {'50000': {'pid': 22, 'start': '500'}}, True), 22)

    def test_namespace_pid_collision_is_not_a_match(self):
        self.assertIsNone(c.map_gpu_pid(22, {22: {'start': '500'}}, {}, True))

    def test_reused_pid_is_not_a_match(self):
        self.assertIsNone(c.map_gpu_pid(50000, {22: {'start': '501'}}, {'50000': {'pid': 22, 'start': '500'}}, True))

    def test_native_pid_mapping(self):
        self.assertEqual(c.map_gpu_pid(22, {22: {'start': '500'}}, {}, False), 22)


if __name__ == "__main__":
    unittest.main()
