package port.runtime.swf;

import openfl.display.CapsStyle;
import openfl.display.GradientType;
import openfl.display.Graphics;
import openfl.display.InterpolationMethod;
import openfl.display.JointStyle;
import openfl.display.LineScaleMode;
import openfl.display.SpreadMethod;
import openfl.geom.Matrix;

class SwfShape {
    public static var drawn(default, null):Int = 0;
    public static var skippedFills(default, null):Int = 0;

    static var bitmaps:Int->openfl.display.BitmapData = null;

    public static function draw(g:Graphics, r:SwfReader, code:Int, ?bitmapOf:Int->openfl.display.BitmapData):Void {
        bitmaps = bitmapOf;
        r.u16();
        r.rect();
        if (code == 83) {
            r.rect();
            r.u8();
        }
        var withAlpha = code == 32 || code == 83;
        var fills = readFills(r, code, withAlpha);
        var lines = readLines(r, code, withAlpha);
        var fillBits = r.ub(4);
        var lineBits = r.ub(4);
        var group = new Group(fills, lines);
        var groups = 1;
        var starts:Array<Int> = [];
        var x = 0, y = 0;
        var fill0 = 0, fill1 = 0, line = 0;
        while (true) {
            if (r.ub(1) == 0) {
                var newStyles = r.ub(1), lineStyle = r.ub(1), f1 = r.ub(1), f0 = r.ub(1), moveTo = r.ub(1);
                if (newStyles == 0 && lineStyle == 0 && f1 == 0 && f0 == 0 && moveTo == 0) break;
                if (moveTo == 1) {
                    var bits = r.ub(5);
                    x = r.sb(bits);
                    y = r.sb(bits);
                }
                if (f0 == 1) fill0 = r.ub(fillBits);
                if (f1 == 1) fill1 = r.ub(fillBits);
                if (lineStyle == 1) line = r.ub(lineBits);
                if (newStyles == 1) {
                    groups++;
                    starts.push(commandCount(g));
                    group.draw(g);
                    r.seek(r.pos);
                    group = new Group(readFills(r, code, withAlpha), readLines(r, code, withAlpha));
                    fillBits = r.ub(4);
                    lineBits = r.ub(4);
                    fill0 = fill1 = line = 0;
                }
            } else if (r.ub(1) == 1) {
                var bits = r.ub(4) + 2;
                var dx = 0, dy = 0;
                if (r.ub(1) == 1) {
                    dx = r.sb(bits);
                    dy = r.sb(bits);
                } else if (r.ub(1) == 1) {
                    dy = r.sb(bits);
                } else {
                    dx = r.sb(bits);
                }
                group.add(new Edge(x, y, x, y, x + dx, y + dy, false), fill0, fill1, line);
                x += dx;
                y += dy;
            } else {
                var bits = r.ub(4) + 2;
                var cx = x + r.sb(bits);
                var cy = y + r.sb(bits);
                var ax = cx + r.sb(bits);
                var ay = cy + r.sb(bits);
                group.add(new Edge(x, y, cx, cy, ax, ay, true), fill0, fill1, line);
                x = ax;
                y = ay;
            }
        }
        starts.push(commandCount(g));
        group.draw(g);
        g.__portAdditive = true;
        g.__portGroups = groups > 1 ? starts : null;
        if (groups > 1) multiGroup++;
        drawn++;
    }

    static inline function commandCount(g:Graphics):Int {
        #if openfl
        return @:privateAccess g.__commands.types.length;
        #else
        return g.fills.length;
        #end
    }

    public static var multiGroup(default, null):Int = 0;

    public static var textsDrawn(default, null):Int = 0;

