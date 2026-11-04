package port.engine;

import port.engine.art.FilterMath;
import port.engine.art.RasterAtlas;
import port.engine.art.VectorRaster;

@:access(flash.display.DisplayObject)
@:access(flash.geom.Transform)
class DisplayRenderer {
	public static var onRaster:(Int, Float) -> Void;

	public static var drawn(default, null) = 0;
	public static var rasters(default, null) = 0;
	public static var rasterSeconds(default, null) = 0.0;
	public static var notDrawn(default, null) = new Map<String, Int>();
	public static var layersDrawn(default, null) = 0;
	public static var layersFiltered(default, null) = 0;
	public static var filterSeconds(default, null) = 0.0;
	public static var filterReadSeconds(default, null) = 0.0;
	public static var filterMathSeconds(default, null) = 0.0;

	static inline var KEEP = 120;

	var engine:h3d.Engine;
	var raster:VectorRaster;
	var shader = new QuadShader();
	var fx:h3d.pass.ScreenFx<QuadShader>;
	var range = new Range();
	var bitmaps = new Map<flash.display.BitmapData, Cached>();
	var vectors = new Map<flash.display.Graphics, Cached>();
	static var useAtlas = Sys.getEnv("BH_PORT_RASTER_ATLAS") != "0";
	var atlas = new RasterAtlas();
	static var current:DisplayRenderer;

	public static function atlasReport():String {
		if (current == null) return "atlas off";
		var a = current.atlas;
		return "atlas " + a.pageCount + " pages, slots made " + a.slotsMade + ", reused " + a.slotsReused;
	}
	static inline var VARIANTS = 32;
	var retired:Array<Cached> = [];
	public static var variantHits(default, null) = 0;
	public static var rasterReasons(default, null) = new Map<String, Int>();

	static var traceRasters = Sys.getEnv("BH_PORT_TRACE_RASTERS") == "1" || Sys.getEnv("BH_PORT_TRACE_RASTERS") == "2";
	static var traceRasterDetail = Sys.getEnv("BH_PORT_TRACE_RASTERS") == "2";
	var rasterOwner:flash.display.DisplayObject;
	var rasterTrace = new Map<String, Int>();

	static function rasterWhy(why:String):Void {
		rasterReasons.set(why, (rasterReasons.exists(why) ? rasterReasons.get(why) : 0) + 1);
	}

	static inline function sameLinear(e:Cached, m:flash.geom.Matrix):Bool {
		return Math.abs(e.a - m.a) < 1e-4 && Math.abs(e.b - m.b) < 1e-4 && Math.abs(e.c - m.c) < 1e-4
			&& Math.abs(e.d - m.d) < 1e-4;
	}
	var texts = new Map<flash.text.TextField, TextCache>();
	var textDrawings = new Map<String, flash.display.Graphics>();
	var textUsed = new Map<String, Int>();
	var drawingMask:flash.display.DisplayObject = null;
	var layerCaches = new Map<flash.display.DisplayObject, LayerCache>();
	var spareLayers = new Map<String, LayerCache>();
	var spareOrder:Array<String> = [];
	var spareBytes = 0.0;
	public static var spareHits(default, null) = 0;
	public static var layersNew(default, null) = 0;
	public static var layersChanged(default, null) = 0;
	static var traceLayers = Sys.getEnv("BH_PORT_TRACE_LAYERS") == "1";

	public static function spareReport():String {
		var r = current;
		if (r == null) return "";
		return "spare " + r.spareOrder.length + " (" + Math.round(r.spareBytes / 104857.6) / 10 + " MB), hits " + spareHits
			+ ", new " + layersNew + ", changed " + layersChanged;
	}
	static var spareBudget:Float = {
		var mb = Std.parseFloat(Sys.getEnv("BH_PORT_LAYER_SPARE_MB"));
		(Math.isNaN(mb) ? 64.0 : mb) * 1024 * 1024;
	};
	var layers:Array<Layer> = [];
	var pool = new Map<Int, Array<h3d.mat.Texture>>();
	var lent:Array<h3d.mat.Texture> = [];
	public static var maskLayers(default, null) = 0;
	var clip:Array<Float> = null;
	var stageRef:flash.display.Stage;
	var quads:Array<Quad> = [];
	var frame = 0;
	var width = 1.0;
	var height = 1.0;
	var ySign = 1.0;

	public function new(engine:h3d.Engine, raster:VectorRaster) {
		this.engine = engine;
		this.raster = raster;
		current = this;
		fx = new h3d.pass.ScreenFx(shader);
		fx.pass.blend(One, OneMinusSrcAlpha);
		fx.primitive = range;
		if (Sys.getEnv("BH_PORT_GPU_FILTERS") != "0") gpuFilters = new port.engine.art.GpuFilters(engine);
	}

	var gpuFilters:port.engine.art.GpuFilters;
	static var checkGpuFilters = Sys.getEnv("BH_PORT_GPU_FILTERS_CHECK") == "1";
	public static var layersGpuFiltered(default, null) = 0;
	public static var gpuFilterChecks(default, null) = 0;
	public static var gpuFilterMismatches(default, null) = 0;
	static var cpuFilterKinds = new Map<String, Int>();

	public static function cpuFilterReport():String {
		var keys = [for (k in cpuFilterKinds.keys()) k];
		keys.sort((a, b) -> cpuFilterKinds.get(b) - cpuFilterKinds.get(a));
		return [for (k in keys.slice(0, 6)) cpuFilterKinds.get(k) + "x " + k].join(", ");
	}

	static function skip(why:String):Void {
		notDrawn.set(why, (notDrawn.exists(why) ? notDrawn.get(why) : 0) + 1);
	}

	public function render(stage:flash.display.Stage):Void {
		frame++;
		width = engine.width;
		height = engine.height;
		ySign = engine.driver.hasFeature(BottomLeftCoords) && engine.getCurrentTarget() != null ? -1 : 1;
		layers = [];
		stageRef = stage;
		clip = null;
		matrixDepth = 0;
		colorsUsed = 0;
		quadsUsed = 0;
		listsUsed = 0;
		quads = takeList();
		var c = stage.numChildren;
		for (i in 0...c) walk(stage.getChildAt(i), new flash.geom.Matrix(), ONE, ZERO);
		drawn = quads.length;
		layersDrawn = layers.length;
		maskLayers = 0;
		var entered = port.engine.art.FxContext.enter();
		for (l in layers) drawLayer(l);
		flush(quads, 0, 0, width, height, ySign);
		port.engine.art.FxContext.leave(entered);
		for (t in lent) {
			var key = (t.width << 16) | t.height;
			if (!pool.exists(key)) pool.set(key, []);
			pool.get(key).push(t);
		}
		lent = [];
		for (r in retired) r.disposeChain();
		retired = [];
		if (frame % 60 == 0) evict();
		if (traceRasters && rasterTrace.iterator().hasNext()) {
			var parts = [for (k => v in rasterTrace) k + " x" + v];
			parts.sort(Reflect.compare);
			BootLog.log("rasters at frame " + frame + ": " + parts.join("; "));
			rasterTrace.clear();
		}
	}

