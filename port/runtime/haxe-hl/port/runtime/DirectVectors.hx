package port.runtime;

import lime.graphics.cairo.CairoPattern;
import openfl.display.CairoRenderer;
import openfl.display.DisplayObject;
import openfl.display._internal.DrawCommandReader;
import openfl.display._internal.DrawCommandType;
import openfl.geom.Matrix;

@:access(openfl.display.DisplayObject)
@:access(openfl.display.Graphics)
@:access(openfl.display.CairoRenderer)
@:access(openfl.display._internal.CairoGraphics)
@:access(openfl.display._internal.DrawCommandBuffer)
@:access(openfl.geom.Matrix)
class DirectVectors {
    public static var enabled:Bool = Sys.getEnv("BH_PORT_DIRECT_VECTORS") != "0";
    public static var drawn(default, null):Int = 0;
    public static var fallbacks(default, null):Int = 0;

    static var inverse = new Matrix();

    public static function render(shape:DisplayObject, renderer:CairoRenderer, alpha:Float):Bool {
        if (!enabled || !RasterRelease.drawing()) return false;
        var graphics = shape.__graphics;
        var cairo = renderer.cairo;
        if (graphics == null || cairo == null || !graphics.__visible || graphics.__bounds == null
            || graphics.__bounds.width <= 0 || graphics.__bounds.height <= 0 || shape.__worldScale9Grid != null
            || shape.__scale9Grid != null) return false;
        var commands = graphics.__commands;
        if (commands.types.length == 0) return false;
        for (type in commands.types) {
            switch (type) {
                case BEGIN_FILL | BEGIN_GRADIENT_FILL | BEGIN_BITMAP_FILL | MOVE_TO | LINE_TO | CURVE_TO | CUBIC_CURVE_TO
                    | END_FILL | WINDING_EVEN_ODD | WINDING_NON_ZERO:
                default:
                    fallbacks++;
                    return false;
            }
        }
        var bounds = graphics.__bounds;
        renderer.__setBlendMode(shape.__worldBlendMode);
        renderer.__pushMaskObject(shape);
        var blendOperator = cairo.getOperator();
        cairo.save();
        renderer.applyMatrix(shape.__renderTransform, cairo);
        cairo.newPath();
        cairo.rectangle(bounds.x - 1, bounds.y - 1, bounds.width + 2, bounds.height + 2);
        cairo.clip();
        var groups = graphics.__portGroups;
        var nested = groups != null && groups.length > 1;
        var additive = graphics.__portAdditive && RasterRelease.additiveFills;
        if (nested) cairo.pushGroup();
        inline function beginGroup() {
            cairo.pushGroup();
            RasterRelease.shiftFill(cairo, 1);
            cairo.fillRule = EVEN_ODD;
            cairo.antialias = RasterRelease.fillAntialias;
            cairo.setOperator(additive ? ADD : OVER);
        }
        beginGroup();
        var nextGroup = 1;
        var pattern:CairoPattern = null;
        var hasPath = false;
        var x = 0.0, y = 0.0;
        inline function fill() {
            if (hasPath && pattern != null) {
                cairo.source = pattern;
                cairo.fill();
            }
            cairo.newPath();
            hasPath = false;
        }
        var data = new DrawCommandReader(commands);
        var types = commands.types;
        for (index in 0...types.length) {
            var type = types[index];
            if (nested && nextGroup < groups.length && index == groups[nextGroup]) {
                fill();
                pattern = null;
                cairo.popGroupToSource();
                cairo.setOperator(OVER);
                cairo.paint();
                beginGroup();
                nextGroup++;
            }
            switch (type) {
                case BEGIN_FILL:
                    fill();
                    var c = data.readBeginFill();
                    pattern = c.alpha < 0.005 ? null : CairoPattern.createRGBA(((c.color & 0xFF0000) >>> 16) / 0xFF,
                        ((c.color & 0x00FF00) >>> 8) / 0xFF, (c.color & 0x0000FF) / 0xFF, c.alpha);
                case BEGIN_GRADIENT_FILL:
                    fill();
                    var c = data.readBeginGradientFill();
                    pattern = gradient(c.type, c.colors, c.alphas, c.ratios, c.matrix, c.spreadMethod, c.focalPointRatio);
                case BEGIN_BITMAP_FILL:
                    fill();
                    var c = data.readBeginBitmapFill();
                    if (c.bitmap != null && c.bitmap.readable) {
                        openfl.display._internal.CairoGraphics.allowSmoothing = renderer.__allowSmoothing;
                        pattern = openfl.display._internal.CairoGraphics.createImagePattern(c.bitmap, c.repeat, c.smooth);
                        if (c.matrix != null) {
                            inverse.copyFrom(c.matrix);
                            inverse.invert();
                        } else {
                            inverse.identity();
                        }
                        pattern.matrix = inverse.__toMatrix3();
                    } else {
                        pattern = CairoPattern.createRGB(0, 0, 0);
                    }
                case END_FILL:
                    data.readEndFill();
                    fill();
                    pattern = null;
                case MOVE_TO:
                    var c = data.readMoveTo();
                    cairo.moveTo(x = c.x, y = c.y);
                case LINE_TO:
                    var c = data.readLineTo();
                    cairo.lineTo(x = c.x, y = c.y);
                    hasPath = true;
                case CURVE_TO:
                    var c = data.readCurveTo();
                    cairo.curveTo(x + 2 / 3 * (c.controlX - x), y + 2 / 3 * (c.controlY - y),
                        c.anchorX + 2 / 3 * (c.controlX - c.anchorX), c.anchorY + 2 / 3 * (c.controlY - c.anchorY), c.anchorX,
                        c.anchorY);
                    x = c.anchorX;
                    y = c.anchorY;
                    hasPath = true;
                case CUBIC_CURVE_TO:
                    var c = data.readCubicCurveTo();
                    cairo.curveTo(c.controlX1, c.controlY1, c.controlX2, c.controlY2, x = c.anchorX, y = c.anchorY);
                    hasPath = true;
                case WINDING_EVEN_ODD:
                    data.readWindingEvenOdd();
                    cairo.fillRule = EVEN_ODD;
                case WINDING_NON_ZERO:
                    data.readWindingNonZero();
                    cairo.fillRule = WINDING;
                default:
                    data.skip(type);
            }
        }
        fill();
        data.destroy();
        cairo.popGroupToSource();
        if (nested) {
            cairo.setOperator(OVER);
            cairo.paint();
            cairo.popGroupToSource();
        }
        cairo.setOperator(blendOperator);
        cairo.identityMatrix();
        if (alpha >= 1) cairo.paint() else cairo.paintWithAlpha(alpha);
        cairo.restore();
        renderer.__popMaskObject(shape);
        drawn++;
        return true;
    }

