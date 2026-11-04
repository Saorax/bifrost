"""compare the native build's vector drawing with AIR's, symbol by symbol.

    python tools/port_pixcompare.py run --native C:/Coding/BRAWLHALLA PROJECTS/bh-new-engine/workspace/build/port-hl/x/game.hl \
        --flash C:/Coding/BRAWLHALLA PROJECTS/bh-new-engine/workspace/build/port-flash-x.swf --out build/port-perf/pix --modes subpixel,fast
    python tools/port_pixcompare.py compare build/port-perf/pix/pix-air.txt build/port-perf/pix/pix-subpixel.txt

``run`` boots the native TEST build to the main menu, writes ``pixnames N`` (up to N sprite symbols of every SWF
loaded by then, evenly spread), and for each Cairo antialiasing mode (``BH_PORT_CAIRO_AA``; ``subpixel`` is
OpenFL's) draws them with the driver's ``pixdump`` (``drawWithQuality`` HIGH, as the art baker draws). then it
boots the Flash TEST build in AIR with the same names and draws them there. ``compare`` reads two dumps and reports,
over the symbols both drew at the same size, the mean absolute channel difference (premultiplied by alpha, 0-255),
the share of pixels off by more than 8 and by more than 32 in any channel, and the worst symbols. the AIR dump is
the reference: a native mode is acceptable when it is no further from AIR than OpenFL's own ``subpixel``.
"""

from __future__ import annotations

import argparse
import base64
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AIR_SMOKE = Path(os.environ.get("USERPROFILE", "")) / "Documents" / "Bifrost" / "bh-port-smoke"


def load(path: Path) -> dict[str, tuple[int, int, bytes]]:
    out = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split(" ")
        if len(parts) == 4 and parts[1].isdigit():
            out[parts[0]] = (int(parts[1]), int(parts[2]), base64.b64decode(parts[3]))
    return out