	function flush(list:Array<Quad>, ox:Float, oy:Float, w:Float, h:Float, ys:Float):Void {
		if (list.length == 0) return;
		var count = list.length * 6;
		var v = flushFloats;
		if (v.length < count * 4) v.grow(count * 4);
		var n = 0;
		for (q in list) {
			var r = q.uv, p = q.p;
			var u0 = 0.0, v0 = 0.0, u1 = 1.0, v1 = 1.0;
			if (r != null) {
				u0 = r[0];
				v0 = r[1];
				u1 = r[2];
				v1 = r[3];
			}
			for (j in 0...6) {
				var k = CORNERS[j];
				v[n++] = (p[k * 2] - ox) / w * 2 - 1;
				v[n++] = (1 - (p[k * 2 + 1] - oy) / h * 2) * ys;
				v[n++] = k == 0 || k == 3 ? u0 : u1;
				v[n++] = k < 2 ? v0 : v1;
			}
		}
		var buffer:h3d.Buffer;
		if (keepFlushBuffer) {
			if (flushBuffer == null || flushBuffer.isDisposed() || flushBuffer.vertices < count) {
				if (flushBuffer != null) flushBuffer.dispose();
				var room = 1024;
				while (room < count) room *= 2;
				flushBuffer = new h3d.Buffer(room, hxd.BufferFormat.XY_UV, [Dynamic]);
			}
			flushBuffer.uploadFloats(v, 0, count);
			buffer = flushBuffer;
		} else {
			var own = new hxd.FloatBuffer(count * 4);
			for (i in 0...count * 4) own[i] = v[i];
			buffer = h3d.Buffer.ofFloats(own, hxd.BufferFormat.XY_UV);
		}
		range.source = buffer;
		var zone:Array<Float> = null;
		var empty = false;
		for (i in 0...list.length) {
			var q = list[i];
			if (i == 0 || q.clip != zone) {
				zone = q.clip;
				empty = false;
				if (zone == null) {
					engine.setRenderZone();
				} else {
					var x = Std.int(Math.max(0, Math.floor(zone[0] - ox))), y = Std.int(Math.max(0, Math.floor(zone[1] - oy)));
					var zw = Std.int(Math.min(w, Math.ceil(zone[2] - ox))) - x, zh = Std.int(Math.min(h, Math.ceil(zone[3] - oy))) - y;
					if (zw <= 0 || zh <= 0) {
						empty = true;
					} else {
						engine.setRenderZone(x, ys < 0 ? Std.int(h) - y - zh : y, zw, zh);
					}
				}
			}
			if (empty) continue;
			var texture = q.layer != null ? q.layer.out : q.texture;
			if (texture == null) continue;
			shader.texture = texture;
			var mask = q.layer != null ? q.layer.mask : null;
			shader.masked = mask != null;
			if (mask != null) shader.maskTexture = mask;
			shader.premultiplied = q.premultiplied;
			texture.filter = q.smooth ? Linear : Nearest;
			shader.mul.set(q.mul[0], q.mul[1], q.mul[2], q.mul[3]);
			shader.add.set(q.add[0], q.add[1], q.add[2], q.add[3]);
			range.start = i * 2;
			range.count = 2;
			fx.render();
		}
		engine.setRenderZone();
		if (buffer != flushBuffer) buffer.dispose();
	}

	static var CORNERS = [0, 1, 2, 0, 2, 3];
	static var keepFlushBuffer = Sys.getEnv("BH_PORT_FLUSH_BUFFER") != "0";
	var flushFloats = new hxd.FloatBuffer();
	var flushBuffer:h3d.Buffer;

	function borrow(w:Int, h:Int):h3d.mat.Texture {
		var free = pool.get((w << 16) | h);
		var t = free != null && free.length > 0 ? free.pop() : null;
		if (t == null) t = newTarget(w, h, true) else targetsPooled++;
		lent.push(t);
		return t;
	}

	function giveBack(t:h3d.mat.Texture):Void {
		if (!lent.remove(t)) return;
		var key = (t.width << 16) | t.height;
		var free = pool.get(key);
		if (free == null) pool.set(key, free = []);
		free.push(t);
	}

	static var scratchBack = Sys.getEnv("BH_PORT_SCRATCH_BACK") != "0";

	static function newTarget(w:Int, h:Int, target:Bool):h3d.mat.Texture {
		targetsMade++;
		targetBytesMade += w * h * 4.0;
		return target ? new h3d.mat.Texture(w, h, [Target]) : new h3d.mat.Texture(w, h);
	}
	public static var targetsMade(default, null) = 0;
	public static var targetBytesMade(default, null) = 0.0;
	public static var targetsPooled(default, null) = 0;

	function drawInto(list:Array<Quad>, l:Layer):h3d.mat.Texture {
		var target = borrow(l.w, l.h);
		engine.pushTarget(target);
		engine.clear(0);
		flush(list, l.ox, l.oy, l.w, l.h, 1);
		engine.popTarget();
		return target;
	}

	function drawLayer(l:Layer):Void {
		if (l.filters.length > 0) filterLayer(l) else l.out = drawInto(l.quads, l);
		if (l.maskQuads != null) {
			l.mask = drawInto(l.maskQuads, l);
			maskLayers++;
		}
	}

