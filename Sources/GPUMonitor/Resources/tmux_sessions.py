"""Conservative tmux session inventory and explicitly requested deletion.

This source is sent over SSH stdin before the collector, never installed remotely.
Monitoring's relaxed worker classification must never authorize session deletion.
"""
import hashlib
import json
import os
import re
import subprocess


class SessionCheckError(Exception):
    pass


def tmux_command(arguments):
    try:
        result = subprocess.run(["tmux"] + arguments, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, timeout=4)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise SessionCheckError(str(error)[:300]) from error
    if result.returncode:
        message = result.stderr.strip()
        if ("no server running" in message or "no sessions" in message or
                ("error connecting to" in message and "No such file or directory" in message)):
            raise SessionCheckError("tmux 세션이 없습니다. 목록을 갱신하세요.")
        raise SessionCheckError(message[:300] or "tmux 조회 실패")
    return result.stdout


def strict_processes():
    result = {}
    try:
        entries = os.listdir("/proc")
    except OSError as error:
        raise SessionCheckError("프로세스 목록을 확인할 수 없습니다.") from error
    for entry in entries:
        if not entry.isdigit():
            continue
        try:
            with open("/proc/" + entry + "/stat") as file:
                stat = file.read()
            first, last = stat.index("("), stat.rindex(")")
            fields = stat[last + 2:].split()
            result[int(entry)] = dict(pid=int(entry), parent=int(fields[1]),
                                      name=stat[first + 1:last], state=fields[0],
                                      pgrp=int(fields[2]), tty=int(fields[4]),
                                      foreground=int(fields[5]), start=fields[19])
        except FileNotFoundError:
            continue  # Process exited during enumeration.
        except (OSError, ValueError, IndexError) as error:
            raise SessionCheckError("프로세스 정보를 모두 확인할 수 없어 삭제할 수 없습니다.") from error
    return result


def interactive_shell(pid):
    try:
        with open("/proc/%d/cmdline" % pid, "rb") as file:
            args = [a.decode("utf-8", "replace") for a in file.read().split(b"\0") if a]
        executable = os.path.basename(os.readlink("/proc/%d/exe" % pid))
    except OSError:
        return False
    if executable not in {"bash", "zsh", "sh", "dash", "fish"} or not args:
        return False
    # A shell running a script, -c, or an unknown option is not an idle shell.
    return all(a in {"--login", "--noprofile", "--norc"} or re.fullmatch(r"-[il]+", a)
               for a in args[1:])


def pane_blocker(pane, processes, shell_check=interactive_shell):
    pid = pane["pid"]
    root = processes.get(pid)
    live = {p: info for p, info in processes.items() if info["state"] not in {"Z", "X"}}
    descendants, pending = set(), [pid]
    while pending:
        parent = pending.pop()
        for child, info in live.items():
            if info["parent"] == parent and child != pid and child not in descendants:
                descendants.add(child)
                pending.append(child)
    if descendants:
        return "백그라운드를 포함한 실행 프로세스가 있습니다."
    if pane["pipe"]:
        return "pane의 로그 파이프가 실행 중입니다."
    # Also catch processes reparented away from the pane shell but on its TTY.
    try:
        tty = os.stat(pane["tty"]).st_rdev
    except FileNotFoundError:
        if not pane["dead"]:
            return "pane 터미널을 확인할 수 없습니다."
        tty = None
    except OSError:
        return "pane 터미널을 확인할 수 없습니다."
    if tty is not None and any(p != pid and info["tty"] != 0 and (info["tty"] & 0xffffffff) == tty
                               for p, info in live.items()):
        return "이 터미널을 사용하는 프로세스가 있습니다."
    if pane["dead"]:
        return "종료된 pane의 PID가 재사용되어 상태를 확인할 수 없습니다." if root else None
    if not root or root["state"] != "S" or not shell_check(pid):
        return "대기 중인 대화형 쉘인지 확인할 수 없습니다."
    if not root["tty"] or root["pgrp"] != root["foreground"]:
        return "포그라운드 작업을 확인해 주세요."
    return None


