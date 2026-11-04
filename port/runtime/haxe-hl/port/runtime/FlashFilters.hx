package port.runtime;

import openfl.display.BitmapData;
import openfl.geom.Point;
import openfl.geom.Rectangle;

@:access(openfl.display.BitmapData)
class FlashFilters {
    static function kernel(blur:Float):Array<Float> {
        if (blur <= 1) return [1.0];
        var half = blur / 2;
        var n = Math.ceil(half - 0.5);
        var weights = [];
        for (d in -n...n + 1) {
            var lo = Math.max(d - 0.5, -half), hi = Math.min(d + 0.5, half);
            weights.push(hi > lo ? (hi - lo) / blur : 0.0);
        }
        return weights;
    }

    static function pass(plane:haxe.ds.Vector<Int>, w:Int, h:Int, weights:Array<Float>, horizontal:Bool):Void {
        var n = weights.length >> 1;
        if (n == 0) return;
        var line = new haxe.ds.Vector<Int>(horizontal ? w : h);
        var count = horizontal ? h : w, length = horizontal ? w : h;
        for (j in 0...count) {
            for (i in 0...length) line[i] = plane[horizontal ? j * w + i : i * w + j];
            for (i in 0...length) {
                var sum = 0.0;
                for (k in 0...weights.length) {
                    var at = i + k - n;
                    if (at >= 0 && at < length) sum += line[at] * weights[k];
                }
                plane[horizontal ? j * w + i : i * w + j] = Std.int(sum + 1e-7);
            }
        }
    }

    static function blurPlane(plane:haxe.ds.Vector<Int>, w:Int, h:Int, blurX:Float, blurY:Float, quality:Int):Void {
        var kx = kernel(blurX), ky = kernel(blurY);
        for (q in 0...quality) pass(plane, w, h, kx, true);
        for (q in 0...quality) pass(plane, w, h, ky, false);
    }

    public static function glow(target:BitmapData, source:BitmapData, sourceRect:Rectangle, destPoint:Point, color:Int,
            alpha:Float, blurX:Float, blurY:Float, strength:Float, quality:Int, inner:Bool, knockout:Bool, offsetX:Float = 0,
            offsetY:Float = 0, hideObject:Bool = false):BitmapData {
        var w = Std.int(sourceRect.width), h = Std.int(sourceRect.height);
        var src = read(source, Std.int(sourceRect.x), Std.int(sourceRect.y), w, h);
        var srcAlpha = src[0];
        var plane = new haxe.ds.Vector<Int>(w * h);
        for (i in 0...w * h) plane[i] = inner ? 255 - srcAlpha[i] : srcAlpha[i];
        blurPlane(plane, w, h, blurX, blurY, quality);
        if (offsetX != 0 || offsetY != 0) plane = shift(plane, w, h, offsetX, offsetY);
        var alpha8 = Std.int(alpha * 255);
        var gr = (color >> 16) & 0xFF, gg = (color >> 8) & 0xFF, gb = color & 0xFF;
        var out = [for (c in 0...4) new haxe.ds.Vector<Int>(w * h)];
        for (i in 0...w * h) {
            var ga = Std.int((Std.int(Math.min(255, plane[i] * strength)) * alpha8 + 127) / 255);
            var sa = srcAlpha[i];
            var spr = src[1][i], spg = src[2][i], spb = src[3][i];
            var oa:Int, orr:Int, og:Int, ob:Int;
            if (inner) {
                if (knockout) {
                    oa = Std.int((ga * sa + 127) / 255);
                    orr = premul(gr, oa);
                    og = premul(gg, oa);
                    ob = premul(gb, oa);
                } else {
                    var inv = 255 - ga;
                    oa = sa;
                    orr = Std.int((premul(gr, sa) * ga + spr * inv + 127) / 255);
                    og = Std.int((premul(gg, sa) * ga + spg * inv + 127) / 255);
                    ob = Std.int((premul(gb, sa) * ga + spb * inv + 127) / 255);
                }
            } else if (knockout) {
                ga = Std.int((ga * (255 - sa) + 127) / 255);
                oa = ga;
                orr = premul(gr, ga);
                og = premul(gg, ga);
                ob = premul(gb, ga);
            } else if (hideObject) {
                oa = ga;
                orr = premul(gr, ga);
                og = premul(gg, ga);
                ob = premul(gb, ga);
            } else {
                var inv = 256 - sa;
                oa = sa + ((ga * inv) >> 8);
                orr = spr + ((premul(gr, ga) * inv) >> 8);
                og = spg + ((premul(gg, ga) * inv) >> 8);
                ob = spb + ((premul(gb, ga) * inv) >> 8);
            }
            if (oa > 255) oa = 255;
            out[0][i] = oa;
            out[1][i] = orr > oa ? oa : orr;
            out[2][i] = og > oa ? oa : og;
            out[3][i] = ob > oa ? oa : ob;
        }
        write(target, Std.int(destPoint.x), Std.int(destPoint.y), w, h, out);
        return target;
    }

