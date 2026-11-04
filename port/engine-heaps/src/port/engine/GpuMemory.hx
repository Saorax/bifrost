package port.engine;

class GpuMemory {
	static var lastCounts = new Map<String, Int>();

	static function places(mem:h3d.impl.MemoryManager, top:Int):String {
		if (!@:privateAccess hxd.impl.AllocPos.ENABLED) return "";
		var stats = mem.allocStats();
		var counts = new Map<String, Int>();
		for (s in stats) counts.set((s.tex ? "tex " : "buf ") + s.position, s.count);
		stats.sort((a, b) -> b.size > a.size ? 1 : b.size < a.size ? -1 : b.count - a.count);
		var parts = [];
		for (s in stats.slice(0, top)) {
			var key = (s.tex ? "tex " : "buf ") + s.position;
			var d = s.count - (lastCounts.exists(key) ? lastCounts.get(key) : 0);
			parts.push(key + " x" + s.count + " (" + (d >= 0 ? "+" : "") + d + ") " + mb(s.size) + " MB");
		}
		lastCounts = counts;
		return "; by place: " + parts.join(", ");
	}

	static function mb(b:Float):String {
		return Std.string(Math.round(b / 104857.6) / 10);
	}

	public static function report(top:Int = 10):String {
		var engine = h3d.Engine.getCurrent();
		if (engine == null || engine.mem == null) return "no engine";
		var mem = engine.mem;
		var stats = mem.stats();
		var groups = new Map<String, {count:Int, bytes:Float}>();
		var textures:Array<h3d.mat.Texture> = @:privateAccess mem.textures;
		for (t in textures) {
			var key = t.width + "x" + t.height + " " + t.format + (t.flags.has(Target) ? " target" : "");
			var g = groups.get(key);
			if (g == null) groups.set(key, g = {count: 0, bytes: 0.0});
			g.count++;
			g.bytes += hxd.Pixels.calcDataSize(t.width, t.height, t.format) * t.layerCount;
		}
		var keys = [for (k in groups.keys()) k];
		keys.sort((a, b) -> groups.get(b).bytes > groups.get(a).bytes ? 1 : groups.get(b).bytes < groups.get(a).bytes ? -1 : 0);
		return "buffers " + stats.bufferCount + " (" + mb(stats.bufferMemory) + " MB), textures " + stats.textureCount + " ("
			+ mb(stats.textureMemory) + " MB) in " + keys.length + " sizes; largest: "
			+ [for (k in keys.slice(0, top)) k + " x" + groups.get(k).count + " " + mb(groups.get(k).bytes) + " MB"].join(", ")
			+ "; " + GpuStage3D.census() + "; gpu bitmaps resident " + port.engine.art.GpuBitmaps.residentCount()
			+ ", free " + port.engine.art.GpuBitmaps.freeCount() + "; " + StagingPool.census() + "; " + UploadStats.take(top) + places(mem, top);
	}
}