    public static function drawText(g:Graphics, r:SwfReader, code:Int,
            glyphOf:(Int, Int) -> {reader:SwfReader, em:Float}):Void {
        r.u16();
        r.rect();
        var m = r.matrix();
        var glyphBits = r.u8(), advanceBits = r.u8();
        var font = -1, color = 0, alpha = 1.0, height = 0, x = 0, y = 0;
        while (true) {
            var flags = r.u8();
            if (flags == 0) break;
            if (flags & 0x08 != 0) font = r.u16();
            if (flags & 0x04 != 0) {
                var c = new FillStyle();
                readColor(r, code == 33, c);
                color = c.color;
                alpha = c.alpha;
            }
            if (flags & 0x01 != 0) x = r.s16();
            if (flags & 0x02 != 0) y = r.s16();
            if (flags & 0x08 != 0) height = r.u16();
            var count = r.u8();
            var entries = [for (i in 0...count) {glyph: r.ub(glyphBits), advance: r.sb(advanceBits)}];
            r.seek(r.pos);
            g.beginFill(color, alpha);
            for (entry in entries) {
                var glyph = glyphOf(font, entry.glyph);
                if (glyph != null) drawGlyph(g, glyph.reader, height / glyph.em, x, y, m);
                x += entry.advance;
            }
            g.endFill();
        }
        textsDrawn++;
    }

    static function drawGlyph(g:Graphics, r:SwfReader, scale:Float, ox:Int, oy:Int, m:Matrix) {
        var fillBits = r.ub(4);
        var lineBits = r.ub(4);
        var x = 0, y = 0;
        inline function px(gx:Float, gy:Float):Float return m.a * (ox + gx * scale) / 20 + m.c * (oy + gy * scale) / 20 + m.tx;
        inline function py(gx:Float, gy:Float):Float return m.b * (ox + gx * scale) / 20 + m.d * (oy + gy * scale) / 20 + m.ty;
        g.moveTo(px(0, 0), py(0, 0));
        while (true) {
            if (r.ub(1) == 0) {
                var newStyles = r.ub(1), lineStyle = r.ub(1), f1 = r.ub(1), f0 = r.ub(1), moveTo = r.ub(1);
                if (newStyles == 0 && lineStyle == 0 && f1 == 0 && f0 == 0 && moveTo == 0) break;
                if (moveTo == 1) {
                    var bits = r.ub(5);
                    x = r.sb(bits);
                    y = r.sb(bits);
                    g.moveTo(px(x, y), py(x, y));
                }
                if (f0 == 1) r.ub(fillBits);
                if (f1 == 1) r.ub(fillBits);
                if (lineStyle == 1) r.ub(lineBits);
                if (newStyles == 1) break;
            } else if (r.ub(1) == 1) {
                var bits = r.ub(4) + 2;
                if (r.ub(1) == 1) {
                    x += r.sb(bits);
                    y += r.sb(bits);
                } else if (r.ub(1) == 1) {
                    y += r.sb(bits);
                } else {
                    x += r.sb(bits);
                }
                g.lineTo(px(x, y), py(x, y));
            } else {
                var bits = r.ub(4) + 2;
                var cx = x + r.sb(bits), cy = y + r.sb(bits);
                x = cx + r.sb(bits);
                y = cy + r.sb(bits);
                g.curveTo(px(cx, cy), py(cx, cy), px(x, y), py(x, y));
            }
        }
    }

    public static var morphsDrawn(default, null):Int = 0;

