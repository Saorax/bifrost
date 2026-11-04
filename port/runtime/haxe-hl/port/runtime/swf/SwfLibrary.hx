package port.runtime.swf;

import haxe.io.Bytes;
import openfl.geom.ColorTransform;
import openfl.geom.Matrix;

class SwfLibrary {
    public var name(default, null):String;
    public var frameRate(default, null):Float;
    public var symbols(default, null):FastStringMap<Int> = new FastStringMap();
    public var tagCount(default, null):Int = 0;

    var body:Bytes;
    var dictionary:FastIntMap<TagRef> = new FastIntMap();
    var sprites:FastIntMap<SpriteDef> = new FastIntMap();
    var texts:FastIntMap<EditTextDef> = new FastIntMap();
    var bounds:FastIntMap<Bounds> = new FastIntMap();
    var fonts:FastIntMap<FontDef> = new FastIntMap();
    var fontCodes:FastIntMap<Array<Int>> = new FastIntMap();
    var textSettings:FastIntMap<TextSettings> = new FastIntMap();

    public static var parseMs(default, null):Float = 0;
    public static var inflateMs(default, null):Float = 0;
    public static var spillMs(default, null):Float = 0;

    public function new(bytes:Bytes, length:Int, ?name:String, ?inflated:Bytes) {
        var start = Sys.time();
        this.name = name;
        var sig = bytes.getString(0, 3);
        if (inflated != null) {
            body = inflated;
        } else if (sig == "CWS") {
            body = inflate(bytes, length);
            inflateMs += (Sys.time() - start) * 1000;
        } else if (sig == "FWS") {
            body = bytes.sub(8, length - 8);
        } else {
            throw "unsupported SWF signature " + sig;
        }
        var r = new SwfReader(body, 0, body.length);
        r.rect();
        frameRate = r.u16() / 256;
        r.u16();
        index(r);
        var spillStart = Sys.time();
        spill();
        spillMs += (Sys.time() - spillStart) * 1000;
        parseMs += (Sys.time() - start) * 1000;
        all.push(this);
    }

    static function inflate(bytes:Bytes, length:Int):Bytes {
        var body = SwfInflate.now(bytes, length);
        return body != null ? body : haxe.zip.Uncompress.run(bytes.sub(8, length - 8), bytes.getInt32(4));
    }

    public function reader(tag:TagRef):SwfReader {
        if (tag.spill >= 0) return new SwfReader(SwfSpill.read(tag.spill, tag.length), 0, tag.length);
        return new SwfReader(body, tag.pos, tag.pos + tag.length);
    }

    function spill():Void {
        var shapes:Array<TagRef> = [];
        for (id in dictionary.keys()) {
            var tag = dictionary.get(id);
            if (tag.code == 2 || tag.code == 22 || tag.code == 32 || tag.code == 83) shapes.push(tag);
        }
        if (shapes.length == 0) return;
        shapes.sort(function(a, b) return a.pos - b.pos);
        var cuts:Array<Int> = [];
        var cutBytes:Array<Int> = [];
        var total = 0;
        for (tag in shapes) {
            var at = SwfSpill.write(body, tag.pos, tag.length);
            if (at < 0) break;
            var r = new SwfReader(body, tag.pos, tag.pos + tag.length);
            var id = r.u16();
            if (bounds.get(id) == null) bounds.set(id, r.rect());
            cuts.push(tag.pos);
            total += tag.length;
            cutBytes.push(total);
            tag.spill = at;
        }
        if (total == 0) return;
        function moved(pos:Int):Int {
            var lo = 0, hi = cuts.length;
            while (lo < hi) {
                var mid = (lo + hi) >> 1;
                if (cuts[mid] < pos) lo = mid + 1; else hi = mid;
            }
            return lo == 0 ? pos : pos - cutBytes[lo - 1];
        }
        var kept = Bytes.alloc(body.length - total);
        var from = 0, to = 0;
        for (i in 0...cuts.length) {
            var length = cuts[i] - from;
            kept.blit(to, body, from, length);
            to += length;
            from = cuts[i] + (cutBytes[i] - (i == 0 ? 0 : cutBytes[i - 1]));
        }
        kept.blit(to, body, from, body.length - from);
        for (id in dictionary.keys()) {
            var tag = dictionary.get(id);
            if (tag.spill < 0) tag.pos = moved(tag.pos);
        }
        if (jpegTables != null) jpegTables.pos = moved(jpegTables.pos);
        for (i in 0...abcBlocks.length) abcBlocks[i] = moved(abcBlocks[i]);
        body = kept;
    }

    public static function bodyBytes():Float {
        var total = 0.0;
        for (library in all) total += library.body.length;
        return total;
    }

