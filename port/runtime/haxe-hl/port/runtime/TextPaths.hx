package port.runtime;

import lime.graphics.cairo.Cairo;
import lime.graphics.cairo.CairoGlyph;

class TextPaths {
    public static var mode:String = switch (Sys.getEnv("BH_PORT_TEXT_PATHS")) {
        case null | "": "normal";
        case value: value;
    };
    public static var drawn(default, null):Int = 0;

    public static function show(cairo:Cairo, font:Dynamic, size:Float, glyphs:Array<CairoGlyph>, advanced:Bool):Bool {
        if (mode == "none" || (advanced && mode != "all")) return false;
        var outlines = port.runtime.swf.SwfFonts.outlines(font);
        if (outlines == null) return false;
        var scale = size / port.runtime.swf.SwfFont.UNITS_PER_EM;
        var antialias = cairo.antialias;
        var rule = cairo.fillRule;
        RasterRelease.shiftFill(cairo, 1);
        cairo.newPath();
        for (glyph in glyphs) {
            var index = glyph.index;
            if (index < 0 || index >= outlines.length) continue;
            var ox = glyph.x, oy = glyph.y;
            for (contour in outlines[index].contours) {
                var first = contour[0];
                var cx = ox + first.x * scale, cy = oy - first.y * scale;
                cairo.moveTo(cx, cy);
                var i = 1;
                var n = contour.length;
                while (i <= n) {
                    var p = contour[i % n];
                    if (p.on) {
                        cx = ox + p.x * scale;
                        cy = oy - p.y * scale;
                        cairo.lineTo(cx, cy);
                        i++;
                    } else {
                        var q = contour[(i + 1) % n];
                        var px = ox + p.x * scale, py = oy - p.y * scale;
                        var qx = ox + q.x * scale, qy = oy - q.y * scale;
                        cairo.curveTo(cx + (px - cx) * 2 / 3, cy + (py - cy) * 2 / 3, qx + (px - qx) * 2 / 3,
                            qy + (py - qy) * 2 / 3, qx, qy);
                        cx = qx;
                        cy = qy;
                        i += 2;
                    }
                }
                cairo.closePath();
            }
        }
        cairo.antialias = RasterRelease.fillAntialias;
        cairo.fillRule = WINDING;
        cairo.fill();
        RasterRelease.shiftFill(cairo, -1);
        cairo.antialias = antialias;
        cairo.fillRule = rule;
        drawn++;
        return true;
    }
}
