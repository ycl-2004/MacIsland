import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


def run_swift_regression(*sources):
    """Compiles the given app sources with a regression `main` and runs it."""
    with tempfile.TemporaryDirectory() as temporary_directory:
        temporary_path = pathlib.Path(temporary_directory)
        executable = temporary_path / "regression"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(temporary_path / "module-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(temporary_path / "module-cache")
        subprocess.run(
            ["swiftc", *(str(ROOT / source) for source in sources), "-o", str(executable)],
            check=True,
            cwd=ROOT,
            env=environment,
        )
        subprocess.run([str(executable)], check=True, cwd=ROOT)


class TimerLifecycleTests(unittest.TestCase):
    def test_replacement_session_invalidates_delayed_cleanup_token(self):
        run_swift_regression(
            "DynamicIsland/managers/TimerLifecycle.swift",
            "tests/TimerLifecycleRegression.swift",
        )

    def test_countdown_is_measured_from_its_end_date(self):
        run_swift_regression(
            "DynamicIsland/managers/TimerCountdown.swift",
            "tests/TimerCountdownRegression.swift",
        )

    def test_chosen_sound_is_kept_as_atolls_own_copy(self):
        run_swift_regression(
            "DynamicIsland/managers/TimerSoundStore.swift",
            "tests/TimerSoundStoreRegression.swift",
        )


if __name__ == "__main__":
    unittest.main()