    public static function cacheReport():String {
        var sprites = 0, texts = 0, shapes = 0, morphs = 0, bitmaps = 0, palettes = 0, labels = new Map<String, Int>();
        var pixels = 0.0, commandBytes = 0.0, places = 0, templateBitmaps = 0.0;
        for (library in all) {
            for (def in library.sprites) {
                sprites++;
                for (frame in def.frames) places += frame.length;
            }
            for (_ in library.texts) texts++;
            for (template in library.shapeTemplates) {
                shapes++;
                commandBytes += template.bytes;
                var g = template.shape.graphics;
                #if openfl
                @:privateAccess if (g.__bitmap != null) templateBitmaps += g.__bitmap.width * g.__bitmap.height * 4.0;
                #end
            }
            for (_ in library.morphTemplates) morphs++;
            for (b in library.bitmapCache) {
                bitmaps++;
                pixels += b.width * b.height * 4.0;
            }
            if (library.palettes != null) for (_ in library.palettes.keys()) palettes++;
            var label = library.label();
            labels.set(label, (labels.exists(label) ? labels.get(label) : 0) + 1);
        }
        var repeats = 0, repeated:Array<String> = [];
        for (label => n in labels) if (n > 1) {
            repeats += n - 1;
            if (repeated.length < 8) repeated.push(label + " x" + n);
        }
        return "libraries " + all.length + " (" + repeats + " repeat a label" + (repeated.length > 0 ? ": " + repeated.join(", ") : "")
            + "), sprites " + sprites + " (" + places + " frame placements), edit texts " + texts + ", shape templates "
            + shapes + " (commands ~" + Std.int(commandBytes / 1048576) + " MB, rendered bitmaps "
            + Std.int(templateBitmaps / 1048576) + " MB), morph templates " + morphs + ", templates built "
            + templatesBuilt + ", dropped " + templatesDropped + ", built again " + templatesRebuilt + " (budget "
            + Std.int(templateBudget / 1048576) + " MB, held ~" + Std.int(templateBytes / 1048576) + " MB)"
            + ", bitmaps " + bitmaps + " (" + Std.int(pixels / 1048576) + " MB of pixels), palettes " + palettes
            + ", bodies " + Std.int(bodyBytes() / 1048576) + " MB";
    }

    static var useTagBounds:Bool = Sys.getEnv("BH_PORT_SHAPE_TAG_BOUNDS") != "0";

    #if openfl
    @:access(openfl.display.Graphics)
    static function tagBounds(g:openfl.display.Graphics, b:Bounds):Void {
        if (!useTagBounds || b == null || g.__bounds == null || b.xMax <= b.xMin || b.yMax <= b.yMin) return;
        g.__bounds.setTo(b.xMin, b.yMin, b.xMax - b.xMin, b.yMax - b.yMin);
    }

    @:access(openfl.display.Graphics)
    @:access(openfl.display._internal.DrawCommandBuffer)
    static function trim(g:openfl.display.Graphics):Void {
        var c = g.__commands;
        if (c == null || c.types.length == 0) {
            if (c == scratch) g.__commands = new openfl.display._internal.DrawCommandBuffer();
            return;
        }
        if (c == scratch) {
            var own = new openfl.display._internal.DrawCommandBuffer();
            own.types = c.types.copy();
            own.b = c.b.copy();
            own.i = c.i.copy();
            own.f = c.f.copy();
            own.o = c.o.copy();
            own.ff = c.ff.copy();
            own.ii = c.ii.copy();
            own.copyOnWrite = true;
            g.__commands = own;
            return;
        }
        c.types = c.types.copy();
        if (c.b.length > 0) c.b = c.b.copy();
        if (c.i.length > 0) c.i = c.i.copy();
        if (c.f.length > 0) c.f = c.f.copy();
        if (c.o.length > 0) c.o = c.o.copy();
        if (c.ff.length > 0) c.ff = c.ff.copy();
        if (c.ii.length > 0) c.ii = c.ii.copy();
    }

    static var scratch:openfl.display._internal.DrawCommandBuffer;

    @:access(openfl.display.Graphics)
    @:access(openfl.display._internal.DrawCommandBuffer)
    static function useScratch(g:openfl.display.Graphics):Void {
        if (scratch == null) {
            scratch = new openfl.display._internal.DrawCommandBuffer();
            scratch.prepareWrite();
        } else if (scratch.copyOnWrite) {
        } else {
            scratch.types.resize(0);
            scratch.b.resize(0);
            scratch.i.resize(0);
            scratch.f.resize(0);
            scratch.o.resize(0);
            scratch.ff.resize(0);
            scratch.ii.resize(0);
        }
        g.__commands = scratch;
    }

    @:access(openfl.display.Graphics)
    @:access(openfl.display._internal.DrawCommandBuffer)
    static function commandSize(g:openfl.display.Graphics):Float {
        var c = g.__commands;
        if (c == null) return 0;
        var n = c.types.length * 4.0 + c.b.length * 4.0 + c.i.length * 4.0 + c.f.length * 8.0 + c.o.length * 8.0;
        for (a in c.ff) if (a != null) n += a.length * 8.0;
        for (a in c.ii) if (a != null) n += a.length * 4.0;
        return n;
    }
    #else
    static function tagBounds(g:openfl.display.Graphics, b:Bounds):Void {
        if (!useTagBounds || b == null || b.xMax <= b.xMin || b.yMax <= b.yMin) return;
        g.__portSetBounds(b.xMin, b.yMin, b.xMax - b.xMin, b.yMax - b.yMin);
    }
    static function trim(g:openfl.display.Graphics):Void g.__portTrim();
    static function useScratch(g:openfl.display.Graphics):Void {}
    static function commandSize(g:openfl.display.Graphics):Float return g.__portRecordBytes();
    #end

    public static var all(default, null):Array<SwfLibrary> = [];

    static var tagCodes = new FastIntMap<Int>();

    static var tagBytes = new FastIntMap<Float>();

    static final RARE = [46, 84, 11, 33, 6, 21, 35, 36, 20, 90];
    var rareCodes:Array<Int> = [];

    function label():String {
        if (name != null) return name;
        var first:String = null;
        for (k in symbols.keys()) if (first == null || k < first) first = k;
        return first == null ? "(no symbols)" : first;
    }

