"""build HashLink's ``libhl.dll`` from source with the port's patches (``PATCHES``).

    python tools/port_hashlink_build.py [--out build/port-hashlink] [--unpatched] [--version 1.15]

the source is the HashLink commit the pinned Lime 8.3.2 builds its own ``libhl.dll`` from (its
``project/lib/hashlink`` submodule), downloaded once into ``.tools/downloads``. it is staged into ``OUT/src``, patched
there (the download stays as fetched), and compiled with the local MSVC: ``libhl.vcxproj``'s own file list and
Release x64 defines. the result must have every export of Lime's bundled ``libhl.dll`` (``dumpbin``).
``tools/port_hl_run.py --libhl OUT/libhl.dll`` runs the game with it.

``--version 1.15`` builds the same patches on HashLink's 1.15.0 release instead (the Heaps engine's runtime,
``.tools/hashlink``), checked against that release's own ``libhl.dll``; ``tools/port_heaps.py`` puts
``build/port-hashlink-1.15/libhl.dll`` into its run folders.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tools import port_native_build

COMMIT = "03110f7e11fb76acf13312864b1d0bb700a6eda4"
URL = f"https://github.com/HaxeFoundation/hashlink/archive/{COMMIT}.zip"
DOWNLOAD = ROOT / ".tools" / "downloads" / f"hashlink-{COMMIT[:7]}"
LIME_LIBHL = ROOT / ".tools" / "haxelib" / "lime" / "8,3,2" / "templates" / "bin" / "hl" / "Windows64" / "libhl.dll"
DEFAULT_OUT = ROOT / "build" / "port-hashlink"
DEFINES = ["NDEBUG", "_WINDOWS", "_USRDLL", "LIBHL_EXPORTS", "HAVE_CONFIG_H", "PCRE2_CODE_UNIT_WIDTH=16",
           "UNICODE", "_UNICODE"]

PAGE_CAP_DEFAULTS = {None: 0, "1.15": 65536}
PAGE_CAP_OLD = """		while( num_pages > 8 && (size<<1) / block <= GC_PAGE_SIZE ) {"""
PAGE_CAP_NEW = """		static int page_cap = -1;
		if( page_cap < 0 ) {
			char *cap = getenv("HL_GC_PAGE_CAP");
			page_cap = cap ? atoi(cap) : HL_GC_PAGE_CAP_DEFAULT;
			if( page_cap < 0 ) page_cap = 0;
		}
		while( num_pages > 8 && (size<<1) / block <= GC_PAGE_SIZE && (page_cap == 0 || (size<<1) <= page_cap) ) {"""

MIN_BASE_OLD = """	if( (m > gc_stats.pages_total_memory * gc_mark_threshold || b > gc_stats.pages_blocks * gc_mark_threshold || (gc_flags & GC_FORCE_MAJOR)) && gc_is_active )"""
MIN_BASE_NEW = """	static int64 min_base = -1;
	if( min_base < 0 ) {
		char *base = getenv("HL_GC_MIN_BASE");
		min_base = base ? _atoi64(base) : ((int64)64 << 20);
		if( min_base < 0 ) min_base = 0;
	}
	int64 mem_base = gc_stats.pages_total_memory < min_base ? min_base : gc_stats.pages_total_memory;
	int64 block_base = gc_stats.pages_blocks;
	if( gc_stats.pages_total_memory > 0 && mem_base > gc_stats.pages_total_memory )
		block_base = (int64)((double)block_base * mem_base / gc_stats.pages_total_memory);
	if( (m > mem_base * gc_mark_threshold || b > block_base * gc_mark_threshold || (gc_flags & GC_FORCE_MAJOR)) && gc_is_active )"""

FILL_DECL_OLD = """	fl_cursor nblocks = (fl_cursor)(size >> GC_SBITS[part]);
	int bid = -1;
	while( ph ) {
		p = &ph->alloc;
		if( p->need_flush )
			flush_free_list(ph);
		gc_freelist *fl = &p->free;
		int k;"""
FILL_DECL_NEW = """	fl_cursor nblocks = (fl_cursor)(size >> GC_SBITS[part]);
	int bid = -1;
	static int fill = -1;
	if( fill < 0 ) {
		char *f = getenv("HL_GC_FILL");
		fill = f && atoi(f) > 0 ? 1 : 0;
	}
	gc_pheader *first_open = NULL;
	while( ph ) {
		p = &ph->alloc;
		if( p->need_flush )
			flush_free_list(ph);
		gc_freelist *fl = &p->free;
		if( fill && !first_open && fl->current < fl->count )
			first_open = ph;
		int k;"""
FILL_SET_OLD = """	p->sizes[bid] = (unsigned char)nblocks;
	gc_free_pages[pid] = ph;
	return ptr;"""
FILL_SET_NEW = """	p->sizes[bid] = (unsigned char)nblocks;
	if( first_open && first_open != ph )
		gc_free_pages[pid] = first_open;
	else
		gc_free_pages[pid] = ph;
	return ptr;"""

FILL_NEW_OLD = """		ph = gc_allocator_new_page(pid, GC_SIZES[part], psize, kind, true);"""
FILL_NEW_NEW = """		first_open = NULL;
		ph = gc_allocator_new_page(pid, GC_SIZES[part], psize, kind, true);"""

SEED_OLD = """	hl_rnd_set_seed(r,time ^ (pid | (pid << 16)));"""
SEED_NEW = """	{
		char *seed = getenv("HL_RANDOM_SEED");
		if( seed && *seed ) {
			time = (unsigned int)atoi(seed);
			pid = 0;
		}
	}
	hl_rnd_set_seed(r,time ^ (pid | (pid << 16)));"""

MARK_DECL_OLD = """} gc_stats = {0};"""
MARK_DECL_NEW = """} gc_stats = {0};
static double gc_mark_seconds = 0;"""
MARK_TIME_OLD = """	gc_stop_world(true);
	gc_mark();
	gc_stop_world(false);
	dt = TIMESTAMP() - time;"""
MARK_TIME_NEW = """#ifdef HL_WIN
	LARGE_INTEGER mark_q0, mark_q1, mark_qf;
	QueryPerformanceCounter(&mark_q0);
#endif
	gc_stop_world(true);
	gc_mark();
	gc_stop_world(false);
	dt = TIMESTAMP() - time;
#ifdef HL_WIN
	QueryPerformanceCounter(&mark_q1);
	QueryPerformanceFrequency(&mark_qf);
	gc_mark_seconds += (double)(mark_q1.QuadPart - mark_q0.QuadPart) / (double)mark_qf.QuadPart;
#endif"""
MARK_API_OLD = """HL_API void hl_gc_enable( bool b ) {"""
MARK_API_NEW = """HL_API void hl_gc_mark_stats( double *count, double *seconds ) {
	*count = (double)gc_stats.mark_count;
	*seconds = gc_mark_seconds;
}

HL_API void hl_gc_enable( bool b ) {"""
MARK_PRIM_OLD = """DEFINE_PRIM(_VOID, gc_stats, _REF(_F64) _REF(_F64) _REF(_F64));"""
MARK_PRIM_NEW = """DEFINE_PRIM(_VOID, gc_stats, _REF(_F64) _REF(_F64) _REF(_F64));
DEFINE_PRIM(_VOID, gc_mark_stats, _REF(_F64) _REF(_F64));"""

MARK_CAP_OLD = """#	define GC_MAX_MARK_THREADS 4"""
MARK_CAP_NEW = """#	define GC_MAX_MARK_THREADS 8"""
MARK_DEFAULT_OLD = """static int gc_mark_threads = GC_MAX_MARK_THREADS;"""
MARK_DEFAULT_NEW = """static int gc_mark_threads = 4;"""
MARK_AUTO_DEFAULTS = {None: 0, "1.15": 1}
MARK_AUTO_OLD = """		if( gc_mark_threads > GC_MAX_MARK_THREADS ) gc_mark_threads = GC_MAX_MARK_THREADS;
	}
"""
MARK_AUTO_NEW = """		if( gc_mark_threads > GC_MAX_MARK_THREADS ) gc_mark_threads = GC_MAX_MARK_THREADS;
	}
#	if defined(HL_WIN) && HL_GC_MARK_AUTO
	else {
		SYSTEM_INFO si;
		GetSystemInfo(&si);
		int half = (int)si.dwNumberOfProcessors / 2;
		if( half > gc_mark_threads ) gc_mark_threads = half > GC_MAX_MARK_THREADS ? GC_MAX_MARK_THREADS : half;
	}
#	endif
"""
MARK_PRIO_OLD = """	gc_mthread *inf = &mark_threads[index];
	while( true ) {"""
MARK_PRIO_NEW = """	gc_mthread *inf = &mark_threads[index];
#ifdef HL_WIN
	{
		char *prio = getenv("HL_GC_THREAD_PRIORITY");
		int p = prio ? atoi(prio) : 0;
		if( p != 0 ) SetThreadPriority(GetCurrentThread(), p);
	}
#endif
	while( true ) {"""

EXISTS_OLD = """	pstat st;
	return stat((pchar*)path,&st) == 0;"""
EXISTS_NEW = """	pstat st;
	hl_blocking(true);
	bool found = stat((pchar*)path,&st) == 0;
	hl_blocking(false);
	return found;"""
CONTENTS_OLD = """	FILE *f = fopen((uchar*)name,USTR("rb"));
#	else
	FILE *f = fopen((char*)name,"rb");
#	endif
	if( f == NULL )
		return NULL;
	hl_blocking(true);"""
CONTENTS_NEW = """	hl_blocking(true);
	FILE *f = fopen((uchar*)name,USTR("rb"));
#	else
	hl_blocking(true);
	FILE *f = fopen((char*)name,"rb");
#	endif
	if( f == NULL ) {
		hl_blocking(false);
		return NULL;
	}"""

def pipe_read(handle: str) -> tuple[str, str]:
    old = f"""	if( !ReadFile(p->{handle},str+pos,len,&nbytes,NULL) )
		return -1;"""
    new = f"""	hl_blocking(true);
	BOOL read_ok = ReadFile(p->{handle},str+pos,len,&nbytes,NULL);
	hl_blocking(false);
	if( !read_ok )
		return -1;"""
    return old, new


PATCHES = [("src/std/process.c", *pipe_read("oread")), ("src/std/process.c", *pipe_read("eread")),
           ("src/allocator.c", PAGE_CAP_OLD, PAGE_CAP_NEW), ("src/gc.c", MIN_BASE_OLD, MIN_BASE_NEW),
           ("src/std/sys.c", EXISTS_OLD, EXISTS_NEW), ("src/std/file.c", CONTENTS_OLD, CONTENTS_NEW),
           ("src/gc.c", MARK_CAP_OLD, MARK_CAP_NEW), ("src/gc.c", MARK_DEFAULT_OLD, MARK_DEFAULT_NEW),
           ("src/gc.c", MARK_PRIO_OLD, MARK_PRIO_NEW), ("src/gc.c", MARK_AUTO_OLD, MARK_AUTO_NEW),
           ("src/allocator.c", FILL_DECL_OLD, FILL_DECL_NEW), ("src/allocator.c", FILL_SET_OLD, FILL_SET_NEW),
           ("src/allocator.c", FILL_NEW_OLD, FILL_NEW_NEW), ("src/std/random.c", SEED_OLD, SEED_NEW),
           ("src/gc.c", MARK_DECL_OLD, MARK_DECL_NEW), ("src/gc.c", MARK_TIME_OLD, MARK_TIME_NEW),
           ("src/gc.c", MARK_API_OLD, MARK_API_NEW), ("src/gc.c", MARK_PRIM_OLD, MARK_PRIM_NEW)]


RELEASES = {"1.15": ("1.15", ROOT / ".tools" / "hashlink" / "libhl.dll", ROOT / "build" / "port-hashlink-1.15")}


def source(version: str | None = None) -> Path:
    if version is None:
        download, url, name = DOWNLOAD, URL, f"hashlink-{COMMIT}"
    else:
        tag = RELEASES[version][0]
        download = ROOT / ".tools" / "downloads" / f"hashlink-{tag}"
        url, name = f"https://github.com/HaxeFoundation/hashlink/archive/refs/tags/{tag}.zip", f"hashlink-{tag}"
    tree = download / name
    if not tree.exists():
        download.mkdir(parents=True, exist_ok=True)
        archive = download / "hashlink.zip"
        if not archive.exists():
            urllib.request.urlretrieve(url, archive)
        with zipfile.ZipFile(archive) as z:
            z.extractall(download)
    return tree


def compiled_files(tree: Path) -> list[str]:
    text = (tree / "libhl.vcxproj").read_text(encoding="utf-8-sig")
    return [name.replace("\\", "/") for name in re.findall(r'<ClCompile Include="([^"]+)"', text)]


def stage(tree: Path, src: Path, patched: bool) -> int:
    if src.exists():
        shutil.rmtree(src)
    shutil.copytree(tree, src)
    applied = 0
    if patched:
        for name, old, new in PATCHES:
            path = src / name
            text = path.read_text(encoding="utf-8")
            if text.count(old) != 1:
                raise RuntimeError(f"patch for {name} does not apply (expected the line once)")
            path.write_text(text.replace(old, new), encoding="utf-8")
            applied += 1
    return applied


def exports(dll: Path, vcvars: Path) -> set[str]:
    with tempfile.TemporaryDirectory() as tmp:
        script = Path(tmp) / "dump.bat"
        script.write_text(f'@echo off\r\ncall "{vcvars}" >nul\r\ndumpbin /nologo /exports "{dll}"\r\n', encoding="utf-8")
        out = subprocess.run(["cmd", "/d", "/c", str(script)], capture_output=True, text=True).stdout
    return set(re.findall(r"^\s+\d+\s+[0-9A-F]+\s+[0-9A-F]{8}\s+(\S+)", out, re.M))


def build(out: Path, patched: bool = True, version: str | None = None) -> int:
    vcvars = port_native_build.find_vcvars()
    if vcvars is None:
        print("no Visual Studio vcvars64.bat found", file=sys.stderr)
        return 2
    tree = source(version)
    src = out / "src"
    applied = stage(tree, src, patched)
    files = compiled_files(src)
    obj = out / "obj"
    obj.mkdir(parents=True, exist_ok=True)
    defines = " ".join(f"/D{d}" for d in [*DEFINES, f"HL_GC_PAGE_CAP_DEFAULT={PAGE_CAP_DEFAULTS[version] if patched else 0}",
                                                 f"HL_GC_MARK_AUTO={MARK_AUTO_DEFAULTS[version] if patched else 0}"])
    sources = " ".join(f'"{src / f}"' for f in files)
    command = (f'cl /nologo /c /O2 /Oi /Gy /GS- /MD /W0 {defines} /I"{src / "src"}" /I"{src / "include"}" '
               f'/I"{src / "include" / "pcre"}" {sources} /Fo"{obj}\\\\"')
    link = (f'link /nologo /DLL /OPT:REF /OPT:ICF /OUT:"{out / "libhl.dll"}" /IMPLIB:"{out / "libhl.lib"}" '
            f'"{obj}\\*.obj" ws2_32.lib user32.lib')
    script = out / "build.bat"
    script.write_text("@echo off\r\n" + f'call "{vcvars}" >nul\r\n' + f"{command}\r\nif errorlevel 1 exit /b 1\r\n"
                      + f"{link}\r\nif errorlevel 1 exit /b 1\r\n", encoding="utf-8")
    result = subprocess.run(["cmd", "/d", "/c", str(script)], capture_output=True, text=True)
    if result.returncode != 0:
        print((result.stdout + result.stderr)[-4000:], file=sys.stderr)
        return result.returncode
    reference = LIME_LIBHL if version is None else RELEASES[version][1]
    ours, lime = exports(out / "libhl.dll", vcvars), exports(reference, vcvars)
    missing = sorted(lime - ours)
    print(f"built {out / 'libhl.dll'} from HashLink {version or COMMIT[:7]} ({len(files)} files, {applied} patch(es)); "
          f"exports {len(ours)}, the reference's {len(lime)}, missing {len(missing)}")
    if missing:
        print("missing exports: " + ", ".join(missing[:40]), file=sys.stderr)
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--unpatched", action="store_true", help="build the source as fetched (no patches)")
    parser.add_argument("--version", choices=sorted(RELEASES), help="a HashLink release instead of Lime's commit")
    args = parser.parse_args(argv)
    out = args.out or (RELEASES[args.version][2] if args.version else DEFAULT_OUT)
    return build(out.resolve(), not args.unpatched, args.version)


if __name__ == "__main__":
    sys.exit(main())
