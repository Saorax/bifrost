package port.engine;

class BootLog {
	public static var path:String = null;

	#if (hl && target.threaded)
	static var queue:sys.thread.Deque<String> = null;
	static var pending:Int = 0;
	static var lock = new sys.thread.Mutex();
	#end

	public static function log(text:String):Void {
		var line = DateTools.format(Date.now(), "%Y-%m-%d %H:%M:%S") + " " + text;
		#if (hl && target.threaded)
		if (path != null) {
			if (queue == null) start();
			lock.acquire();
			pending++;
			lock.release();
			queue.add(line);
			return;
		}
		#end
		write(line, null);
	}

	public static function flush(seconds:Float = 2.0):Void {
		#if (hl && target.threaded)
		var until = Sys.time() + seconds;
		while (queue != null && Sys.time() < until) {
			lock.acquire();
			var left = pending;
			lock.release();
			if (left == 0) break;
			Sys.sleep(0.002);
		}
		#end
	}

	static function write(line:String, out:sys.io.FileOutput):sys.io.FileOutput {
		Sys.println(line);
		if (path == null) return out;
		try {
			if (out == null) {
				var once = sys.io.File.append(path, false);
				once.writeString(line + "\n");
				once.close();
				return null;
			}
			out.writeString(line + "\n");
			out.flush();
		} catch (_:Dynamic) {}
		return out;
	}

	#if (hl && target.threaded)
	static function start():Void {
		queue = new sys.thread.Deque<String>();
		var file = path;
		sys.thread.Thread.create(() -> {
			var out:sys.io.FileOutput = null;
			try {
				out = sys.io.File.append(file, false);
			} catch (_:Dynamic) {}
			while (true) {
				var line = queue.pop(true);
				if (out != null) write(line, out) else write(line, null);
				lock.acquire();
				pending--;
				lock.release();
			}
		});
	}
	#end
}