    public static function census(quick:Bool = false):String {
        var started = Sys.time();
        var shapes = 0, failed = 0, skippedBefore = SwfShape.skippedFills;
        var failures:Array<String> = [];
        var scratch = new openfl.display.Shape();
        if (!quick) for (library in all) {
            for (id in library.dictionary.keys()) {
                var tag = library.dictionary.get(id);
                if (!(tag.code == 2 || tag.code == 22 || tag.code == 32 || tag.code == 83)) continue;
                shapes++;
                try {
                    scratch.graphics.clear();
                    SwfShape.draw(scratch.graphics, library.reader(tag), tag.code,
                        library.bitmap);
                } catch (e:Dynamic) {
                    failed++;
                    if (failures.length < 5) failures.push(library.name + "#" + id + ": " + Std.string(e));
                }
            }
        }
        var morphs = 0, morphsFailed = 0, texts = 0, textsFailed = 0;
        for (library in all) {
            for (id in library.dictionary.keys()) {
                var tag = library.dictionary.get(id);
                if (tag.code == 11 || tag.code == 33) {
                    texts++;
                    try {
                        scratch.graphics.clear();
                        SwfShape.drawText(scratch.graphics, library.reader(tag),
                            tag.code, library.glyph);
                    } catch (e:Dynamic) {
                        textsFailed++;
                        if (failures.length < 5) failures.push(library.name + "#" + id + " (text): " + Std.string(e));
                    }
                    continue;
                }
                if (!(tag.code == 46 || tag.code == 84)) continue;
                morphs++;
                try {
                    for (ratio in [0, 32768, 65535]) {
                        scratch.graphics.clear();
                        SwfShape.drawMorph(scratch.graphics, library.reader(tag),
                            tag.code, ratio, library.bitmap);
                    }
                } catch (e:Dynamic) {
                    morphsFailed++;
                    if (failures.length < 5) failures.push(library.name + "#" + id + " (morph): " + Std.string(e));
                }
            }
        }
        var paletteStart = Sys.time();
        for (library in all) library.palette("");
        var paletteMs = Std.int((Sys.time() - paletteStart) * 1000);
        var counts = new Map<String, Int>();
        var names = [
            46 => "morph shapes", 84 => "morph shapes", 11 => "static texts", 33 => "static texts",
            6 => "bitmaps", 21 => "bitmaps", 35 => "bitmaps", 36 => "bitmaps", 20 => "bitmaps", 90 => "bitmaps",
            14 => "sounds", 18 => "sounds", 19 => "sounds", 60 => "videos", 37 => "edit texts", 39 => "sprites",
            48 => "fonts", 75 => "fonts", 82 => "ABC blocks", 72 => "ABC blocks"
        ];
        var other = 0;
        for (code in tagCodes.keys()) {
            var n = tagCodes.get(code);
            var label = names.get(code);
            if (label == null) {
                other += n;
                continue;
            }
            counts.set(label, (counts.exists(label) ? counts.get(label) : 0) + n);
        }
        var parts = [for (label in counts.keys()) label + " " + counts.get(label)];
        parts.sort(Reflect.compare);
        return all.length + " libraries; shapes " + shapes + " parsed, " + failed + " failed; morph shapes " + morphs
            + " drawn at 3 ratios, " + morphsFailed + " failed; static texts " + texts + " drawn, " + textsFailed
            + " failed; palettes " + AbcPalettes.classesRead + " read ("
            + AbcPalettes.unreadBodies + " frame1 bodies without one, " + paletteErrors + " ABC blocks failed, "
            + paletteMs + " ms)"
            + (failures.length > 0 ? " (" + failures.join("; ") + ")" : "") + ", "
            + (SwfShape.skippedFills - skippedBefore) + " bitmap fills left out (bitmaps decoded " + bitmapsDecoded + ", "
            + bitmapErrors + " failed); tags: " + parts.join(", ")
            + ", other " + other + "; " + Std.int((Sys.time() - started) * 1000) + " ms"
            + "; body MB by tag code: " + [for (code in sortedTagBytes()) code + " " + Std.int(tagBytes.get(code) / 1048576 * 10) / 10].join(", ")
            + "; rare tags (library: codes): "
            + [for (l in all) if (l.rareCodes.length > 0) l.label() + ": " + l.rareCodes.join(" ")].join(", ");
    }

    static function sortedTagBytes():Array<Int> {
        var codes = [for (code in tagBytes.keys()) code];
        codes.sort(function(a, b) return Reflect.compare(tagBytes.get(b), tagBytes.get(a)));
        return codes.slice(0, 10);
    }

