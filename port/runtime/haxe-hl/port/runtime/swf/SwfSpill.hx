package port.runtime.swf;

import haxe.io.Bytes;

class SwfSpill {
    public static var bytesSpilled(default, null):Float = 0;
    public static var reads(default, null):Int = 0;
    public static var waitMs(default, null):Float = 0;

    static inline var FLUSH_BYTES = 8 << 20;

    static var out:sys.io.FileOutput = null;
    static var input:sys.io.FileInput = null;
    static var size:Int = 0;
    static var state = 0;
    static var queue:sys.thread.Deque<SpillChunk>;
    static var lost:sys.thread.Deque<SpillChunk>;
    static var held:Map<Int, Bytes> = new Map();
    static var mutex:sys.thread.Mutex;
    static var durable = 0;

    public static function write(body:Bytes, pos:Int, length:Int):Int {
        if (state == 0) open();
        if (state != 1 || size + length < size) return -1;
        var at = size;
        size += length;
        bytesSpilled += length;
        queue.add(new SpillChunk(body, pos, length, at));
        return at;
    }

    public static function read(at:Int, length:Int):Bytes {
        if (durableTo() < at + length) {
            var started = Sys.time();
            while (durableTo() < at + length) Sys.sleep(0.0005);
            waitMs += (Sys.time() - started) * 1000;
        }
        var chunk = lost.pop(false);
        while (chunk != null) {
            held.set(chunk.at, chunk.body);
            chunk = lost.pop(false);
        }
        reads++;
        var kept = held.get(at);
        if (kept != null) return kept;
        if (input == null) input = sys.io.File.read(path, true);
        input.seek(at, sys.io.FileSeek.SeekBegin);
        var bytes = Bytes.alloc(length);
        input.readFullBytes(bytes, 0, length);
        return bytes;
    }

    static function durableTo():Int {
        mutex.acquire();
        var to = durable;
        mutex.release();
        return to;
    }

    static function work():Void {
        var failed = false, unflushed = 0, end = 0;
        while (true) {
            var chunk = queue.pop(false);
            if (chunk == null) {
                if (unflushed > 0 && !failed) failed = !flushed();
                unflushed = 0;
                publish(end);
                chunk = queue.pop(true);
            }
            if (!failed) {
                try {
                    out.writeBytes(chunk.body, chunk.pos, chunk.length);
                } catch (e:Dynamic) {
                    failed = true;
                }
            }
            if (failed) lost.add(new SpillChunk(chunk.body.sub(chunk.pos, chunk.length), 0, chunk.length, chunk.at));
            end = chunk.at + chunk.length;
            unflushed += chunk.length;
            if (unflushed >= FLUSH_BYTES) {
                if (!failed) failed = !flushed();
                unflushed = 0;
                publish(end);
            }
        }
    }

    static function flushed():Bool {
        return try {
            out.flush();
            true;
        } catch (e:Dynamic) false;
    }

    static function publish(end:Int):Void {
        mutex.acquire();
        durable = end;
        mutex.release();
    }

    static var path:String;

    static function open():Void {
        state = -1;
        if (Sys.getEnv("BH_PORT_SPILL") == "0") return;
        try {
            var dir = haxe.io.Path.join([port.runtime.services.Launch.storageDirectory(), "BhPort", "Cache"]);
            sys.FileSystem.createDirectory(dir);
            for (name in sys.FileSystem.readDirectory(dir)) {
                if (StringTools.startsWith(name, "swf-shapes-")) {
                    try sys.FileSystem.deleteFile(haxe.io.Path.join([dir, name])) catch (e:Dynamic) {}
                }
            }
            path = haxe.io.Path.join([dir, "swf-shapes-" + Std.string(Math.ffloor(Sys.time())) + "-" + Std.random(1000000) + ".bin"]);
            out = sys.io.File.write(path, true);
            queue = new sys.thread.Deque();
            lost = new sys.thread.Deque();
            mutex = new sys.thread.Mutex();
            sys.thread.Thread.create(work);
            state = 1;
        } catch (e:Dynamic) {
            out = null;
        }
    }
}

class SpillChunk {
    public var body(default, null):Bytes;
    public var pos(default, null):Int;
    public var length(default, null):Int;
    public var at(default, null):Int;

    public function new(body:Bytes, pos:Int, length:Int, at:Int) {
        this.body = body;
        this.pos = pos;
        this.length = length;
        this.at = at;
    }
}