	function filterLayer(l:Layer):Void {
		var cache = layerCaches.get(l.object);
		if (cache == null) {
			cache = new LayerCache();
			layerCaches.set(l.object, cache);
		}
		cache.used = frame;
		if (cache.out != null && cache.key == l.key && cache.width == l.w && cache.height == l.h) {
			l.out = cache.out;
			return;
		}
		var spare = spareLayers.get(l.key);
		if (spare != null && spare.width == l.w && spare.height == l.h) {
			cache.dispose();
			takeSpare(l.key);
			cache.out = spare.out;
			cache.key = l.key;
			cache.width = l.w;
			cache.height = l.h;
			l.out = cache.out;
			spareHits++;
			return;
		}
		if (cache.out != null) {
			layersChanged++;
			if (traceLayers) {
				var a = cache.key, b = l.key, i = 0;
				while (i < a.length && i < b.length && a.charCodeAt(i) == b.charCodeAt(i)) i++;
				BootLog.log("layer changed at frame " + frame + " (" + l.w + "x" + l.h + ", key " + b.length + " chars, from "
					+ i + "): " + a.substr(i > 40 ? i - 40 : 0, 120) + " -> " + b.substr(i > 40 ? i - 40 : 0, 120));
			}
		} else layersNew++;
		var started = haxe.Timer.stamp();
		cache.dispose();
		var drawn = drawInto(l.quads, l);
		if (gpuFilters != null && port.engine.art.GpuFilters.supported(l.filters)) {
			var out = newTarget(l.w, l.h, true);
			gpuFilters.apply(drawn, l.w, l.h, l.filters, out, borrow, scratchBack ? giveBack : null);
			if (checkGpuFilters) {
				var cpu = drawn.capturePixels();
				cpu.convert(RGBA);
				var bytes = cpu.bytes;
				if (cpu.offset != 0 || bytes.length != l.w * l.h * 4) bytes = bytes.sub(cpu.offset, l.w * l.h * 4);
				var planes = FilterMath.fromPremultipliedRGBA(bytes, l.w, l.h);
				for (f in l.filters) planes = FilterMath.apply(planes, f);
				var want = FilterMath.toPremultipliedRGBA(planes);
				var got = out.capturePixels();
				got.convert(RGBA);
				var gb = got.bytes, off = 0, first = -1;
				for (i in 0...l.w * l.h * 4) if (gb.get(got.offset + i) != want.get(i)) {
					if (first < 0) first = i;
					off++;
				}
				gpuFilterChecks++;
				if (off > 0) {
					gpuFilterMismatches++;
					BootLog.log("gpu filter check: " + l.w + "x" + l.h + " " + off + " bytes off, first at pixel " + (first >> 2)
						+ " channel " + (first & 3) + ": gpu " + gb.get(got.offset + first) + " cpu " + want.get(first) + "; "
						+ [for (f in l.filters) Std.string(f)].join(", "));
				}
			}
			if (scratchBack) giveBack(drawn);
			cache.out = out;
			cache.key = l.key;
			cache.width = l.w;
			cache.height = l.h;
			l.out = out;
			layersFiltered++;
			layersGpuFiltered++;
			filterSeconds += haxe.Timer.stamp() - started;
			return;
		}
		if (gpuFilters != null) {
			var why = [for (f in l.filters) Type.getClassName(Type.getClass(f)).split(".").pop() + port.engine.art.GpuFilters.describe(f)].join("+");
			cpuFilterKinds.set(why, (cpuFilterKinds.exists(why) ? cpuFilterKinds.get(why) : 0) + 1);
		}
		var pixels = drawn.capturePixels();
		if (scratchBack) giveBack(drawn);
		var read = haxe.Timer.stamp();
		filterReadSeconds += read - started;
		pixels.convert(RGBA);
		var bytes = pixels.bytes;
		if (pixels.offset != 0 || bytes.length != l.w * l.h * 4) bytes = bytes.sub(pixels.offset, l.w * l.h * 4);
		var planes = FilterMath.fromPremultipliedRGBA(bytes, l.w, l.h);
		for (f in l.filters) {
			var next = FilterMath.apply(planes, f);
			port.engine.art.FilterMath.Planes.release(planes);
			planes = next;
		}
		filterMathSeconds += haxe.Timer.stamp() - read;
		cache.out = newTarget(l.w, l.h, false);
		UploadStats.add("filter layer", l.w * l.h * 4.0);
		var n = l.w * l.h * 4;
		if (n <= UPLOAD_SCRATCH_MAX && (uploadScratch == null || uploadScratch.length < n)) uploadScratch = haxe.io.Bytes.alloc(n);
		var rgba = FilterMath.toPremultipliedRGBA(planes, n <= UPLOAD_SCRATCH_MAX ? uploadScratch : null);
		port.engine.art.FilterMath.Planes.release(planes);
		cache.out.uploadPixels(new hxd.Pixels(l.w, l.h, rgba, RGBA));
		cache.key = l.key;
		cache.width = l.w;
		cache.height = l.h;
		l.out = cache.out;
		layersFiltered++;
		filterSeconds += haxe.Timer.stamp() - started;
	}

	function evict():Void {
		var oldBitmaps = [for (k => e in bitmaps) if (frame - e.used > KEEP) k];
		for (k in oldBitmaps) {
			bitmaps.get(k).dispose();
			bitmaps.remove(k);
		}
		var oldTexts = [for (k => e in texts) if (frame - e.used > KEEP) k];
		for (k in oldTexts) texts.remove(k);
		for (free in pool) for (t in free) t.dispose();
		pool = new Map();
		var oldKeys = [for (k => e in layerKeys) if (frame - e.used > KEEP) k];
		for (k in oldKeys) layerKeys.remove(k);
		var oldLayers = [for (k => e in layerCaches) if (frame - e.used > KEEP) k];
		for (k in oldLayers) {
			keepSpare(layerCaches.get(k));
			layerCaches.remove(k);
		}
		var total = 0.0;
		for (e in vectors) total += e.chainBytes();
		rasterBytes = total;
		if (total > rasterBudget) {
			var old:Array<{g:flash.display.Graphics, used:Int, bytes:Float}> = [];
			for (k => e in vectors) if (frame - e.used > 2) old.push({g: k, used: e.used, bytes: e.chainBytes()});
			rasterBudgetPass(total, old);
		}
		var oldDrawings:Array<String> = null;
		for (k in textDrawings.keys()) {
			if (!vectors.exists(textDrawings.get(k)) && frame - (textUsed.exists(k) ? textUsed.get(k) : 0) > KEEP) {
				if (oldDrawings == null) oldDrawings = [];
				oldDrawings.push(k);
			}
		}
		if (oldDrawings != null) for (k in oldDrawings) {
			textDrawings.remove(k);
			textUsed.remove(k);
		}
	}

	function keepSpare(c:LayerCache):Void {
		if (c.out == null || c.key == null || spareBudget <= 0) {
			c.dispose();
			return;
		}
		if (spareLayers.exists(c.key)) takeSpare(c.key).dispose();
		spareLayers.set(c.key, c);
		spareOrder.push(c.key);
		spareBytes += c.width * c.height * 4.0;
		while (spareBytes > spareBudget && spareOrder.length > 0) takeSpare(spareOrder[0]).dispose();
	}

	function takeSpare(key:String):LayerCache {
		var c = spareLayers.get(key);
		spareLayers.remove(key);
		spareOrder.remove(key);
		spareBytes -= c.width * c.height * 4.0;
		return c;
	}

	function rasterBudgetPass(total:Float, old:Array<{g:flash.display.Graphics, used:Int, bytes:Float}>):Void {
		old.sort((x, y) -> x.used - y.used);
		for (o in old) {
			if (total <= rasterBudget) break;
			vectors.get(o.g).disposeChain();
			vectors.remove(o.g);
			total -= o.bytes;
			rasterEvicted++;
		}
		rasterBytes = total;
	}

	static var rasterBudget:Float = {
		var mb = Std.parseFloat(Sys.getEnv("BH_PORT_RASTER_BUDGET_MB"));
		(Math.isNaN(mb) ? 128.0 : mb) * 1024 * 1024;
	};
	public static var rasterBytes(default, null) = 0.0;
	public static var rasterEvicted(default, null) = 0;

