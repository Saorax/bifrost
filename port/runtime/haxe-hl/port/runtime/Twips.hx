package port.runtime;

class Twips {
    public static inline function edge(v:Float):Float {
        return Math.round(v * 20) / 20;
    }

    public static function snap(r:openfl.geom.Rectangle):openfl.geom.Rectangle {
        if (r.width == 0 && r.height == 0) return r;
        var left = edge(r.x), top = edge(r.y), right = edge(r.x + r.width), bottom = edge(r.y + r.height);
        r.setTo(left, top, right - left, bottom - top);
        return r;
    }
}
