package port.engine;

class HeadlessMain {
	static var traceLoads = Sys.getEnv("BH_PORT_TRACE_LOADS") == "1";

	static function main():Void {
		BootLog.path = Sys.getEnv("BH_PORT_LOG");
		if (BootLog.path == null || BootLog.path == "") BootLog.path = "bh-port-heaps-boot.txt";
		var appDir = Sys.getEnv("BH_PORT_APP_DIR");
		if (appDir != null && appDir != "") port.runtime.services.Launch.configure("application", appDir);
		var storageDir = Sys.getEnv("BH_PORT_STORAGE_DIR");
		if (storageDir != null && storageDir != "") port.runtime.services.Launch.configure("storage", storageDir);
		HeapsMain.log("boot: start (Heaps engine, headless, application "
			+ port.runtime.services.Launch.applicationDirectory() + ")");
		var width = 1920, height = 1080;
		var size = Sys.getEnv("BH_PORT_STAGE");
		if (size != null && size.indexOf("x") > 0) {
			var parts = size.split("x");
			width = Std.parseInt(parts[0]);
			height = Std.parseInt(parts[1]);
		}
		var stage = new flash.display.Stage(null, 0);
		Display.start(HeapsMain.settingsPath());
		stage.onDisplayState = function(state) Display.gameDisplayState(state != flash.display.StageDisplayState.NORMAL);
		var root = new flash.display.MovieClip();
		stage.addChild(root);
		flash.Lib.current = root;
		FrameLoop.root = stage;
		stage.resized(width, height);
		HeapsMain.stage = stage;
		HeapsMain.boot();

		var limit = Std.parseInt(Sys.getEnv("BH_PORT_FRAMES"));
		var pacing = Sys.getEnv("BH_PORT_NO_PACING") != "1";
		var pacer = new FramePacer();
		var frames = 0;
		var firstFrameAt = 0.0;
		while (limit == null || limit <= 0 || frames < limit) {
			var now = haxe.Timer.stamp();
			if (pacing && !pacer.due(now, stage.frameRate)) {
				Sys.sleep(0.001);
				continue;
			}
			HeapsMain.gameFrame(frames);
			if (traceLoads && (frames < 12 || frames % 10 == 0) && frames < 200) HeapsMain.log("frame " + frames + ": " + HeapsMain.archiveFiles());
			if (++frames == 1) {
				firstFrameAt = now;
				HeapsMain.log("boot: first frame");
			} else if (frames % 600 == 1) {
				HeapsMain.log("boot: " + (frames - 1) + " frames in " + Std.int((now - firstFrameAt) * 1000) + " ms at frameRate "
					+ stage.frameRate);
				HeapsMain.log(HeapsMain.progress());
			}
		}
		HeapsMain.log("boot: stopped after " + frames + " frames");
		HeapsMain.log(HeapsMain.progress());
	}
}