	var matrixStack:Array<flash.geom.Matrix> = [];
	var matrixDepth = 0;
	var colorArena:Array<Array<Float>> = [];
	var colorsUsed = 0;
	static final ONE:Array<Float> = [1.0, 1, 1, 1];
	static final ZERO:Array<Float> = [0.0, 0, 0, 0];

	inline function color4(r:Float, g:Float, b:Float, a:Float):Array<Float> {
		var c:Array<Float>;
		if (colorsUsed < colorArena.length) {
			c = colorArena[colorsUsed];
			c[0] = r;
			c[1] = g;
			c[2] = b;
			c[3] = a;
		} else {
			c = [r, g, b, a];
			colorArena.push(c);
		}
		colorsUsed++;
		return c;
	}

	function walk(o:flash.display.DisplayObject, parent:flash.geom.Matrix, pMul:Array<Float>, pAdd:Array<Float>):Void {
		if (o == null || !o.visible) return;
		if (o.__isMask && o != drawingMask) return;
		var alpha = drawingMask != null ? 1.0 : o.__alpha;
		if (alpha <= 0) return;
		var m:flash.geom.Matrix;
		if (matrixDepth < matrixStack.length) {
			m = matrixStack[matrixDepth];
		} else {
			m = new flash.geom.Matrix();
			matrixStack.push(m);
		}
		matrixDepth++;
		m.copyFrom(o.__transform);
		m.concat(parent);
		var ct = o.__objectTransform != null ? o.__objectTransform.color : null;
		var mul = ct == null ? (alpha == 1 ? pMul : color4(pMul[0], pMul[1], pMul[2], alpha * pMul[3]))
			: color4(ct.redMultiplier * pMul[0], ct.greenMultiplier * pMul[1], ct.blueMultiplier * pMul[2], alpha * pMul[3]);
		var add = ct == null ? pAdd : color4(ct.redOffset / 255 * pMul[0] + pAdd[0], ct.greenOffset / 255 * pMul[1] + pAdd[1],
			ct.blueOffset / 255 * pMul[2] + pAdd[2], ct.alphaOffset / 255 * pMul[3] + pAdd[3]);
		var savedClip = clip;
		if (o.scrollRect != null) {
			var sr = o.scrollRect;
			clip = intersect(clip, box(m, 0, 0, sr.width, sr.height));
			var shifted = new flash.geom.Matrix(1, 0, 0, 1, -sr.x, -sr.y);
			shifted.concat(m);
			m = shifted;
		}
		var shapedMask:flash.display.DisplayObject = null;
		if (o.mask != null) {
			var b = stageRef != null ? o.mask.getBounds(stageRef) : null;
			if (b != null) clip = intersect(clip, [b.x, b.y, b.x + b.width, b.y + b.height]);
			if (rectangular(o.mask)) skip("mask (a rectangle)") else shapedMask = o.mask;
		}
		var filters:Array<flash.filters.BitmapFilter> = null;
		if (o.__filters != null) for (f in o.__filters) {
			if (f != null && FilterMath.known(f)) {
				if (filters == null) filters = [];
				filters.push(f);
			} else {
				skip("filter " + (f == null ? "null" : Type.getClassName(Type.getClass(f))));
			}
		}
		if (o.blendMode != null && o.blendMode != flash.display.BlendMode.NORMAL && o.blendMode != flash.display.BlendMode.LAYER) skip("blend " + o.blendMode);
		if (filters != null || shapedMask != null) {
			var outer = quads;
			quads = takeList();
			content(o, m, ONE, ZERO);
			var inner = quads;
			quads = outer;
			layer(o, inner, filters != null ? filters : [], mul, add, savedClip,
				shapedMask != null ? maskDrawing(shapedMask) : null);
		} else {
			content(o, m, mul, add);
		}
		clip = savedClip;
		matrixDepth--;
	}

	function content(o:flash.display.DisplayObject, m:flash.geom.Matrix, mul:Array<Float>, add:Array<Float>):Void {
		if (Std.isOfType(o, flash.display.Bitmap)) {
			bitmap(cast o, m, mul, add);
		} else if (Std.isOfType(o, flash.text.TextField)) {
			if (traceRasters) rasterOwner = o;
			text(cast o, m, mul, add);
		} else {
			var g:flash.display.Graphics = Std.isOfType(o, flash.display.Shape) ? (cast o : flash.display.Shape).graphics
				: Std.isOfType(o, flash.display.Sprite) ? (cast o : flash.display.Sprite).graphics : null;
			if (g != null && g.bounds != null && (g.fills.length > 0 || g.strokes.length > 0)) {
				if (traceRasters) rasterOwner = o;
				vector(drawingMask != null ? opaque(g) : g, m, mul, add);
			}
		}
		if (Std.isOfType(o, flash.display.DisplayObjectContainer)) {
			var c:flash.display.DisplayObjectContainer = cast o;
			for (i in 0...c.numChildren) walk(c.getChildAt(i), m, mul, add);
		}
	}

	function maskDrawing(mask:flash.display.DisplayObject):Array<Quad> {
		var outer = quads, saved = clip;
		quads = takeList();
		clip = null;
		var parent = mask.parent != null ? mask.parent.concatenatedMatrix() : new flash.geom.Matrix();
		var savedMask = drawingMask;
		drawingMask = mask;
		var shown = mask.visible;
		@:privateAccess mask.visible = true;
		walk(mask, parent, ONE, ZERO);
		@:privateAccess mask.visible = shown;
		drawingMask = savedMask;
		var drawn = quads;
		quads = outer;
		clip = saved;
		return drawn;
	}

	var opaqueMasks = new Map<flash.display.Graphics, flash.display.Graphics>();

	function opaque(g:flash.display.Graphics):flash.display.Graphics {
		var shared = g.__shared();
		if (shared != null) g = shared;
		var faint = false;
		for (f in g.fills) if (f.paint.kind == port.engine.art.VectorRecord.Paint.SOLID && f.paint.alpha < 1) faint = true;
		if (!faint) return g;
		var held = opaqueMasks.get(g);
		if (held != null && @:privateAccess held.__copiedVersion == g.__version) return held;
		var o = new flash.display.Graphics(null);
		@:privateAccess {
			o.bounds = g.bounds.clone();
			o.padding = g.padding;
			o.__portAdditive = g.__portAdditive;
			o.__portGroups = g.__portGroups;
			o.__copiedVersion = g.__version;
		}
		for (f in g.fills) {
			var c = f.copy();
			if (c.paint.kind == port.engine.art.VectorRecord.Paint.SOLID) c.paint = port.engine.art.VectorRecord.Paint.solid(c.paint.color, 1);
			o.fills.push(c);
		}
		for (s in g.strokes) o.strokes.push(s);
		opaqueMasks.set(g, o);
		return o;
	}