    static function gradient(type:openfl.display.GradientType, colors:Array<Int>, alphas:Array<Float>, ratios:Array<Int>,
            matrix:Matrix, spread:openfl.display.SpreadMethod, focal:Float):CairoPattern {
        var m = matrix != null ? matrix : identity;
        inline function px(x:Float, y:Float):Float return m.a * x + m.c * y + m.tx;
        inline function py(x:Float, y:Float):Float return m.b * x + m.d * y + m.ty;
        var pattern:CairoPattern;
        if (type == RADIAL) {
            focal = focal > 1.0 ? 1.0 : focal < -1.0 ? -1.0 : focal;
            var dx = px(819.2, 0) - px(0, 0), dy = py(819.2, 0) - py(0, 0);
            pattern = CairoPattern.createRadial(px(focal * 819.2, 0), py(focal * 819.2, 0), 0.0, px(0, 0), py(0, 0),
                Math.sqrt(dx * dx + dy * dy));
        } else {
            pattern = CairoPattern.createLinear(px(-819.2, 0), py(-819.2, 0), px(819.2, 0), py(819.2, 0));
        }
        for (i in 0...colors.length) {
            var rgb = colors[i];
            var ratio = ratios[i] / 0xFF;
            pattern.addColorStopRGBA(ratio < 0 ? 0 : ratio > 1 ? 1 : ratio, ((rgb & 0xFF0000) >>> 16) / 0xFF,
                ((rgb & 0x00FF00) >>> 8) / 0xFF, (rgb & 0x0000FF) / 0xFF, alphas[i]);
        }
        pattern.extend = spread == REFLECT ? lime.graphics.cairo.CairoExtend.REFLECT
            : spread == REPEAT ? lime.graphics.cairo.CairoExtend.REPEAT : lime.graphics.cairo.CairoExtend.PAD;
        return pattern;
    }

    static var identity = new Matrix();
}
