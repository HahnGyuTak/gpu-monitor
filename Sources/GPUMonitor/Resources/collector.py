"""Read-only, stdlib-only Linux snapshot. Sent over SSH stdin; never installed.

Progress is scoped to the displayed bar, NOT assumed to be whole-run progress.
The protocol intentionally separates observations from UI/notification policy.
"""
import csv
import glob
import io
import json
import os
import re
import subprocess
import time

VERSION = 1
SHELLS = {"bash", "zsh", "sh", "fish", "dash", "tmux", "tmux: server"}
HELPERS = {"tee", "cat", "tail", "less", "more", "watch", "nvidia-smi", "top", "htop"}
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07]*(?:\x07|\x1b\\)")
BAR = re.compile(r"(?P<pct>\d{1,3}(?:\.\d+)?)%\|[^\n|]*\|\s*(?P<step>\d[\d,]*)\s*/\s*(?P<total>\d[\d,]*)")
STEPS = re.compile(r"\b(?P<label>global[_ ]?step|steps?|epochs?)\s*[:=]?\s*(?P<step>\d[\d,]*)\s*/\s*(?P<total>\d[\d,]*)", re.I)
ERROR = re.compile(r"CUDA out of memory|torch\.OutOfMemoryError|OutOfMemoryError|CUDA error:|Traceback \(most recent call last\)|RuntimeError:", re.I)
COMPLETE = re.compile(r"(?:training|evaluation|inference)\s+(?:is\s+)?(?:completed|finished)(?:\s+successfully)?\b", re.I)
EXIT = re.compile(r"GPU_MONITOR_EXIT\s+run=([A-Za-z0-9_.-]+)\s+code=(\d+)")


def run(args, timeout=4):
    try:
        p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           text=True, errors="replace", timeout=timeout)
        return p.returncode, p.stdout, p.stderr.strip()[:500]
    except (OSError, subprocess.TimeoutExpired) as e:
        return -1, "", str(e)[:500]


def number(value):
    try:
        return float(value.strip())
    except (ValueError, AttributeError):
        return None


def seconds(value):
    try:
        days = 0
        if "d " in value:
            d, value = value.split("d ")
            days = int(d)
        parts = [int(x) for x in value.strip().split(":")]
        if len(parts) not in (2, 3):
            return None
        result = 0
        for part in parts:
            result = result * 60 + part
        return result + days * 86400
    except ValueError:
        return None


def parse_progress(text):
    text = ANSI.sub("", text).replace("\r", "\n")
    # A wrapped tmux line may contain many successive bars. Always use the last.
    candidates = []
    for pattern, kind in ((BAR, "bar"), (STEPS, "steps")):
        for m in pattern.finditer(text):
            step = int(m.group("step").replace(",", ""))
            total = int(m.group("total").replace(",", ""))
            if total <= 0 or step > total:
                continue
            tail = text[m.end():m.end() + 180].split("\n")[0]
            # Don't steal ETA from a later bar on the same wrapped line.
            tail = re.split(r"\d{1,3}%\|", tail)[0]
            eta = re.search(r"<\s*((?:\d+d )?\d+:\d+(?::\d+)?)(?=\s*[,\]])", tail)
            if not eta:
                eta = re.search(r"\bETA\s*[:=]?\s*(\d+:\d+(?::\d+)?)", tail, re.I)
            start = text.rfind("\n", 0, m.start()) + 1
            prefix = text[start:m.start()].strip()
            # Prefix can itself contain prior bars in a badly wrapped terminal.
            prefix = re.split(r"\]", prefix)[-1].strip()[-90:]
            scope = "epoch" if kind == "steps" and m.group("label").lower().startswith("epoch") else "displayed"
            label = prefix.rstrip(": ") if kind == "bar" else m.group("label")
            candidates.append((m.start(), {
                "step": step, "total": total, "fraction": step / total,
                "etaSeconds": seconds(eta.group(1)) if eta else None,
                "label": label or "진행 중인 단계", "scope": scope,
                "source": "tmux", "etaSource": "log" if eta else None,
            }))
    return max(candidates, key=lambda x: x[0])[1] if candidates else None


def parse_events(text):
    lines = ANSI.sub("", text).replace("\r", "\n").splitlines()
    result = []
    for line in lines:
        marker = EXIT.search(line)
        # Match only a standalone marker printed by the optional wrapper.
        if marker and line.strip() == marker.group(0):
            result.append({"kind": "exit", "message": marker.group(0), "exitCode": int(marker.group(2)), "runID": marker.group(1)})
        elif ERROR.search(line):
            result.append({"kind": "oom" if re.search(r"out.?of.?memory", line, re.I) else "error", "message": line.strip()[:350]})
        elif COMPLETE.search(line) and not re.search(r"\b(echo|print|grep)\b", line):
            result.append({"kind": "completionHint", "message": line.strip()[:350]})
    return result[-12:]


def processes():
    result = {}
    for path in glob.glob("/proc/[0-9]*/stat"):
        try:
            stat = open(path).read()
            first = stat.index("(")
            last = stat.rindex(")")
            pid = int(stat[:first].strip())
            fields = stat[last + 2:].split()
            if fields[0] == "Z":
                continue
            # /proc stat field 22: starttime, persistent identity across PID reuse.
            result[pid] = {"pid": pid, "parent": int(fields[1]), "name": stat[first + 1:last],
                           "start": fields[19], "pgrp": int(fields[2]), "foreground": int(fields[5])}
        except (OSError, ValueError, IndexError):
            pass
    return result