	static function rectangular(mask:flash.display.DisplayObject):Bool {
		var found = 0;
		function visit(o:flash.display.DisplayObject):Bool {
			var m = o.concatenatedMatrix();
			if (Std.isOfType(o, flash.display.Bitmap)) {
				found++;
				return Math.abs(m.b) < 1e-9 && Math.abs(m.c) < 1e-9;
			}
			if (Std.isOfType(o, flash.text.TextField)) return false;
			var g:flash.display.Graphics = Std.isOfType(o, flash.display.Shape) ? (cast o : flash.display.Shape).graphics
				: Std.isOfType(o, flash.display.Sprite) ? (cast o : flash.display.Sprite).graphics : null;
			if (g != null && (g.fills.length > 0 || g.strokes.length > 0)) {
				found++;
				if (g.strokes.length > 0 || g.fills.length != 1 || Math.abs(m.b) > 1e-9 || Math.abs(m.c) > 1e-9) return false;
				if (!rectanglePath(g.fills[0].commands, g.fills[0].data)) return false;
			}
			if (Std.isOfType(o, flash.display.DisplayObjectContainer)) {
				var c:flash.display.DisplayObjectContainer = cast o;
				for (i in 0...c.numChildren) if (!visit(c.getChildAt(i))) return false;
			}
			return true;
		}
		return visit(mask) && found == 1;
	}

	static function rectanglePath(commands:port.engine.art.VectorRecord.PathCommands, data:port.engine.art.VectorRecord.PathNumbers):Bool {
		if (commands.length < 4 || commands.length > 5 || commands[0] != 1) return false;
		for (k in 1...commands.length) if (commands[k] != 2) return false;
		var xs = [], ys = [];
		for (k in 0...commands.length) {
			var x = data[k * 2], y = data[k * 2 + 1];
			if (xs.indexOf(x) < 0) xs.push(x);
			if (ys.indexOf(y) < 0) ys.push(y);
		}
		if (xs.length != 2 || ys.length != 2) return false;
		for (k in 0...commands.length) {
			var j = (k + 1) % commands.length;
			if (data[k * 2] != data[j * 2] && data[k * 2 + 1] != data[j * 2 + 1]) return false;
		}
		return true;
	}

	function layer(o:flash.display.DisplayObject, inner:Array<Quad>, filters:Array<flash.filters.BitmapFilter>,
			mul:Array<Float>, add:Array<Float>, outerClip:Array<Float>, maskQuads:Array<Quad>):Void {
		if (inner.length == 0) return;
		var x0 = Math.POSITIVE_INFINITY, y0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY;
		for (q in inner) for (k in 0...4) {
			var px = q.p[k * 2], py = q.p[k * 2 + 1];
			if (q.clip != null) {
				px = Math.max(q.clip[0], Math.min(q.clip[2], px));
				py = Math.max(q.clip[1], Math.min(q.clip[3], py));
			}
			if (px < x0) x0 = px;
			if (py < y0) y0 = py;
			if (px > x1) x1 = px;
			if (py > y1) y1 = py;
		}
		if (x1 <= x0 || y1 <= y0) return;
		var mx = 0, my = 0;
		for (f in filters) {
			var r = FilterMath.margin(f);
			mx += r[0];
			my += r[1];
		}
		var ox = Math.floor(x0) - mx, oy = Math.floor(y0) - my;
		var w = Math.ceil(x1) + mx - ox, h = Math.ceil(y1) + my - oy;
		var saved = clip;
		clip = outerClip;
		if (w > VectorRaster.MAX || h > VectorRaster.MAX) {
			skip("filter layer over " + VectorRaster.MAX + " px");
			for (q in inner) {
				q.mul = [q.mul[0] * mul[0], q.mul[1] * mul[1], q.mul[2] * mul[2], q.mul[3] * mul[3]];
				q.add = [q.add[0] * mul[0] + add[0], q.add[1] * mul[1] + add[1], q.add[2] * mul[2] + add[2],
					q.add[3] * mul[3] + add[3]];
				quads.push(q);
			}
			clip = saved;
			return;
		}
		var l = new Layer(o, inner, filters, ox, oy, w, h, layerKey(o, inner, filters, ox, oy));
		l.maskQuads = maskQuads;
		layers.push(l);
		var q = takeQuad(null, ox, oy, ox + w, oy, ox + w, oy + h, ox, oy + h, false, mul, add, true, 0, null);
		q.layer = l;
		quads.push(q);
		clip = saved;
	}

	function layerKey(o:flash.display.DisplayObject, inner:Array<Quad>, filters:Array<flash.filters.BitmapFilter>,
			ox:Float, oy:Float):String {
		if (!layerKeyCache) return buildLayerKey(inner, filters, ox, oy);
		var nums = keyNums, strs = keyStrs;
		nums.resize(0);
		strs.resize(0);
		for (f in filters) filterNums(f, nums);
		for (q in inner) {
			if (q.layer != null) {
				nums.push(0);
				strs.push(q.layer.key);
			} else {
				nums.push(1);
				nums.push(q.texture.id);
				nums.push(q.version);
			}
			nums.push(q.smooth ? 1 : 0);
			for (k in 0...8) nums.push(rel(q.p[k] - (k % 2 == 0 ? ox : oy)));
			nums.push(q.mul.length);
			for (v in q.mul) nums.push(v);
			nums.push(q.add.length);
			for (v in q.add) nums.push(v);
			if (q.clip != null) {
				nums.push(1);
				for (k in 0...4) nums.push(rel(q.clip[k] - (k % 2 == 0 ? ox : oy)));
			} else nums.push(0);
		}
		var snap = layerKeys.get(o);
		if (snap == null) layerKeys.set(o, snap = new LayerKey());
		snap.used = frame;
		if (snap.key != null && snap.same(nums, strs)) return snap.key;
		snap.nums = nums.copy();
		snap.strs = strs.copy();
		return snap.key = buildLayerKey(inner, filters, ox, oy);
	}

	static var layerKeyCache = Sys.getEnv("BH_PORT_LAYER_KEY_CACHE") != "0";
	var keyNums:Array<Float> = [];
	var keyStrs:Array<String> = [];
	var layerKeys = new Map<flash.display.DisplayObject, LayerKey>();

	static function buildLayerKey(inner:Array<Quad>, filters:Array<flash.filters.BitmapFilter>, ox:Float, oy:Float):String {
		var key = new StringBuf();
		for (f in filters) key.add(filterKey(f));
		for (q in inner) {
			key.add(q.layer != null ? "L" + q.layer.key : "T" + q.texture.id + "." + q.version);
			key.add(q.smooth ? "s" : "n");
			for (k in 0...8) {
				key.add(",");
				key.add(rel(q.p[k] - (k % 2 == 0 ? ox : oy)));
			}
			key.add(":");
			key.add(q.mul.join(","));
			key.add(":");
			key.add(q.add.join(","));
			if (q.clip != null) key.add("c" + [for (k in 0...4) rel(q.clip[k] - (k % 2 == 0 ? ox : oy))].join(","));
			key.add(";");
		}
		return key.toString();
	}