    public static function drawMorph(g:Graphics, r:SwfReader, code:Int, ratio:Int,
            ?bitmapOf:Int->openfl.display.BitmapData):Void {
        bitmaps = bitmapOf;
        var t = ratio / 65535;
        r.u16();
        r.rect();
        r.rect();
        if (code == 84) {
            r.rect();
            r.rect();
            r.u8();
        }
        var offset = r.u32();
        var endEdges = r.pos + offset;
        var count = r.u8();
        if (count == 0xff) count = r.u16();
        var fills = [for (i in 0...count) readMorphFill(r, t)];
        count = r.u8();
        if (count == 0xff) count = r.u16();
        var lines = [for (i in 0...count) readMorphLine(r, code, t)];
        var start = readMorphRecords(r);
        r.seek(endEdges);
        var end = readMorphRecords(r);
        var group = new Group(fills, lines);
        var ei = 0;
        var sx = 0, sy = 0, ex = 0, ey = 0;
        var fill0 = 0, fill1 = 0, line = 0;
        inline function lerp(a:Float, b:Float):Int return Math.round(a + (b - a) * t);
        for (s in start) {
            if (s.kind == 0) {
                if (s.hasStyles) {
                    if (s.fill0 >= 0) fill0 = s.fill0;
                    if (s.fill1 >= 0) fill1 = s.fill1;
                    if (s.line >= 0) line = s.line;
                }
                if (s.moved) {
                    sx = s.x1;
                    sy = s.y1;
                    if (ei < end.length && end[ei].kind == 0) {
                        if (end[ei].moved) {
                            ex = end[ei].x1;
                            ey = end[ei].y1;
                        }
                        ei++;
                    }
                }
                continue;
            }
            while (ei < end.length && end[ei].kind == 0) {
                if (end[ei].moved) {
                    ex = end[ei].x1;
                    ey = end[ei].y1;
                }
                ei++;
            }
            if (ei >= end.length) break;
            var e = end[ei++];
            var scx = s.kind == 2 ? s.cx : (sx + s.x1) / 2, scy = s.kind == 2 ? s.cy : (sy + s.y1) / 2;
            var ecx = e.kind == 2 ? e.cx : (ex + e.x1) / 2, ecy = e.kind == 2 ? e.cy : (ey + e.y1) / 2;
            var curved = s.kind == 2 || e.kind == 2;
            var x0 = lerp(sx, ex), y0 = lerp(sy, ey);
            var x1 = lerp(s.x1, e.x1), y1 = lerp(s.y1, e.y1);
            var cx = curved ? lerp(scx, ecx) : x0, cy = curved ? lerp(scy, ecy) : y0;
            group.add(new Edge(x0, y0, cx, cy, x1, y1, curved), fill0, fill1, line);
            sx = s.x1;
            sy = s.y1;
            ex = e.x1;
            ey = e.y1;
        }
        group.draw(g);
        g.__portAdditive = true;
        g.__portGroups = null;
        morphsDrawn++;
    }

    static function readMorphRecords(r:SwfReader):Array<MorphRecord> {
        var fillBits = r.ub(4);
        var lineBits = r.ub(4);
        var out = [];
        var x = 0, y = 0;
        while (true) {
            if (r.ub(1) == 0) {
                var newStyles = r.ub(1), lineStyle = r.ub(1), f1 = r.ub(1), f0 = r.ub(1), moveTo = r.ub(1);
                if (newStyles == 0 && lineStyle == 0 && f1 == 0 && f0 == 0 && moveTo == 0) break;
                var rec = new MorphRecord(0);
                if (moveTo == 1) {
                    var bits = r.ub(5);
                    x = r.sb(bits);
                    y = r.sb(bits);
                    rec.moved = true;
                }
                rec.hasStyles = f0 == 1 || f1 == 1 || lineStyle == 1;
                if (f0 == 1) rec.fill0 = r.ub(fillBits);
                if (f1 == 1) rec.fill1 = r.ub(fillBits);
                if (lineStyle == 1) rec.line = r.ub(lineBits);
                if (newStyles == 1) throw "new styles in a morph shape";
                rec.x1 = x;
                rec.y1 = y;
                out.push(rec);
            } else if (r.ub(1) == 1) {
                var bits = r.ub(4) + 2;
                var dx = 0, dy = 0;
                if (r.ub(1) == 1) {
                    dx = r.sb(bits);
                    dy = r.sb(bits);
                } else if (r.ub(1) == 1) {
                    dy = r.sb(bits);
                } else {
                    dx = r.sb(bits);
                }
                x += dx;
                y += dy;
                var rec = new MorphRecord(1);
                rec.x1 = x;
                rec.y1 = y;
                out.push(rec);
            } else {
                var bits = r.ub(4) + 2;
                var rec = new MorphRecord(2);
                rec.cx = x + r.sb(bits);
                rec.cy = y + r.sb(bits);
                x = rec.cx + r.sb(bits);
                y = rec.cy + r.sb(bits);
                rec.x1 = x;
                rec.y1 = y;
                out.push(rec);
            }
        }
        return out;
    }

