import hashlib
import json
import yaml
import re

from datetime import datetime
from pathlib import Path


def calculate_sha1(file_path):
    sha1 = hashlib.sha1()
    with open(file_path, "rb") as f:
        while True:
            data = f.read(65536)
            if not data:
                break
            sha1.update(data)
    return sha1.hexdigest()


def get_version_from_file(file_path: Path):
    with open(file_path, "r") as f:
        for line in f:
            if m := re.match("^(?:export )?script_version += +(.*)", line):
                return m.group(1).strip().strip("\"'")
    return None


def get_file_modified_date(file_path: Path):
    return datetime.fromtimestamp(file_path.stat().st_mtime)


def set_general(info):
    exclude = {"repository"}

    if base_url := info.get("baseUrl"):
        info["baseUrl"] = base_url
    elif repository := info.get("repository"):
        info["baseUrl"] = f"https://github.com/{repository}"
    else:
        raise ValueError("Cannot set baseUrl")

    if file_base_url := info.get("baseUrl"):
        info["fileBaseUrl"] = file_base_url
    elif repository := info.get("repository"):
        info["fileBaseUrl"] = (
            f"https://raw.githubusercontent.com/{repository}/@{{channel}}"
        )
    else:
        raise ValueError("Cannot set fileBaseUrl")

    info.setdefault("url", "@{baseUrl}")
    info.setdefault("description", info["name"])

    return {k: v for k, v in info.items() if k not in exclude}


def read_from_yaml(file_path: Path) -> dict:
    res = {}

    with open(file_path, "r") as f:
        dic = yaml.safe_load(f)

    for key, value in dic.items():
        if key == "general":
            res |= set_general(value)
        else:
            res[key] = value

    return res


def set_channels(root_dir, macro_name, macro_info):
    has_default = False
    for channel_info in macro_info["channels"].values():
        has_default |= channel_info.get("default", False)
        release_date = None
        version = None

        channel_info.setdefault("files", [{"name": ".moon"}])

        for file_info in channel_info["files"]:
            file_info.setdefault("url", "@{fileBaseUrl}/@{fileName}")

            # TODO: extract requiredModules from files

            if "sha1" not in file_info:
                filename = file_info["name"]
                if filename.startswith("."):
                    filename = macro_name + filename
                file_path = root_dir / "macros" / filename
                file_info["sha1"] = calculate_sha1(file_path)

                if not version:
                    version = get_version_from_file(file_path)

                if not release_date:
                    release_date = get_file_modified_date(file_path)
                else:
                    release_date = max(
                        release_date,
                        get_file_modified_date(file_path),
                    )

        if "version" not in channel_info:
            if not version:
                raise ValueError(
                    f"Version not found for {macro_name} in {channel_info}"
                )
            channel_info["version"] = version

        if "released" not in channel_info:
            channel_info["released"] = release_date.strftime("%Y-%m-%d")

    if not has_default:
        for channel_info in macro_info["channels"].values():
            channel_info["default"] = True
            break


def set_macro_base(macro_name, macro_info):
    if "name" not in macro_info:
        name = macro_name.split(".", 1)[-1].replace("-", " ")
        name = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", name)
        macro_info["name"] = name


def set_macros(root_dir, info):
    for macro_name, macro_info in info["macros"].items():
        if "author" not in macro_info:
            macro_info["author"] = info["maintainer"]

        if "url" not in macro_info:
            macro_info["url"] = "@{baseUrl}#@{scriptName}"

        if "fileBaseUrl" not in macro_info:
            macro_info["fileBaseUrl"] = "@{fileBaseUrl}/macros/@{namespace}"

        if "channels" not in macro_info:
            macro_info["channels"] = {"main": {}}

        set_macro_base(macro_name, macro_info)
        set_channels(root_dir, macro_name, macro_info)


def set_modules(root_dir, info):
    pass


def main():
    root_dir = Path(__file__).parent.parent.parent

    info = read_from_yaml(root_dir / "FeedInfo.yaml")

    if "macros" in info:
        set_macros(root_dir, info)

    if "modules" in info:
        set_modules(root_dir, info)

    with open(root_dir / "DependencyControl.json", "w") as f:
        json.dump(info, f, indent=4)


if __name__ == "__main__":
    main()