    function index(r:SwfReader) {
        while (r.pos < r.end) {
            var tag = r.tagHeader();
            tagCount++;
            var seen = tagCodes.get(tag.code);
            tagCodes.set(tag.code, seen == null ? 1 : seen + 1);
            var size = tagBytes.get(tag.code);
            tagBytes.set(tag.code, (size == null ? 0.0 : size) + tag.length);
            if (RARE.indexOf(tag.code) >= 0) rareCodes.push(tag.code);
            var at = r.pos;
            switch (tag.code) {
                case 0:
                    break;
                case 76:
                    var n = r.u16();
                    for (i in 0...n) {
                        var id = r.u16();
                        symbols.set(r.string(), id);
                    }
                case 82:
                    var sub = new SwfReader(body, at + 4, at + tag.length);
                    sub.string();
                    abcBlocks.push(sub.pos);
                case 72:
                    abcBlocks.push(at);
                case 74:
                    var flags = body.get(at + 2);
                    textSettings.set(body.getUInt16(at), {advanced: ((flags >> 6) & 3) == 1, gridFit: (flags >> 3) & 7,
                        thickness: body.getFloat(at + 3), sharpness: body.getFloat(at + 7)});
                case 8:
                    jpegTables = {code: 8, pos: at, length: tag.length, spill: -1};
                case 2 | 22 | 32 | 83 | 46 | 84 | 11 | 33 | 39 | 37 | 10 | 48 | 75 | 34 | 7 | 6 | 21 | 35 | 90 | 20 | 36:
                    dictionary.set(body.getUInt16(at), {code: tag.code, pos: at, length: tag.length, spill: -1});
                    if (tag.code == 48 || tag.code == 75) readFont(new SwfReader(body, at, at + tag.length));
                    if (tag.code == 75) {
                        var font = fonts.get(body.getUInt16(at));
                        if (font != null) {
                            var codes = SwfFonts.add(font.name, new SwfReader(body, at, at + tag.length));
                            if (codes != null) fontCodes.set(body.getUInt16(at), codes);
                        }
                    }
                case 73:
                    var font = fonts.get(body.getUInt16(at));
                    var codes = fontCodes.get(body.getUInt16(at));
                    if (font != null && codes != null) SwfFonts.addZones(font.name, codes, new SwfReader(body, at, at + tag.length));
                default:
            }
            r.pos = at + tag.length;
        }
    }

    public static function drawHash(limit:Int, placed:Bool = false):String {
        var lines:Array<String> = [];
        var total = 0x811c9dc5, shapes = 0, drawn = 0;
        var drawSeconds = 0.0;
        var shape = new openfl.display.Shape();
        var scales = [1.0, 0.37, 2.3];
        for (library in all) {
            var ids = [for (id in library.dictionary.keys()) id];
            ids.sort((a, b) -> a - b);
            for (id in ids) {
                if (shapes >= limit) break;
                var tag = library.dictionary.get(id);
                if (!(tag.code == 2 || tag.code == 22 || tag.code == 32 || tag.code == 83)) continue;
                shapes++;
                shape.graphics.clear();
                if (placed) {
                    shape = library.shape(id);
                    if (shape == null) {
                        shape = new openfl.display.Shape();
                        continue;
                    }
                } else try {
                    SwfShape.draw(shape.graphics, library.reader(tag), tag.code, library.bitmap);
                } catch (e:Dynamic) {
                    continue;
                }
                var bounds = shape.getBounds(shape);
                if (!(bounds.width > 0 && bounds.height > 0)) continue;
                var hashes = [];
                for (scale in scales) {
                    var width = Std.int(Math.min(1024, Math.ceil(bounds.width * scale) + 2));
                    var height = Std.int(Math.min(1024, Math.ceil(bounds.height * scale) + 2));
                    if (placed) {
                        var again = library.shape(id);
                        if (again != null) shape = again;
                    }
                    var target = new openfl.display.BitmapData(width, height, true, 0);
                    var started = Sys.time();
                    target.draw(shape, new Matrix(scale, 0, 0, scale, 1 - bounds.x * scale, 1 - bounds.y * scale),
                        null, null, null, true);
                    drawSeconds += Sys.time() - started;
                    var hash = 0x811c9dc5;
                    var data = target.image.data;
                    for (i in 0...width * height * 4) {
                        hash = (hash ^ data[i]) * 0x01000193;
                    }
                    target.dispose();
                    hashes.push(StringTools.hex(hash, 8));
                    total = (total ^ hash) * 0x01000193;
                    drawn++;
                }
                lines.push(library.name + "#" + id + " " + hashes.join(" "));
            }
        }
        lines.unshift("drawhash: " + shapes + " shapes, " + drawn + " draws, total " + StringTools.hex(total, 8)
            + ", drawing " + Std.int(drawSeconds * 1000) + " ms");
        return lines.join("\n");
    }

    public static function symbolNames(perLibrary:Int, total:Int):Array<String> {
        var out:Array<String> = [];
        var seen = new FastStringMap<Bool>();
        for (library in all) {
            var names = [for (name in library.symbols.keys())
                if (!seen.exists(name) && library.kindOf(library.symbols.get(name)) == SymbolKind.Sprite) name];
            names.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
            var step = Math.max(1, names.length / perLibrary);
            var i = 0.0;
            while (Std.int(i) < names.length && out.length < 100000) {
                var name = names[Std.int(i)];
                seen.set(name, true);
                out.push(name);
                i += step;
            }
        }
        if (out.length <= total) return out;
        var step = out.length / total;
        return [for (k in 0...total) out[Std.int(k * step)]];
    }

    public static function instantiate(className:String):openfl.display.MovieClip {
        for (library in all) {
            var id = library.symbols.get(className);
            if (id != null && library.kindOf(id) == SymbolKind.Sprite) {
                return openfl.display.MovieClip.fromTimeline(new SwfTimeline(library, library.sprite(id)));
            }
        }
        return null;
    }

    public static function instantiateAll(className:String):Array<{library:String, clip:openfl.display.MovieClip,
            palette:Array<Dynamic>}> {
        var out = [];
        for (library in all) {
            var id = library.symbols.get(className);
            if (id != null && library.kindOf(id) == SymbolKind.Sprite) {
                out.push({library: library.name,
                    clip: openfl.display.MovieClip.fromTimeline(new SwfTimeline(library, library.sprite(id))),
                    palette: library.palette(className)});
            }
        }
        return out;
    }

