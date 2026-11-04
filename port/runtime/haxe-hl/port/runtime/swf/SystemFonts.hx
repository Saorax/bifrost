package port.runtime.swf;

import haxe.io.Bytes;
import port.runtime.swf.SwfFont.FontPart;
import port.runtime.swf.SwfFont.Glyph;
import port.runtime.swf.SwfFont.Point;

class SystemFonts {
    static final FILES:Map<String, String> = [
        "_sans" => "arial", "_sans Bold" => "arialbd", "_sans Italic" => "ariali", "_sans Bold Italic" => "arialbi",
        "_serif" => "times", "_serif Bold" => "timesbd", "_serif Italic" => "timesi", "_serif Bold Italic" => "timesbi",
        "_typewriter" => "cour", "_typewriter Bold" => "courbd", "_typewriter Italic" => "couri",
        "_typewriter Bold Italic" => "courbi",
    ];
    static inline var LAST_CODE = 0x2200;

    static var tried = new Map<String, Bool>();
    public static var loaded(default, null):Int = 0;
    public static var loadMs(default, null):Float = 0;

    public static function ensure(name:String):Bool {
        if (SwfFonts.layout.exists(name)) return true;
        if (tried.exists(name) || !FILES.exists(name)) return false;
        tried.set(name, true);
        var dir = Sys.getEnv("WINDIR");
        var path = (dir != null ? dir : "C:\\Windows") + "\\Fonts\\" + FILES.get(name) + ".ttf";
        var started = Sys.time();
        var part = try {
            sys.FileSystem.exists(path) ? parse(sys.io.File.getBytes(path), name.indexOf("Bold") >= 0, name.indexOf("Italic") >= 0) : null;
        } catch (_:Dynamic) null;
        if (part == null) return false;
        SwfFonts.addPart(name, part);
        loaded++;
        loadMs += (Sys.time() - started) * 1000;
        return SwfFonts.layout.exists(name);
    }

    public static function parse(b:Bytes, bold:Bool, italic:Bool):FontPart {
        var tables = new Map<String, Int>();
        var numTables = u16(b, 4);
        for (i in 0...numTables) {
            var at = 12 + i * 16;
            tables.set(b.getString(at, 4), u32(b, at + 8));
        }
        for (t in ["head", "hhea", "hmtx", "maxp", "cmap", "loca", "glyf"]) if (!tables.exists(t)) return null;
        var head = tables.get("head"), hhea = tables.get("hhea");
        var unitsPerEm = u16(b, head + 18);
        var longLoca = s16(b, head + 50) == 1;
        var numGlyphs = u16(b, tables.get("maxp") + 4);
        var numMetrics = u16(b, hhea + 34);
        var ascender = s16(b, hhea + 4), descender = -s16(b, hhea + 6), lineGap = s16(b, hhea + 8);
        if (tables.exists("OS/2")) {
            var os2 = tables.get("OS/2");
            ascender = u16(b, os2 + 74);
            descender = u16(b, os2 + 76);
        }
        var scale = SwfFont.UNITS_PER_EM / unitsPerEm;
        var loca = tables.get("loca"), glyf = tables.get("glyf"), hmtx = tables.get("hmtx");
        function offset(g:Int):Int return longLoca ? u32(b, loca + g * 4) : u16(b, loca + g * 2) * 2;
        function advance(g:Int):Int return u16(b, hmtx + (g < numMetrics ? g : numMetrics - 1) * 4);

        var part = new FontPart();
        var map = cmap(b, tables.get("cmap"));
        var codes = [for (code in map.keys()) if (code <= LAST_CODE) code];
        codes.sort((a, c) -> a - c);
        for (code in codes) {
            var g = map.get(code);
            if (g <= 0 || g >= numGlyphs) continue;
            var glyph = new Glyph();
            var raw:Array<Array<RawPoint>> = [];
            outline(b, glyf, offset, g, 0, 0, 1, 0, 0, 1, raw, 0);
            for (contour in raw) {
                var c = alternate(contour, scale);
                if (c.length > 1) glyph.contours.push(c);
            }
            glyph.advance = Math.round(advance(g) * scale);
            glyph.xMin = 0;
            part.glyphs.push(glyph);
            part.codes.push(code);
            part.advances.push(advance(g) / unitsPerEm);
        }
        if (part.codes.length == 0) return null;
        part.ascent = Math.round(ascender * scale);
        part.descent = Math.round(descender * scale);
        part.leading = Math.round(lineGap * scale);
        part.ascentEm = ascender / unitsPerEm;
        part.descentEm = descender / unitsPerEm;
        part.bold = bold;
        part.italic = italic;
        return part;
    }

