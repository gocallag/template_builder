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

        self.hostname = socket.gethostname()

        #
        # Prefer explicit job id, otherwise use container hostname.
        # Docker/Podman hostname is typically the container id.
        #
        self.job_id = os.getenv(
            "IMAGEBUILDER_JOB_ID",
            self.hostname
        )

        self.events_path = os.getenv(
            "IMAGEBUILDER_EVENTS_FILE",
            f"/tmp/imagebuilder-{self.job_id}.ndjson"
        )

        self.task_start_times = {}

        self._lock = threading.Lock()

        #
        # First event proves callback loaded.
        #
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

        with self._lock:

            os.makedirs(
                os.path.dirname(self.events_path),
                exist_ok=True
            )

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

        started = self.task_start_times.get(task_uuid)

        if started is None:
            return None

        return int(
            (time.time() - started) * 1000
        )

    def _safe_message(self, result):

        msg = (
            result._result.get("msg")
            or result._result.get("stderr")
            or result._result.get("stdout")
        )

        if msg is None:
            return None

        msg = str(msg)

        if len(msg) > 2000:
            msg = msg[:2000] + "...(truncated)"

        return msg

    #
    # PLAYBOOK
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

        processed = {}

        for host in stats.processed.keys():

            summary = stats.summarize(host)

            processed[host] = {
                "ok": summary.get("ok", 0),
                "changed": summary.get("changed", 0),
                "failed": summary.get("failures", 0),
                "unreachable": summary.get("unreachable", 0),
                "skipped": summary.get("skipped", 0)
            }

        self._emit({
            "type": "playbook_end",
            "stats": processed
        })

    #
    # TASKS
    #

    def v2_playbook_on_task_start(
        self,
        task,
        is_conditional
    ):

        self.task_start_times[task._uuid] = time.time()

        self._emit({
            "type": "task_start",
            "task": task.get_name(),
            "task_uuid": task._uuid,
            "action": task.action,
        })

    #
    # SUCCESS
    #

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

    #
    # FAILURE
    #

    def v2_runner_on_failed(
        self,
        result,
        ignore_errors=False
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
            "msg": self._safe_message(result),
        })

    #
    # UNREACHABLE
    #

    def v2_runner_on_unreachable(self, result):

        task = result._task

        self._emit({
            "type": "task_unreachable",
            "task": task.get_name(),
            "task_uuid": task._uuid,
            "host": result._host.get_name(),
            "duration_ms": self._duration_ms(
                task._uuid
            ),
            "msg": self._safe_message(result),
        })

    #
    # SKIPPED
    #
    # Keep for now. UI can ignore.
    #

    def v2_runner_on_skipped(self, result):

        task = result._task

        self._emit({
            "type": "task_skipped",
            "task": task.get_name(),
            "task_uuid": task._uuid,
            "host": result._host.get_name(),
        })