	static inline function rel(v:Float):Float {
		return Math.round(v * 64) / 64;
	}

	static function filterNums(f:flash.filters.BitmapFilter, n:Array<Float>):Void {
		inline function bool(b:Bool):Float return b ? 1 : 0;
		if (Std.isOfType(f, flash.filters.GlowFilter)) {
			var g:flash.filters.GlowFilter = cast f;
			n.push(1);
			n.push(g.color);
			n.push(g.alpha);
			n.push(g.blurX);
			n.push(g.blurY);
			n.push(g.strength);
			n.push(g.quality);
			n.push(bool(g.inner));
			n.push(bool(g.knockout));
		} else if (Std.isOfType(f, flash.filters.DropShadowFilter)) {
			var d:flash.filters.DropShadowFilter = cast f;
			n.push(2);
			n.push(d.distance);
			n.push(d.angle);
			n.push(d.color);
			n.push(d.alpha);
			n.push(d.blurX);
			n.push(d.blurY);
			n.push(d.strength);
			n.push(d.quality);
			n.push(bool(d.inner));
			n.push(bool(d.knockout));
			n.push(bool(d.hideObject));
		} else if (Std.isOfType(f, flash.filters.BlurFilter)) {
			var b:flash.filters.BlurFilter = cast f;
			n.push(3);
			n.push(b.blurX);
			n.push(b.blurY);
			n.push(b.quality);
		} else if (Std.isOfType(f, flash.filters.ColorMatrixFilter)) {
			var values = (cast f : flash.filters.ColorMatrixFilter).__values();
			n.push(4);
			n.push(values.length);
			for (v in values) n.push(v);
		} else n.push(0);
	}

	static function filterKey(f:flash.filters.BitmapFilter):String {
		if (Std.isOfType(f, flash.filters.GlowFilter)) {
			var g:flash.filters.GlowFilter = cast f;
			return 'G${g.color},${g.alpha},${g.blurX},${g.blurY},${g.strength},${g.quality},${g.inner},${g.knockout}|';
		}
		if (Std.isOfType(f, flash.filters.DropShadowFilter)) {
			var d:flash.filters.DropShadowFilter = cast f;
			return 'D${d.distance},${d.angle},${d.color},${d.alpha},${d.blurX},${d.blurY},${d.strength},${d.quality},${d.inner},${d.knockout},${d.hideObject}|';
		}
		if (Std.isOfType(f, flash.filters.BlurFilter)) {
			var b:flash.filters.BlurFilter = cast f;
			return 'B${b.blurX},${b.blurY},${b.quality}|';
		}
		if (Std.isOfType(f, flash.filters.ColorMatrixFilter)) {
			return "M" + (cast f : flash.filters.ColorMatrixFilter).__values().join(",") + "|";
		}
		return "?|";
	}

	static function box(m:flash.geom.Matrix, x:Float, y:Float, w:Float, h:Float):Array<Float> {
		var x0 = Math.POSITIVE_INFINITY, y0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY;
		for (p in [[x, y], [x + w, y], [x, y + h], [x + w, y + h]]) {
			var px = m.a * p[0] + m.c * p[1] + m.tx, py = m.b * p[0] + m.d * p[1] + m.ty;
			if (px < x0) x0 = px;
			if (py < y0) y0 = py;
			if (px > x1) x1 = px;
			if (py > y1) y1 = py;
		}
		return [x0, y0, x1, y1];
	}

	static function intersect(a:Array<Float>, b:Array<Float>):Array<Float> {
		if (a == null) return b;
		return [Math.max(a[0], b[0]), Math.max(a[1], b[1]), Math.min(a[2], b[2]), Math.min(a[3], b[3])];
	}

	function bitmap(b:flash.display.Bitmap, m:flash.geom.Matrix, mul:Array<Float>, add:Array<Float>):Void {
		var data = b.bitmapData;
		if (data == null || data.width <= 0 || data.height <= 0) return;
		if (data.__gpu != null) {
			port.engine.art.GpuBitmaps.touch(data);
			var w = data.width, h = data.height;
			quad(data.__gpu, m.tx, m.ty, m.a * w + m.tx, m.b * w + m.ty, m.a * w + m.c * h + m.tx, m.b * w + m.d * h + m.ty,
				m.c * h + m.tx, m.d * h + m.ty, b.smoothing, mul, add, true, data.__version);
			return;
		}
		var e = bitmaps.get(data);
		if (e == null || e.width != data.width || e.height != data.height) {
			if (e != null && e.texture != null) e.texture.dispose();
			e = new Cached();
			e.width = data.width;
			e.height = data.height;
			e.texture = new h3d.mat.Texture(data.width, data.height);
			e.version = data.__version - 1;
			bitmaps.set(data, e);
		}
		if (e.version != data.__version) {
			upload(e.texture, data);
			e.version = data.__version;
		}
		e.used = frame;
		var w = data.width, h = data.height;
		quad(e.texture, m.tx, m.ty, m.a * w + m.tx, m.b * w + m.ty, m.a * w + m.c * h + m.tx, m.b * w + m.d * h + m.ty,
			m.c * h + m.tx, m.d * h + m.ty, b.smoothing, mul, add, false, e.version);
	}

	static var uploadScratch:haxe.io.Bytes = null;
	static inline var UPLOAD_SCRATCH_MAX = 16 << 20;

	static function upload(texture:h3d.mat.Texture, data:flash.display.BitmapData):Void {
		var w = data.width, h = data.height;
		var bytes:haxe.io.Bytes;
		if (data.__hasPixels()) {
			var n = w * h * 4;
			if (n > UPLOAD_SCRATCH_MAX) {
				bytes = data.pixels.sub(0, n);
			} else {
				if (uploadScratch == null || uploadScratch.length < n) uploadScratch = haxe.io.Bytes.alloc(n);
				uploadScratch.blit(0, data.pixels, 0, n);
				bytes = uploadScratch;
			}
		} else {
			bytes = haxe.io.Bytes.alloc(w * h * 4);
			var fill = @:privateAccess data.fill;
			if (fill != 0) for (i in 0...w * h) bytes.setInt32(i * 4, fill);
		}
		UploadStats.add("display bitmap", w * h * 4.0);
		texture.uploadPixels(new hxd.Pixels(w, h, bytes, BGRA));
	}

