package port.runtime.swf;

import port.runtime.swf.SwfFont.FontPart;

class SwfFonts {
    static var parts = new Map<String, Array<FontPart>>();
    static var codes = new Map<String, Map<Int, Bool>>();
    static var exact = new haxe.ds.ObjectMap<Dynamic, Array<Float>>();
    static var shapes = new haxe.ds.ObjectMap<Dynamic, Array<SwfFont.Glyph>>();
    static var byName = new Map<String, openfl.text.Font>();

    public static var layout(default, null) = new Map<String, FontData>();

    public static var built(default, null):Int = 0;
    public static var buildMs(default, null):Float = 0;

    public static var zones(default, null) = new Map<String, Map<Int, Array<Float>>>();

    public static function addZones(name:String, codes:Array<Int>, r:SwfReader):Void {
        var map = zones.get(name);
        if (map == null) zones.set(name, map = new Map());
        inline function f16(h:Int):Float return (h & 1023) * Math.pow(2, ((h >> 10) & 31) - 26);
        r.u16();
        r.u8();
        var i = 0;
        while (r.pos < r.end && i < codes.length) {
            var count = r.u8();
            var values = [];
            for (_ in 0...count) {
                values.push(f16(r.u16()));
                values.push(f16(r.u16()));
            }
            var mask = r.u8() & 3;
            if (mask != 0 && values.length >= 4 && !map.exists(codes[i])) map.set(codes[i], [values[0], values[2]]);
            i++;
        }
    }

    public static function add(name:String, r:SwfReader):Array<Int> {
        var part = try SwfFont.parse(r) catch (_:Dynamic) null;
        if (part == null) return null;
        var known = codes.get(name);
        if (known == null) {
            known = new Map();
            codes.set(name, known);
            parts.set(name, []);
        }
        var adds = false;
        for (code in part.codes) {
            if (!known.exists(code)) {
                known.set(code, true);
                adds = true;
            }
        }
        if (adds) {
            parts.get(name).push(part);
            register(name);
        }
        return part.codes;
    }

    public static function addPart(name:String, part:SwfFont.FontPart):Void {
        var known = new Map<Int, Bool>();
        for (code in part.codes) known.set(code, true);
        codes.set(name, known);
        parts.set(name, [part]);
        register(name);
    }

    static function register(name:String):Void {
        var current = byName.get(name);
        var started = Sys.time();
        var m = SwfFont.merged(name, parts.get(name));
        var first = parts.get(name)[0];
        var data = new FontData(name, first.ascent, first.descent, first.leading, first.bold, first.italic);
        data.ascentEm = first.ascentEm;
        data.descentEm = first.descentEm;
        for (i in 0...m.codes.length) data.index.set(m.codes[i], i);
        data.glyphs = m.glyphs.length > m.codes.length ? m.glyphs.slice(1) : m.glyphs;
        data.advances = m.advances.slice(1);
        layout.set(name, data);
        var font = openfl.text.Font.fromBytes(openfl.utils.ByteArray.fromBytes(m.bytes));
        if (font == null) return;
        font.fontName = name;
        if (current != null) {
            exact.remove(current);
            shapes.remove(current);
        }
        exact.set(font, m.advances);
        shapes.set(font, m.glyphs);
        byName.set(name, font);
        built++;
        buildMs += (Sys.time() - started) * 1000;
    }

    public static function find(name:String):openfl.text.Font {
        return name == null ? null : byName.get(name);
    }

    public static function note(font:Dynamic, advances:Array<Float>, ?glyphs:Array<SwfFont.Glyph>):Void {
        if (font != null && advances != null) exact.set(font, advances);
        if (font != null && glyphs != null) shapes.set(font, glyphs);
    }

    public static inline function outlines(font:Dynamic):Array<SwfFont.Glyph> {
        return font == null ? null : shapes.get(font);
    }

    public static inline function advances(font:Dynamic):Array<Float> {
        return font == null ? null : exact.get(font);
    }

    public static inline function twipAdvance(pixels:Float):Float {
        return Math.ffloor(pixels * 20 + 1e-7) / 20;
    }
}

class FontData {
    public var name:String;
    public var index = new Map<Int, Int>();
    public var glyphs:Array<SwfFont.Glyph> = [];
    public var advances:Array<Float> = [];
    public var ascent:Int;
    public var descent:Int;
    public var leading:Int;
    public var bold:Bool;
    public var italic:Bool;
    public var ascentEm:Float = -1;
    public var descentEm:Float = -1;

    public function new(name, ascent, descent, leading, bold, italic) {
        this.name = name;
        this.ascent = ascent;
        this.descent = descent;
        this.leading = leading;
        this.bold = bold;
        this.italic = italic;
    }
}