    var abcBlocks:Array<Int> = [];
    var palettes:FastStringMap<Array<Dynamic>> = null;

    public static var paletteErrors(default, null):Int = 0;

    public function palette(className:String):Array<Dynamic> {
        if (palettes == null) {
            palettes = new FastStringMap();
            for (start in abcBlocks) {
                try {
                    AbcPalettes.read(body, start, palettes);
                } catch (e:Dynamic) {
                    paletteErrors++;
                }
            }
        }
        return palettes.get(className);
    }

    public function hasSymbol(className:String):Bool {
        var id = symbols.get(className);
        if (id == null) return false;
        var kind = kindOf(id);
        return kind == SymbolKind.Sprite || kind == SymbolKind.Font;
    }

    public function fontTrueType(id:Int):{name:String, bytes:Bytes, advances:Array<Float>, glyphs:Array<SwfFont.Glyph>} {
        var tag = dictionary.get(id);
        var font = fonts.get(id);
        if (tag == null || tag.code != 75 || font == null) return null;
        var part = SwfFont.parse(new SwfReader(body, tag.pos, tag.pos + tag.length));
        if (part == null) return null;
        var m = SwfFont.merged(font.name, [part]);
        return {name: font.name, bytes: m.bytes, advances: m.advances, glyphs: m.glyphs};
    }

    public function kindOf(id:Int):SymbolKind {
        var tag = dictionary.get(id);
        if (tag == null) return SymbolKind.Unknown;
        return switch (tag.code) {
            case 39: SymbolKind.Sprite;
            case 37: SymbolKind.EditText;
            case 2 | 22 | 32 | 83 | 46 | 84 | 11 | 33: SymbolKind.Shape;
            case 10 | 48 | 75: SymbolKind.Font;
            default: SymbolKind.Unknown;
        }
    }

    public function sprite(id:Int):SpriteDef {
        var def = sprites.get(id);
        if (def == null) {
            var tag = dictionary.get(id);
            if (tag == null || tag.code != 39) return null;
            def = readSprite(id, new SwfReader(body, tag.pos, tag.pos + tag.length));
            sprites.set(id, def);
        }
        return def;
    }

    public function editText(id:Int):EditTextDef {
        var def = texts.get(id);
        if (def == null) {
            var tag = dictionary.get(id);
            if (tag == null || tag.code != 37) return null;
            def = readEditText(new SwfReader(body, tag.pos, tag.pos + tag.length));
            def.settings = textSettings.get(id);
            texts.set(id, def);
        }
        return def;
    }

    var shapeTemplates:FastIntMap<Template> = new FastIntMap();

    public static var shapeErrors(default, null):Int = 0;

    static var templateBudget:Float = {
        var v = Sys.getEnv("BH_PORT_TEMPLATE_MB");
        var fallback = #if openfl 32.0 #else 128.0 #end;
        var mb = v == null ? fallback : Std.parseFloat(v);
        Math.isNaN(mb) ? fallback * 1048576 : mb * 1048576;
    };
    public static var templateBytes(default, null):Float = 0;
    public static var templatesBuilt(default, null):Int = 0;
    public static var templatesDropped(default, null):Int = 0;
    public static var templatesRebuilt(default, null):Int = 0;
    static var templateClock:Int = 0;
    var droppedTemplates:FastIntMap<Bool> = null;

    function keep(map:FastIntMap<Template>, key:Int, shape:openfl.display.Shape):Template {
        var t = new Template(shape, commandSize(shape.graphics), ++templateClock);
        map.set(key, t);
        templatesBuilt++;
        templateBytes += t.bytes;
        var rebuildKey = map == shapeTemplates ? key : -1 - key;
        if (droppedTemplates != null && droppedTemplates.exists(rebuildKey)) templatesRebuilt++;
        if (templateBudget > 0 && templateBytes > templateBudget) dropTemplates(templateBudget * 0.75);
        return t;
    }

    static function dropTemplates(target:Float):Void {
        var entries:Array<{library:SwfLibrary, morph:Bool, key:Int, t:Template}> = [];
        for (library in all) {
            for (key in library.shapeTemplates.keys())
                entries.push({library: library, morph: false, key: key, t: library.shapeTemplates.get(key)});
            for (key in library.morphTemplates.keys())
                entries.push({library: library, morph: true, key: key, t: library.morphTemplates.get(key)});
        }
        entries.sort((a, b) -> a.t.stamp - b.t.stamp);
        for (e in entries) {
            if (templateBytes <= target) break;
            if (e.morph) e.library.morphTemplates.remove(e.key) else e.library.shapeTemplates.remove(e.key);
            if (e.library.droppedTemplates == null) e.library.droppedTemplates = new FastIntMap();
            e.library.droppedTemplates.set(e.morph ? -1 - e.key : e.key, true);
            templateBytes -= e.t.bytes;
            templatesDropped++;
        }
    }