	function vector(g:flash.display.Graphics, m:flash.geom.Matrix, mul:Array<Float>, add:Array<Float>):Void {
		var shared = g.__shared();
		if (shared != null) g = shared;
		var px = Math.floor(m.tx), py = Math.floor(m.ty);
		var fx = Math.floor((m.tx - px) * 4) / 4, fy = Math.floor((m.ty - py) * 4) / 4;
		var head = vectors.get(g);
		var redrawn = false;
		if (head != null && head.version != g.__version) {
			retired.push(head);
			head = null;
			vectors.remove(g);
			redrawn = true;
		}
		var e = head, count = 0;
		while (e != null && !(sameLinear(e, m) && e.fx == fx && e.fy == fy && (!e.pinned || (e.px == px && e.py == py)))) {
			count++;
			if (count == VARIANTS && e.next != null) {
				retired.push(e.next);
				e.next = null;
			}
			e = e.next;
		}
		if (e != null) {
			variantHits++;
			head.used = frame;
		} else {
			var why = redrawn ? "redrawn" : head == null ? "new" : sameLinear(head, m) ? "phase" : "transform";
			rasterWhy(why);
			if (traceRasters) {
				var o = rasterOwner;
				var k = why + " " + (o == null ? "?" : Type.getClassName(Type.getClass(o)) + ":" + o.name);
				rasterTrace.set(k, (rasterTrace.exists(k) ? rasterTrace.get(k) : 0) + 1);
				if (traceRasterDetail) {
					var chain = 0, c = head;
					while (c != null) { chain++; c = c.next; }
					inline function r3(v:Float) return Math.round(v * 1000) / 1000;
					BootLog.log("raster " + k + " m " + r3(m.a) + "," + r3(m.b) + "," + r3(m.c) + "," + r3(m.d) + " t " + r3(m.tx)
						+ "," + r3(m.ty) + " chain " + chain + (head == null ? "" : " head " + r3(head.a) + "," + r3(head.d)
						+ " f " + head.fx + "," + head.fy) + " shared " + (shared != null) + " bounds " + g.bounds);
				}
			}
			e = new Cached();
			e.next = head;
			vectors.set(g, e);
			e.version = g.__version;
			e.a = m.a;
			e.b = m.b;
			e.c = m.c;
			e.d = m.d;
			e.fx = fx;
			e.fy = fy;
			var r = g.bounds;
			var xs = [r.x, r.x + r.width], ys = [r.y, r.y + r.height];
			var x0 = Math.POSITIVE_INFINITY, y0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY;
			for (x in xs) for (y in ys) {
				var tx = m.a * x + m.c * y + fx, ty = m.b * x + m.d * y + fy;
				if (tx < x0) x0 = tx;
				if (ty < y0) y0 = ty;
				if (tx > x1) x1 = tx;
				if (ty > y1) y1 = ty;
			}
			var left = Math.floor(x0) - 2, top = Math.floor(y0) - 2;
			var w = Math.ceil(x1) + 2 - left, h = Math.ceil(y1) + 2 - top;
			if (w > VectorRaster.MAX || h > VectorRaster.MAX) {
				var cl = Std.int(Math.max(left, -px)), ct = Std.int(Math.max(top, -py));
				var cr = Std.int(Math.min(left + w, Math.ceil(width) - px)), cb = Std.int(Math.min(top + h, Math.ceil(height) - py));
				if (cr > cl && cb > ct && cr - cl <= VectorRaster.MAX && cb - ct <= VectorRaster.MAX) {
					left = cl;
					top = ct;
					w = cr - cl;
					h = cb - ct;
					e.pinned = true;
					e.px = px;
					e.py = py;
					skip("drawing over " + VectorRaster.MAX + " px (its part on the stage)");
				}
			}
			var scale = 1.0;
			if (w > VectorRaster.MAX || h > VectorRaster.MAX) {
				scale = VectorRaster.MAX / Math.max(w, h);
				skip("drawing over " + VectorRaster.MAX + " px (scaled to fit)");
			}
			if (w > 0 && h > 0) {
				var started = haxe.Timer.stamp();
				var rw = scale < 1 ? Std.int(Math.max(1, Math.min(VectorRaster.MAX, Math.floor(w * scale)))) : w;
				var rh = scale < 1 ? Std.int(Math.max(1, Math.min(VectorRaster.MAX, Math.floor(h * scale)))) : h;
				var at = new flash.geom.Matrix(m.a * scale, m.b * scale, m.c * scale, m.d * scale, (fx - left) * scale,
					(fy - top) * scale);
				if (useAtlas && RasterAtlas.fits(rw, rh)) {
					var slot = atlas.alloc(rw, rh);
					if (raster.drawGraphicsSlot(g, at, rw, rh, slot)) {
						e.slot = slot;
						e.atlas = atlas;
						e.texture = slot.page;
						e.uv = [slot.x / RasterAtlas.PAGE, slot.y / RasterAtlas.PAGE, (slot.x + rw) / RasterAtlas.PAGE,
							(slot.y + rh) / RasterAtlas.PAGE];
					} else {
						atlas.release(slot);
					}
				} else {
					e.texture = raster.drawGraphicsTexture(g, at, rw, rh);
				}
				e.premultiplied = true;
				e.left = left;
				e.top = top;
				e.width = w;
				e.height = h;
				rasters++;
				var spent = haxe.Timer.stamp() - started;
				rasterSeconds += spent;
				if (onRaster != null) onRaster(w * h, spent * 1000);
			}
		}
		e.used = frame;
		if (e.texture == null) return;
		var x0 = px + e.left, y0 = py + e.top, x1 = x0 + e.width, y1 = y0 + e.height;
		quad(e.texture, x0, y0, x1, y0, x1, y1, x0, y1, false, mul, add, true, e.slot != null ? e.slot.serial : 0, e.uv);
	}

	@:access(flash.text.TextField)
	function text(tf:flash.text.TextField, m:flash.geom.Matrix, mul:Array<Float>, add:Array<Float>):Void {
		tf.__layout();
		var layoutKey = port.engine.text.TextLayout.key(tf);
		port.engine.text.TextLayout.deviceProbe(tf, m);
		var kind = port.engine.text.TextLayout.deviceKind, scale = port.engine.text.TextLayout.deviceScale;
		var phase = port.engine.text.TextLayout.devicePhase;
		var caret = port.engine.text.TextLayout.caretOn(tf) ? tf.caretIndex : -1, scrollV = tf.__scrollV;
		var cache = texts.get(tf);
		if (cache == null) {
			cache = new TextCache(null);
			texts.set(tf, cache);
		}
		cache.used = frame;
		var key = cache.key;
		if (key == null || cache.layoutKey != layoutKey || cache.kind != kind || cache.scale != scale || cache.phase != phase
			|| cache.caret != caret || cache.scrollV != scrollV) {
			key = layoutKey + port.engine.text.TextLayout.deviceKey(tf, m) + port.engine.text.TextLayout.stateKey(tf);
			cache.layoutKey = layoutKey;
			cache.kind = kind;
			cache.scale = scale;
			cache.phase = phase;
			cache.caret = caret;
			cache.scrollV = scrollV;
		}
		if (cache.key != key) {
			cache.key = key;
			var shared = textDrawings.get(key);
			if (shared == null) {
				shared = new flash.display.Graphics(null);
				port.engine.text.TextLayout.draw(tf, shared, m);
				textDrawings.set(key, shared);
				textsLaidOut++;
			}
			cache.graphics = shared;
		}
		textUsed.set(key, frame);
		var g = cache.graphics;
		if (g.bounds != null && (g.fills.length > 0 || g.strokes.length > 0)) {
			var saved = clip;
			if (clipText) clip = intersect(clip, box(m, 0, 0, tf.__width, tf.__height));
			vector(g, m, mul, add);
			clip = saved;
		}
	}

