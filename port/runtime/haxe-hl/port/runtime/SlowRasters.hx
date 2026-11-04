package port.runtime;

import openfl.display.Graphics;

class SlowRasters {
    static var limit:Float = {
        var value = Std.parseFloat(Sys.getEnv("BH_PORT_SLOW_RASTER_MS"));
        Math.isNaN(value) ? 30 : value;
    };

    public static function render(graphics:Graphics, renderer:openfl.display.CairoRenderer):Void {
        var started = Sys.time();
        @:privateAccess openfl.display._internal.CairoGraphics.render(graphics, renderer);
        var ms = (Sys.time() - started) * 1000;
        if (!RasterRelease.drawing()) {
            var bitmap = @:privateAccess graphics.__bitmap;
            DrawStats.noteRaster(bitmap != null ? bitmap.width * bitmap.height : 0, ms);
        }
        if (ms >= limit) report(graphics, Math.round(ms * 10) / 10, started);
    }

    public static function drawn(source:openfl.display.IBitmapDrawable, target:openfl.display.BitmapData,
            started:Float, ?matrix:openfl.geom.Matrix, ?colorTransform:openfl.geom.ColorTransform):Void {
        var ms = (Sys.time() - started) * 1000;
        DrawStats.note(source, target, matrix, colorTransform, ms);
        if (ms < limit) return;
        var described = Std.isOfType(source, openfl.display.DisplayObject) ? path(cast source)
            : Type.getClassName(Type.getClass(source));
        NativeMain.log("slow draw at " + clock(started) + ": " + Math.round(ms * 10) / 10 + " ms, into " + target.width
            + "x" + target.height + ", " + described);
    }

    static function report(graphics:Graphics, ms:Float, started:Float):Void {
        var bitmap = @:privateAccess graphics.__bitmap;
        var size = bitmap != null ? bitmap.width + "x" + bitmap.height : "none";
        var bounds = @:privateAccess graphics.__bounds;
        NativeMain.log("slow raster at " + clock(started) + ": " + ms + " ms, " + size + " px, "
            + @:privateAccess graphics.__commands.length + " commands, bounds "
            + (bounds != null ? Std.string(bounds) : "null") + ", scale "
            + Math.round(@:privateAccess graphics.__renderTransform.a * 100) / 100 + ", "
            + path(@:privateAccess graphics.__owner));
    }

    static inline function clock(_:Float):Int {
        var stamp = haxe.Timer.stamp();
        return Std.int((stamp % 10000) * 1000);
    }

    static function path(node:openfl.display.DisplayObject):String {
        var parts = [];
        while (node != null && parts.length < 8) {
            parts.push((node.name != null ? node.name : "?") + ":" + Type.getClassName(Type.getClass(node)));
            node = node.parent;
        }
        return parts.join(" < ");
    }
}
