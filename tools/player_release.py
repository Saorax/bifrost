"""makes a release for GitHub, one product at a time: Bifrost or Official.

    python tools/player_release.py --product bifrost [--server HOST:PORT] [--release NAME] [--no-build] [--repo OWNER/NAME] [--publish]
    python tools/player_release.py --product official [--release NAME] [--repo OWNER/NAME] [--publish]

each product has its own version, ``YYYYMMDD-NN<commit>``: the day, that product's release number of the day and its
source's current commit (Bifrost: this workspace; Official: bh-client, or this workspace's while bh-client has none).
the repositories are in
``tools/release_repos.json`` (``--repo`` overrides); a release's tag is ``<product>-<version>``, so one repository
can hold both. writes ``build/player-release/<product>-<version>/``:

- bifrost: ``bifrost-<version>.zip`` (the engine kit, ``tools/player_kit.py``, never game code),
  ``bifrost-server-<version>.zip`` (the server at its pin, for the app's Server tab) and ``bifrost.json``.
- official: ``official-<version>.zip`` (bh-client's layer and its two DLLs, ``nc.py package``) and ``official.json``.

every manifest names the game files it is for (``tools/game_files.py``): the app refuses to install a product whose
release doesn't match the player's game. without ``--publish`` nothing is uploaded and ``gh release create`` is printed;
with it the GitHub release is created (the GitHub CLI signed in, or GH_TOKEN in a workflow). the app's own
releases are made by its repository (bifrost-app, ``tools/release_app.py``).
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import shutil
import subprocess
import sys
import tarfile
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tools import game_files, player_kit

OUT = ROOT / "build" / "player-release"
REPOS = ROOT / "tools" / "release_repos.json"
PRODUCTS = ("bifrost", "official")
NEW_CLIENT = Path("C:/Coding/bh-client")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def asset(path: Path) -> dict:
    return {"asset": path.name, "size": path.stat().st_size, "sha256": sha256(path)}


def pins() -> dict[str, str]:
    from tools import pins as source
    return source.pins()


def repos() -> dict[str, str]:
    return json.loads(REPOS.read_text(encoding="utf-8")) if REPOS.exists() else {}


def head(repo: Path) -> str | None:
    out = subprocess.run(["git", "-C", str(repo), "rev-parse", "--short=8", "HEAD"], capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else None


def source_dirs(product: str) -> list[Path]:
    return {"bifrost": [Path(pins()["repo"]), ROOT], "official": [NEW_CLIENT, ROOT]}[product]


def contents_hash(source: Path) -> str:
    files = subprocess.run(["git", "-C", str(source), "ls-files", "-z"], capture_output=True)
    if files.returncode != 0:
        return "none"
    h = hashlib.sha256()
    for name in sorted(n for n in files.stdout.decode("utf-8", "replace").split("\0") if n):
        path = source / name
        if path.is_file():
            h.update(name.encode() + b"\0" + hashlib.sha256(path.read_bytes()).digest())
    return h.hexdigest()[:12]


def sources_key(product: str, server: str | None) -> str:
    parts = [contents_hash(source) for source in source_dirs(product)]
    if product == "bifrost":
        parts.append(server or player_kit.default_server())
    return "+".join(parts)


def latest_sources(repo: str, product: str) -> tuple[str | None, str | None]:
    out = subprocess.run(["gh", "release", "list", "--repo", repo, "--limit", "50", "--json", "tagName,createdAt"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        return None, None
    tags = sorted((r for r in json.loads(out.stdout or "[]") if r["tagName"].startswith(f"{product}-")),
                  key=lambda r: r["createdAt"], reverse=True)
    if not tags:
        return None, None
    tag = tags[0]["tagName"]
    view = subprocess.run(["gh", "release", "view", tag, "--repo", repo, "--json", "body"], capture_output=True, text=True)
    if view.returncode != 0:
        return tag, None
    m = re.search(r"^Sources: (\S+)$", json.loads(view.stdout).get("body") or "", re.M)
    return tag, m.group(1) if m else None


def next_release(repo: str | None, product: str, commit: str | None) -> str:
    day = time.strftime("%Y%m%d")
    tags: list[str] = []
    if repo:
        out = subprocess.run(["gh", "release", "list", "--repo", repo, "--limit", "200", "--json", "tagName"],
                             capture_output=True, text=True)
        if out.returncode == 0:
            tags = [r["tagName"] for r in json.loads(out.stdout or "[]")]
        else:
            print(f"player_release: gh couldn't list {repo}'s releases ({out.stderr.strip()[:200]}); counting the local "
                  "ones", file=sys.stderr)
    if OUT.exists():
        tags += [p.name for p in OUT.iterdir() if p.is_dir()]
    numbers = [int(m.group(1)) for t in tags if (m := re.match(rf"{product}-{day}-(\d\d)", t))]
    return f"{day}-{max(numbers, default=0) + 1:02d}{commit or ''}"


def pack_dir(folder: Path, out: Path) -> Path:
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for path in sorted(folder.rglob("*")):
            if path.is_file():
                z.write(path, path.relative_to(folder).as_posix())
    return out


def pack_kit(kit: Path, folder: Path, release: str) -> Path:
    problems = player_kit.audit(kit)
    if problems:
        raise player_kit.KitError("the kit holds game files:\n" + "\n".join(problems[:20]))
    return pack_dir(kit, folder / f"bifrost-{release}.zip")


def pack_server(folder: Path, release: str) -> Path:
    p = pins()
    server, commit = Path(p["server-repo"]), p["server-commit"]
    data = subprocess.run(["git", "-C", str(server), "archive", "--format=tar", commit], capture_output=True)
    if data.returncode != 0:
        raise player_kit.KitError(f"git archive {server} {commit}: {data.stderr.decode(errors='replace')}")
    wrapper = subprocess.run(["git", "-C", p["repo"], "show", f"{p['commit']}:tools/studio_run.py"], capture_output=True)
    if wrapper.returncode != 0:
        raise player_kit.KitError(f"no tools/studio_run.py at AIR {p['commit']}")
    out = folder / f"bifrost-server-{release}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z, tarfile.open(fileobj=io.BytesIO(data.stdout)) as tar:
        for member in tar.getmembers():
            if member.isfile():
                z.writestr(member.name, tar.extractfile(member).read())
        z.writestr("studio_run.py", wrapper.stdout)
        z.writestr("SERVER.txt", f"bifrost-server {commit}\n")
    return out


def fresh(folder: Path) -> Path:
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True)
    return folder


def release_bifrost(a: argparse.Namespace, repo: str | None) -> tuple[str, list[Path], dict]:
    name = a.release or next_release(repo, "bifrost", head(ROOT))
    if not a.no_build:
        player_kit.build(player_kit.DEFAULT_OUT, player_kit.DEFAULT_ENGINE, a.server, name)
    info = json.loads((player_kit.DEFAULT_OUT / "kit.json").read_text(encoding="utf-8"))
    name = info["release"]
    folder = fresh(OUT / f"bifrost-{name}")
    kit = pack_kit(player_kit.DEFAULT_OUT, folder, name)
    server = pack_server(folder, name)
    symbols = json.loads((player_kit.DEFAULT_OUT / "client" / "symbols" / f"{info['game']}.json").read_text(encoding="utf-8"))
    manifest = {"product": "bifrost", "release": name, "game": info["game"], "swf_sha256": symbols["input_sha256"],
                "game_files": info.get("game_files") or game_files.fingerprint(ROOT / "versions" / info["game"]),
                "game_file_list": info.get("game_file_list") or game_files.listing(ROOT / "versions" / info["game"]),
                "port_commit": info.get("port_commit"), "server": info["server"], **asset(kit),
                "server_package": asset(server), "built": info["built"]}
    return name, [kit, server], manifest


def release_official(a: argparse.Namespace, repo: str | None) -> tuple[str, list[Path], dict]:
    name = a.release or next_release(repo, "official", head(NEW_CLIENT) or head(ROOT))
    folder = fresh(OUT / f"official-{name}")
    package = folder / "package"
    cmd = [sys.executable, str(NEW_CLIENT / "tools" / "nc.py"), "package", "--out", str(package), "--version", name]
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        raise player_kit.KitError(f"nc.py package failed:\n{out.stdout[-2000:]}{out.stderr[-2000:]}")
    info = json.loads((package / "official.json").read_text(encoding="utf-8"))
    zipped = pack_dir(package, folder / f"official-{name}.zip")
    shutil.rmtree(package)
    manifest = {"product": "official", "release": name, "game": info["game"], "game_files": info["game_files"],
                "game_file_list": info.get("game_file_list") or game_files.listing(ROOT / "versions" / info["game"]),
                "port_commit": info["port_commit"], **asset(zipped), "built": info["built"]}
    return name, [zipped], manifest


def release_notes(product: str, title: str, key: str) -> str:
    sources = {"bifrost": [Path(pins()["repo"]), ROOT], "official": [NEW_CLIENT]}[product]
    lines = []
    for source in sources:
        out = subprocess.run(["git", "-C", str(source), "log", "-1", "--format=%s"], capture_output=True, text=True)
        if out.returncode == 0 and out.stdout.strip():
            lines.append(f"- {out.stdout.strip()}")
    return title + ("\n\n" + "\n".join(lines) if lines else "") + f"\n\nSources: {key}"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--product", choices=PRODUCTS, default="bifrost")
    p.add_argument("--server", default=None, help="bifrost: the server the engine plays on (default: bifrost.saorax.com:7910)")
    p.add_argument("--release", default=None, help="the version (default: YYYYMMDD-NN<commit>)")
    p.add_argument("--no-build", action="store_true", help="bifrost: pack the kit already in build/player-kit")
    p.add_argument("--repo", default=None, help="OWNER/NAME (default: tools/release_repos.json)")
    p.add_argument("--publish", action="store_true", help="create the GitHub release")
    p.add_argument("--force", action="store_true", help="publish even when the sources match the latest release's")
    a = p.parse_args(argv)
    repo = a.repo or repos().get(a.product)
    key = sources_key(a.product, a.server)
    if a.publish and repo and not a.force:
        tag, last = latest_sources(repo, a.product)
        if last == key:
            print(f"player_release: the sources match {tag} ({key}); nothing new to release (--force to publish anyway)")
            return 0
    started = time.monotonic()
    try:
        name, files, manifest = {"bifrost": release_bifrost, "official": release_official}[a.product](a, repo)
    except player_kit.KitError as e:
        print(f"player_release: {e}", file=sys.stderr)
        return 1
    folder = files[0].parent
    manifest_path = folder / f"{a.product}.json"
    manifest_path.write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
    files.append(manifest_path)
    print(f"{a.product} {name} in {time.monotonic() - started:.0f} s -> {folder}")
    for f in files:
        print(f"  {f.name:40} {f.stat().st_size / 2**20:8.1f} MB")
    if repo:
        quoted = " ".join(f'"{f}"' for f in files)
        title = {"bifrost": "Bifrost", "official": "Official"}[a.product]
        print(f'\ngh release create {a.product}-{name} {quoted} --repo {repo} --title "{title} {name}" '
              f'--notes "{title} {name}"')
        if a.publish:
            out = subprocess.run(["gh", "release", "create", f"{a.product}-{name}", *map(str, files), "--repo", repo,
                                  "--title", f"{title} {name}", "--notes", release_notes(a.product, f"{title} {name}", key)])
            return out.returncode
    elif a.publish:
        print("player_release: no repository to publish to (tools/release_repos.json or --repo)", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
