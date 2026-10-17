# plugins/callback/imagebuilder_events.py

from __future__ import annotations

import json
import os
import socket
import threading
import time
from datetime import datetime, timezone

from ansible.plugins.callback import CallbackBase


class CallbackModule(CallbackBase):

    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "notification"
    CALLBACK_NAME = "imagebuilder_events"
    CALLBACK_NEEDS_ENABLED = True

    def __init__(self):
        super().__init__()

        #
        # In Docker/Podman the hostname is normally the
        # container id (or short container id).
        #
        self.hostname = socket.gethostname()

        #
        # Allow explicit override but default to hostname.
        #
        self.job_id = os.getenv(
            "IMAGEBUILDER_JOB_ID",
            self.hostname
        )

        #
        # Mounted by host:
        #
        #   -v ${BUILD_DIR}/jobs:/jobs
        #
        self.events_path = os.getenv(
            "IMAGEBUILDER_EVENTS_FILE",
            f"/jobs/{self.job_id}.ndjson"
        )

        self.task_start_times = {}

        #
        # Protect writes if Ansible forks.
        #
        self._lock = threading.Lock()

        self._emit({
            "type": "callback_start",
            "hostname": self.hostname,
            "pid": os.getpid(),
            "events_file": self.events_path,
        })

    def _emit(self, event):

        event.setdefault(
            "timestamp",
            datetime.now(timezone.utc).isoformat()
        )

        event.setdefault(
            "job_id",
            self.job_id
        )

        directory = os.path.dirname(self.events_path)

        if directory:
            os.makedirs(
                directory,
                exist_ok=True
            )

        with self._lock:
            with open(
                self.events_path,
                "a",
                encoding="utf-8"
            ) as f:

                json.dump(
                    event,
                    f,
                    separators=(",", ":")
                )

                f.write("\n")
                f.flush()

    def _duration_ms(self, task_uuid):

        started = self.task_start_times.get(
            task_uuid
        )

        if started is None:
            return None

        return int(
            (time.time() - started) * 1000
        )

    @staticmethod
    def _truncate(value, max_length=4000):

        if value is None:
            return None

        value = str(value)

        if len(value) <= max_length:
            return value

        return (
            value[:max_length] +
            "...(truncated)"
        )

    def _message(self, result):

        output = (
            result._result.get("msg")
            or result._result.get("stderr")
            or result._result.get("stdout")
        )

        return self._truncate(output)

    #
    # Playbook lifecycle
    #

    def v2_playbook_on_start(self, playbook):

        self._emit({
            "type": "playbook_start",
            "playbook": getattr(
                playbook,
                "_file_name",
                None
            )
        })

    def v2_playbook_on_stats(self, stats):

        summary = {}

        for host in stats.processed.keys():

            host_summary = stats.summarize(host)

            summary[host] = {
                "ok": host_summary.get("ok", 0),
                "changed": host_summary.get("changed", 0),
                "failed": host_summary.get("failures", 0),
                "unreachable": host_summary.get("unreachable", 0),
                "skipped": host_summary.get("skipped", 0),
            }

        self._emit({
            "type": "playbook_end",
            "stats": summary,
        })

    #
    # Task lifecycle
    #

    def v2_playbook_on_task_start(
        self,
        task,
        is_conditional,
    ):

        self.task_start_times[
            task._uuid
        ] = time.time()

        self._emit({
            "type": "task_start",
            "task": task.get_name(),
            "task_uuid": task._uuid,
            "action": task.action,
        })

    def v2_runner_on_ok(self, result):

        task = result._task

        self._emit({
            "type": "task_ok",
            "task": task.get_name(),
            "task_uuid": task._uuid,
            "host": result._host.get_name(),
            "changed": result._result.get(
                "changed",
                False
            ),
            "duration_ms": self._duration_ms(
                task._uuid
            ),
        })

    def v2_runner_on_failed(
        self,
        result,
        ignore_errors=False,
    ):

        task = result._task

        self._emit({
            "type": "task_failed",
            "task": task.get_name(),
            "task_uuid": task._uuid,
            "host": result._host.get_name(),
            "ignored": ignore_errors,
            "duration_ms": self._duration_ms(
                task._uuid
            ),
            "msg": self._message(result),
        })

    def v2_runner_on_unreachable(
        self,
        result,
    ):

        task = result._task

        self._emit({
            "type": "task_unreachable",
            "task": task.get_name(),
            "task_uuid": task._uuid,
            "host": result._host.get_name(),
            "duration_ms": self._duration_ms(
                task._uuid
            ),
            "msg": self._message(result),
        })

    #
    # Optional
    # Keep initially so you can see
    # branching behaviour.
    #

    def v2_runner_on_skipped(self, result):

        task = result._task

        self._emit({
            "type": "task_skipped",
            "task": task.get_name(),
            "task_uuid": task._uuid,
            "host": result._host.get_name(),
            "duration_ms": self._duration_ms(
                task._uuid
            ),
        })