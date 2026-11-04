package port.engine.art;

class RasterAtlas {
	public static inline var PAGE = 2048;
	public static var LIMIT = limitFromEnv(Sys.getEnv("BH_PORT_RASTER_ATLAS_LIMIT"));

	public static function limitFromEnv(value:Null<String>):Int {
		var n = value == null ? null : Std.parseInt(value);
		return n == null || n <= 0 ? 512 : n > 1024 ? 1024 : n;
	}

	var pages:Array<AtlasPage> = [];
	var free = new Map<Int, Array<AtlasSlot>>();
	public var slotsMade(default, null) = 0;
	public var slotsReused(default, null) = 0;
	public var pageCount(get, never):Int;

	function get_pageCount():Int
		return pages.length;

	public function new() {}

	public static function fits(w:Int, h:Int):Bool {
		return VectorRaster.bucket(w) <= LIMIT && VectorRaster.bucket(h) <= LIMIT;
	}

	public function alloc(w:Int, h:Int):AtlasSlot {
		var s = take(w, h);
		s.serial = ++serials;
		return s;
	}

	static var serials = 0;

	function take(w:Int, h:Int):AtlasSlot {
		var bw = VectorRaster.bucket(w), bh = VectorRaster.bucket(h);
		var key = (bw << 16) | bh;
		var list = free.get(key);
		if (list != null && list.length > 0) {
			slotsReused++;
			return list.pop();
		}
		var best:Array<AtlasSlot> = null, bestArea = 2 * bw * bh + 1;
		for (k => l in free) {
			var fw = k >>> 16, fh = k & 0xFFFF;
			if (l.length > 0 && fw >= bw && fh >= bh && fw * fh < bestArea) {
				best = l;
				bestArea = fw * fh;
			}
		}
		if (best != null) {
			slotsReused++;
			return best.pop();
		}
		for (p in pages) {
			var s = p.take(bw, bh);
			if (s != null) {
				slotsMade++;
				return s;
			}
		}
		var p = new AtlasPage(new h3d.mat.Texture(PAGE, PAGE, [Target]));
		p.texture.filter = Nearest;
		pages.push(p);
		slotsMade++;
		return p.take(bw, bh);
	}

	public function release(s:AtlasSlot):Void {
		var key = (s.w << 16) | s.h;
		var list = free.get(key);
		if (list == null) free.set(key, list = []);
		list.push(s);
	}
}

class AtlasSlot {
	public var page:h3d.mat.Texture;
	public var x:Int;
	public var y:Int;
	public var w:Int;
	public var h:Int;
	public var serial = 0;

	public function new(page, x, y, w, h) {
		this.page = page;
		this.x = x;
		this.y = y;
		this.w = w;
		this.h = h;
	}
}

private class AtlasPage {
	public var texture:h3d.mat.Texture;
	var shelves:Array<{y:Int, h:Int, x:Int}> = [];
	var nextY = 0;

	public function new(texture) {
		this.texture = texture;
	}

	public function take(w:Int, h:Int):AtlasSlot {
		for (s in shelves) {
			if (s.h == h && s.x + w <= RasterAtlas.PAGE) {
				var slot = new AtlasSlot(texture, s.x, s.y, w, h);
				s.x += w;
				return slot;
			}
		}
		if (nextY + h > RasterAtlas.PAGE) return null;
		var s = {y: nextY, h: h, x: w};
		shelves.push(s);
		nextY += h;
		return new AtlasSlot(texture, 0, s.y, w, h);
	}
}
