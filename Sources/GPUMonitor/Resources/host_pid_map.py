"""Read only NVIDIA host PID -> selected Docker namespace PID translation.

No namespace entry, process signals, installs, or persistent files. Unsupported
host permissions/tooling return an empty map and UI leaves GPUs unassigned.
"""
import json
import subprocess
import sys


def output(args):
    return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL, timeout=4)


def ns_pids(pid):
    with open('/proc/%s/status' % pid) as f:
        for line in f:
            if line.startswith('NSpid:'):
                return [int(value) for value in line.split()[1:]]
    return []


def start_time(pid):
    with open('/proc/%s/stat' % pid) as f:
        stat = f.read()
    return stat[stat.rindex(')') + 2:].split()[19]


def collect(container):
    try:
        init = int(output(['docker', 'inspect', '--format', '{{.State.Pid}}', container]).strip())
        depth = len(ns_pids(init)) - 1
        if depth < 0:
            return {}
        members = {int(p) for p in output(['docker', 'top', container, '-eo', 'pid']).splitlines()[1:] if p.strip().isdigit()}
        gpu_pids = {int(p.strip()) for p in output(['nvidia-smi', '--query-compute-apps=pid', '--format=csv,noheader,nounits']).splitlines() if p.strip().isdigit()}
        result = {}
        for pid in members & gpu_pids:
            try:
                before = start_time(pid)
                values = ns_pids(pid)
                after = start_time(pid)
                if len(values) > depth and before == after:
                    result[str(pid)] = {'pid': values[depth], 'start': before}
            except (OSError, ValueError, IndexError):
                continue
        return result
    except (OSError, ValueError, subprocess.SubprocessError):
        return {}


if __name__ == '__main__':
    print(json.dumps(collect(sys.argv[1]), separators=(',', ':')))
