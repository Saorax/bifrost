package port.engine;

class TimeSpread {
	static inline var STEP_MS = 0.25;
	static inline var BUCKETS = 1000;

	public var count(default, null) = 0;

	var longest = 0.0;
	var buckets:Array<Int> = [for (_ in 0...BUCKETS) 0];

	public function new() {}

	public function add(ms:Float):Void {
		var at = Std.int(ms / STEP_MS);
		buckets[at < 0 ? 0 : at >= BUCKETS ? BUCKETS - 1 : at]++;
		count++;
		if (ms > longest) longest = ms;
	}

	public function percentile(share:Float):Float {
		var needed = Math.ceil(count * share);
		var seen = 0;
		for (at in 0...BUCKETS) {
			seen += buckets[at];
			if (seen >= needed && seen > 0) {
				var middle = (at + 0.5) * STEP_MS;
				return middle < longest ? middle : longest;
			}
		}
		return longest;
	}

	public function text():String {
		if (count == 0) return "none";
		return round(percentile(0.5)) + "/" + round(percentile(0.95)) + "/" + round(longest);
	}

	public function clear():Void {
		for (at in 0...BUCKETS) buckets[at] = 0;
		count = 0;
		longest = 0;
	}

	static function round(ms:Float):Float {
		return Math.round(ms * 10) / 10;
	}
}

class InputTiming {
	static inline var REPORT_SECONDS = 60.0;
	static inline var CONTINUOUS_SECONDS = 0.1;

	public static var waitingForRead(default, null) = false;

	static var padName:String = null;
	static var padChanges = 0;
	static var keyPresses = 0;
	static var reportAt = -1.0;
	static var frameAt = -1.0;
	static var padAt = -1.0;
	static var padPresentAt = -1.0;
	static var keyPresentAt = -1.0;
	static var padShownAt = -1.0;
	static var keyShownAt = -1.0;

	static final padUpdates = new TimeSpread();
	static final padToRead = new TimeSpread();
	static final padToPresent = new TimeSpread();
	static final keyToPresent = new TimeSpread();
	static final frames = new TimeSpread();
	static final presents = new TimeSpread();

	public static function frame(now:Float, vsync:Bool):Void {
		if (frameAt >= 0) frames.add((now - frameAt) * 1000);
		frameAt = now;
		if (reportAt < 0) {
			reportAt = now + REPORT_SECONDS;
		} else if (now >= reportAt) {
			var line = report(vsync);
			if (line != null) BootLog.log(line);
			clear();
			reportAt = now + REPORT_SECONDS;
		}
	}

	public static function padChanged(previous:Float, name:String, now:Float):Float {
		padName = name;
		padChanges++;
		if (previous >= 0 && now - previous < CONTINUOUS_SECONDS) padUpdates.add((now - previous) * 1000);
		if (padAt < 0) padAt = now;
		if (padPresentAt < 0) padPresentAt = now;
		waitingForRead = true;
		return now;
	}

	public static function gameRead(now:Float):Void {
		if (padAt >= 0 && now - padAt < 1) padToRead.add((now - padAt) * 1000);
		padAt = -1;
		waitingForRead = false;
	}

	public static function keyDown(now:Float):Void {
		keyPresses++;
		if (keyPresentAt < 0) keyPresentAt = now;
	}

	public static function rendered():Void {
		if (padShownAt < 0) padShownAt = padPresentAt;
		if (keyShownAt < 0) keyShownAt = keyPresentAt;
		padPresentAt = -1;
		keyPresentAt = -1;
	}

	public static function presented(seconds:Float, now:Float):Void {
		presents.add(seconds * 1000);
		if (padShownAt >= 0) padToPresent.add((now - padShownAt) * 1000);
		if (keyShownAt >= 0) keyToPresent.add((now - keyShownAt) * 1000);
		padShownAt = -1;
		keyShownAt = -1;
	}

	public static function report(vsync:Bool):Null<String> {
		if (padChanges == 0 && keyPresses == 0) return null;
		var pad = padChanges == 0 ? "pad: no changes"
			: "pad \"" + padName + "\": " + padChanges + " changes, updates every " + padUpdates.text() + ", to game read "
				+ padToRead.text() + " (" + padToRead.count + "), to present " + padToPresent.text();
		var keys = keyPresses == 0 ? "keys: no presses" : "keys: " + keyPresses + " presses, to present " + keyToPresent.text();
		return "input timing (ms, median/95%/longest): " + pad + "; " + keys + "; frames every " + frames.text() + ", present "
			+ presents.text() + ", vsync " + (vsync ? "on" : "off");
	}

	public static function clear():Void {
		padChanges = 0;
		keyPresses = 0;
		padAt = -1;
		padPresentAt = -1;
		keyPresentAt = -1;
		padShownAt = -1;
		keyShownAt = -1;
		waitingForRead = false;
		padUpdates.clear();
		padToRead.clear();
		padToPresent.clear();
		keyToPresent.clear();
		frames.clear();
		presents.clear();
	}
}
