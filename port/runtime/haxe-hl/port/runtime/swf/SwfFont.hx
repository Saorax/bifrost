package port.runtime.swf;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

class SwfFont {
    public static inline var UNITS_PER_EM = 1024;

    public static function parse(r:SwfReader):FontPart {
        r.u16();
        var flags = r.u8();
        r.u8();
        var nameLength = r.u8();
        r.pos += nameLength;
        var count = r.u16();
        var hasLayout = flags & 0x80 != 0;
        var wideOffsets = flags & 0x08 != 0;
        var wideCodes = flags & 0x04 != 0;
        if (count == 0 || !hasLayout) return null;
        var tableStart = r.pos;
        var offsets = [for (i in 0...count) wideOffsets ? r.u32() : r.u16()];
        var codeOffset = wideOffsets ? r.u32() : r.u16();
        var part = new FontPart();
        for (i in 0...count) {
            r.seek(tableStart + offsets[i]);
            part.glyphs.push(readGlyph(r));
        }
        r.seek(tableStart + codeOffset);
        part.codes = [for (i in 0...count) wideCodes ? r.u16() : r.u8()];
        var ascent = r.u16(), descent = r.u16();
        part.ascent = Math.round(ascent / 20);
        part.descent = Math.round(descent / 20);
        part.ascentEm = ascent / (20.0 * UNITS_PER_EM);
        part.descentEm = descent / (20.0 * UNITS_PER_EM);
        part.leading = Math.round(r.s16() / 20);
        for (i in 0...count) {
            var advance = r.s16();
            part.glyphs[i].advance = Math.round(advance / 20);
            part.advances.push(advance / (20.0 * UNITS_PER_EM));
        }
        part.bold = flags & 0x01 != 0;
        part.italic = flags & 0x02 != 0;
        return part;
    }

    public static function merged(name:String, parts:Array<FontPart>):{bytes:Bytes, advances:Array<Float>, glyphs:Array<Glyph>,
            codes:Array<Int>} {
        var glyphs = [], codes = [], advances = [0.0];
        var seen = new Map<Int, Bool>();
        for (part in parts) {
            for (i in 0...part.codes.length) {
                if (seen.exists(part.codes[i])) continue;
                seen.set(part.codes[i], true);
                glyphs.push(part.glyphs[i]);
                codes.push(part.codes[i]);
                advances.push(part.advances[i]);
            }
        }
        var first = parts[0];
        return {bytes: build(name, glyphs, codes, first.ascent, first.descent, first.leading, first.bold, first.italic),
            advances: advances, glyphs: glyphs, codes: codes};
    }

    static function readGlyph(r:SwfReader):Glyph {
        var glyph = new Glyph();
        var fillBits = r.ub(4);
        var lineBits = r.ub(4);
        var x = 0, y = 0;
        var contour:Array<Point> = null;
        inline function close() {
            if (contour != null) {
                var first = contour[0], last = contour[contour.length - 1];
                if (contour.length > 1 && last.on && last.x == first.x && last.y == first.y) contour.pop();
                if (contour.length > 1) glyph.contours.push(contour);
                contour = null;
            }
        }
        inline function begin() {
            if (contour == null) contour = [{x: unit(x), y: -unit(y), on: true}];
        }
        inline function point(px:Int, py:Int, on:Bool) {
            contour.push({x: unit(px), y: -unit(py), on: on});
        }
        while (true) {
            if (r.ub(1) == 0) {
                var newStyles = r.ub(1), lineStyle = r.ub(1), fill1 = r.ub(1), fill0 = r.ub(1), moveTo = r.ub(1);
                if (newStyles == 0 && lineStyle == 0 && fill1 == 0 && fill0 == 0 && moveTo == 0) break;
                if (moveTo == 1) {
                    var bits = r.ub(5);
                    x = r.sb(bits);
                    y = r.sb(bits);
                    close();
                    contour = [{x: unit(x), y: -unit(y), on: true}];
                }
                if (fill0 == 1) r.ub(fillBits);
                if (fill1 == 1) r.ub(fillBits);
                if (lineStyle == 1) r.ub(lineBits);
                if (newStyles == 1) throw "font glyph with new styles";
            } else if (r.ub(1) == 1) {
                begin();
                var bits = r.ub(4) + 2;
                if (r.ub(1) == 1) {
                    x += r.sb(bits);
                    y += r.sb(bits);
                } else if (r.ub(1) == 1) {
                    y += r.sb(bits);
                } else {
                    x += r.sb(bits);
                }
                point(x, y, true);
            } else {
                begin();
                var bits = r.ub(4) + 2;
                x += r.sb(bits);
                y += r.sb(bits);
                point(x, y, false);
                x += r.sb(bits);
                y += r.sb(bits);
                point(x, y, true);
            }
        }
        close();
        return glyph;
    }