    static function outline(b:Bytes, glyf:Int, offset:Int->Int, g:Int, dx:Float, dy:Float, a:Float, bb:Float, c:Float,
            d:Float, out:Array<Array<RawPoint>>, depth:Int):Void {
        var start = offset(g), end = offset(g + 1);
        if (end <= start || depth > 8) return;
        var at = glyf + start;
        var contours = s16(b, at);
        at += 10;
        if (contours >= 0) {
            var ends = [for (i in 0...contours) u16(b, at + i * 2)];
            at += contours * 2;
            at += 2 + u16(b, at);
            var count = contours > 0 ? ends[contours - 1] + 1 : 0;
            var flags = [];
            while (flags.length < count) {
                var f = b.get(at++);
                flags.push(f);
                if (f & 8 != 0) {
                    var n = b.get(at++);
                    for (_ in 0...n) flags.push(f);
                }
            }
            var xs = [], ys = [];
            var v = 0;
            for (f in flags) {
                if (f & 2 != 0) {
                    var delta = b.get(at++);
                    v += f & 16 != 0 ? delta : -delta;
                } else if (f & 16 == 0) {
                    v += s16(b, at);
                    at += 2;
                }
                xs.push(v);
            }
            v = 0;
            for (f in flags) {
                if (f & 4 != 0) {
                    var delta = b.get(at++);
                    v += f & 32 != 0 ? delta : -delta;
                } else if (f & 32 == 0) {
                    v += s16(b, at);
                    at += 2;
                }
                ys.push(v);
            }
            var first = 0;
            for (e in ends) {
                var contour = [];
                for (i in first...e + 1) {
                    contour.push({x: a * xs[i] + c * ys[i] + dx, y: bb * xs[i] + d * ys[i] + dy, on: flags[i] & 1 != 0});
                }
                out.push(contour);
                first = e + 1;
            }
            return;
        }
        while (true) {
            var f = u16(b, at), component = u16(b, at + 2);
            at += 4;
            var arg1:Float, arg2:Float;
            if (f & 1 != 0) {
                arg1 = s16(b, at);
                arg2 = s16(b, at + 2);
                at += 4;
            } else {
                arg1 = s8(b.get(at));
                arg2 = s8(b.get(at + 1));
                at += 2;
            }
            var ca = 1.0, cb = 0.0, cc = 0.0, cd = 1.0;
            if (f & 8 != 0) {
                ca = cd = f2dot14(b, at);
                at += 2;
            } else if (f & 0x40 != 0) {
                ca = f2dot14(b, at);
                cd = f2dot14(b, at + 2);
                at += 4;
            } else if (f & 0x80 != 0) {
                ca = f2dot14(b, at);
                cb = f2dot14(b, at + 2);
                cc = f2dot14(b, at + 4);
                cd = f2dot14(b, at + 6);
                at += 8;
            }
            var ox = f & 2 != 0 ? arg1 : 0.0, oy = f & 2 != 0 ? arg2 : 0.0;
            outline(b, glyf, offset, component, a * ox + c * oy + dx, bb * ox + d * oy + dy, a * ca + c * cb,
                bb * ca + d * cb, a * cc + c * cd, bb * cc + d * cd, out, depth + 1);
            if (f & 0x20 == 0) break;
        }
    }

    public static function alternate(contour:Array<RawPoint>, scale:Float):Array<Point> {
        var n = contour.length;
        if (n < 2) return [];
        var startAt = -1;
        for (i in 0...n) if (contour[i].on) {
            startAt = i;
            break;
        }
        var pts:Array<RawPoint> = [];
        if (startAt < 0) {
            var p = contour[0], q = contour[1];
            pts.push({x: (p.x + q.x) / 2, y: (p.y + q.y) / 2, on: true});
            for (i in 1...n + 1) pts.push(contour[i % n]);
        } else {
            for (i in 0...n) pts.push(contour[(startAt + i) % n]);
        }
        var out:Array<Point> = [];
        var prevOn = true;
        for (i in 0...pts.length) {
            var p = pts[i];
            if (!p.on && !prevOn) {
                var q = pts[i - 1];
                out.push({x: Math.round((p.x + q.x) / 2 * scale), y: Math.round((p.y + q.y) / 2 * scale), on: true});
            }
            out.push({x: Math.round(p.x * scale), y: Math.round(p.y * scale), on: p.on});
            prevOn = p.on;
        }
        var last = out[out.length - 1];
        if (last.on && out.length > 1 && last.x == out[0].x && last.y == out[0].y) out.pop();
        return out;
    }

    static function cmap(b:Bytes, table:Int):Map<Int, Int> {
        var out = new Map<Int, Int>();
        var count = u16(b, table + 2);
        var sub = -1;
        for (i in 0...count) {
            var at = table + 4 + i * 8;
            if (u16(b, at) == 3 && (u16(b, at + 2) == 1 || u16(b, at + 2) == 0)) {
                sub = table + u32(b, at + 4);
                break;
            }
        }
        if (sub < 0 || u16(b, sub) != 4) return out;
        var segs = u16(b, sub + 6) >> 1;
        var ends = sub + 14, starts = ends + segs * 2 + 2, deltas = starts + segs * 2, ranges = deltas + segs * 2;
        for (s in 0...segs) {
            var end = u16(b, ends + s * 2), start = u16(b, starts + s * 2);
            var delta = u16(b, deltas + s * 2), range = u16(b, ranges + s * 2);
            if (start > LAST_CODE) break;
            for (code in start...(end < LAST_CODE ? end : LAST_CODE) + 1) {
                if (code == 0xFFFF) continue;
                var g:Int;
                if (range == 0) {
                    g = (code + delta) & 0xFFFF;
                } else {
                    var at = ranges + s * 2 + range + (code - start) * 2;
                    g = u16(b, at);
                    if (g != 0) g = (g + delta) & 0xFFFF;
                }
                if (g != 0) out.set(code, g);
            }
        }
        return out;
    }

    static inline function u16(b:Bytes, at:Int):Int return (b.get(at) << 8) | b.get(at + 1);

    static inline function s16(b:Bytes, at:Int):Int {
        var v = u16(b, at);
        return v >= 0x8000 ? v - 0x10000 : v;
    }

    static inline function s8(v:Int):Int return v >= 0x80 ? v - 0x100 : v;

    static inline function u32(b:Bytes, at:Int):Int return (u16(b, at) << 16) | u16(b, at + 2);

    static inline function f2dot14(b:Bytes, at:Int):Float return s16(b, at) / 16384.0;
}

typedef RawPoint = {x:Float, y:Float, on:Bool};
