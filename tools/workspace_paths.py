from pathlib import Path


def checked_output(path: Path, allowed: Path) -> Path:
    path, allowed = path.absolute(), allowed.absolute()
    if not path.is_relative_to(allowed) or not path.resolve().is_relative_to(allowed):
        raise ValueError(f"Output must remain under {allowed}: {path}")
    for component in (path, *path.parents):
        if component.is_symlink():
            raise ValueError(f"Output path contains a link: {component}")
    return path