    static inline function unit(twips:Int):Int {
        return Math.round(twips / 20);
    }

    static function build(name:String, glyphs:Array<Glyph>, codes:Array<Int>, ascent:Int, descent:Int, leading:Int,
            bold:Bool, italic:Bool):Bytes {
        glyphs.unshift(new Glyph());
        var numGlyphs = glyphs.length;
        var xMin = 0x7fff, yMin = 0x7fff, xMax = -0x8000, yMax = -0x8000;
        var maxPoints = 0, maxContours = 0, advanceMax = 0;
        var glyf = new BytesBuffer();
        var loca = new BytesBuffer();
        for (glyph in glyphs) {
            loca.addInt32(bigEndian(glyf.length));
            if (glyph.advance > advanceMax) advanceMax = glyph.advance;
            if (glyph.contours.length == 0) continue;
            var points = 0;
            var gx0 = 0x7fff, gy0 = 0x7fff, gx1 = -0x8000, gy1 = -0x8000;
            for (contour in glyph.contours) {
                for (p in contour) {
                    if (p.x < gx0) gx0 = p.x;
                    if (p.x > gx1) gx1 = p.x;
                    if (p.y < gy0) gy0 = p.y;
                    if (p.y > gy1) gy1 = p.y;
                }
                points += contour.length;
            }
            glyph.xMin = gx0;
            if (gx0 < xMin) xMin = gx0;
            if (gy0 < yMin) yMin = gy0;
            if (gx1 > xMax) xMax = gx1;
            if (gy1 > yMax) yMax = gy1;
            if (points > maxPoints) maxPoints = points;
            if (glyph.contours.length > maxContours) maxContours = glyph.contours.length;
            var g = new Writer();
            g.s16(glyph.contours.length);
            g.s16(gx0);
            g.s16(gy0);
            g.s16(gx1);
            g.s16(gy1);
            var end = -1;
            for (contour in glyph.contours) {
                end += contour.length;
                g.u16(end);
            }
            g.u16(0);
            for (contour in glyph.contours) for (p in contour) g.u8(p.on ? 1 : 0);
            var last = 0;
            for (contour in glyph.contours) for (p in contour) {
                g.s16(p.x - last);
                last = p.x;
            }
            last = 0;
            for (contour in glyph.contours) for (p in contour) {
                g.s16(p.y - last);
                last = p.y;
            }
            while (g.length % 4 != 0) g.u8(0);
            glyf.add(g.bytes());
        }
        loca.addInt32(bigEndian(glyf.length));
        if (xMin > xMax) {
            xMin = yMin = xMax = yMax = 0;
        }

        var head = new Writer();
        head.u32(0x00010000);
        head.u32(0x00010000);
        head.u32(0);
        head.u32(0x5F0F3CF5);
        head.u16(0x000B);
        head.u16(UNITS_PER_EM);
        for (i in 0...16) head.u8(0);
        head.s16(xMin);
        head.s16(yMin);
        head.s16(xMax);
        head.s16(yMax);
        head.u16((bold ? 1 : 0) | (italic ? 2 : 0));
        head.u16(8);
        head.s16(2);
        head.s16(1);
        head.s16(0);

        var hhea = new Writer();
        hhea.u32(0x00010000);
        hhea.s16(ascent);
        hhea.s16(-descent);
        hhea.s16(leading);
        hhea.u16(advanceMax);
        hhea.s16(xMin);
        hhea.s16(0);
        hhea.s16(xMax);
        hhea.s16(1);
        hhea.s16(0);
        hhea.s16(0);
        for (i in 0...4) hhea.s16(0);
        hhea.s16(0);
        hhea.u16(numGlyphs);

        var hmtx = new Writer();
        for (glyph in glyphs) {
            hmtx.u16(glyph.advance < 0 ? 0 : glyph.advance);
            hmtx.s16(glyph.contours.length > 0 ? glyph.xMin : 0);
        }

        var maxp = new Writer();
        maxp.u32(0x00010000);
        maxp.u16(numGlyphs);
        maxp.u16(maxPoints);
        maxp.u16(maxContours);
        maxp.u16(0);
        maxp.u16(0);
        maxp.u16(2);
        for (i in 0...7) maxp.u16(0);
        maxp.u16(0);
        maxp.u16(0);

        var post = new Writer();
        post.u32(0x00030000);
        post.u32(0);
        post.s16(0);
        post.s16(0);
        for (i in 0...5) post.u32(0);

        var tables = [
            {tag: "cmap", data: cmap(codes)},
            {tag: "glyf", data: glyf.getBytes()},
            {tag: "head", data: head.bytes()},
            {tag: "hhea", data: hhea.bytes()},
            {tag: "hmtx", data: hmtx.bytes()},
            {tag: "loca", data: loca.getBytes()},
            {tag: "maxp", data: maxp.bytes()},
            {tag: "name", data: nameTable(name, bold, italic)},
            {tag: "post", data: post.bytes()},
        ];
        var file = new Writer();
        var n = tables.length;
        var pow = 1, log = 0;
        while (pow * 2 <= n) {
            pow *= 2;
            log++;
        }
        file.u32(0x00010000);
        file.u16(n);
        file.u16(pow * 16);
        file.u16(log);
        file.u16(n * 16 - pow * 16);
        var offset = 12 + 16 * n;
        var headOffset = 0;
        for (table in tables) {
            file.string(table.tag);
            file.u32(checksum(table.data));
            file.u32(offset);
            file.u32(table.data.length);
            if (table.tag == "head") headOffset = offset;
            offset += (table.data.length + 3) & ~3;
        }
        for (table in tables) {
            file.add(table.data);
            while (file.length % 4 != 0) file.u8(0);
        }
        var bytes = file.bytes();
        var adjust = 0xB1B0AFBA - checksum(bytes);
        bytes.set(headOffset + 8, (adjust >>> 24) & 0xff);
        bytes.set(headOffset + 9, (adjust >>> 16) & 0xff);
        bytes.set(headOffset + 10, (adjust >>> 8) & 0xff);
        bytes.set(headOffset + 11, adjust & 0xff);
        return bytes;
    }

