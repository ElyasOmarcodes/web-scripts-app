import time

from webscripts.models import Script, Step, Target
from webscripts.storage import Storage, StorageError

import pytest


def make_script() -> Script:
    return Script(
        name="فیسبوک تم",
        start_url="https://facebook.com",
        steps=[
            Step(action="goto", url="https://facebook.com"),
            Step(
                action="click",
                targets=[Target(type="css", value='[aria-label="Settings"]', kind="aria")],
                label="Settings",
            ),
        ],
    )


def test_save_and_get_roundtrip(tmp_path):
    storage = Storage(tmp_path)
    saved = storage.save(make_script())

    loaded = storage.get(saved.id)
    assert loaded is not None
    assert loaded.name == "فیسبوک تم"
    assert len(loaded.steps) == 2
    assert loaded.steps[1].targets[0].value == '[aria-label="Settings"]'


def test_list_is_newest_first(tmp_path):
    storage = Storage(tmp_path)
    storage.save(Script(name="یو"))
    time.sleep(0.005)
    storage.save(Script(name="دوه"))

    names = [s.name for s in storage.list()]
    assert names == ["دوه", "یو"]


def test_delete(tmp_path):
    storage = Storage(tmp_path)
    saved = storage.save(make_script())
    assert storage.delete(saved.id) is True
    assert storage.get(saved.id) is None
    assert storage.delete(saved.id) is False


def test_rejects_path_traversal(tmp_path):
    storage = Storage(tmp_path)
    with pytest.raises(StorageError):
        storage.get("../../etc/passwd")


def test_corrupt_file_is_skipped(tmp_path):
    storage = Storage(tmp_path)
    storage.save(make_script())
    (tmp_path / "broken.json").write_text("{not json", "utf-8")
    assert len(storage.list()) == 1


def test_import_assigns_new_id(tmp_path):
    storage = Storage(tmp_path / "store")
    saved = storage.save(make_script())
    exported = storage.export(saved.id, tmp_path / "out.json")

    imported = storage.import_file(exported)
    assert imported.id != saved.id
    assert len(storage.list()) == 2