def premultiplied(data: bytes) -> list[int]:
    out = []
    for i in range(0, len(data), 4):
        a = data[i]
        out += (a, data[i + 1] * a // 255, data[i + 2] * a // 255, data[i + 3] * a // 255)
    return out


def diff(a: bytes, b: bytes) -> tuple[float, int, int, int]:
    pa, pb = premultiplied(a), premultiplied(b)
    total = over8 = over32 = 0
    for i in range(0, len(pa), 4):
        worst = 0
        for k in range(4):
            d = abs(pa[i + k] - pb[i + k])
            total += d
            if d > worst:
                worst = d
        over8 += worst > 8
        over32 += worst > 32
    return total, over8, over32, len(pa) // 4


def compare(ref_path: Path, other_path: Path, worst: int = 8,
            only: set[str] | None = None) -> tuple[list[str], dict[str, float]]:
    ref, other = load(ref_path), load(other_path)
    if only is not None:
        ref = {name: value for name, value in ref.items() if name in only}
    common = [name for name in ref if name in other and ref[name][:2] == other[name][:2]]
    size_mismatch = [name for name in ref if name in other and ref[name][:2] != other[name][:2]]
    total = over8 = over32 = pixels = 0
    per = []
    for name in common:
        t, o8, o32, n = diff(ref[name][2], other[name][2])
        total += t
        over8 += o8
        over32 += o32
        pixels += n
        per.append((t / max(1, n * 4), name))
    per.sort(reverse=True)
    stats = {"symbols": len(common), "pixels": pixels, "mean": total / max(1, pixels * 4),
             "over8": 100 * over8 / max(1, pixels), "over32": 100 * over32 / max(1, pixels)}
    lines = [f"{other_path.name} vs {ref_path.name}: {len(common)} symbols ({pixels:,} pixels), "
             f"mean abs difference {stats['mean']:.3f}, pixels off by >8 {stats['over8']:.2f}%, "
             f"by >32 {stats['over32']:.2f}%; {len(size_mismatch)} drawn at another size"]
    lines += [f"  {mean:.2f} {name}" for mean, name in per[:worst]]
    lines += [f"  another size: {name} {ref[name][0]}x{ref[name][1]} vs {other[name][0]}x{other[name][1]}"
              for name in size_mismatch]
    return lines, stats


def show(ref_path: Path, other_path: Path, names: list[str], out: Path, zoom: int = 6, worst: int = 0) -> list[Path]:
    from PIL import Image

    ref, other = load(ref_path), load(other_path)
    if worst:
        names = names + compare_names(ref, other)[:worst]
    out.mkdir(parents=True, exist_ok=True)
    written = []
    for name in names:
        if name not in ref or name not in other or ref[name][:2] != other[name][:2]:
            print(f"{name}: not in both dumps at one size")
            continue
        w, h = ref[name][:2]
        sheet = Image.new("RGB", (w * 3 + 4, h), (128, 128, 128))
        pa, pb = premultiplied(ref[name][2]), premultiplied(other[name][2])
        for column, values in ((0, pa), (1, pb)):
            image = Image.new("RGB", (w, h))
            image.putdata([tuple(values[i + 1 + k] + (255 - values[i]) * 128 // 255 for k in range(3))
                           for i in range(0, len(values), 4)])
            sheet.paste(image, (column * (w + 2), 0))
        delta = Image.new("RGB", (w, h))
        delta.putdata([(min(255, 4 * abs(pa[i] - pb[i])),) + (min(255, 4 * max(abs(pa[i + k] - pb[i + k])
                       for k in (1, 2, 3))),) * 2 for i in range(0, len(pa), 4)])
        sheet.paste(delta, (2 * (w + 2), 0))
        target = out / f"{name}.png"
        sheet.resize((sheet.width * zoom, sheet.height * zoom), Image.NEAREST).save(target)
        written.append(target)
    return written


def png_compare(ref_path: Path, others: list[Path], shift: int = 2) -> list[str]:
    from PIL import Image

    ref = Image.open(ref_path).convert("RGBA")
    pr = ref.load()

    def partial(image) -> int:
        return sum(1 for y in range(image.height) for x in range(image.width) if 0 < image.getpixel((x, y))[3] < 255)

    lines = [f"{ref_path.name}: {ref.width}x{ref.height}, {partial(ref):,} partly transparent pixels (reference)"]
    for path in others:
        other = Image.open(path).convert("RGBA")
        po = other.load()
        best = None
        for dx in range(-shift, shift + 1):
            for dy in range(-shift, shift + 1):
                total = over = count = 0
                for y in range(shift + 1, ref.height - shift - 1):
                    for x in range(shift + 1, ref.width - shift - 1):
                        if not (0 <= x + dx < other.width and 0 <= y + dy < other.height):
                            continue
                        p, q = pr[x, y], po[x + dx, y + dy]
                        d = max(abs(p[3] - q[3]), *(abs(p[k] * p[3] // 255 - q[k] * q[3] // 255) for k in range(3)))
                        total += d
                        over += d > 32
                        count += 1
                score = (total / max(1, count), 100 * over / max(1, count), dx, dy)
                if best is None or score < best:
                    best = score
        lines.append(f"{path.name}: {other.width}x{other.height}, {partial(other):,} partly transparent pixels; "
                     f"best offset {best[2]},{best[3]}: mean largest difference {best[0]:.2f}, off by >32 {best[1]:.2f}%")
    return lines


def compare_names(ref: dict, other: dict) -> list[str]:
    per = []
    for name in ref:
        if name in other and ref[name][:2] == other[name][:2]:
            t, _, _, n = diff(ref[name][2], other[name][2])
            per.append((t / max(1, n * 4), name))
    return [name for _, name in sorted(per, reverse=True)]


def run_native(hl: str, out: Path, modes: list[str], per_library: int, total: int, scale: float) -> None:
    smoke = out / "hl-smoke"
    smoke.mkdir(parents=True, exist_ok=True)
    for index, mode in enumerate(modes):
        env = dict(os.environ)
        env["BH_PORT_CAIRO_AA"] = mode
        commands = ["waitmenu", "wait 120"] + ([f"pixnames {per_library} {total}"] if index == 0 else [])
        commands += [f"pixdump {mode} {scale:g}", "quit"]
        subprocess.run([sys.executable, str(ROOT / "tools" / "port_hl_run.py"), "--hl", hl, "--seconds", "400",
                        "--smoke-dir", str(smoke), "--commands", *commands], cwd=ROOT, env=env, check=False)
        shutil.copy(smoke / f"pix-{mode}.txt", out / f"pix-{mode}.txt")
    shutil.copy(smoke / "pixnames.txt", out / "pixnames.txt")


RENDER_NAME = "ADA_Default_ClassicColors.png"
NATIVE_RENDERS = ROOT / "build" / "port-hl" / "storage" / "BhPort" / "User" / "BrawlhallaRenders"
AIR_RENDERS = (Path(os.environ.get("APPDATA", "")) / "BrawlhallaAir" / "Local Store" / "BhPort" / "User"
               / "BrawlhallaRenders")
RENDER_COMMANDS = ["waitmenu", "display hub", "wait 30", "display imagetool", "wait 60", "display imagerender",
                   "wait 150", "stats", "quit"]


def render(out: Path, native: str | None, flash: str | None, smoke: Path | None = None) -> list[Path]:
    out.mkdir(parents=True, exist_ok=True)
    made = []
    for build, folder, target in ((native, NATIVE_RENDERS, "native.png"), (flash, AIR_RENDERS, "air.png")):
        if not build:
            continue
        (folder / RENDER_NAME).unlink(missing_ok=True)
        if build is native:
            tool = [str(ROOT / "tools" / "port_hl_run.py"), "--hl", build, "--seconds", "200"]
            if smoke is not None:
                tool += ["--smoke-dir", str(smoke)]
        else:
            tool = [str(ROOT / "data" / "tools" / "port_boot_check.py"), build, "--direct", "--timeout", "300"]
        subprocess.run([sys.executable, *tool, "--commands", *RENDER_COMMANDS], cwd=ROOT, check=False)
        if (folder / RENDER_NAME).exists():
            shutil.copy(folder / RENDER_NAME, out / target)
            made.append(out / target)
        else:
            print(f"{target}: the render tool wrote no {RENDER_NAME}")
    if not (out / "air.png").exists() and (AIR_RENDERS / RENDER_NAME).exists():
        shutil.copy(AIR_RENDERS / RENDER_NAME, out / "air.png")
    return made


def run_flash(swf: str, out: Path, scale: float) -> None:
    AIR_SMOKE.mkdir(parents=True, exist_ok=True)
    shutil.copy(out / "pixnames.txt", AIR_SMOKE / "pixnames.txt")
    subprocess.run([sys.executable, str(ROOT / "data" / "tools" / "port_boot_check.py"), swf, "--direct", "--timeout", "500",
                    "--commands", "waitmenu", "wait 120", f"pixdump air {scale:g}", "quit"], cwd=ROOT, check=False)
    shutil.copy(AIR_SMOKE / "pix-air.txt", out / "pix-air.txt")


FLASH_LEVELS = frozenset(k * 255 // 16 for k in range(1, 16))
CAIRO_LEVELS = frozenset(k * 16 for k in range(1, 16))


def levels(paths: list[Path]) -> list[str]:
    out = []
    for path in paths:
        symbols = load(path)
        few = flash = cairo = 0
        for _w, _h, data in symbols.values():
            partial = {a for a in data[0::4] if 0 < a < 255}
            if not partial:
                continue
            few += len(partial) <= 16
            flash += partial <= FLASH_LEVELS
            cairo += partial <= CAIRO_LEVELS
        out.append(f"{path}: {len(symbols)} symbols, {few} with at most 16 partial alphas; every partial alpha on "
                   f"Flash's 4x4 grid (floor(255k/16)): {flash}, on Cairo's (16k): {cairo}")
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--native", help="native TEST build (absolute path)")
    r.add_argument("--reuse-native", action="store_true", help="keep --out's native dumps and pixnames.txt")
    r.add_argument("--flash", help="Flash TEST build (absolute path); omit to reuse --out's pix-air.txt")
    r.add_argument("--air-from", type=Path,
                   help="take pix-air.txt from this earlier --out (a native-only change: AIR draws the same names)")
    r.add_argument("--out", type=Path, required=True)
    r.add_argument("--modes", default="subpixel,fast")
    r.add_argument("--per-library", type=int, default=4)
    r.add_argument("--total", type=int, default=400, help="at most this many symbols in all")
    r.add_argument("--scale", type=float, default=1.0)
    c = sub.add_parser("compare")
    c.add_argument("reference", type=Path)
    c.add_argument("others", type=Path, nargs="+")
    s = sub.add_parser("show", help="AIR | native | difference PNGs of symbols, enlarged")
    s.add_argument("reference", type=Path)
    s.add_argument("other", type=Path)
    s.add_argument("names", nargs="*")
    s.add_argument("--worst", type=int, default=0, help="also the N worst symbols")
    s.add_argument("--zoom", type=int, default=6)
    s.add_argument("--out", type=Path, required=True)
    g = sub.add_parser("png", help="whole PNGs against a reference (best offset, differences, partial alpha)")
    g.add_argument("reference", type=Path)
    g.add_argument("others", type=Path, nargs="+")
    g.add_argument("--shift", type=int, default=2)
    lv = sub.add_parser("levels", help="which 4x4-sample alpha grid each dump's edges are on (Flash's or Cairo's)")
    lv.add_argument("dumps", type=Path, nargs="+")
    d = sub.add_parser("render", help="the Image Render Tool's PNG in either build, compared with AIR's")
    d.add_argument("--native", help="native TEST build (absolute path)")
    d.add_argument("--flash", help="Flash TEST build (absolute path); omit to compare with AIR's last render")
    d.add_argument("--smoke-dir", type=Path, help="native smoke folder (to run beside an AIR run)")
    d.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)
    if args.cmd == "render":
        render(args.out, args.native, args.flash, args.smoke_dir)
        others = [p for p in (args.out / "native.png",) if p.exists()]
        if (args.out / "air.png").exists() and others:
            print("\n".join(png_compare(args.out / "air.png", others)))
        return 0
    if args.cmd == "levels":
        print("\n".join(levels(args.dumps)))
        return 0
    if args.cmd == "png":
        print("\n".join(png_compare(args.reference, args.others, args.shift)))
        return 0
    if args.cmd == "show":
        for path in show(args.reference, args.other, args.names, args.out, args.zoom, args.worst):
            print(path)
        return 0
    if args.cmd == "compare":
        for other in args.others:
            print("\n".join(compare(args.reference, other)[0]))
        return 0
    args.out.mkdir(parents=True, exist_ok=True)
    modes = [m.strip() for m in args.modes.split(",") if m.strip()]
    if not args.reuse_native:
        run_native(args.native, args.out, modes, args.per_library, args.total, args.scale)
    if args.flash:
        run_flash(args.flash, args.out, args.scale)
    elif args.air_from:
        shutil.copy(args.air_from / "pix-air.txt", args.out / "pix-air.txt")
        theirs, ours = args.air_from / "pixnames.txt", args.out / "pixnames.txt"
        if theirs.exists() and ours.exists() and theirs.read_bytes() != ours.read_bytes():
            print(f"warning: {theirs} lists other symbols than {ours}; only the common ones compare")
    report = []
    for mode in modes:
        report += compare(args.out / "pix-air.txt", args.out / f"pix-{mode}.txt")[0]
    if len(modes) > 1:
        report += compare(args.out / f"pix-{modes[0]}.txt", args.out / f"pix-{modes[1]}.txt")[0]
    (args.out / "report.txt").write_text("\n".join(report) + "\n", encoding="utf-8")
    print("\n".join(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
