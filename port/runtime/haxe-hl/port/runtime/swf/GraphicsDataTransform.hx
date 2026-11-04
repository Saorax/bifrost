package port.runtime.swf;

import openfl.Vector;
import openfl.display.GraphicsBitmapFill;
import openfl.display.GraphicsGradientFill;
import openfl.display.GraphicsPath;
import openfl.display.IGraphicsData;
import openfl.geom.Matrix;

class GraphicsDataTransform {
    public static var readAdditive:Bool = false;

    public static var lastAdditiveRead:Dynamic = null;

    public static var reads:Int = 0;
    public static var additiveReads:Int = 0;
    public static var additiveDraws:Int = 0;

    static var readGroups:Array<Int> = [];

    static var lastGroups:Array<Int> = null;

    public static function beginRead():Void {
        readAdditive = true;
        readGroups = [];
    }

    public static function groupAt(index:Int):Void {
        if (readGroups.length == 0 || readGroups[readGroups.length - 1] != index) readGroups.push(index);
    }

    public static function endRead(data:Dynamic):Void {
        reads++;
        if (readAdditive) additiveReads++;
        lastAdditiveRead = readAdditive ? data : null;
        lastGroups = readAdditive ? readGroups : null;
    }

    public static function groupsOf(data:Vector<IGraphicsData>):Array<Int> {
        return same(data) ? lastGroups : null;
    }

    public static function drawsBack(data:Vector<IGraphicsData>):Bool {
        if (!same(data)) return false;
        additiveDraws++;
        return true;
    }

    static function same(data:Vector<IGraphicsData>):Bool {
        if (data == null || lastAdditiveRead == null) return false;
        var read:Vector<IGraphicsData> = lastAdditiveRead;
        if (data.length != read.length) return false;
        for (i in 0...data.length) if (data[i] != read[i]) return false;
        return true;
    }

    public static var calls(default, null):Int = 0;

    public static function apply(data:Vector<IGraphicsData>, start:Int, m:Matrix):Void {
        calls++;
        for (i in start...data.length) {
            var item = data[i];
            if (Std.isOfType(item, GraphicsPath)) {
                var path:GraphicsPath = cast item;
                var coords = path.data;
                if (coords == null) continue;
                var j = 0;
                while (j + 1 < coords.length) {
                    var x = coords[j], y = coords[j + 1];
                    coords[j] = m.a * x + m.c * y + m.tx;
                    coords[j + 1] = m.b * x + m.d * y + m.ty;
                    j += 2;
                }
            } else if (Std.isOfType(item, GraphicsGradientFill)) {
                var fill:GraphicsGradientFill = cast item;
                fill.matrix = concat(fill.matrix, m);
            } else if (Std.isOfType(item, GraphicsBitmapFill)) {
                var fill:GraphicsBitmapFill = cast item;
                fill.matrix = concat(fill.matrix, m);
            }
        }
    }

    static function concat(inner:Matrix, outer:Matrix):Matrix {
        var result = inner != null ? inner.clone() : new Matrix();
        result.concat(outer);
        return result;
    }
}
