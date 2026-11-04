package port.runtime.swf;

import haxe.io.Bytes;
import openfl.geom.ColorTransform;
import openfl.geom.Matrix;

class SwfReader {
    public var pos:Int;
    public var end:Int;

    var bytes:Bytes;
    var bitBuffer:Int = 0;
    var bitCount:Int = 0;

    public function new(bytes:Bytes, pos:Int, end:Int) {
        this.bytes = bytes;
        this.pos = pos;
        this.end = end;
    }

    public inline function u8():Int {
        bitCount = 0;
        return bytes.get(pos++);
    }

    public inline function u16():Int {
        bitCount = 0;
        var v = bytes.getUInt16(pos);
        pos += 2;
        return v;
    }

    public inline function seek(offset:Int) {
        bitCount = 0;
        pos = offset;
    }

    public inline function peekU16():Int {
        return bytes.getUInt16(pos);
    }

    public inline function s16():Int {
        var v = u16();
        return v >= 0x8000 ? v - 0x10000 : v;
    }

    public inline function u32():Int {
        bitCount = 0;
        var v = bytes.getInt32(pos);
        pos += 4;
        return v;
    }

    public function tagHeader():{code:Int, length:Int} {
        var header = u16();
        var length = header & 0x3f;
        if (length == 0x3f) length = u32();
        return {code: header >> 6, length: length};
    }

    public function string():String {
        bitCount = 0;
        var start = pos;
        while (pos < end && bytes.get(pos) != 0) pos++;
        var s = bytes.getString(start, pos - start);
        pos++;
        return s;
    }

    public function fixedString(length:Int):String {
        bitCount = 0;
        var n = length;
        while (n > 0 && bytes.get(pos + n - 1) == 0) n--;
        var s = bytes.getString(pos, n);
        pos += length;
        return s;
    }

    public function ub(n:Int):Int {
        var v = 0;
        while (n > 0) {
            if (bitCount == 0) {
                bitBuffer = bytes.get(pos++);
                bitCount = 8;
            }
            var take = n < bitCount ? n : bitCount;
            v = (v << take) | ((bitBuffer >> (bitCount - take)) & ((1 << take) - 1));
            bitCount -= take;
            n -= take;
        }
        return v;
    }

    public function sb(n:Int):Int {
        if (n == 0) return 0;
        var v = ub(n);
        return (v & (1 << (n - 1))) != 0 ? v - (1 << n) : v;
    }

    public inline function fb(n:Int):Float {
        return sb(n) / 65536.0;
    }

    public function rect():{xMin:Float, yMin:Float, xMax:Float, yMax:Float} {
        bitCount = 0;
        var n = ub(5);
        var r = {xMin: sb(n) / 20, xMax: sb(n) / 20, yMin: sb(n) / 20, yMax: sb(n) / 20};
        bitCount = 0;
        return r;
    }

    public function matrix():Matrix {
        bitCount = 0;
        var a = 1.0, d = 1.0, b = 0.0, c = 0.0;
        if (ub(1) == 1) {
            var n = ub(5);
            a = fb(n);
            d = fb(n);
        }
        if (ub(1) == 1) {
            var n = ub(5);
            b = fb(n);
            c = fb(n);
        }
        var n = ub(5);
        var tx = sb(n) / 20;
        var ty = sb(n) / 20;
        bitCount = 0;
        return new Matrix(a, b, c, d, tx, ty);
    }

    public function colorTransform():ColorTransform {
        bitCount = 0;
        var hasAdd = ub(1) == 1;
        var hasMult = ub(1) == 1;
        var n = ub(4);
        var ct = new ColorTransform();
        if (hasMult) {
            ct.redMultiplier = sb(n) / 256;
            ct.greenMultiplier = sb(n) / 256;
            ct.blueMultiplier = sb(n) / 256;
            ct.alphaMultiplier = sb(n) / 256;
        }
        if (hasAdd) {
            ct.redOffset = sb(n);
            ct.greenOffset = sb(n);
            ct.blueOffset = sb(n);
            ct.alphaOffset = sb(n);
        }
        bitCount = 0;
        return ct;
    }

    public function filters():Array<openfl.filters.BitmapFilter> {
        var out:Array<openfl.filters.BitmapFilter> = [];
        var count = u8();
        for (i in 0...count) {
            switch (u8()) {
                case 0:
                    var c = rgba();
                    var blurX = fixed(), blurY = fixed(), angle = fixed(), distance = fixed(), strength = fixed8();
                    var f = u8();
                    out.push(new openfl.filters.DropShadowFilter(distance, angle * 180 / Math.PI, c.rgb, c.alpha, blurX,
                        blurY, strength, f & 0x1F, f & 0x80 != 0, f & 0x40 != 0, f & 0x20 == 0));
                case 1:
                    var blurX = fixed(), blurY = fixed();
                    out.push(new openfl.filters.BlurFilter(blurX, blurY, u8() >> 3));
                case 2:
                    var c = rgba();
                    var blurX = fixed(), blurY = fixed(), strength = fixed8();
                    var f = u8();
                    out.push(new openfl.filters.GlowFilter(c.rgb, c.alpha, blurX, blurY, strength, f & 0x1F,
                        f & 0x80 != 0, f & 0x40 != 0));
                case 3:
                    var shadow = rgba(), highlight = rgba();
                    var blurX = fixed(), blurY = fixed(), angle = fixed(), distance = fixed(), strength = fixed8();
                    var f = u8();
                    var type = f & 0x80 != 0 ? openfl.filters.BitmapFilterType.INNER
                        : f & 0x10 != 0 ? openfl.filters.BitmapFilterType.FULL : openfl.filters.BitmapFilterType.OUTER;
                    out.push(new openfl.filters.BevelFilter(distance, angle * 180 / Math.PI, highlight.rgb,
                        highlight.alpha, shadow.rgb, shadow.alpha, blurX, blurY, strength, f & 0x0F, type, f & 0x40 != 0));
                case 4 | 7:
                    var colors = u8();
                    pos += colors * 5 + 19;
                case 5:
                    var x = u8(), y = u8();
                    var divisor = float(), bias = float();
                    var matrix = [for (k in 0...x * y) float()];
                    var c = rgba();
                    var f = u8();
                    out.push(new openfl.filters.ConvolutionFilter(x, y, matrix, divisor, bias, f & 0x01 != 0,
                        f & 0x02 != 0, c.rgb, c.alpha));
                case 6:
                    out.push(new openfl.filters.ColorMatrixFilter([for (k in 0...20) float()]));
                default: throw "unknown SWF filter";
            }
        }
        return out;
    }

    inline function rgba():{rgb:Int, alpha:Float} {
        var r = u8(), g = u8(), b = u8(), a = u8();
        return {rgb: (r << 16) | (g << 8) | b, alpha: a / 255};
    }

    inline function fixed():Float {
        var v = u32();
        return (v | 0) / 65536.0;
    }

    inline function fixed8():Float {
        return s16() / 256.0;
    }

    inline function float():Float {
        return haxe.io.FPHelper.i32ToFloat(u32());
    }
}
