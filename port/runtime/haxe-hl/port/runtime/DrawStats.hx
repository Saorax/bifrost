package port.runtime;

class DrawStats {
    static var count:Int = 0;
    static var totalMs:Float = 0;
    static var repeats:Int = 0;
    static var repeatMs:Float = 0;
    static var buckets:Array<Int> = [0, 0, 0, 0, 0];
    static var bucketMs:Array<Float> = [0, 0, 0, 0, 0];
    static var keys:Map<String, KeyStat> = new Map();
    static var rasters:Int = 0;
    static var rasterMs:Float = 0;
    static var rasterPixels:Float = 0;

    public static function noteRaster(pixels:Int, ms:Float):Void {
        rasters++;
        rasterMs += ms;
        rasterPixels += pixels;
    }

    public static function note(source:openfl.display.IBitmapDrawable, target:openfl.display.BitmapData,
            matrix:openfl.geom.Matrix, colorTransform:openfl.geom.ColorTransform, ms:Float):Void {
        count++;
        totalMs += ms;
        var bucket = ms < 1 ? 0 : ms < 5 ? 1 : ms < 20 ? 2 : ms < 50 ? 3 : 4;
        buckets[bucket]++;
        bucketMs[bucket] += ms;
        var key = Type.getClassName(Type.getClass(source));
        if (Std.isOfType(source, openfl.display.MovieClip)) key += "@" + (cast source:openfl.display.MovieClip).currentFrame;
        if (matrix != null) key += " m" + r(matrix.a) + "," + r(matrix.b) + "," + r(matrix.c) + "," + r(matrix.d) + ","
            + r(matrix.tx) + "," + r(matrix.ty);
        if (colorTransform != null) key += " c" + r(colorTransform.redMultiplier) + "," + r(colorTransform.greenMultiplier)
            + "," + r(colorTransform.blueMultiplier) + "," + r(colorTransform.alphaMultiplier) + ","
            + r(colorTransform.redOffset) + "," + r(colorTransform.greenOffset) + "," + r(colorTransform.blueOffset);
        key += " " + target.width + "x" + target.height;
        var stat = keys.get(key);
        if (stat == null) {
            keys.set(key, {draws: 1, ms: ms, pixels: target.width * target.height});
        } else {
            stat.draws++;
            stat.ms += ms;
            repeats++;
            repeatMs += ms;
        }
    }

    static inline function r(value:Float):Float {
        return Math.round(value * 1000) / 1000;
    }

    static inline function f1(value:Float):Float {
        return Math.round(value * 10) / 10;
    }

    public static function report(tag:String):String {
        var top = [for (key => stat in keys) {key: key, stat: stat}];
        top.sort((a, b) -> a.stat.ms > b.stat.ms ? -1 : a.stat.ms < b.stat.ms ? 1 : 0);
        var lines = ["draws " + tag + ": " + count + " draws, " + f1(totalMs) + " ms, distinct " + Lambda.count(keys)
            + ", repeats " + repeats + " (" + f1(repeatMs) + " ms), by time <1/1-5/5-20/20-50/50+ ms: "
            + [for (i in 0...5) buckets[i] + " (" + f1(bucketMs[i]) + " ms)"].join(" / ") + "; on-stage rasters " + rasters
            + " (" + f1(rasterMs) + " ms, " + Math.round(rasterPixels / 1000) + " kpx)"];
        for (i in 0...Std.int(Math.min(10, top.length)))
            lines.push("draws " + tag + " top: " + top[i].stat.draws + "x, " + f1(top[i].stat.ms) + " ms, "
                + top[i].stat.pixels + " px, " + top[i].key);
        count = 0;
        totalMs = 0;
        repeats = 0;
        repeatMs = 0;
        buckets = [0, 0, 0, 0, 0];
        bucketMs = [0, 0, 0, 0, 0];
        keys = new Map();
        rasters = 0;
        rasterMs = 0;
        rasterPixels = 0;
        return lines.join("\n");
    }
}

private typedef KeyStat = {draws:Int, ms:Float, pixels:Int};
