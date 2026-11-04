package port.runtime.swf;

import openfl.display.MovieClip;
import openfl.system.ApplicationDomain;

class SymbolClass extends hl.BaseType.Class {
    public var library(default, null):SwfLibrary;
    public var charId(default, null):Int;

    public function new(library:SwfLibrary, charId:Int, className:String) {
        var base:hl.BaseType.Class = cast MovieClip;
        __type__ = base.__type__;
        __constructor__ = base.__constructor__;
        __meta__ = null;
        __implementedBy__ = null;
        __name__ = className;
        this.library = library;
        this.charId = charId;
    }

    public static var palettesSet(default, null):Int = 0;

    public function create():MovieClip {
        var clip = MovieClip.fromTimeline(new SwfTimeline(library, library.sprite(charId)));
        var palette = library.palette(__name__);
        if (palette != null) {
            port.runtime.As3.dyn(clip).a = palette.copy();
            palettesSet++;
        }
        return clip;
    }

    var font:openfl.text.Font;

    public function createFont():openfl.text.Font {
        if (font == null && library.kindOf(charId) == SwfLibrary.SymbolKind.Font) {
            var data = library.fontTrueType(charId);
            if (data != null) {
                font = openfl.text.Font.fromBytes(openfl.utils.ByteArray.fromBytes(data.bytes));
                if (font != null) {
                    font.fontName = data.name;
                    SwfFonts.note(font, data.advances, data.glyphs);
                }
            }
        }
        return font;
    }
}

class SwfSymbols {
    static var domains:Array<{domain:ApplicationDomain, classes:FastStringMap<SymbolClass>}> = [];

    public static var registered(default, null):Int = 0;

    public static function domainCount():Int {
        return domains.length;
    }

    public static function register(domain:ApplicationDomain, library:SwfLibrary):Int {
        var classes = classesOf(domain, true);
        var count = 0;
        for (name => id in library.symbols) {
            if (!library.hasSymbol(name)) continue;
            if (!classes.exists(name)) {
                classes.set(name, new SymbolClass(library, id, name));
                count++;
            }
        }
        registered += count;
        return count;
    }

    static function classesOf(domain:ApplicationDomain, create:Bool):FastStringMap<SymbolClass> {
        for (entry in domains) {
            if (entry.domain == domain) return entry.classes;
        }
        if (!create) return null;
        var classes = new FastStringMap<SymbolClass>();
        domains.push({domain: domain, classes: classes});
        return classes;
    }

    public static function find(domain:ApplicationDomain, name:String):SymbolClass {
        if (domain == null) return null;
        var inherited = find(domain.parentDomain == domain ? null : domain.parentDomain, name);
        if (inherited != null) return inherited;
        var classes = classesOf(domain, false);
        return classes == null ? null : classes.get(name);
    }

    public static var fonts(default, null):Int = 0;
    public static var fontMs(default, null):Float = 0;

    public static function fontOf(font:Dynamic):Dynamic {
        if (Std.isOfType(font, SymbolClass)) {
            var start = Sys.time();
            var instance = (font : SymbolClass).createFont();
            fontMs += (Sys.time() - start) * 1000;
            if (instance != null) fonts++;
            return instance;
        }
        return font;
    }

    public static function resolve(domain:ApplicationDomain, name:String):Class<Dynamic> {
        var symbol = find(domain, name);
        if (symbol != null) return cast symbol;
        return Type.resolveClass(name);
    }
}
