import importlib.util
import json
import os
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch


CALLBACK_PATH = (
    Path(__file__).resolve().parents[1]
    / "plugins"
    / "callback"
    / "imagebuilder_events.py"
)


class Task:
    def __init__(self, action, task_uuid="task-1", name="Task"):
        self.action = action
        self._uuid = task_uuid
        self.name = name

    def get_name(self):
        return self.name


class Host:
    def get_name(self):
        return "localhost"


class Result:
    def __init__(self, task, result=None):
        self._task = task
        self._host = Host()
        self._result = result or {}


class CallbackModuleTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.event_path = os.path.join(self.temp_dir.name, "events.ndjson")

        callback_base = type("CallbackBase", (), {"__init__": lambda self: None})
        ansible = types.ModuleType("ansible")
        plugins = types.ModuleType("ansible.plugins")
        callback_module = types.ModuleType("ansible.plugins.callback")
        callback_module.CallbackBase = callback_base

        modules = {
            "ansible": ansible,
            "ansible.plugins": plugins,
            "ansible.plugins.callback": callback_module,
        }

        with patch.dict(sys.modules, modules), patch.dict(
            os.environ, {"IMAGEBUILDER_EVENTS_FILE": self.event_path}
        ):
            spec = importlib.util.spec_from_file_location(
                "imagebuilder_events_test_module", CALLBACK_PATH
            )
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            self.callback = module.CallbackModule()

    def tearDown(self):
        self.temp_dir.cleanup()

    def events(self):
        with open(self.event_path, encoding="utf-8") as event_file:
            return [json.loads(line) for line in event_file]

    def test_hides_successful_role_wrapper_but_keeps_role_tasks(self):
        wrapper = Task("ansible.builtin.include_role", name="Include role")
        child = Task("ansible.builtin.debug", task_uuid="task-2", name="Child task")

        self.callback.v2_playbook_on_task_start(wrapper, False)
        self.callback.v2_runner_on_ok(Result(wrapper))
        self.callback.v2_playbook_on_task_start(child, False)
        self.callback.v2_runner_on_ok(Result(child))

        events = self.events()
        self.assertEqual(
            [event["type"] for event in events],
            ["callback_start", "task_start", "task_ok"],
        )
        self.assertEqual(events[-2]["task"], "Child task")

    def test_hides_import_role_wrapper(self):
        wrapper = Task("ansible.builtin.import_role", name="Import role")

        self.callback.v2_playbook_on_task_start(wrapper, False)
        self.callback.v2_runner_on_ok(Result(wrapper))

        self.assertEqual(
            [event["type"] for event in self.events()],
            ["callback_start"],
        )

    def test_keeps_role_wrapper_failure_visible(self):
        wrapper = Task("ansible.builtin.include_role", name="Include role")

        self.callback.v2_playbook_on_task_start(wrapper, False)
        self.callback.v2_runner_on_failed(
            Result(wrapper, {"msg": "Role could not be loaded"})
        )

        events = self.events()
        self.assertEqual(
            [event["type"] for event in events],
            ["callback_start", "task_start", "task_failed"],
        )
        self.assertEqual(events[-1]["msg"], "Role could not be loaded")


if __name__ == "__main__":
    unittest.main()