    public function shape(id:Int):openfl.display.Shape {
        var template = shapeTemplates.get(id);
        if (template == null) {
            var tag = dictionary.get(id);
            if (tag == null || !(tag.code == 2 || tag.code == 22 || tag.code == 32 || tag.code == 83 || tag.code == 11
                || tag.code == 33)) return null;
            var drawn = new openfl.display.Shape();
            useScratch(drawn.graphics);
            try {
                var r = reader(tag);
                if (tag.code == 11 || tag.code == 33) SwfShape.drawText(drawn.graphics, r, tag.code, glyph)
                else SwfShape.draw(drawn.graphics, r, tag.code, bitmap);
            } catch (e:Dynamic) {
                shapeErrors++;
                drawn = null;
            }
            if (drawn == null) return null;
            if (tag.code != 11 && tag.code != 33) tagBounds(drawn.graphics, shapeBounds(id));
            trim(drawn.graphics);
            template = keep(shapeTemplates, id, drawn);
        } else {
            template.stamp = ++templateClock;
        }
        var shape = new openfl.display.Shape();
        shape.graphics.copyFrom(template.shape.graphics);
        return shape;
    }

    public function isMorph(id:Int):Bool {
        var tag = dictionary.get(id);
        return tag != null && (tag.code == 46 || tag.code == 84);
    }

    var morphTemplates:FastIntMap<Template> = new FastIntMap();

    public function drawMorph(id:Int, ratio:Int, g:openfl.display.Graphics):Bool {
        var key = id * 65536 + ratio;
        var template = morphTemplates.get(key);
        if (template == null) {
            var tag = dictionary.get(id);
            if (tag == null || !(tag.code == 46 || tag.code == 84)) return false;
            var drawn = new openfl.display.Shape();
            useScratch(drawn.graphics);
            try {
                SwfShape.drawMorph(drawn.graphics, new SwfReader(body, tag.pos, tag.pos + tag.length), tag.code, ratio,
                    bitmap);
            } catch (e:Dynamic) {
                shapeErrors++;
                return false;
            }
            trim(drawn.graphics);
            template = keep(morphTemplates, key, drawn);
        } else {
            template.stamp = ++templateClock;
        }
        g.clear();
        g.copyFrom(template.shape.graphics);
        return true;
    }

    var glyphTables:FastIntMap<{start:Int, offsets:Array<Int>, em:Float}> = new FastIntMap();

    public function glyph(fontId:Int, index:Int):{reader:SwfReader, em:Float} {
        var table = glyphTables.get(fontId);
        if (table == null) {
            var tag = dictionary.get(fontId);
            if (tag == null || !(tag.code == 10 || tag.code == 48 || tag.code == 75)) return null;
            var r = new SwfReader(body, tag.pos + 2, tag.pos + tag.length);
            var offsets:Array<Int> = [];
            var start:Int;
            if (tag.code == 10) {
                start = r.pos;
                var first = r.u16();
                offsets.push(first);
                for (i in 1...Std.int(first / 2)) offsets.push(r.u16());
            } else {
                var flags = r.u8();
                r.u8();
                r.pos += r.u8();
                var count = r.u16();
                start = r.pos;
                for (i in 0...count) offsets.push(flags & 0x08 != 0 ? r.u32() : r.u16());
            }
            table = {start: start, offsets: offsets, em: tag.code == 75 ? 20480.0 : 1024.0};
            glyphTables.set(fontId, table);
        }
        if (index < 0 || index >= table.offsets.length) return null;
        var tag = dictionary.get(fontId);
        return {reader: new SwfReader(body, table.start + table.offsets[index], tag.pos + tag.length), em: table.em};
    }

    var jpegTables:TagRef = null;
    var bitmapCache:FastIntMap<openfl.display.BitmapData> = new FastIntMap();

    public static var bitmapsDecoded(default, null):Int = 0;
    public static var bitmapErrors(default, null):Int = 0;

    public function bitmap(id:Int):openfl.display.BitmapData {
        var cached = bitmapCache.get(id);
        if (cached != null) return cached;
        var tag = dictionary.get(id);
        if (tag == null) return null;
        var decoded:openfl.display.BitmapData = null;
        try {
            decoded = switch (tag.code) {
                case 6 | 21 | 35 | 90: decodeJpeg(tag);
                case 20 | 36: decodeLossless(tag);
                default: null;
            }
        } catch (e:Dynamic) {
            decoded = null;
        }
        if (decoded == null) {
            bitmapErrors++;
            return null;
        }
        bitmapsDecoded++;
        bitmapCache.set(id, decoded);
        return decoded;
    }

    function jpegBytes(pos:Int, length:Int):Bytes {
        if (length >= 4 && body.get(pos) == 0xff && body.get(pos + 1) == 0xd9 && body.get(pos + 2) == 0xff
            && body.get(pos + 3) == 0xd8) {
            pos += 4;
            length -= 4;
        }
        return body.sub(pos, length);
    }