	static var clipText = Sys.getEnv("BH_PORT_TEXT_CLIP") != "0";

	public static var textsLaidOut(default, null) = 0;

	function quad(texture:h3d.mat.Texture, x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float,
			smooth:Bool, mul:Array<Float>, add:Array<Float>, premultiplied = false, version = 0, ?uv:Array<Float>):Void {
		if (clip != null && (clip[2] <= clip[0] || clip[3] <= clip[1] || clip[2] <= x0 && clip[2] <= x1 && clip[2] <= x2
			&& clip[2] <= x3)) {
			return;
		}
		quads.push(takeQuad(texture, x0, y0, x1, y1, x2, y2, x3, y3, smooth, mul, add, premultiplied, version, uv));
	}

	var listPool:Array<Array<Quad>> = [];
	var listsUsed = 0;

	function takeList():Array<Quad> {
		if (listsUsed < listPool.length) {
			var l = listPool[listsUsed++];
			l.resize(0);
			return l;
		}
		var l:Array<Quad> = [];
		listPool.push(l);
		listsUsed++;
		return l;
	}

	var quadPool:Array<Quad> = [];
	var quadsUsed = 0;

	function takeQuad(texture:h3d.mat.Texture, x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float, x3:Float,
			y3:Float, smooth:Bool, mul:Array<Float>, add:Array<Float>, premultiplied:Bool, version:Int, uv:Array<Float>):Quad {
		var q:Quad;
		if (quadsUsed < quadPool.length) {
			q = quadPool[quadsUsed];
		} else {
			q = {texture: null, layer: null, p: [0.0, 0, 0, 0, 0, 0, 0, 0], smooth: false, mul: null, add: null,
				premultiplied: false, clip: null, version: 0};
			quadPool.push(q);
		}
		quadsUsed++;
		var p = q.p;
		p[0] = x0;
		p[1] = y0;
		p[2] = x1;
		p[3] = y1;
		p[4] = x2;
		p[5] = y2;
		p[6] = x3;
		p[7] = y3;
		q.texture = texture;
		q.layer = null;
		q.smooth = smooth;
		q.mul = mul;
		q.add = add;
		q.premultiplied = premultiplied;
		q.clip = clip;
		q.version = version;
		q.uv = uv;
		return q;
	}
}

@:structInit private class Quad {
	public var texture:h3d.mat.Texture;
	public var layer:Layer;
	public var p:Array<Float>;
	public var smooth:Bool;
	public var mul:Array<Float>;
	public var add:Array<Float>;
	public var premultiplied:Bool;
	public var clip:Array<Float>;
	public var version:Int;
	public var uv:Array<Float> = null;
}

private class Layer {
	public var object:flash.display.DisplayObject;
	public var quads:Array<Quad>;
	public var filters:Array<flash.filters.BitmapFilter>;
	public var ox:Float;
	public var oy:Float;
	public var w:Int;
	public var h:Int;
	public var key:String;
	public var out:h3d.mat.Texture;
	public var maskQuads:Array<Quad>;
	public var mask:h3d.mat.Texture;

	public function new(object, quads, filters, ox, oy, w, h, key) {
		this.object = object;
		this.quads = quads;
		this.filters = filters;
		this.ox = ox;
		this.oy = oy;
		this.w = w;
		this.h = h;
		this.key = key;
	}
}

private class LayerCache {
	public var out:h3d.mat.Texture;
	public var key:String;
	public var width = 0;
	public var height = 0;
	public var used = 0;

	public function new() {}

	public function dispose():Void {
		if (out != null) out.dispose();
		out = null;
	}
}

private class TextCache {
	public var graphics:flash.display.Graphics;
	public var key:String;
	public var used = 0;
	public var layoutKey:String = null;
	public var kind = 0;
	public var scale = 0.0;
	public var phase = 0;
	public var caret = -1;
	public var scrollV = 0;

	public function new(graphics) {
		this.graphics = graphics;
	}
}

private class Cached {
	public var texture:h3d.mat.Texture;
	public var version = 0;
	public var used = 0;
	public var width = 0;
	public var height = 0;
	public var left = 0;
	public var top = 0;
	public var a = 0.0;
	public var b = 0.0;
	public var c = 0.0;
	public var d = 0.0;
	public var fx = 0.0;
	public var fy = 0.0;
	public var premultiplied = false;
	public var pinned = false;
	public var px = 0;
	public var py = 0;

	public var next:Cached;

	public var slot:port.engine.art.RasterAtlas.AtlasSlot;
	public var atlas:RasterAtlas;
	public var uv:Array<Float>;

	public function new() {}

	public function dispose():Void {
		if (slot != null) {
			atlas.release(slot);
			slot = null;
		} else if (texture != null) {
			texture.dispose();
		}
		texture = null;
	}

	public function chainBytes():Float {
		var bytes = 0.0, e = this;
		while (e != null) {
			if (e.texture != null) bytes += e.width * e.height * 4.0;
			e = e.next;
		}
		return bytes;
	}

	public function disposeChain():Void {
		var e = this;
		while (e != null) {
			e.dispose();
			e = e.next;
		}
	}
}

private class Range extends h3d.prim.Primitive {
	public var source:h3d.Buffer;
	public var start = 0;
	public var count = 0;

	public function new() {}

	override function triCount()
		return count;

	override function render(engine:h3d.Engine) {
		if (count > 0) engine.renderTriBuffer(source, start, count);
	}
}

private class QuadShader extends h3d.shader.ScreenShader {
	static var SRC = {
		@param var texture : Sampler2D;
		@param var mul : Vec4;
		@param var add : Vec4;
		@const var premultiplied : Bool;
		@const var masked : Bool;
		@param var maskTexture : Sampler2D;
		function fragment() {
			var t = texture.get(calculatedUV);
			if( masked ) t *= maskTexture.get(calculatedUV).a;
			if( premultiplied && t.a > 0 ) t = vec4(t.rgb / t.a, t.a);
			var c = clamp(t * mul + add, vec4(0, 0, 0, 0), vec4(1, 1, 1, 1));
			pixelColor = vec4(c.rgb * c.a, c.a);
		}
	};
}

private class LayerKey {
	public var key:String = null;
	public var nums:Array<Float> = [];
	public var strs:Array<String> = [];
	public var used = 0;

	public function new() {}

	public function same(n:Array<Float>, s:Array<String>):Bool {
		if (n.length != nums.length || s.length != strs.length) return false;
		for (i in 0...n.length) if (n[i] != nums[i]) return false;
		for (i in 0...s.length) if (s[i] != strs[i]) return false;
		return true;
	}
}