    static function lerpColor(r:SwfReader, t:Float, into:FillStyle) {
        var a = new FillStyle(), b = new FillStyle();
        readColor(r, true, a);
        readColor(r, true, b);
        into.color = lerpRgb(a.color, b.color, t);
        into.alpha = a.alpha + (b.alpha - a.alpha) * t;
    }

    static function lerpRgb(a:Int, b:Int, t:Float):Int {
        var out = 0;
        for (shift in [16, 8, 0]) {
            var ca = (a >> shift) & 0xff, cb = (b >> shift) & 0xff;
            out |= Math.round(ca + (cb - ca) * t) << shift;
        }
        return out;
    }

    static function lerpMatrix(a:Matrix, b:Matrix, t:Float):Matrix {
        return new Matrix(a.a + (b.a - a.a) * t, a.b + (b.b - a.b) * t, a.c + (b.c - a.c) * t, a.d + (b.d - a.d) * t,
            a.tx + (b.tx - a.tx) * t, a.ty + (b.ty - a.ty) * t);
    }

    static function readMorphFill(r:SwfReader, t:Float):FillStyle {
        var fill = new FillStyle();
        fill.type = r.u8();
        switch (fill.type) {
            case 0x00:
                lerpColor(r, t, fill);
            case 0x10 | 0x12 | 0x13:
                fill.matrix = lerpMatrix(r.matrix(), r.matrix(), t);
                var flags = r.u8();
                fill.spread = flags >> 6;
                fill.linearRGB = (flags >> 4) & 3 == 1;
                for (i in 0...(flags & 0x0f)) {
                    var startRatio = r.u8();
                    var a = new FillStyle();
                    readColor(r, true, a);
                    var endRatio = r.u8();
                    var b = new FillStyle();
                    readColor(r, true, b);
                    fill.ratios.push(Math.round(startRatio + (endRatio - startRatio) * t));
                    fill.colors.push(lerpRgb(a.color, b.color, t));
                    fill.alphas.push(a.alpha + (b.alpha - a.alpha) * t);
                }
                if (fill.type == 0x13) {
                    var a = r.s16() / 256, b = r.s16() / 256;
                    fill.focal = a + (b - a) * t;
                }
            case 0x40 | 0x41 | 0x42 | 0x43:
                fill.bitmapId = r.u16();
                var m = lerpMatrix(r.matrix(), r.matrix(), t);
                fill.matrix = new Matrix(m.a / 20, m.b / 20, m.c / 20, m.d / 20, m.tx, m.ty);
            default:
                throw "unknown SWF morph fill style " + fill.type;
        }
        return fill;
    }

    static function readMorphLine(r:SwfReader, code:Int, t:Float):LineStyle {
        var line = new LineStyle();
        var startWidth = r.u16(), endWidth = r.u16();
        line.width = (startWidth + (endWidth - startWidth) * t) / 20;
        if (code == 84) {
            var startCap = r.ub(2);
            var join = r.ub(2);
            var hasFill = r.ub(1) == 1;
            line.noHScale = r.ub(1) == 1;
            line.noVScale = r.ub(1) == 1;
            line.pixelHinting = r.ub(1) == 1;
            r.ub(5);
            r.ub(1);
            r.ub(2);
            line.caps = startCap == 1 ? CapsStyle.NONE : startCap == 2 ? CapsStyle.SQUARE : CapsStyle.ROUND;
            line.joints = join == 1 ? JointStyle.BEVEL : join == 2 ? JointStyle.MITER : JointStyle.ROUND;
            if (join == 2) line.miterLimit = r.u16() / 256;
            if (hasFill) {
                var fill = readMorphFill(r, t);
                line.color = fill.type == 0 ? fill.color : (fill.colors.length > 0 ? fill.colors[0] : 0);
                line.alpha = fill.type == 0 ? fill.alpha : (fill.alphas.length > 0 ? fill.alphas[0] : 1);
                return line;
            }
        }
        var c = new FillStyle();
        lerpColor(r, t, c);
        line.color = c.color;
        line.alpha = c.alpha;
        return line;
    }

