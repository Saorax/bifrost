package port.engine;

class ImageDecoder {
	public static var workers:Int = {
		var n = Std.parseInt(Sys.getEnv("BH_PORT_DECODE_THREADS"));
		n == null || n < 0 ? 0 : n;
	};
	public static var threaded(default, null):Int = 0;

	static var jobs:sys.thread.Deque<ImageJob>;
	static var results:sys.thread.Deque<ImageJob>;

	public static function start(bytes:haxe.io.Bytes, png:Bool, width:Int, height:Int):ImageJob {
		var job = new ImageJob(bytes, png, width, height);
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
			job.done = true;
			job = results.pop(false);
		}
	}

	static function work():Void {
		while (true) {
			var job = jobs.pop(true);
			var data = job.bytes.getData(), out = job.out.getData();
			var length = job.bytes.length, w = job.width, h = job.height;
			hl.Gc.blocking(true);
			var ok = job.png
				? hl.Format.decodePNG(data, length, out, w, h, w * 4, hl.Format.PixelFormat.BGRA, 0)
				: hl.Format.decodeJPG(data, length, out, w, h, w * 4, hl.Format.PixelFormat.BGRA, 0);
			hl.Gc.blocking(false);
			job.ok = ok;
			results.add(job);
		}
	}
}

class ImageJob {
	public var bytes(default, null):haxe.io.Bytes;
	public var out(default, null):haxe.io.Bytes;
	public var png(default, null):Bool;
	public var width(default, null):Int;
	public var height(default, null):Int;
	public var ok:Bool = false;
	public var done:Bool = false;

	public function new(bytes:haxe.io.Bytes, png:Bool, width:Int, height:Int) {
		this.bytes = bytes;
		this.png = png;
		this.width = width;
		this.height = height;
		out = haxe.io.Bytes.alloc(width * height * 4);
	}
}
