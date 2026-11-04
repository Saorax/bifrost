package port.runtime.swf;

import haxe.io.Bytes;

class SwfInflate {
    public static var workers:Int = {
        var n = Std.parseInt(Sys.getEnv("BH_PORT_SWF_THREADS") ?? "");
        if (n == null) {
            var cpus = Std.parseInt(Sys.getEnv("NUMBER_OF_PROCESSORS") ?? "");
            n = cpus == null ? 2 : cpus - 2;
        }
        n < 0 ? 0 : n > 6 ? 6 : n;
    };
    public static var threaded(default, null):Int = 0;
    public static var workerMs(default, null):Float = 0;
    public static var waitMs(default, null):Float = 0;

    static var jobs:sys.thread.Deque<SwfInflate>;
    static var results:sys.thread.Deque<SwfInflate>;

    public var source(default, null):Bytes;
    public var length(default, null):Int;
    public var body(default, null):Null<Bytes> = null;
    public var done(default, null):Bool = false;

    var out:Bytes;
    var stream:haxe.zip.Uncompress;
    var written = 0;
    var finished = false;
    var seconds = 0.0;

    function new(source:Bytes, length:Int, size:Int) {
        this.source = source;
        this.length = length;
        out = Bytes.alloc(size);
        stream = new haxe.zip.Uncompress();
        stream.setFlushMode(haxe.zip.FlushMode.SYNC);
    }

    static function inflatedSize(bytes:Bytes, length:Int):Int {
        if (length < 8 || bytes.get(0) != "C".code || bytes.get(1) != "W".code || bytes.get(2) != "S".code) return 0;
        return bytes.getInt32(4) - 8;
    }

    public static function now(bytes:Bytes, length:Int):Null<Bytes> {
        var size = inflatedSize(bytes, length);
        if (size <= 0) return null;
        var job = new SwfInflate(bytes, length, size);
        job.run();
        job.land();
        return job.body;
    }

    public static function start(bytes:Bytes, length:Int):Null<SwfInflate> {
        var size = workers > 0 ? inflatedSize(bytes, length) : 0;
        if (size <= 0) return null;
        var job = new SwfInflate(bytes.sub(0, length), length, size);
        if (jobs == null) {
            jobs = new sys.thread.Deque();
            results = new sys.thread.Deque();
            for (_ in 0...workers) sys.thread.Thread.create(work);
        }
        threaded++;
        jobs.add(job);
        return job;
    }

    public static function poll():Void {
        if (results == null) return;
        var job = results.pop(false);
        while (job != null) {
            job.landed();
            job = results.pop(false);
        }
    }

    public function wait():Bool {
        if (!done) {
            var started = Sys.time();
            while (!done) results.pop(true).landed();
            waitMs += (Sys.time() - started) * 1000;
        }
        return true;
    }

    function landed():Void {
        workerMs += seconds * 1000;
        land();
    }

    function land():Void {
        stream.close();
        stream = null;
        if (finished) body = written == out.length ? out : out.sub(0, written);
        out = null;
        done = true;
    }

    static function work():Void {
        while (true) {
            var job = jobs.pop(true);
            job.run();
            results.add(job);
        }
    }

    function run():Void {
        var started = Sys.time();
        var src = source.getData(), dst = out.getData();
        var size = out.length;
        var pos = 8, total = 0, end = false;
        hl.Gc.blocking(true);
        while (!end && total < size) {
            var read = 0, write = 0;
            end = @:privateAccess haxe.zip.Uncompress.inflate_buffer(stream.s, src, pos, length, dst, total, size, read, write);
            pos += read;
            total += write;
            if (read == 0 && write == 0) break;
        }
        hl.Gc.blocking(false);
        written = total;
        finished = end;
        seconds = Sys.time() - started;
    }
}