    static function readFills(r:SwfReader, code:Int, withAlpha:Bool):Array<FillStyle> {
        var count = r.u8();
        if (count == 0xff && code != 2) count = r.u16();
        return [for (i in 0...count) readFill(r, code, withAlpha)];
    }

    static function readFill(r:SwfReader, code:Int, withAlpha:Bool):FillStyle {
        var fill = new FillStyle();
        fill.type = r.u8();
        switch (fill.type) {
            case 0x00:
                readColor(r, withAlpha, fill);
            case 0x10 | 0x12 | 0x13:
                fill.matrix = r.matrix();
                var flags = r.u8();
                fill.spread = flags >> 6;
                fill.linearRGB = (flags >> 4) & 3 == 1;
                for (i in 0...(flags & 0x0f)) {
                    fill.ratios.push(r.u8());
                    var c = new FillStyle();
                    readColor(r, withAlpha, c);
                    fill.colors.push(c.color);
                    fill.alphas.push(c.alpha);
                }
                if (fill.type == 0x13) fill.focal = r.s16() / 256;
            case 0x40 | 0x41 | 0x42 | 0x43:
                fill.bitmapId = r.u16();
                var m = r.matrix();
                fill.matrix = new Matrix(m.a / 20, m.b / 20, m.c / 20, m.d / 20, m.tx, m.ty);
            default:
                throw "unknown SWF fill style " + fill.type;
        }
        return fill;
    }

    static function readColor(r:SwfReader, withAlpha:Bool, into:FillStyle) {
        var red = r.u8(), green = r.u8(), blue = r.u8();
        into.color = (red << 16) | (green << 8) | blue;
        into.alpha = withAlpha ? r.u8() / 255 : 1.0;
    }

    static function readLines(r:SwfReader, code:Int, withAlpha:Bool):Array<LineStyle> {
        var count = r.u8();
        if (count == 0xff && code != 2) count = r.u16();
        var lines = [];
        for (i in 0...count) {
            var line = new LineStyle();
            line.width = r.u16() / 20;
            if (code == 83) {
                var startCap = r.ub(2);
                var join = r.ub(2);
                var hasFill = r.ub(1) == 1;
                line.noHScale = r.ub(1) == 1;
                line.noVScale = r.ub(1) == 1;
                line.pixelHinting = r.ub(1) == 1;
                r.ub(5);
                r.ub(1);
                r.ub(2);
                line.caps = startCap == 1 ? CapsStyle.NONE : startCap == 2 ? CapsStyle.SQUARE : CapsStyle.ROUND;
                line.joints = join == 1 ? JointStyle.BEVEL : join == 2 ? JointStyle.MITER : JointStyle.ROUND;
                if (join == 2) line.miterLimit = r.u16() / 256;
                if (hasFill) {
                    var fill = readFill(r, code, true);
                    line.color = fill.type == 0 ? fill.color : (fill.colors.length > 0 ? fill.colors[0] : 0);
                    line.alpha = fill.type == 0 ? fill.alpha : (fill.alphas.length > 0 ? fill.alphas[0] : 1);
                } else {
                    var c = new FillStyle();
                    readColor(r, true, c);
                    line.color = c.color;
                    line.alpha = c.alpha;
                }
            } else {
                var c = new FillStyle();
                readColor(r, withAlpha, c);
                line.color = c.color;
                line.alpha = c.alpha;
            }
            lines.push(line);
        }
        return lines;
    }
}

private class MorphRecord {
    public var kind:Int;
    public var moved = false;
    public var hasStyles = false;
    public var fill0 = -1;
    public var fill1 = -1;
    public var line = -1;
    public var cx = 0;
    public var cy = 0;
    public var x1 = 0;
    public var y1 = 0;

