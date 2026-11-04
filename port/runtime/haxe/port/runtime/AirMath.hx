package port.runtime;

#if hl
@:dce class AirMath {
    @:hlNative("bhsound", "math1") public static function math1(op:Int, x:Float):Float return 0.0;

    @:hlNative("bhsound", "math2") public static function math2(op:Int, x:Float, y:Float):Float return 0.0;

    public static function pow(x:Float, y:Float):Float {
        if (Math.isNaN(y))
            return y;
        if (y == 0)
            return 1.0;
        if (!Math.isFinite(y) && Math.abs(x) == 1)
            return Math.NaN;
        if (y == Math.ffloor(y) && Math.abs(y) < 2147483648.0) {
            var n = Std.int(Math.abs(y));
            var negative = y < 0;
            var base = x;
            var value = 1.0;
            while (n != 0) {
                if ((n & 1) != 0) {
                    if (negative)
                        value /= base;
                    else
                        value *= base;
                }
                n >>>= 1;
                if (n != 0)
                    base *= base;
            }
            return value;
        }
        return math2(1, x, y);
    }
}
#end
