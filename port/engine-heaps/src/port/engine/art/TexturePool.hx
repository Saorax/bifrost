package port.engine.art;

class TexturePool {
	var bySize = new port.engine.NativeIntMap<Array<h3d.mat.Texture>>();
	var order:Array<h3d.mat.Texture> = [];
	var capBytes:Float;
	var capCount:Int;
	public var bytes(default, null) = 0.0;

	public var count(get, never):Int;

	function get_count():Int
		return order.length;

	public function new(capCount:Int, capMB:Float) {
		this.capCount = capCount;
		this.capBytes = capMB * 1024 * 1024;
	}

	static inline function size(t:h3d.mat.Texture):Float
		return hxd.Pixels.calcDataSize(t.width, t.height, t.format);

	public function take(w:Int, h:Int):Null<h3d.mat.Texture> {
		var list = bySize.get((w << 16) | h);
		if (list == null || list.length == 0) return null;
		var t = list.pop();
		order.remove(t);
		bytes -= size(t);
		return t;
	}

	public function put(t:h3d.mat.Texture):Void {
		var key = (t.width << 16) | t.height;
		var list = bySize.get(key);
		if (list == null) bySize.set(key, list = []);
		list.push(t);
		order.push(t);
		bytes += size(t);
		while ((bytes > capBytes || order.length > capCount) && order.length > 0) {
			var old = order.shift();
			bytes -= size(old);
			var oldKey = (old.width << 16) | old.height;
			var oldList = bySize.get(oldKey);
			oldList.remove(old);
			if (oldList.length == 0) bySize.remove(oldKey);
			old.dispose();
		}
	}
}