    public function new(kind:Int) {
        this.kind = kind;
    }
}

private class Edge {
    public var x0:Int;
    public var y0:Int;
    public var cx:Int;
    public var cy:Int;
    public var x1:Int;
    public var y1:Int;
    public var curved:Bool;
    public var used:Int = 0;
    public var nextAtStart:Edge;

    public function new(x0:Int, y0:Int, cx:Int, cy:Int, x1:Int, y1:Int, curved:Bool) {
        this.x0 = x0;
        this.y0 = y0;
        this.cx = cx;
        this.cy = cy;
        this.x1 = x1;
        this.y1 = y1;
        this.curved = curved;
    }

    public function reversed():Edge {
        return new Edge(x1, y1, cx, cy, x0, y0, curved);
    }
}

private class Group {
    var fills:Array<FillStyle>;
    var lines:Array<LineStyle>;
    var fillEdges:FastIntMap<Array<Edge>> = new FastIntMap();
    var lineEdges:FastIntMap<Array<Edge>> = new FastIntMap();

    public function new(fills:Array<FillStyle>, lines:Array<LineStyle>) {
        this.fills = fills;
        this.lines = lines;
    }

    public function add(edge:Edge, fill0:Int, fill1:Int, line:Int) {
        if (fill0 != 0) push(fillEdges, fill0, edge.reversed());
        if (fill1 != 0) push(fillEdges, fill1, edge);
        if (line != 0) push(lineEdges, line, edge);
    }

    static function push(map:FastIntMap<Array<Edge>>, key:Int, edge:Edge) {
        var list = map.get(key);
        if (list == null) map.set(key, list = []);
        list.push(edge);
    }

    public function draw(g:Graphics) {
        var keys = [for (k in fillEdges.keys()) k];
        keys.sort(function(a, b) return a - b);
        for (key in keys) {
            var style = fills[key - 1];
            if (style == null) continue;
            if (!begin(g, style)) continue;
            trace_(g, chain(fillEdges.get(key)));
            g.endFill();
        }
        keys = [for (k in lineEdges.keys()) k];
        keys.sort(function(a, b) return a - b);
        for (key in keys) {
            var style = lines[key - 1];
            if (style == null) continue;
            var scale = style.noHScale && style.noVScale ? LineScaleMode.NONE : style.noHScale ? LineScaleMode.VERTICAL
                : style.noVScale ? LineScaleMode.HORIZONTAL : LineScaleMode.NORMAL;
            g.lineStyle(style.width, style.color, style.alpha, style.pixelHinting, scale, style.caps, style.joints,
                style.miterLimit);
            trace_(g, lineEdges.get(key));
            g.lineStyle();
        }
    }

    static function begin(g:Graphics, style:FillStyle):Bool {
        switch (style.type) {
            case 0x00:
                g.beginFill(style.color, style.alpha);
            case 0x10 | 0x12 | 0x13:
                var spread = style.spread == 1 ? SpreadMethod.REFLECT : style.spread == 2 ? SpreadMethod.REPEAT : SpreadMethod.PAD;
                g.beginGradientFill(style.type == 0x10 ? GradientType.LINEAR : GradientType.RADIAL, style.colors, style.alphas,
                    style.ratios, style.matrix, spread, style.linearRGB ? InterpolationMethod.LINEAR_RGB : InterpolationMethod.RGB,
                    style.focal);
            case 0x40 | 0x41 | 0x42 | 0x43:
                var bitmaps = @:privateAccess SwfShape.bitmaps;
                var bitmap = bitmaps != null && style.bitmapId != 0xffff ? bitmaps(style.bitmapId) : null;
                if (bitmap == null) {
                    @:privateAccess SwfShape.skippedFills++;
                    return false;
                }
                g.beginBitmapFill(bitmap, style.matrix, style.type == 0x40 || style.type == 0x42,
                    style.type == 0x40 || style.type == 0x41);
            default:
                @:privateAccess SwfShape.skippedFills++;
                return false;
        }
        return true;
    }

