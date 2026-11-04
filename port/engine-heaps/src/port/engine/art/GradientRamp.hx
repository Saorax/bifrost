package port.engine.art;

class GradientRamp {
	public static function build(ratios:Array<Float>, colours:Array<Int>, alphas:Array<Float>, linear:Bool):Array<Int> {
		var out = [];
		for (i in 0...256) {
			var a = 0, b = 0, f = 0.0;
			if (i > ratios[0]) {
				a = 0;
				while (a + 1 < ratios.length && ratios[a + 1] <= i)
					a++;
				b = a + 1 < ratios.length ? a + 1 : a;
				f = b == a ? 0.0 : (i - ratios[a]) / (ratios[b] - ratios[a]);
			}
			var argb = Std.int(Math.round((alphas[a] + (alphas[b] - alphas[a]) * f) * 255)) << 24;
			for (shift in [16, 8, 0]) {
				var ca = (colours[a] >> shift) & 255, cb = (colours[b] >> shift) & 255;
				var v = linear ? toSrgb(toLinear(ca) + (toLinear(cb) - toLinear(ca)) * f) : Std.int(Math.round(ca + (cb - ca) * f));
				argb |= v << shift;
			}
			out.push(argb);
		}
		return out;
	}

	static inline function toLinear(c:Int):Float {
		var v = c / 255;
		return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
	}

	static inline function toSrgb(v:Float):Int {
		var s = v <= 0.0031308 ? v * 12.92 : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
		return Std.int(Math.max(0, Math.min(255, Math.round(s * 255))));
	}
}