    static function cmap(codes:Array<Int>):Bytes {
        var pairs = [for (i in 0...codes.length) {code: codes[i], glyph: i + 1}];
        pairs.sort(function(a, b) return a.code - b.code);
        var segments:Array<{start:Int, end:Int, delta:Int}> = [];
        for (pair in pairs) {
            if (pair.code >= 0xffff) continue;
            var last = segments.length > 0 ? segments[segments.length - 1] : null;
            if (last != null && pair.code == last.end) continue;
            if (last != null && pair.code == last.end + 1 && pair.glyph - pair.code == last.delta) {
                last.end = pair.code;
            } else {
                segments.push({start: pair.code, end: pair.code, delta: pair.glyph - pair.code});
            }
        }
        segments.push({start: 0xffff, end: 0xffff, delta: 1});
        var segCount = segments.length;
        var pow = 1, log = 0;
        while (pow * 2 <= segCount) {
            pow *= 2;
            log++;
        }
        var sub = new Writer();
        sub.u16(4);
        sub.u16(16 + 8 * segCount);
        sub.u16(0);
        sub.u16(segCount * 2);
        sub.u16(pow * 2);
        sub.u16(log);
        sub.u16(segCount * 2 - pow * 2);
        for (s in segments) sub.u16(s.end);
        sub.u16(0);
        for (s in segments) sub.u16(s.start);
        for (s in segments) sub.u16(s.delta & 0xffff);
        for (s in segments) sub.u16(0);
        var w = new Writer();
        w.u16(0);
        w.u16(1);
        w.u16(3);
        w.u16(1);
        w.u32(12);
        w.add(sub.bytes());
        return w.bytes();
    }