    function decodeJpeg(tag:TagRef):openfl.display.BitmapData {
        var pos = tag.pos + 2, end = tag.pos + tag.length;
        var alphaOffset = -1;
        if (tag.code == 35 || tag.code == 90) {
            alphaOffset = body.getInt32(pos);
            pos += 4;
            if (tag.code == 90) pos += 2;
        }
        var imageLength = alphaOffset >= 0 ? alphaOffset : end - pos;
        var data = jpegBytes(pos, imageLength);
        if (tag.code == 6 && jpegTables != null && jpegTables.length > 4) {
            var tables = jpegBytes(jpegTables.pos, jpegTables.length);
            var joined = Bytes.alloc(tables.length - 2 + data.length - 2);
            joined.blit(0, tables, 0, tables.length - 2);
            joined.blit(tables.length - 2, data, 2, data.length - 2);
            data = joined;
        }
        #if openfl
        var image = lime.graphics.Image.fromBytes(data);
        if (image == null) return null;
        var bitmapData = openfl.display.BitmapData.fromImage(image, true);
        #else
        var bitmapData = openfl.display.BitmapData.decode(data);
        if (bitmapData == null) return null;
        #end
        if (alphaOffset >= 0 && pos + alphaOffset < end) {
            var alpha = haxe.zip.Uncompress.run(body.sub(pos + alphaOffset, end - pos - alphaOffset));
            var w = bitmapData.width, h = bitmapData.height;
            if (alpha.length >= w * h) {
                var argb = new openfl.utils.ByteArray(w * h * 4);
                var pixels = bitmapData.getPixels(bitmapData.rect);
                for (i in 0...w * h) {
                    argb[i * 4] = alpha.get(i);
                    argb[i * 4 + 1] = pixels[i * 4 + 1];
                    argb[i * 4 + 2] = pixels[i * 4 + 2];
                    argb[i * 4 + 3] = pixels[i * 4 + 3];
                }
                argb.position = 0;
                bitmapData.setPixels(bitmapData.rect, argb);
            }
        }
        return bitmapData;
    }

    function decodeLossless(tag:TagRef):openfl.display.BitmapData {
        var r = new SwfReader(body, tag.pos + 2, tag.pos + tag.length);
        var format = r.u8(), w = r.u16(), h = r.u16();
        var withAlpha = tag.code == 36;
        var paletteSize = format == 3 ? r.u8() + 1 : 0;
        var data = haxe.zip.Uncompress.run(body.sub(r.pos, tag.pos + tag.length - r.pos));
        var argb = new openfl.utils.ByteArray(w * h * 4);
        inline function put(i:Int, a:Int, red:Int, green:Int, blue:Int) {
            if (withAlpha && a > 0 && a < 255) {
                red = Std.int(Math.min(255, red * 255 / a));
                green = Std.int(Math.min(255, green * 255 / a));
                blue = Std.int(Math.min(255, blue * 255 / a));
            }
            argb[i * 4] = a;
            argb[i * 4 + 1] = red;
            argb[i * 4 + 2] = green;
            argb[i * 4 + 3] = blue;
        }
        switch (format) {
            case 3:
                var entry = withAlpha ? 4 : 3;
                var stride = (w + 3) & ~3;
                var base = paletteSize * entry;
                for (y in 0...h) for (x in 0...w) {
                    var k = data.get(base + y * stride + x) * entry;
                    put(y * w + x, withAlpha ? data.get(k + 3) : 255, data.get(k), data.get(k + 1), data.get(k + 2));
                }
            case 4:
                var stride = (w * 2 + 3) & ~3;
                for (y in 0...h) for (x in 0...w) {
                    var v = (data.get(y * stride + x * 2) << 8) | data.get(y * stride + x * 2 + 1);
                    put(y * w + x, 255, ((v >> 10) & 31) * 255 >> 5, ((v >> 5) & 31) * 255 >> 5, (v & 31) * 255 >> 5);
                }
            case 5:
                for (i in 0...w * h) {
                    put(i, withAlpha ? data.get(i * 4) : 255, data.get(i * 4 + 1), data.get(i * 4 + 2), data.get(i * 4 + 3));
                }
            default:
                return null;
        }
        argb.position = 0;
        var bitmapData = new openfl.display.BitmapData(w, h, true, 0);
        bitmapData.setPixels(bitmapData.rect, argb);
        return bitmapData;
    }

    public function shapeBounds(id:Int):Bounds {
        var b = bounds.get(id);
        if (b == null) {
            var tag = dictionary.get(id);
            if (tag == null) return null;
            var r = reader(tag);
            r.u16();
            b = r.rect();
            bounds.set(id, b);
        }
        return b;
    }

    function readFont(r:SwfReader) {
        var id = r.u16();
        var flags = r.u8();
        r.u8();
        var len = r.u8();
        var fontName = r.fixedString(len);
        fonts.set(id, {name: fontName, bold: flags & 1 != 0, italic: flags & 2 != 0});
    }

    function readSprite(id:Int, r:SwfReader):SpriteDef {
        r.u16();
        var frameCount = r.u16();
        var frames:Array<Array<PlaceState>> = [];
        var labels:Array<{name:String, frame:Int}> = [];
        var current = new FastIntMap<PlaceState>();
        var serial = 0;
        while (r.pos < r.end) {
            var tag = r.tagHeader();
            var at = r.pos;
            switch (tag.code) {
                case 0:
                    break;
                case 1:
                    var list = [for (state in current) state];
                    list.sort(function(a, b) return a.depth - b.depth);
                    frames.push(list);
                case 43:
                    labels.push({name: r.string(), frame: frames.length + 1});
                case 26 | 70:
                    var flags = r.u8();
                    var flags2 = tag.code == 70 ? r.u8() : 0;
                    var depth = r.u16();
                    if (flags2 & 0x08 != 0 || (flags2 & 0x10 != 0 && flags & 0x02 != 0)) r.string();
                    var old = current.get(depth);
                    var state:PlaceState;
                    if (flags & 0x02 != 0 && (flags & 0x01 == 0 || old == null || old.charId != r.peekU16())) {
                        state = new PlaceState(depth, r.u16(), ++serial);
                        if (flags & 0x01 != 0 && old != null) {
                            state.matrix = old.matrix;
                            state.colorTransform = old.colorTransform;
                            state.name = old.name;
                        }
                    } else {
                        if (flags & 0x02 != 0) r.u16();
                        if (old == null) {
                            r.pos = at + tag.length;
                            continue;
                        }
                        state = old.copy();
                    }
                    if (flags & 0x04 != 0) state.matrix = r.matrix();
                    if (flags & 0x08 != 0) state.colorTransform = r.colorTransform();
                    if (flags & 0x10 != 0) state.ratio = r.u16();
                    if (flags & 0x20 != 0) state.name = r.string();
                    if (flags & 0x40 != 0) state.clipDepth = r.u16();
                    if (tag.code == 70 && flags & 0x80 == 0) {
                        if (flags2 & 0x01 != 0) state.filters = r.filters();
                        if (flags2 & 0x02 != 0) state.blendMode = r.u8();
                        if (flags2 & 0x04 != 0) r.u8();
                        if (flags2 & 0x20 != 0) state.visible = r.u8() != 0 ? 1 : 0;
                    }
                    current.set(depth, state);
                case 28:
                    current.remove(r.u16());
                case 5:
                    r.u16();
                    current.remove(r.u16());
                default:
            }
            r.pos = at + tag.length;
        }
        while (frames.length < frameCount) frames.push(frames.length > 0 ? frames[frames.length - 1] : []);
        return {id: id, frames: frames, labels: labels};
    }