def descendants(root, all_processes):
    children = {}
    for p in all_processes.values():
        children.setdefault(p["parent"], []).append(p)
    result, queue, seen = [], [root], {root}
    while queue:
        for p in children.get(queue.pop(), []):
            if p["pid"] not in seen:
                seen.add(p["pid"])
                result.append(p)
                queue.append(p["pid"])
    return result


def map_gpu_pid(pid, all_processes, mapping, in_container):
    if not in_container:
        return pid if pid in all_processes else None
    # Never equate host PID numbers with namespace PID numbers by coincidence.
    entry = mapping.get(str(pid))
    if not isinstance(entry, dict):
        return None
    target = entry.get('pid')
    process = all_processes.get(target)
    return target if process and process['start'] == entry.get('start') else None


def snapshot():
    errors = []
    code, output, error = run(["nvidia-smi", "--query-gpu=index,uuid,name,utilization.gpu,memory.used,memory.total,temperature.gpu", "--format=csv,noheader,nounits"])
    gpus = []
    if code:
        errors.append("GPU: " + error)
    else:
        for row in csv.reader(io.StringIO(output), skipinitialspace=True):
            if len(row) != 7:
                continue
            gpus.append(dict(zip(["index", "id", "name", "utilization", "memoryUsed", "memoryTotal", "temperature"],
                                 [int(row[0]), row[1], row[2]] + [number(x) for x in row[3:]])))
    proc_code, proc_output, proc_error = run(["nvidia-smi", "--query-compute-apps=pid,gpu_uuid,process_name,used_memory", "--format=csv,noheader,nounits"])
    gpu_processes = []
    if proc_code:
        errors.append("GPU processes: " + proc_error)
    for row in csv.reader(io.StringIO(proc_output), skipinitialspace=True):
        if len(row) == 4 and row[0].isdigit():
            gpu_processes.append({"pid": int(row[0]), "gpuID": row[1]})
    occupied_gpus = {p['gpuID'] for p in gpu_processes}
    for gpu in gpus:
        gpu['hasComputeProcess'] = gpu['id'] in occupied_gpus if proc_code == 0 else None
    all_processes = processes()
    in_container = os.environ.get('GPU_MONITOR_CONTAINER') == '1'
    try:
        pid_mapping = json.loads(os.environ.get('GPU_MONITOR_PID_MAP', '{}'))
        if not isinstance(pid_mapping, dict):
            pid_mapping = {}
    except ValueError:
        pid_mapping = {}
    for process in gpu_processes:
        process['localPID'] = map_gpu_pid(process['pid'], all_processes, pid_mapping, in_container)
    code, output, error = run(["tmux", "list-panes", "-a", "-F", "#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_id}\t#{pane_pid}\t#{pane_current_command}\t#{pane_dead}\t#{pane_dead_status}\t#{pane_tty}"])
    panes = []
    tmux_available = code == 0
    no_server = code != -1 and (any(s in error for s in ("no server running", "no sessions")) or ("error connecting to" in error and "No such file or directory" in error))
    if code and not no_server:
        errors.append("tmux: " + error)
    for row in output.splitlines() if not code else []:
        f = row.split("\t")
        if len(f) != 9 or not f[4].isdigit():
            continue
        session, window, index, pane_id, pid, command, dead, exit_code, tty = f
        pid = int(pid)
        children = descendants(pid, all_processes)
        root = all_processes.get(pid)
        # A pane may execute python directly or keep an interactive shell alive.
        workers = sorted([p for p in children if p["name"] not in SHELLS | HELPERS], key=lambda p: (int(p["start"]), p["pid"]))
        if root and root["name"] not in SHELLS | HELPERS:
            workers.insert(0, root)
        cap_code, capture, cap_error = run(["tmux", "capture-pane", "-p", "-J", "-S", "-100", "-t", pane_id], timeout=2)
        # Bounded payload. Capture errors remain distinct from successful empty output.
        capture = capture[-24000:]
        pids = {p["pid"] for p in workers}
        gpu_ids = sorted({p["gpuID"] for p in gpu_processes if p["localPID"] in pids})
        # NVIDIA can report host PIDs inside a container: don't guess a GPU mapping.
        panes.append({
            "id": pane_id, "session": session, "window": window, "index": index,
            "pid": pid, "command": command, "dead": dead == "1",
            "exitCode": int(exit_code) if exit_code.isdigit() else None,
            "workers": [{"pid": p["pid"], "name": p["name"], "identity": str(p["pid"]) + ":" + p["start"]} for p in workers],
            "instance": str(pid) + ":" + (root["start"] if root else "dead"),
            "gpuIDs": gpu_ids, "progress": parse_progress(capture), "events": parse_events(capture),
            "captureError": cap_error if cap_code else None,
            "preview": "\n".join(capture.splitlines()[-18:])[-6000:],
        })
    sessions = []
    if code == 0:
        try:
            sessions = inspect_tmux_sessions()
        except (SessionCheckError, NameError) as error:
            errors.append("tmux 삭제 상태: " + str(error))
    return {"version": VERSION, "timestamp": time.time(), "gpus": gpus, "panes": panes, "sessions": sessions,
            "errors": errors, "tmuxAvailable": tmux_available, "tmuxHealthy": code == 0 or no_server,
            "gpuPIDMappingLimited": any(p["localPID"] is None for p in gpu_processes)}


if __name__ == "__main__":
    print(json.dumps(snapshot(), ensure_ascii=False, separators=(",", ":")))
