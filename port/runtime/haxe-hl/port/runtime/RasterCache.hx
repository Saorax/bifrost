package port.runtime;

import openfl.display.BitmapData;
import openfl.display.Graphics;

@:access(openfl.display.Graphics)
@:access(openfl.display.BitmapData)
@:access(openfl.display.DisplayObject)
@:access(openfl.display._internal.DrawCommandBuffer)
class RasterCache {
    public static var hits(default, null):Int = 0;
    public static var cacheBitmapDepth:Int = 0;
    static var cacheBitmapOnly:Bool = Sys.getEnv("BH_PORT_RASTER_CACHE_SCOPE") == "cachebitmap";
    public static var skippedScope(default, null):Int = 0;
    public static var stored(default, null):Int = 0;
    public static var evicted(default, null):Int = 0;
    public static var heldBytes(default, null):Float = 0;
    public static var skippedDraw(default, null):Int = 0;
    public static var skippedOffStage(default, null):Int = 0;
    public static var skippedCheap(default, null):Int = 0;

    static var minSeconds:Float = -1;
    static var started:Float = 0;
    static var startedFor:Graphics = null;

    static var budget:Float = -1;
    static var entries = new haxe.ds.ObjectMap<{}, Array<Entry>>();
    static var queue:Array<Entry> = [];
    static var head = 0;
    static var seen = new haxe.ds.ObjectMap<{}, Array<Entry>>();
    static var seenCount = 0;
    static inline var SEEN_LIMIT = 8192;

    static inline function enabled():Bool {
        if (budget < 0) {
            var mb = Sys.getEnv("BH_PORT_RASTER_CACHE_MB");
            var value = mb == null ? 0.0 : Std.parseFloat(mb);
            budget = Math.isNaN(value) || value < 0 ? 0 : value * 1048576;
        }
        return budget > 0;
    }

    static inline function cacheable(graphics:Graphics, hasScale9Grid:Bool):Bool {
        var commands = graphics.__commands;
        return !hasScale9Grid && commands.copyOnWrite && commands.length > 0 && graphics.__visible
            && graphics.__bounds != null && graphics.__width >= 1 && graphics.__height >= 1
            && (graphics.__owner == null || !graphics.__owner.__isMask);
    }

    static function find(list:Array<Entry>, graphics:Graphics, smooth:Bool):Entry {
        if (list == null) return null;
        var t = graphics.__renderTransform;
        for (e in list) {
            if (e.a == t.a && e.d == t.d && e.tx == t.tx && e.ty == t.ty && e.width == graphics.__width
                && e.height == graphics.__height && e.smooth == smooth && e.b == t.b && e.c == t.c)
                return e;
        }
        return null;
    }

    public static function lookup(graphics:Graphics, hasScale9Grid:Bool, smooth:Bool):Bool {
        if (!enabled() || !cacheable(graphics, hasScale9Grid)) return false;
        var e = find(entries.get(graphics.__commands.types), graphics, smooth);
        if (e == null) {
            startedFor = graphics;
            started = Sys.time();
            return false;
        }
        hits++;
        if (e.queued < 4) {
            e.queued++;
            queue.push(e);
        }
        graphics.__cairo = null;
        graphics.__bitmap = e.bitmap;
        graphics.__softwareDirty = false;
        graphics.__dirty = false;
        return true;
    }

    public static function store(graphics:Graphics, hasScale9Grid:Bool, smooth:Bool):Void {
        if (!enabled() || graphics.__bitmap == null || !cacheable(graphics, hasScale9Grid)) return;
        var timed = startedFor == graphics;
        startedFor = null;
        if (cacheBitmapOnly && cacheBitmapDepth <= 0) {
            skippedScope++;
            return;
        }
        if (RasterRelease.drawing()) {
            skippedDraw++;
            return;
        }
        if (graphics.__owner == null || graphics.__owner.stage == null) {
            skippedOffStage++;
            return;
        }
        if (minSeconds < 0) {
            var ms = Sys.getEnv("BH_PORT_RASTER_CACHE_MIN_MS");
            var value = ms == null ? 0.25 : Std.parseFloat(ms);
            minSeconds = Math.isNaN(value) || value < 0 ? 0 : value / 1000;
        }
        if (!timed || Sys.time() - started < minSeconds) {
            skippedCheap++;
            return;
        }
        var types:{} = graphics.__commands.types;
        var t = graphics.__renderTransform;
        var list = seen.get(types);
        if (find(list, graphics, smooth) == null) {
            if (list == null) {
                if (seenCount >= SEEN_LIMIT) {
                    seen = new haxe.ds.ObjectMap();
                    seenCount = 0;
                }
                list = [];
                seen.set(types, list);
                seenCount++;
            }
            if (list.length < 8) list.push(new Entry(types, t.a, t.b, t.c, t.d, t.tx, t.ty, graphics.__width,
                graphics.__height, smooth, null));
            return;
        }
        var bitmap = graphics.__bitmap;
        bitmap.__portShared = true;
        graphics.__cairo = null;
        var e = new Entry(types, t.a, t.b, t.c, t.d, t.tx, t.ty, graphics.__width, graphics.__height, smooth, bitmap);
        var held = entries.get(types);
        if (held == null) {
            held = [];
            entries.set(types, held);
        }
        held.push(e);
        e.queued = 1;
        queue.push(e);
        heldBytes += e.bytes;
        stored++;
        while (heldBytes > budget && head < queue.length) {
            var old = queue[head];
            queue[head++] = null;
            if (--old.queued > 0) continue;
            var list = entries.get(old.types);
            if (list != null) {
                list.remove(old);
                if (list.length == 0) entries.remove(old.types);
            }
            heldBytes -= old.bytes;
            evicted++;
        }
        if (head > 4096 && head * 2 > queue.length) {
            queue = queue.slice(head);
            head = 0;
        }
    }

    public static function census():String {
        return 'raster cache: hits $hits, stored $stored, evicted $evicted, held ${Math.round(heldBytes / 1048576)} MB'
            + ', not offered: in a draw $skippedDraw, off the stage $skippedOffStage, cheap $skippedCheap, out of scope $skippedScope';
    }
}

private class Entry {
    public var types:{};
    public var a:Float;
    public var b:Float;
    public var c:Float;
    public var d:Float;
    public var tx:Float;
    public var ty:Float;
    public var width:Int;
    public var height:Int;
    public var smooth:Bool;
    public var bitmap:BitmapData;
    public var bytes:Float;
    public var queued = 0;

    public function new(types:{}, a:Float, b:Float, c:Float, d:Float, tx:Float, ty:Float, width:Int, height:Int,
            smooth:Bool, bitmap:BitmapData) {
        this.types = types;
        this.a = a;
        this.b = b;
        this.c = c;
        this.d = d;
        this.tx = tx;
        this.ty = ty;
        this.width = width;
        this.height = height;
        this.smooth = smooth;
        this.bitmap = bitmap;
        bytes = bitmap == null ? 0 : bitmap.width * bitmap.height * 4.0;
    }
}