def inspect_tmux_sessions():
    fields = ["pid", "session_id", "session_created", "session_name", "session_attached",
              "window_id", "pane_id", "pane_pid", "pane_current_command", "pane_dead", "pane_tty", "pane_pipe"]
    output = tmux_command(["list-panes", "-a", "-F", "\t".join("#{%s}" % f for f in fields)])
    groups, memberships = {}, {}
    for line in output.splitlines():
        values = line.split("\t")
        if len(values) != len(fields):
            raise SessionCheckError("tmux 메타데이터를 해석할 수 없습니다.")
        p = dict(zip(fields, values))
        if not (re.fullmatch(r"\$\d+", p["session_id"]) and re.fullmatch(r"%\d+", p["pane_id"])):
            raise SessionCheckError("tmux ID를 확인할 수 없습니다.")
        try:
            pane = dict(id=p["pane_id"], window=p["window_id"], pid=int(p["pane_pid"]),
                        command=p["pane_current_command"], dead=bool(int(p["pane_dead"])),
                        tty=p["pane_tty"], pipe=bool(int(p["pane_pipe"])))
            item = groups.setdefault(p["session_id"], dict(id=p["session_id"], name=p["session_name"],
                                     created=int(p["session_created"]), serverPID=int(p["pid"]),
                                     attached=int(p["session_attached"]), panes=[]))
        except ValueError as error:
            raise SessionCheckError("tmux 메타데이터가 불완전합니다.") from error
        item["panes"].append(pane)
        memberships.setdefault(pane["id"], set()).add(item["id"])
    try:
        processes = strict_processes()
        with open("/proc/sys/kernel/random/boot_id") as file:
            boot_id = file.read().strip()
        process_error = None
    except (OSError, SessionCheckError) as error:
        processes, boot_id, process_error = {}, "", str(error)
    result = []
    for item in groups.values():
        reason = process_error
        if not reason and item["attached"]:
            reason = "연결된 tmux 클라이언트를 먼저 detach하세요."
        server = processes.get(item["serverPID"])
        if not reason and not server:
            reason = "tmux 서버의 프로세스를 확인할 수 없습니다."
        for pane in item["panes"]:
            pane["start"] = processes.get(pane["pid"], {}).get("start")
            if not reason and len(memberships[pane["id"]]) > 1:
                reason = "다른 세션과 공유하는 window가 있습니다."
            if not reason:
                reason = pane_blocker(pane, processes)
        item["panes"].sort(key=lambda pane: pane["id"])
        identity = dict(session=item, boot=boot_id, serverStart=server["start"] if server else None)
        token = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
        result.append(dict(id=item["id"], name=item["name"], paneIDs=[p["id"] for p in item["panes"]],
                           canDelete=not reason, reason=reason or "실행 작업 없음 · 삭제 가능", token=token,
                           serverPID=item["serverPID"], created=item["created"]))
    return result


def delete_empty_session(request, inspect=inspect_tmux_sessions, command=tmux_command):
    try:
        target, token = request["id"], request["token"]
        if not re.fullmatch(r"\$\d+", target) or not re.fullmatch(r"[0-9a-f]{64}", token):
            raise SessionCheckError("올바른 세션 ID와 확인 정보가 필요합니다.")
        # Re-read all panes and processes twice. Never trust cached UI eligibility.
        for _ in range(2):
            current = next((s for s in inspect() if s["id"] == target), None)
            if not current:
                raise SessionCheckError("세션이 이미 사라졌습니다. 목록을 갱신하세요.")
            if not current["canDelete"]:
                raise SessionCheckError(current["reason"])
            if current["token"] != token:
                raise SessionCheckError("세션 구성이 변경되었습니다. 갱신 후 다시 확인하세요.")
        # Check attachment and server/session identity again in tmux's command queue.
        condition = "#{&&:#{==:#{session_attached},0},#{&&:#{==:#{pid},%d},#{==:#{session_created},%d}}}" % (current["serverPID"], current["created"])
        result = command(["if-shell", "-F", "-t", target, condition,
                          "kill-session -t '" + target + "'", "display-message -p GPU_MONITOR_DELETE_BLOCKED"])
        if "GPU_MONITOR_DELETE_BLOCKED" in result:
            raise SessionCheckError("삭제 직전에 세션 상태가 변경되어 중단했습니다.")
        return dict(version=1, deleted=True, message="‘%s’ 세션을 삭제했습니다." % current["name"])
    except (SessionCheckError, KeyError, TypeError) as error:
        return dict(version=1, deleted=False, message=str(error))
