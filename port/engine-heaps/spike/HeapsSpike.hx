class HeapsSpike extends hxd.App {
	static var started = haxe.Timer.stamp();
	var frames = 0;
	var firstFrame = -1.0;

	override function init() {
		var g = new h2d.Graphics(s2d);
		g.beginFill(0xFF8000);
		g.drawCircle(200, 150, 80);
		g.endFill();
		g.lineStyle(4, 0x2060FF);
		g.moveTo(40, 280);
		g.lineTo(360, 40);
		var text = new h2d.Text(hxd.res.DefaultFont.get(), s2d);
		text.text = "Heaps spike";
		text.x = 20;
		text.y = 20;
		Sys.println('init after ${ms(started)} ms, driver ${Type.getClassName(Type.getClass(engine.driver))}, '
			+ '${engine.width}x${engine.height}');
	}

	override function update(dt:Float) {
		frames++;
		if (firstFrame < 0)
			firstFrame = haxe.Timer.stamp();
		if (frames == 120) {
			var out = Sys.getEnv("BH_HEAPS_SHOT");
			if (out != null) {
				var tex = new h3d.mat.Texture(400, 300, [Target]);
				engine.pushTarget(tex);
				engine.clear(0x000000, 1);
				s2d.render(engine);
				engine.popTarget();
				sys.io.File.saveBytes(out, tex.capturePixels().toPNG());
				Sys.println('shot $out');
			}
			Sys.println('120 frames in ${ms(firstFrame)} ms after the first');
			hxd.System.exit();
		}
	}

	static function ms(since:Float):Int
		return Std.int((haxe.Timer.stamp() - since) * 1000);

	static function main() {
		new HeapsSpike();
	}
}