    function readEditText(r:SwfReader):EditTextDef {
        var def = new EditTextDef();
        r.u16();
        def.bounds = r.rect();
        var f1 = r.u8();
        var f2 = r.u8();
        def.wordWrap = f1 & 0x40 != 0;
        def.multiline = f1 & 0x20 != 0;
        def.password = f1 & 0x10 != 0;
        def.readOnly = f1 & 0x08 != 0;
        def.autoSize = f2 & 0x40 != 0;
        def.noSelect = f2 & 0x10 != 0;
        def.border = f2 & 0x08 != 0;
        def.html = f2 & 0x02 != 0;
        def.useOutlines = f2 & 0x01 != 0;
        if (f1 & 0x01 != 0) {
            var font = fonts.get(r.u16());
            if (font != null) {
                def.font = font.name;
                def.bold = font.bold;
                def.italic = font.italic;
            }
        }
        if (f2 & 0x80 != 0) def.font = r.string();
        if (f1 & 0x01 != 0 || f2 & 0x80 != 0) def.size = r.u16() / 20;
        if (f1 & 0x04 != 0) {
            var red = r.u8(), green = r.u8(), blue = r.u8();
            r.u8();
            def.color = (red << 16) | (green << 8) | blue;
        }
        if (f1 & 0x02 != 0) def.maxChars = r.u16();
        if (f2 & 0x20 != 0) {
            def.align = r.u8();
            def.leftMargin = r.u16() / 20;
            def.rightMargin = r.u16() / 20;
            def.indent = r.u16() / 20;
            def.leading = r.s16() / 20;
        }
        r.string();
        if (f1 & 0x80 != 0) def.text = r.string();
        return def;
    }
}

enum SymbolKind {
    Sprite;
    EditText;
    Shape;
    Font;
    Unknown;
}

typedef TagRef = {code:Int, pos:Int, length:Int, spill:Int};

class Template {
    public var shape(default, null):openfl.display.Shape;
    public var bytes(default, null):Float;
    public var stamp:Int;

    public function new(shape:openfl.display.Shape, bytes:Float, stamp:Int) {
        this.shape = shape;
        this.bytes = bytes;
        this.stamp = stamp;
    }
}
typedef Bounds = {xMin:Float, yMin:Float, xMax:Float, yMax:Float};
typedef FontDef = {name:String, bold:Bool, italic:Bool};
typedef SpriteDef = {id:Int, frames:Array<Array<PlaceState>>, labels:Array<{name:String, frame:Int}>};

class PlaceState {
    public var depth:Int;
    public var charId:Int;
    public var serial:Int;
    public var matrix:Matrix;
    public var colorTransform:ColorTransform;
    public var ratio:Int = 0;
    public var name:String;
    public var clipDepth:Int = 0;
    public var blendMode:Int = 0;
    public var filters:Array<openfl.filters.BitmapFilter>;
    public var visible:Int = -1;

    public function new(depth:Int, charId:Int, serial:Int) {
        this.depth = depth;
        this.charId = charId;
        this.serial = serial;
    }

    public function copy():PlaceState {
        var s = new PlaceState(depth, charId, serial);
        s.matrix = matrix;
        s.colorTransform = colorTransform;
        s.ratio = ratio;
        s.name = name;
        s.filters = filters;
        s.clipDepth = clipDepth;
        s.blendMode = blendMode;
        s.visible = visible;
        return s;
    }
}

class EditTextDef {
    public var bounds:Bounds;
    public var wordWrap = false;
    public var multiline = false;
    public var password = false;
    public var readOnly = false;
    public var autoSize = false;
    public var noSelect = false;
    public var border = false;
    public var html = false;
    public var useOutlines = false;
    public var font:String;
    public var bold = false;
    public var italic = false;
    public var size:Float = 12;
    public var color:Int = 0;
    public var maxChars:Int = 0;
    public var align:Int = 0;
    public var leftMargin:Float = 0;
    public var rightMargin:Float = 0;
    public var indent:Float = 0;
    public var leading:Float = 0;
    public var text:String;
    public var settings:TextSettings;

    public function new() {}
}

typedef TextSettings = {advanced:Bool, gridFit:Int, thickness:Float, sharpness:Float};
