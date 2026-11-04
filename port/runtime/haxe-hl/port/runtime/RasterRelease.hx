package port.runtime;

import openfl.display.Graphics;

@:access(openfl.display.Graphics)
@:access(openfl.display.DisplayObject)
class RasterRelease {
    public static var fillAntialias:lime.graphics.cairo.CairoAntialias = switch (Sys.getEnv("BH_PORT_CAIRO_AA")) {
        case "subpixel": SUBPIXEL;
        case "good": GOOD;
        case "none": NONE;
        default: FAST;
    };

    public static var additiveFills:Bool = Sys.getEnv("BH_PORT_ADDITIVE_FILLS") != "0";

    public static var fillDx:Float = envFloat("BH_PORT_FILL_DX", fillAntialias == FAST ? 0.125 : 0);
    public static var fillDy:Float = envFloat("BH_PORT_FILL_DY", 0);

    public static var textDx:Float = envFloat("BH_PORT_TEXT_DX", 0);
    public static var textDy:Float = envFloat("BH_PORT_TEXT_DY", 0);

    public static var textSnap:Bool = Sys.getEnv("BH_PORT_TEXT_SNAP") != "0";

    public static function snapText(field:openfl.text.TextField, matrix:openfl.geom.Matrix):Void {
        if (!textSnap || matrix.b != 0 || matrix.c != 0 || !gridFitted(field)) return;
        matrix.tx = Math.fround(matrix.tx);
        matrix.ty = Math.fround(matrix.ty);
    }

    public static function snapPaint(shape:openfl.display.DisplayObject, cairo:lime.graphics.cairo.Cairo):Void {
        if (!textSnap || !Std.isOfType(shape, openfl.text.TextField) || !gridFitted(cast shape)) return;
        var m = cairo.matrix;
        if (m.b != 0 || m.c != 0) return;
        m.tx = Math.fround(m.tx);
        m.ty = Math.fround(m.ty);
        cairo.matrix = m;
    }

    static inline function gridFitted(field:openfl.text.TextField):Bool {
        return field.antiAliasType == openfl.text.AntiAliasType.ADVANCED && field.gridFitType == openfl.text.GridFitType.PIXEL;
    }

    static function envFloat(name:String, otherwise:Float):Float {
        var value = Std.parseFloat(Sys.getEnv(name));
        return Math.isNaN(value) ? otherwise : value;
    }

    public static function shiftFill(cairo:lime.graphics.cairo.Cairo, sign:Float):Void {
        if (fillDx == 0 && fillDy == 0) return;
        var m = cairo.matrix;
        m.tx += sign * fillDx;
        m.ty += sign * fillDy;
        cairo.matrix = m;
    }

    static var depth = 0;
    static var noted:Array<Graphics> = [];
    static var enabled:Null<Bool> = null;

    public static var released(default, null):Int = 0;
    public static var releasedBytes(default, null):Float = 0;
    public static var reused(default, null):Int = 0;
    public static var refitted(default, null):Int = 0;

    static inline var POOL_BYTES = 16 * 1048576;
    static var pool:Array<openfl.display.BitmapData> = [];
    static var pooledBytes = 0;
    static var refit:Null<Bool> = null;

    public static function take(width:Int, height:Int):openfl.display.BitmapData {
        var need = width * height * 4, best = -1, bestBytes = 0;
        if (width > 0 && height > 0) {
            for (i in 0...pool.length) {
                var bitmap = pool[i];
                if (bitmap.width == width && bitmap.height == height) {
                    best = i;
                    bestBytes = -1;
                    break;
                }
                var bytes = capacity(bitmap);
                if (bytes >= need && bytes <= need + (need >> 1) && (best < 0 || bytes < bestBytes)) {
                    best = i;
                    bestBytes = bytes;
                }
            }
        }
        if (best >= 0 && bestBytes >= 0) {
            if (refit == null) refit = Sys.getEnv("BH_PORT_RASTER_REFIT") != "0";
            if (!refit) best = -1;
        }
        if (best < 0) {
            return new openfl.display.BitmapData(width, height, true, 0);
        }
        var bitmap = pool[best];
        pool[best] = pool[pool.length - 1];
        pool.pop();
        pooledBytes -= capacity(bitmap);
        reused++;
        if (bestBytes < 0) {
            return bitmap;
        }
        refitted++;
        var memory = bitmap.image.buffer.data.buffer;
        bitmap.dispose();
        var buffer = new lime.graphics.ImageBuffer(lime.utils.UInt8Array.fromBytes(memory, 0, need), width, height);
        buffer.format = BGRA32;
        buffer.premultiplied = true;
        return openfl.display.BitmapData.fromImage(new lime.graphics.Image(buffer, 0, 0, width, height), true);
    }

    static inline function capacity(bitmap:openfl.display.BitmapData):Int {
        return bitmap.image.buffer.data.buffer.length;
    }

    static function give(bitmap:openfl.display.BitmapData):Void {
        var bytes = bitmap.image == null || bitmap.image.buffer == null || bitmap.image.buffer.data == null ? -1
            : capacity(bitmap);
        if (bytes < 0 || pooledBytes + bytes > POOL_BYTES) {
            bitmap.dispose();
            return;
        }
        pool.push(bitmap);
        pooledBytes += bytes;
    }

    public static inline function begin():Void {
        depth++;
    }

    public static inline function drawing():Bool {
        return depth > 0;
    }

    public static inline function note(graphics:Graphics):Void {
        if (depth > 0) noted.push(graphics);
    }

    public static function end():Void {
        if (--depth > 0) return;
        depth = 0;
        if (enabled == null) enabled = Sys.getEnv("BH_PORT_KEEP_RASTERS") != "1";
        if (enabled) {
            for (graphics in noted) {
                var owner = graphics.__owner;
                if (owner != null && owner.stage != null) continue;
                var bitmap = graphics.__bitmap;
                if (bitmap == null) continue;
                releasedBytes += bitmap.width * bitmap.height * 4.0;
                released++;
                graphics.__cairo = null;
                graphics.__bitmap = null;
                graphics.__dirty = true;
                if (!bitmap.__portShared) give(bitmap);
            }
        }
        noted.resize(0);
    }
}