    static function channels(format:lime.graphics.PixelFormat):Array<Int> {
        return switch (format) {
            case ARGB32: [0, 1, 2, 3];
            case BGRA32: [3, 2, 1, 0];
            default: [3, 0, 1, 2];
        }
    }

    static function read(bitmap:BitmapData, x0:Int, y0:Int, w:Int, h:Int):Array<haxe.ds.Vector<Int>> {
        var image = bitmap.image;
        var buffer = image.buffer;
        var data = buffer.data;
        var ch = channels(buffer.format);
        var stride = buffer.stride;
        var planes = [for (c in 0...4) new haxe.ds.Vector<Int>(w * h)];
        for (y in 0...h) {
            var iy = y0 + y + image.offsetY;
            if (iy < 0 || iy >= buffer.height || y0 + y >= image.height) continue;
            for (x in 0...w) {
                var ix = x0 + x + image.offsetX;
                if (ix < 0 || ix >= buffer.width || x0 + x >= image.width) continue;
                var p = iy * stride + ix * 4;
                var a = data[p + ch[0]];
                var i = y * w + x;
                planes[0][i] = a;
                for (c in 1...4) planes[c][i] = buffer.premultiplied ? data[p + ch[c]] : premul(data[p + ch[c]], a);
            }
        }
        return planes;
    }

    static function write(bitmap:BitmapData, x0:Int, y0:Int, w:Int, h:Int, planes:Array<haxe.ds.Vector<Int>>):Void {
        var image = bitmap.image;
        var buffer = image.buffer;
        var data = buffer.data;
        var ch = channels(buffer.format);
        var stride = buffer.stride;
        for (y in 0...h) {
            if (y0 + y < 0 || y0 + y >= image.height) continue;
            var iy = y0 + y + image.offsetY;
            for (x in 0...w) {
                if (x0 + x < 0 || x0 + x >= image.width) continue;
                var ix = x0 + x + image.offsetX;
                var p = iy * stride + ix * 4;
                var i = y * w + x;
                var a = planes[0][i];
                data[p + ch[0]] = a;
                for (c in 1...4) data[p + ch[c]] = buffer.premultiplied ? planes[c][i] : unpremul(planes[c][i], a);
            }
        }
        image.dirty = true;
        image.version++;
    }

    static inline function premul(c:Int, a:Int):Int {
        return Std.int((c * a + 127) / 255);
    }

    static inline function unpremul(c:Int, a:Int):Int {
        if (a == 0) return 0;
        var v = Std.int((c * 255 + (a >> 1)) / a);
        return v > 255 ? 255 : v;
    }

    static function shift(plane:haxe.ds.Vector<Int>, w:Int, h:Int, dx:Float, dy:Float):haxe.ds.Vector<Int> {
        var ix = Math.floor(dx), iy = Math.floor(dy);
        var fx = dx - ix, fy = dy - iy;
        inline function at(x:Int, y:Int):Int return x >= 0 && y >= 0 && x < w && y < h ? plane[y * w + x] : 0;
        var out = new haxe.ds.Vector<Int>(w * h);
        for (y in 0...h) for (x in 0...w) {
            var sx = x - ix, sy = y - iy;
            var v = at(sx, sy) * (1 - fx) * (1 - fy) + at(sx - 1, sy) * fx * (1 - fy) + at(sx, sy - 1) * (1 - fx) * fy
                + at(sx - 1, sy - 1) * fx * fy;
            out[y * w + x] = Std.int(v + 1e-7);
        }
        return out;
    }

    public static function blur(target:BitmapData, source:BitmapData, sourceRect:Rectangle, destPoint:Point, blurX:Float,
            blurY:Float, quality:Int):BitmapData {
        var w = Std.int(sourceRect.width), h = Std.int(sourceRect.height);
        var planes = read(source, Std.int(sourceRect.x), Std.int(sourceRect.y), w, h);
        for (p in planes) blurPlane(p, w, h, blurX, blurY, quality);
        for (i in 0...w * h) for (c in 1...4) if (planes[c][i] > planes[0][i]) planes[c][i] = planes[0][i];
        write(target, Std.int(destPoint.x), Std.int(destPoint.y), w, h, planes);
        return target;
    }
}