    static function nameTable(name:String, bold:Bool, italic:Bool):Bytes {
        var style = bold && italic ? "Bold Italic" : bold ? "Bold" : italic ? "Italic" : "Regular";
        var records = [{id: 1, text: name}, {id: 2, text: style}, {id: 4, text: name}, {id: 6, text: StringTools.replace(name, " ", "")}];
        var strings = new Writer();
        var w = new Writer();
        w.u16(0);
        w.u16(records.length);
        w.u16(6 + 12 * records.length);
        for (record in records) {
            var start = strings.length;
            for (i in 0...record.text.length) strings.u16(StringTools.fastCodeAt(record.text, i));
            w.u16(3);
            w.u16(1);
            w.u16(0x0409);
            w.u16(record.id);
            w.u16(strings.length - start);
            w.u16(start);
        }
        w.add(strings.bytes());
        return w.bytes();
    }

    static function checksum(bytes:Bytes):Int {
        var sum = 0;
        var i = 0;
        while (i < bytes.length) {
            var word = 0;
            for (k in 0...4) word = (word << 8) | (i + k < bytes.length ? bytes.get(i + k) : 0);
            sum += word;
            i += 4;
        }
        return sum;
    }

    static inline function bigEndian(v:Int):Int {
        return ((v >>> 24) & 0xff) | (((v >>> 16) & 0xff) << 8) | (((v >>> 8) & 0xff) << 16) | ((v & 0xff) << 24);
    }
}

typedef Point = {x:Int, y:Int, on:Bool};

class FontPart {
    public var glyphs:Array<Glyph> = [];
    public var codes:Array<Int> = [];
    public var advances:Array<Float> = [];
    public var ascent:Int = 0;
    public var descent:Int = 0;
    public var leading:Int = 0;
    public var ascentEm:Float = 0;
    public var descentEm:Float = 0;
    public var bold:Bool = false;
    public var italic:Bool = false;

    public function new() {}
}

class Glyph {
    public var contours:Array<Array<Point>> = [];
    public var advance:Int = 0;
    public var xMin:Int = 0;

    public function new() {}
}

private class Writer {
    var buffer = new BytesBuffer();

    public var length(get, never):Int;

    public function new() {}

    inline function get_length():Int {
        return buffer.length;
    }

    public inline function u8(v:Int) {
        buffer.addByte(v & 0xff);
    }

    public inline function u16(v:Int) {
        buffer.addByte((v >> 8) & 0xff);
        buffer.addByte(v & 0xff);
    }

    public inline function s16(v:Int) {
        u16(v & 0xffff);
    }

    public inline function u32(v:Int) {
        u16((v >>> 16) & 0xffff);
        u16(v & 0xffff);
    }

    public function string(s:String) {
        for (i in 0...s.length) u8(StringTools.fastCodeAt(s, i));
    }

    public inline function add(b:Bytes) {
        buffer.add(b);
    }

    public function bytes():Bytes {
        return buffer.getBytes();
    }
}