    static var chainStamp = 0;

    static var chained:Array<Edge> = [];
    static var slotKey = new hl.NativeArray<Int>(0);
    static var slotEdge = new hl.NativeArray<Edge>(0);
    static var slotStamp = new hl.NativeArray<Int>(0);
    static var slotMask = -1;

    static inline function pointKey(x:Int, y:Int):Int {
        return x * 0x9E3779B1 ^ y;
    }

    static inline function slot(key:Int, stamp:Int):Int {
        var i = (key ^ (key >>> 15)) & slotMask;
        while (slotStamp[i] == stamp && slotKey[i] != key) i = (i + 1) & slotMask;
        return i;
    }

    static function chain(edges:Array<Edge>):Array<Edge> {
        var stamp = ++chainStamp;
        if (slotMask + 1 < edges.length * 2) {
            var size = 64;
            while (size < edges.length * 2) size <<= 1;
            slotKey = new hl.NativeArray<Int>(size);
            slotEdge = new hl.NativeArray<Edge>(size);
            slotStamp = new hl.NativeArray<Int>(size);
            slotMask = size - 1;
        }
        var i = edges.length;
        while (i-- > 0) {
            var e = edges[i];
            var key = pointKey(e.x0, e.y0);
            var at = slot(key, stamp);
            if (slotStamp[at] != stamp) {
                slotStamp[at] = stamp;
                slotKey[at] = key;
                slotEdge[at] = null;
            }
            e.nextAtStart = slotEdge[at];
            slotEdge[at] = e;
        }
        var out = chained;
        out.resize(0);
        for (e in edges) {
            if (e.used == stamp) continue;
            var current = e;
            while (current != null) {
                current.used = stamp;
                out.push(current);
                var x = current.x1, y = current.y1;
                var at = slot(pointKey(x, y), stamp);
                var candidate:Edge = slotStamp[at] == stamp ? slotEdge[at] : null;
                if (candidate != null && candidate.used == stamp) {
                    while (candidate != null && candidate.used == stamp) candidate = candidate.nextAtStart;
                    slotEdge[at] = candidate;
                }
                while (candidate != null && (candidate.used == stamp || candidate.x0 != x || candidate.y0 != y))
                    candidate = candidate.nextAtStart;
                current = candidate;
            }
        }
        for (e in edges) {
            e.nextAtStart = null;
            slotEdge[slot(pointKey(e.x0, e.y0), stamp)] = null;
        }
        return out;
    }

    static function trace_(g:Graphics, edges:Array<Edge>) {
        var px = 0x7fffffff, py = 0x7fffffff;
        for (e in edges) {
            if (e.x0 != px || e.y0 != py) g.moveTo(e.x0 / 20, e.y0 / 20);
            if (e.curved) {
                g.curveTo(e.cx / 20, e.cy / 20, e.x1 / 20, e.y1 / 20);
            } else {
                g.lineTo(e.x1 / 20, e.y1 / 20);
            }
            px = e.x1;
            py = e.y1;
        }
    }
}

private class FillStyle {
    public var type:Int = 0;
    public var color:Int = 0;
    public var alpha:Float = 1;
    public var matrix:Matrix;
    public var spread:Int = 0;
    public var linearRGB = false;
    public var colors:Array<Int> = [];
    public var alphas:Array<Float> = [];
    public var ratios:Array<Int> = [];
    public var focal:Float = 0;
    public var bitmapId:Int = 0;

    public function new() {}
}

private class LineStyle {
    public var width:Float = 0;
    public var color:Int = 0;
    public var alpha:Float = 1;
    public var noHScale = false;
    public var noVScale = false;
    public var pixelHinting = false;
    public var caps:CapsStyle = CapsStyle.ROUND;
    public var joints:JointStyle = JointStyle.ROUND;
    public var miterLimit:Float = 3;

    public function new() {}
}
