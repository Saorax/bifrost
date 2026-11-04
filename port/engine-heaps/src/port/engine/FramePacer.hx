package port.engine;

class FramePacer {
	public static inline var MAX_EARLY = 0.004;

	var nextAt:Float = -1;

	public function new() {}

	public function due(now:Float, frameRate:Float):Bool {
		var interval = 1 / frameRate;
		if (nextAt < 0) {
			nextAt = now + interval;
			return true;
		}
		var early = interval * 0.25 < MAX_EARLY ? interval * 0.25 : MAX_EARLY;
		if (now + early < nextAt) return false;
		nextAt += interval;
		if (nextAt < now) nextAt = now + interval;
		return true;
	}
}
