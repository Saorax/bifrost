package port.engine.art;

import port.engine.art.VectorRecord;

@:access(flash.display.BitmapData)
class VectorRaster {
	public static inline var MAX = 2048;
	static inline var OFFSET_X = -0.0625;

	public static var draws(default, null) = 0;
	public static var seconds(default, null) = 0.0;
	public static var fillsDrawn(default, null) = 0;
	public static var strokesDrawn(default, null) = 0;
	public static var residentDraws(default, null) = 0;
	public static var readBackDraws(default, null) = new Map<String, Int>();
	public static var readBackBy(default, null) = new Map<String, Int>();

	static var traceCallers = Sys.getEnv("BH_PORT_TRACE_PIXELS") == "1";

	static function drawCaller():String {
		if (!traceCallers) return "?";
		var out = [];
		for (item in haxe.CallStack.callStack()) {
			if (out.length >= 3) break;
			var s = StringTools.trim(haxe.CallStack.toString([item]).split("\n").join(" "));
			if (s.indexOf("VectorRaster") < 0 && s.indexOf("BitmapData") < 0 && s.indexOf("CallStack") < 0
				&& s.indexOf("DrawStats") < 0) out.push(s);
		}
		return out.join(" < ");
	}

	public static function readBackReport():String {
		var keys = [for (k in readBackBy.keys()) k];
		keys.sort((a, b) -> readBackBy.get(b) - readBackBy.get(a));
		return [for (k in keys.slice(0, 6)) readBackBy.get(k) + "x " + k].join(" | ");
	}
	public static var notDrawn(default, null) = new Map<String, Int>();

	var engine:h3d.Engine;
	var parityShader = new ParityShader();
	var coverShader = new CoverShader();
	var downShader = new DownShader();
	var parity:h3d.pass.ScreenFx<ParityShader>;
	var union:h3d.pass.ScreenFx<ParityShader>;
	var cover:h3d.pass.ScreenFx<CoverShader>;
	var down:h3d.pass.ScreenFx<DownShader>;
	var clear:h3d.pass.ScreenFx<ClearShader>;
	var range = new Range();
	static var useStencil = Sys.getEnv("BH_PORT_RASTER_STENCIL") != "0";
	var parityS:Array<h3d.pass.ScreenFx<ParityShader>> = [];
	var unionS:Array<h3d.pass.ScreenFx<ParityShader>> = [];
	var coverS:Array<h3d.pass.ScreenFx<CoverShader>> = [];
	static var stencilBits = Sys.getEnv("BH_PORT_RASTER_BITS") == "1" ? 1 : 8;
	var noMask:h3d.mat.Texture;

	public function new(engine:h3d.Engine) {
		this.engine = engine;
		parity = new h3d.pass.ScreenFx(parityShader);
		parity.pass.blend(OneMinusDstColor, Zero);
		parity.primitive = range;
		union = new h3d.pass.ScreenFx(parityShader);
		union.pass.blend(One, Zero);
		union.primitive = range;
		cover = new h3d.pass.ScreenFx(coverShader);
		cover.pass.blend(One, OneMinusSrcAlpha);
		cover.primitive = range;
		down = new h3d.pass.ScreenFx(downShader);
		down.pass.blend(One, OneMinusSrcAlpha);
		down.primitive = range;
		clear = new h3d.pass.ScreenFx(new ClearShader());
		clear.pass.blend(One, Zero);
		clear.primitive = range;
		if (useStencil) {
			for (k in 0...stencilBits) {
				var bit = 1 << k;
				var p = new h3d.pass.ScreenFx(parityShader);
				p.pass.setColorMask(false, false, false, false);
				p.pass.stencil = new h3d.mat.Stencil();
				p.pass.stencil.setFunc(Always, 0, 0xFF, bit);
				p.pass.stencil.setOp(Keep, Keep, Invert);
				p.primitive = range;
				parityS.push(p);
				var u = new h3d.pass.ScreenFx(parityShader);
				u.pass.setColorMask(false, false, false, false);
				u.pass.stencil = new h3d.mat.Stencil();
				u.pass.stencil.setFunc(Always, 0xFF, 0xFF, bit);
				u.pass.stencil.setOp(Keep, Keep, Replace);
				u.primitive = range;
				unionS.push(u);
				var c = new h3d.pass.ScreenFx(coverShader);
				c.pass.blend(One, OneMinusSrcAlpha);
				c.pass.stencil = new h3d.mat.Stencil();
				c.pass.stencil.setFunc(NotEqual, 0, bit, bit);
				c.pass.stencil.setOp(Keep, Keep, Zero);
				c.primitive = range;
				coverS.push(c);
			}
			var white = hxd.Pixels.alloc(1, 1, BGRA);
			white.setPixel(0, 0, 0xFFFFFFFF);
			noMask = new h3d.mat.Texture(1, 1);
			noMask.filter = Nearest;
			noMask.uploadPixels(white);
		}
	}

	static function makeTargets(bw:Int, bh:Int, pooled:Bool):Targets {
		var scratch = new h3d.mat.Texture(bw * 4, bh * 4, [Target]);
		if (!useStencil) return new Targets(new h3d.mat.Texture(bw * 4, bh * 4, [Target]), scratch, bw, bh, pooled);
		scratch.depthBuffer = new h3d.mat.Texture(bw * 4, bh * 4, null, Depth24Stencil8);
		return new Targets(null, scratch, bw, bh, pooled);
	}

	static var POOL_BYTES = {
		var mb = Std.parseInt(Sys.getEnv("BH_PORT_RASTER_POOL_MB"));
		(mb == null || mb <= 0 ? 128 : mb) * 1024.0 * 1024;
	};
	var pool = new port.engine.NativeIntMap<Targets>();
	var pooledBytes = 0.0;
	public static var targetsMade(default, null) = 0;
	public static var poolFlushes(default, null) = 0;
	public static var largeTargetsMade(default, null) = 0;

	public static function bucket(n:Int):Int {
		return n <= 128 ? (n + 15) & ~15 : n <= 512 ? (n + 63) & ~63 : n;
	}

	static var POOL_FIT = {
		var f = Std.parseFloat(Sys.getEnv("BH_PORT_RASTER_POOL_FIT"));
		Math.isNaN(f) ? 2.0 : f < 1 ? 1.0 : f;
	};
	public static var poolFits(default, null) = 0;

	function existingTargets(w:Int, h:Int):Null<Targets> {
		var bw = bucket(w), bh = bucket(h);
		if (w > 512 || h > 512) return keepLarge && large != null && large.w >= bw && large.h >= bh ? large : null;
		var t = pool.get((bw << 16) | bh);
		if (t != null || POOL_FIT <= 1) return t;
		var limit = POOL_FIT * bw * bh, best:Targets = null;
		for (p in pool) if (p.w >= bw && p.h >= bh && p.w * p.h <= limit && (best == null || p.w * p.h < best.w * best.h)) best = p;
		return best;
	}

	function targetSize(w:Int, h:Int):{w:Int, h:Int} {
		var t = existingTargets(w, h);
		if (t != null) return {w: t.w, h: t.h};
		var bw = bucket(w), bh = bucket(h);
		if ((w > 512 || h > 512) && keepLarge && large != null)
			return {w: large.w > bw ? large.w : bw, h: large.h > bh ? large.h : bh};
		return {w: bw, h: bh};
	}

	function targetsFor(w:Int, h:Int):Targets {
		var bw = bucket(w), bh = bucket(h);
		var found = existingTargets(w, h);
		if (found != null) {
			if (found.pooled && found != large) {
				found.used = ++poolClock;
				if (found.w != bw || found.h != bh) poolFits++;
			}
			return found;
		}
		if (w > 512 || h > 512) {
			if (keepLarge) {
				var lw = large == null ? bw : (large.w > bw ? large.w : bw), lh = large == null ? bh : (large.h > bh ? large.h : bh);
				if (large != null) large.dispose();
				targetsMade++;
				largeTargetsMade++;
				return large = makeTargets(lw, lh, true);
			}
			targetsMade++;
			largeTargetsMade++;
			return makeTargets(bw, bh, false);
		}
		var key = (bw << 16) | bh;
		var bytes = bw * bh * 16 * 4 * 2.0;
		while (pooledBytes + bytes > POOL_BYTES) {
			var oldest:Targets = null;
			for (old in pool) if (oldest == null || old.used < oldest.used) oldest = old;
			if (oldest == null) break;
			pool.remove((oldest.w << 16) | oldest.h);
			pooledBytes -= oldest.w * oldest.h * 16 * 4 * 2.0;
			oldest.dispose();
			poolFlushes++;
		}
		targetsMade++;
		var t = makeTargets(bw, bh, true);
		t.used = ++poolClock;
		pool.set(key, t);
		pooledBytes += bytes;
		return t;
	}

	var poolClock = 0;
	var large:Targets = null;
	static var keepLarge = Sys.getEnv("BH_PORT_RASTER_KEEP_LARGE") != "0";

	public static var betweenFrames(default, null) = 0;

	static function skip(why:String):Void {
		notDrawn.set(why, (notDrawn.exists(why) ? notDrawn.get(why) : 0) + 1);
	}

	public function draw(target:flash.display.BitmapData, source:flash.display.DisplayObject, matrix:flash.geom.Matrix,
			colorTransform:flash.geom.ColorTransform, clipRect:flash.geom.Rectangle):Bool {
		var started = haxe.Timer.stamp();
		var drawn = drawTimed(target, source, matrix, colorTransform, clipRect);
		seconds += haxe.Timer.stamp() - started;
		return drawn;
	}

	function drawTimed(target:flash.display.BitmapData, source:flash.display.DisplayObject, matrix:flash.geom.Matrix,
			colorTransform:flash.geom.ColorTransform, clipRect:flash.geom.Rectangle):Bool {
		if (!@:privateAccess engine.inRender) {
			if (@:privateAccess engine.driver.isDisposed()) {
				skip("outside a frame");
				return false;
			}
			betweenFrames++;
			@:privateAccess engine.inRender = true;
			var drawn = try drawTimed(target, source, matrix, colorTransform, clipRect) catch (e:Dynamic) {
				@:privateAccess engine.inRender = false;
				throw e;
			}
			@:privateAccess engine.inRender = false;
			return drawn;
		}
		var w = target.width, h = target.height;
		if (w > MAX || h > MAX) {
			skip("larger than " + MAX + " (tiled)");
			var ok = true;
			var ty = 0;
			while (ty < h) {
				var th = Std.int(Math.min(MAX, h - ty));
				var tx = 0;
				while (tx < w) {
					var tw = Std.int(Math.min(MAX, w - tx));
					var tile = new flash.display.BitmapData(tw, th, true, 0);
					tile.copyPixels(target, new flash.geom.Rectangle(tx, ty, tw, th), new flash.geom.Point(0, 0));
					var moved = matrix != null ? matrix.clone() : new flash.geom.Matrix();
					moved.translate(-tx, -ty);
					var shapes:Array<Item> = [];
					collect(source, moved, colorTransform, true, shapes);
					var tileClip = clipRect == null ? null
						: new flash.geom.Rectangle(clipRect.x - tx, clipRect.y - ty, clipRect.width, clipRect.height);
					if (!drawItems(tile, tw, th, shapes, tileClip)) ok = false;
					target.copyPixels(tile, tile.rect, new flash.geom.Point(tx, ty));
					tile.dispose();
					tx += tw;
				}
				ty += th;
			}
			return ok;
		}
		var shapes:Array<Item> = [];
		collect(source, matrix != null ? matrix.clone() : new flash.geom.Matrix(), colorTransform, true, shapes);
		return drawItems(target, w, h, shapes, clipRect);
	}

	public function drawGraphics(target:flash.display.BitmapData, graphics:flash.display.Graphics,
			matrix:flash.geom.Matrix):Bool {
		if (!@:privateAccess engine.inRender) return false;
		if (target.width > MAX || target.height > MAX) return false;
		return drawItems(target, target.width, target.height, [new Item(graphics, matrix, null)], null);
	}

	public function drawGraphicsTexture(graphics:flash.display.Graphics, matrix:flash.geom.Matrix, w:Int, h:Int):h3d.mat.Texture {
		if (!@:privateAccess engine.inRender || w > MAX || h > MAX || w <= 0 || h <= 0) return null;
		kept = null;
		drawItems(null, w, h, [new Item(graphics, matrix, null)], null);
		var texture = kept;
		kept = null;
		return texture;
	}

	public function drawGraphicsSlot(graphics:flash.display.Graphics, matrix:flash.geom.Matrix, w:Int, h:Int,
			slot:RasterAtlas.AtlasSlot):Bool {
		if (!@:privateAccess engine.inRender || w > slot.w || h > slot.h || w <= 0 || h <= 0) return false;
		into = slot;
		kept = null;
		drawItems(null, w, h, [new Item(graphics, matrix, null)], null);
		var drawn = kept != null;
		into = null;
		kept = null;
		return drawn;
	}

	var kept:h3d.mat.Texture;
	var into:RasterAtlas.AtlasSlot;

	function drawItems(target:Null<flash.display.BitmapData>, w:Int, h:Int, shapes:Array<Item>,
			clipRect:flash.geom.Rectangle):Bool {
		if (shapes.length == 0) return true;
		if (Lambda.exists(shapes, s -> s.content != null)) {
			var layers:Array<flash.display.BitmapData> = [];
			var drawn = drawItems(target, w, h, [for (s in shapes) if (s.content == null) s else filteredLayer(s, w, h, layers)]
				.filter(s -> s != null), clipRect);
			for (l in layers) l.dispose();
			return drawn;
		}
		var w4 = w * 4, h4 = h * 4;
		var v = busy ? new hxd.FloatBuffer() : vertices;
		var fans = busy ? new PathFans() : sharedFans;
		var pathData = busy ? new Array<Float>() : sharedPath;
		var wasBusy = busy;
		busy = true;
		v.getNative().resize(0);
		var entered = FxContext.enter();
		var drawn = drawItemsWith(target, w, h, w4, h4, shapes, clipRect, v, fans, pathData);
		FxContext.leave(entered);
		busy = wasBusy;
		return drawn;
	}

	var busy = false;
	var vertices = new hxd.FloatBuffer();
	var sharedFans = new PathFans();
	var sharedPath = new Array<Float>();
	var sharedBuffer:h3d.Buffer;
	static var keepBuffer = Sys.getEnv("BH_PORT_RASTER_BUFFER_PER_DRAW") != "1";

	function drawItemsWith(target:Null<flash.display.BitmapData>, w:Int, h:Int, w4:Int, h4:Int, shapes:Array<Item>,
			clipRect:flash.geom.Rectangle, v:hxd.FloatBuffer, fans:PathFans, pathData:Array<Float>):Bool {
		var slot = target == null ? into : null;
		if (useTiles && tile == null && slot == null && (w > TILE || h > TILE)) {
			if (checkTiles) checkTiled(w, h, shapes, v, fans, pathData);
			return drawTiled(target, w, h, shapes, clipRect, v, fans, pathData);
		}
		var size = targetSize(w, h);
		var tw4 = size.w * 4, th4 = size.h * 4;
		var tris = 0;
		var ramps:Array<Array<Int>> = [];
		var bitmaps = new Map<flash.display.BitmapData, h3d.mat.Texture>();
		var plans:Array<{fills:Array<FillPlan>, composite:Int}> = [];
		for (item in shapes) {
			var plan = {fills: [], composite: 0};
			for (fill in item.graphics.fills) {
				var paint = fill.paint;
				if (paint.kind == Paint.BITMAP && (paint.bitmap == null || paint.bitmap.width <= 0)) {
					skip("bitmap fill without a bitmap");
					continue;
				}
				fans.reset();
				fans.direct(v.getNative(), 2 / tw4, 2 / th4);
				fans.add(fill.commands, transformed(fill.data, fill.commands, item.matrix, 4, pathData));
				fans.flush();
				if (fans.count == 0) continue;
				if (fans.x0 >= w4 || fans.y0 >= h4 || fans.x1 <= 0 || fans.y1 <= 0) {
					tris += fans.count;
					fillsOutside++;
					continue;
				}
				var start = tris;
				tris += fans.count;
				quad(v, Math.max(0, Math.floor(fans.x0)), Math.max(0, Math.floor(fans.y0)), Math.min(w4, Math.ceil(fans.x1)),
					Math.min(h4, Math.ceil(fans.y1)), tw4, th4);
				tris += 2;
				var fp = new FillPlan(start, fans.count);
				paintPlan(fp, paint, item, ramps, bitmaps);
				plan.fills.push(fp);
				fillsDrawn++;
			}
			for (stroke in item.graphics.strokes) {
				var paint = stroke.paint;
				if (paint == null || paint.kind == Paint.BITMAP && (paint.bitmap == null || paint.bitmap.width <= 0)) {
					skip("stroke without paint");
					continue;
				}
				var outline = new StrokeOutline(strokeWidth(stroke, item.matrix) * 4, stroke.caps, stroke.joints,
					stroke.miterLimit);
				outline.add(stroke.commands, transformed(stroke.data, stroke.commands, item.matrix, 4, pathData));
				outline.flush();
				if (outline.count == 0) continue;
				if (outline.x0 >= w4 || outline.y0 >= h4 || outline.x1 <= 0 || outline.y1 <= 0) {
					fillsOutside++;
					continue;
				}
				var start = tris;
				pushTriangles(v, outline.triangles, tw4, th4);
				tris += outline.count;
				quad(v, Math.max(0, Math.floor(outline.x0)), Math.max(0, Math.floor(outline.y0)),
					Math.min(w4, Math.ceil(outline.x1)), Math.min(h4, Math.ceil(outline.y1)), tw4, th4);
				tris += 2;
				var fp = new FillPlan(start, outline.count);
				fp.union = true;
				paintPlan(fp, paint, item, ramps, bitmaps);
				plan.fills.push(fp);
				strokesDrawn++;
			}
			if (plan.fills.length == 0) continue;
			plan.composite = tris;
			if (slot != null) quadUV(v, slot.x, slot.y, slot.x + w, slot.y + h, RasterAtlas.PAGE, RasterAtlas.PAGE, 0, 0,
				w / (tw4 / 4), h / (th4 / 4));
			else if (tile != null) quadUV(v, tile.ox, tile.oy, tile.ox + w, tile.oy + h, tile.w, tile.h, 0, 0,
				w / (tw4 / 4), h / (th4 / 4));
			else quad(v, 0, 0, w, h, w, h, tw4 / 4, th4 / 4);
			quad(v, 0, 0, w4, h4, tw4, th4);
			tris += 4;
			plans.push(plan);
		}
		if (plans.length == 0) return true;
		var slotClear = tris;
		if (slot != null) {
			quad(v, slot.x, slot.y, slot.x + slot.w, slot.y + slot.h, RasterAtlas.PAGE, RasterAtlas.PAGE);
			tris += 2;
		}
		draws++;
		var buffer:h3d.Buffer;
		if (v == vertices && keepBuffer) {
			var count = Math.ceil(v.length / 4);
			if (sharedBuffer == null || sharedBuffer.isDisposed() || sharedBuffer.vertices < count) {
				if (sharedBuffer != null) sharedBuffer.dispose();
				var room = 4096;
				while (room < count) room *= 2;
				sharedBuffer = new h3d.Buffer(room, hxd.BufferFormat.XY_UV, [Dynamic]);
			}
			port.engine.UploadStats.add("raster vertices", count * 16.0);
			sharedBuffer.uploadFloats(v, 0, count);
			buffer = sharedBuffer;
		} else {
			buffer = h3d.Buffer.ofFloats(v, hxd.BufferFormat.XY_UV);
		}
		range.source = buffer;
		var targets = targetsFor(w, h);
		var mask = targets.mask, scratch = targets.scratch;
		var rampTexture:h3d.mat.Texture = null;
		var rampRows = 1;
		if (ramps.length > 0) {
			rampTexture = rampsFor(ramps.length);
			rampRows = rampTexture.height;
			if (rampPixels == null || rampPixels.height != rampRows) rampPixels = hxd.Pixels.alloc(256, rampRows, BGRA);
			var pixels = rampPixels;
			for (row in 0...ramps.length) for (i in 0...256) pixels.setPixel(i, row, ramps[row][i]);
			port.engine.UploadStats.add("raster ramps", pixels.width * pixels.height * 4.0);
			rampTexture.uploadPixels(pixels);
		}
		var state = tile == null ? openOut(target, w, h, clipRect, slot) : tile.state != null ? tile.state
			: (tile.state = openOut(target, tile.w, tile.h, clipRect, null));
		var out = state.out;
		var stencil = mask == null;
		for (t in [mask, scratch]) {
			if (t == null) continue;
			t.filter = Nearest;
			engine.pushTarget(t);
			if (stencil && t == scratch) engine.clear(0, null, 0) else engine.clear(0);
			engine.popTarget();
		}
		if (slot != null) {
			engine.pushTarget(out);
			range.start = slotClear;
			range.count = 2;
			clear.render();
			engine.popTarget();
		}
		var anyTexture = stencil ? noMask : mask;
		coverShader.mask = anyTexture;
		coverShader.ramp = rampTexture != null ? rampTexture : anyTexture;
		coverShader.bitmap = anyTexture;
		coverShader.size.set(tw4, th4);
		coverShader.offset.set(OFFSET_X, 0);
		downShader.source = scratch;
		downShader.texel.set(1 / tw4, 1 / th4);
		for (plan in plans) {
			if (stencil) {
				engine.pushTarget(scratch);
				var fills = plan.fills, i = 0;
				while (i < fills.length) {
					var n = fills.length - i < stencilBits ? fills.length - i : stencilBits;
					for (k in 0...n) {
						var fill = fills[i + k];
						range.start = fill.start;
						range.count = fill.count;
						(fill.union ? unionS[k] : parityS[k]).render();
					}
					for (k in 0...n) {
						var fill = fills[i + k];
						range.start = fill.start + fill.count;
						range.count = 2;
						coverParams(fill, rampRows);
						coverS[k].render();
					}
					i += n;
				}
				engine.popTarget();
			} else {
				engine.pushTarget(mask);
				for (fill in plan.fills) {
					range.start = fill.start;
					range.count = fill.count;
					(fill.union ? union : parity).render();
					engine.popTarget();
					engine.pushTarget(scratch);
					range.start = fill.start + fill.count;
					range.count = 2;
					coverParams(fill, rampRows);
					cover.render();
					engine.popTarget();
					engine.pushTarget(mask);
					if (fill.union) {
						range.start = fill.start + fill.count;
						range.count = 2;
						clear.render();
					} else {
						range.start = fill.start;
						range.count = fill.count;
						parity.render();
					}
				}
				engine.popTarget();
			}
			engine.pushTarget(out);
			range.start = plan.composite;
			range.count = 2;
			down.render();
			engine.popTarget();
			engine.pushTarget(scratch);
			range.start = plan.composite + 2;
			clear.render();
			engine.popTarget();
		}
		if (tile == null) closeOut(target, state, clipRect);
		if (!targets.pooled) targets.dispose();
		for (t in bitmaps) t.dispose();
		if (buffer != sharedBuffer) buffer.dispose();
		return true;
	}

	function openOut(target:Null<flash.display.BitmapData>, w:Int, h:Int, clipRect:flash.geom.Rectangle,
			slot:RasterAtlas.AtlasSlot):OutState {
		var state = new OutState();
		if (slot != null) state.out = kept = slot.page;
		else if (target == null) state.out = kept = new h3d.mat.Texture(w, h, [Target]);
		else if (GpuBitmaps.engine != null && covers(clipRect, w, h)) {
			state.resident = target.__gpu != null ? target.__gpu : GpuBitmaps.adopt(target);
			GpuBitmaps.touch(target);
			state.out = state.resident;
			residentDraws++;
		} else {
			var why = GpuBitmaps.engine == null ? "off" : !covers(clipRect, w, h) ? "clip" : "CPU pixels";
			readBackDraws.set(why, (readBackDraws.exists(why) ? readBackDraws.get(why) : 0) + 1);
			var by = target.__pixelsBy == null ? "(not traced; " + target.width + "x" + target.height + (target.__gpuUsed > 0 ? ", was resident" : "")
				+ ") drawn from " + drawCaller() : target.__pixelsBy;
			readBackBy.set(by, (readBackBy.exists(by) ? readBackBy.get(by) : 0) + 1);
			state.out = state.readOut = new h3d.mat.Texture(w, h, [Target]);
		}
		if (state.resident == null && slot == null) {
			state.out.filter = Nearest;
			engine.pushTarget(state.out);
			engine.clear(0);
			engine.popTarget();
		}
		return state;
	}

	function closeOut(target:Null<flash.display.BitmapData>, state:OutState, clipRect:flash.geom.Rectangle):Void {
		if (state.resident != null) {
			state.resident.filter = Nearest;
			target.__version = flash.display.BitmapData.__nextVersion();
		} else if (target != null) {
			var pixels = state.out.capturePixels();
			pixels.convert(BGRA);
			composite(target, pixels, clipRect);
		}
		if (state.readOut != null) state.readOut.dispose();
	}

	public static inline var TILE = 512;
	static var useTiles = Sys.getEnv("BH_PORT_RASTER_TILES") != "0";
	public static var tiledDraws(default, null) = 0;
	public static var tilesDrawn(default, null) = 0;
	public static var fillsOutside(default, null) = 0;
	var tile:TileOut = null;

	function drawTiled(target:Null<flash.display.BitmapData>, w:Int, h:Int, shapes:Array<Item>, clipRect:flash.geom.Rectangle,
			v:hxd.FloatBuffer, fans:PathFans, pathData:Array<Float>):Bool {
		var t = new TileOut(w, h);
		tile = t;
		tiledDraws++;
		var ty = 0;
		while (ty < h) {
			var th = h - ty < TILE ? h - ty : TILE;
			var tx = 0;
			while (tx < w) {
				var tw = w - tx < TILE ? w - tx : TILE;
				t.ox = tx;
				t.oy = ty;
				v.getNative().resize(0);
				drawItemsWith(target, tw, th, tw * 4, th * 4, [for (s in shapes) moveItem(s, -tx, -ty)], clipRect, v, fans,
					pathData);
				tilesDrawn++;
				tx += tw;
			}
			ty += th;
		}
		tile = null;
		if (t.state != null) closeOut(target, t.state, clipRect);
		return true;
	}

	static var checkTiles = Sys.getEnv("BH_PORT_RASTER_TILE_CHECK") == "1";
	public static var tileChecks(default, null) = 0;
	public static var tileMismatches(default, null) = 0;

	function checkTiled(w:Int, h:Int, shapes:Array<Item>, v:hxd.FloatBuffer, fans:PathFans, pathData:Array<Float>):Void {
		var wasKept = kept;
		kept = null;
		v.getNative().resize(0);
		drawTiled(null, w, h, shapes, null, v, fans, pathData);
		var tiled = kept;
		kept = null;
		useTiles = false;
		v.getNative().resize(0);
		drawItemsWith(null, w, h, w * 4, h * 4, shapes, null, v, fans, pathData);
		useTiles = true;
		var whole = kept;
		kept = wasKept;
		v.getNative().resize(0);
		tileChecks++;
		if (tiled == null || whole == null) {
			if (tiled != whole) {
				tileMismatches++;
				port.engine.BootLog.log("tile check: " + w + "x" + h + " drawn " + (tiled != null) + " tiled, " + (whole != null) + " whole");
			}
			if (tiled != null) tiled.dispose();
			if (whole != null) whole.dispose();
			return;
		}
		var a = tiled.capturePixels(), b = whole.capturePixels();
		var off = 0, first = -1;
		for (i in 0...w * h * 4) if (a.bytes.get(a.offset + i) != b.bytes.get(b.offset + i)) {
			if (first < 0) first = i;
			off++;
		}
		if (off > 0) {
			tileMismatches++;
			port.engine.BootLog.log("tile check: " + w + "x" + h + " " + off + " bytes off, first at pixel (" + ((first >> 2) % w)
				+ ", " + Std.int((first >> 2) / w) + ")");
		}
		tiled.dispose();
		whole.dispose();
	}

	function coverParams(fill:FillPlan, rampRows:Int):Void {
		coverShader.kind = fill.kind;
		if (fill.kind != Paint.SOLID) {
			coverShader.row = (fill.row + 0.5) / rampRows;
			var m = fill.inverse;
			coverShader.inv.set(m[0], m[1], m[2], m[3]);
			coverShader.invT.set(m[4], m[5]);
			coverShader.focal = fill.focal;
			if (fill.kind == Paint.BITMAP) {
				coverShader.bitmap = fill.bitmap;
				coverShader.bitmapSize.set(fill.bitmap.width, fill.bitmap.height);
				coverShader.ctMul.set(fill.ctMul[0], fill.ctMul[1], fill.ctMul[2], fill.ctMul[3]);
				coverShader.ctAdd.set(fill.ctAdd[0], fill.ctAdd[1], fill.ctAdd[2], fill.ctAdd[3]);
			}
			coverShader.spread = fill.spread;
		}
		var c = fill.color, a = ((c >>> 24) & 255) / 255;
		coverShader.color.set(((c >> 16) & 255) / 255 * a, ((c >> 8) & 255) / 255 * a, (c & 255) / 255 * a, a);
	}

	var rampPool:h3d.mat.Texture;
	var rampPixels:hxd.Pixels;

	function rampsFor(rows:Int):h3d.mat.Texture {
		if (rampPool == null || rampPool.height < rows) {
			var n = 8;
			while (n < rows) n *= 2;
			if (rampPool != null) rampPool.dispose();
			rampPool = new h3d.mat.Texture(256, n);
			rampPool.filter = Nearest;
		}
		return rampPool;
	}

	static function covers(clipRect:flash.geom.Rectangle, w:Int, h:Int):Bool {
		return clipRect == null || (clipRect.x <= 0 && clipRect.y <= 0 && clipRect.x + clipRect.width >= w
			&& clipRect.y + clipRect.height >= h);
	}

	static function pushTriangles(v:hxd.FloatBuffer, t:Array<Float>, w4:Float, h4:Float):Void {
		var n = t.length >> 1;
		if (n == 0) return;
		var out = v.getNative();
		var j = out.length;
		out[j + n * 4 - 1] = 0;
		var sx = 2 / w4, sy = 2 / h4;
		for (i in 0...n) {
			out[j] = t[i * 2] * sx - 1;
			out[j + 1] = 1 - t[i * 2 + 1] * sy;
			out[j + 2] = 0;
			out[j + 3] = 0;
			j += 4;
		}
	}

	static function paintPlan(fp:FillPlan, paint:Paint, item:Item, ramps:Array<Array<Int>>,
			bitmaps:Map<flash.display.BitmapData, h3d.mat.Texture>):Void {
		if (paint.kind == Paint.BITMAP) {
			bitmapPlan(fp, paint, item, bitmaps);
		} else if (paint.kind == Paint.SOLID) {
			fp.color = transformColor(paint.color, paint.alpha, item.ct);
		} else {
			fp.kind = paint.kind;
			fp.row = ramps.length;
			if (paint.ramp == null) paint.ramp = GradientRamp.build([for (r in paint.ratios) r / 1], paint.colors, paint.alphas,
				paint.interpolation == "linearRGB");
			ramps.push(item.ct == null ? paint.ramp : [for (c in paint.ramp) transformArgb(c, item.ct)]);
			fp.inverse = gradientInverse(paint.matrix, item.matrix);
			fp.spread = paint.spread == "reflect" ? 1 : paint.spread == "repeat" ? 2 : 0;
			fp.focal = paint.focal;
		}
	}

	static function bitmapPlan(fp:FillPlan, paint:Paint, item:Item, bitmaps:Map<flash.display.BitmapData, h3d.mat.Texture>):Void {
		fp.kind = Paint.BITMAP;
		var tex = bitmaps.get(paint.bitmap);
		if (tex == null) {
			var b = paint.bitmap, w = b.width, h = b.height;
			var bytes = haxe.io.Bytes.alloc(w * h * 4);
			var pixels = b.pixels;
			if (pixels != null) bytes.blit(0, pixels, 0, w * h * 4);
			else for (i in 0...w * h) bytes.setInt32(i * 4, @:privateAccess b.fill);
			tex = new h3d.mat.Texture(w, h);
			port.engine.UploadStats.add("raster bitmap fill", w * h * 4.0);
			tex.uploadPixels(new hxd.Pixels(w, h, bytes, BGRA));
			bitmaps.set(paint.bitmap, tex);
		}
		tex.filter = paint.smooth ? Linear : Nearest;
		tex.wrap = paint.repeat ? Repeat : Clamp;
		fp.bitmap = tex;
		fp.inverse = gradientInverse(paint.matrix, item.matrix);
		var ct = item.ct;
		fp.ctMul = ct == null ? [1, 1, 1, 1] : [ct.redMultiplier, ct.greenMultiplier, ct.blueMultiplier, ct.alphaMultiplier];
		fp.ctAdd = ct == null ? [0, 0, 0, 0] : [ct.redOffset / 255, ct.greenOffset / 255, ct.blueOffset / 255, ct.alphaOffset / 255];
	}

	static function strokeWidth(stroke:StrokeRecord, m:flash.geom.Matrix):Float {
		var sx = Math.sqrt(m.a * m.a + m.b * m.b), sy = Math.sqrt(m.c * m.c + m.d * m.d);
		var scale = switch (stroke.scaleMode) {
			case "none": 1.0;
			case "horizontal": sx;
			case "vertical": sy;
			default: (sx + sy) / 2;
		}
		var w = (Math.isNaN(stroke.thickness) ? 0 : stroke.thickness) * scale;
		return w < 1 ? 1 : w;
	}

	static function composite(target:flash.display.BitmapData, pixels:hxd.Pixels, clipRect:flash.geom.Rectangle):Void {
		var x0 = 0, y0 = 0, x1 = target.width, y1 = target.height;
		if (clipRect != null) {
			x0 = Std.int(Math.max(0, Math.floor(clipRect.x)));
			y0 = Std.int(Math.max(0, Math.floor(clipRect.y)));
			x1 = Std.int(Math.min(x1, Math.ceil(clipRect.x + clipRect.width)));
			y1 = Std.int(Math.min(y1, Math.ceil(clipRect.y + clipRect.height)));
		}
		var bytes = pixels.bytes, stride = pixels.width * 4;
		for (y in y0...y1) for (x in x0...x1) {
			var o = pixels.offset + y * stride + x * 4;
			var a = bytes.get(o + 3);
			if (a == 0) continue;
			var b = bytes.get(o), g = bytes.get(o + 1), r = bytes.get(o + 2);
			inline function straight(v:Int) return v >= a ? 255 : Std.int(v * 255 / a + 0.5);
			var c = (a << 24) | (straight(r) << 16) | (straight(g) << 8) | straight(b);
			target.put(x, y, target.opaque(flash.display.BitmapData.over(c, target.word(x, y))));
		}
	}

	static function collect(o:flash.display.DisplayObject, m:flash.geom.Matrix, ct:flash.geom.ColorTransform, root:Bool,
			out:Array<Item>):Void {
		if (o == null || (!root && !o.visible)) return;
		var mm = m;
		var cc = ct;
		if (!root) {
			mm = o.transform.matrix;
			mm.concat(m);
			var own = o.transform.colorTransform;
			if (ct != null) own.concat(ct);
			cc = own;
		}
		if (o.mask != null) skip("mask");
		var filters = o.filters;
		if (traceFilters && filters.length > 0)
			port.engine.BootLog.log("art filters on " + Type.getClassName(Type.getClass(o)) + ":" + o.name + " root " + root + ": "
				+ [for (f in filters) Type.getClassName(Type.getClass(f)) + " known " + FilterMath.known(f)].join(", "));
		if (!root && filters != null && filters.length > 0) {
			if (Lambda.foreach(filters, FilterMath.known)) {
				var layer = new Item(null, mm, cc);
				layer.content = [];
				layer.filters = filters;
				collectContent(o, mm, null, layer.content);
				out.push(layer);
				return;
			}
			skip("filters");
		}
		collectContent(o, mm, cc, out);
	}

	static function collectContent(o:flash.display.DisplayObject, mm:flash.geom.Matrix, cc:flash.geom.ColorTransform,
			out:Array<Item>):Void {
		var g:flash.display.Graphics = Std.isOfType(o, flash.display.Shape) ? (cast o : flash.display.Shape).graphics
			: Std.isOfType(o, flash.display.Sprite) ? (cast o : flash.display.Sprite).graphics : null;
		if (g != null && (g.fills.length > 0 || g.strokes.length > 0)) out.push(new Item(g, mm, cc));
		if (Std.isOfType(o, flash.display.DisplayObjectContainer)) {
			var c:flash.display.DisplayObjectContainer = cast o;
			for (i in 0...c.numChildren) collect(c.getChildAt(i), mm, cc, false, out);
		} else if (Std.isOfType(o, flash.text.TextField)) {
			var tf:flash.text.TextField = cast o;
			@:privateAccess tf.__layout();
			var glyphs = new flash.display.Graphics(null);
			port.engine.text.TextLayout.draw(tf, glyphs, mm);
			if (glyphs.bounds != null && (glyphs.fills.length > 0 || glyphs.strokes.length > 0)) out.push(new Item(glyphs, mm, cc));
		} else if (Std.isOfType(o, flash.display.Bitmap)) {
			var b:flash.display.Bitmap = cast o;
			var bd = b.bitmapData;
			if (bd != null && bd.width > 0 && bd.height > 0) {
				var pixels = new flash.display.Graphics(null);
				pixels.beginBitmapFill(bd, null, false, b.smoothing);
				pixels.drawRect(0, 0, bd.width, bd.height);
				pixels.endFill();
				out.push(new Item(pixels, mm, cc));
				bitmapChildren++;
			}
		}
	}

	public static var bitmapChildren(default, null) = 0;

	function filteredLayer(s:Item, w:Int, h:Int, layers:Array<flash.display.BitmapData>):Item {
		var x0 = Math.POSITIVE_INFINITY, y0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY;
		function grow(items:Array<Item>):Void {
			for (i in items) {
				if (i.content != null) {
					grow(i.content);
					continue;
				}
				var r = i.graphics.bounds;
				if (r == null) continue;
				var m = i.matrix;
				for (x in [r.x, r.x + r.width]) for (y in [r.y, r.y + r.height]) {
					var tx = m.a * x + m.c * y + m.tx, ty = m.b * x + m.d * y + m.ty;
					if (tx < x0) x0 = tx;
					if (ty < y0) y0 = ty;
					if (tx > x1) x1 = tx;
					if (ty > y1) y1 = ty;
				}
			}
		}
		grow(s.content);
		if (x0 > x1) return null;
		var mx = 0, my = 0;
		for (f in s.filters) {
			var reach = FilterMath.margin(f);
			mx += reach[0];
			my += reach[1];
		}
		var left = Std.int(Math.max(Math.floor(x0) - 1 - mx, -2 * mx)), top = Std.int(Math.max(Math.floor(y0) - 1 - my, -2 * my));
		var right = Std.int(Math.min(Math.ceil(x1) + 1 + mx, w + 2 * mx)), bottom = Std.int(Math.min(Math.ceil(y1) + 1 + my, h + 2 * my));
		var lw = right - left, lh = bottom - top;
		if (lw <= 0 || lh <= 0) return null;
		if (lw > MAX || lh > MAX) {
			skip("filters (layer over " + MAX + " px)");
			return null;
		}
		var layer = new flash.display.BitmapData(lw, lh, true, 0);
		layers.push(layer);
		var moved = [for (i in s.content) moveItem(i, -left, -top)];
		drawItems(layer, lw, lh, moved, null);
		var all = new flash.geom.Rectangle(0, 0, lw, lh), at = new flash.geom.Point(0, 0);
		for (f in s.filters) layer.applyFilter(layer, all, at, f);
		filteredDraws++;
		var g = new flash.display.Graphics(null);
		g.beginBitmapFill(layer, new flash.geom.Matrix(1, 0, 0, 1, left, top), false, false);
		g.drawRect(left, top, lw, lh);
		g.endFill();
		return new Item(g, new flash.geom.Matrix(), s.ct);
	}

	static var traceFilters = Sys.getEnv("BH_PORT_TRACE_ART_FILTERS") == "1";

	public static var filteredDraws(default, null) = 0;

	static function moveItem(i:Item, dx:Float, dy:Float):Item {
		var m = i.matrix.clone();
		m.translate(dx, dy);
		var moved = new Item(i.graphics, m, i.ct);
		if (i.content != null) {
			moved.content = [for (c in i.content) moveItem(c, dx, dy)];
			moved.filters = i.filters;
		}
		return moved;
	}

	static function transformed(data:PathNumbers, commands:VectorRecord.PathCommands, m:flash.geom.Matrix, scale:Float,
			out:Array<Float>):Array<Float> {
		out.resize(data.length);
		var i = 0;
		while (i + 1 < data.length) {
			var x = data[i], y = data[i + 1];
			out[i] = (m.a * x + m.c * y + m.tx + OFFSET_X) * scale;
			out[i + 1] = (m.b * x + m.d * y + m.ty) * scale;
			i += 2;
		}
		return out;
	}

	static function gradientInverse(paintMatrix:Array<Float>, m:flash.geom.Matrix):Array<Float> {
		var g = paintMatrix != null ? new flash.geom.Matrix(paintMatrix[0], paintMatrix[1], paintMatrix[2], paintMatrix[3],
			paintMatrix[4], paintMatrix[5]) : new flash.geom.Matrix();
		g.concat(m);
		g.invert();
		return [g.a, g.b, g.c, g.d, g.tx, g.ty];
	}

	static function transformColor(rgb:Int, alpha:Float, ct:flash.geom.ColorTransform):Int {
		return transformArgb((Std.int(alpha * 255 + 0.5) << 24) | (rgb & 0xFFFFFF), ct);
	}

	static function transformArgb(c:Int, ct:flash.geom.ColorTransform):Int {
		if (ct == null) return c;
		inline function ch(v:Float, mul:Float, off:Float) {
			var r = Std.int(v * mul + off);
			return r < 0 ? 0 : r > 255 ? 255 : r;
		}
		return (ch((c >>> 24) & 255, ct.alphaMultiplier, ct.alphaOffset) << 24)
			| (ch((c >> 16) & 255, ct.redMultiplier, ct.redOffset) << 16)
			| (ch((c >> 8) & 255, ct.greenMultiplier, ct.greenOffset) << 8)
			| ch(c & 255, ct.blueMultiplier, ct.blueOffset);
	}

	static function quadUV(v:hxd.FloatBuffer, x0:Float, y0:Float, x1:Float, y1:Float, sw:Float, sh:Float, u0:Float,
			v0:Float, u1:Float, v1:Float):Void {
		for (p in [[x0, y0, u0, v0], [x1, y0, u1, v0], [x1, y1, u1, v1], [x0, y0, u0, v0], [x1, y1, u1, v1], [x0, y1, u0, v1]]) {
			v.push(p[0] / sw * 2 - 1);
			v.push(1 - p[1] / sh * 2);
			v.push(p[2]);
			v.push(p[3]);
		}
	}

	static function quad(v:hxd.FloatBuffer, x0:Float, y0:Float, x1:Float, y1:Float, sw:Float, sh:Float, uw = 0.0,
			uh = 0.0):Void {
		if (uw == 0) uw = sw;
		if (uh == 0) uh = sh;
		for (p in [[x0, y0], [x1, y0], [x1, y1], [x0, y0], [x1, y1], [x0, y1]]) {
			v.push(p[0] / sw * 2 - 1);
			v.push(1 - p[1] / sh * 2);
			v.push(p[0] / uw);
			v.push(p[1] / uh);
		}
	}
}

private class Item {
	public var graphics:flash.display.Graphics;
	public var matrix:flash.geom.Matrix;
	public var ct:flash.geom.ColorTransform;
	public var content:Array<Item>;
	public var filters:Array<flash.filters.BitmapFilter>;

	public function new(graphics, matrix, ct) {
		this.graphics = graphics;
		this.matrix = matrix;
		this.ct = ct;
	}
}

private class OutState {
	public var out:h3d.mat.Texture;
	public var resident:h3d.mat.Texture;
	public var readOut:h3d.mat.Texture;

	public function new() {}
}

private class TileOut {
	public var w:Int;
	public var h:Int;
	public var ox = 0;
	public var oy = 0;
	public var state:OutState;

	public function new(w, h) {
		this.w = w;
		this.h = h;
	}
}

private class Targets {
	public var mask:h3d.mat.Texture;
	public var scratch:h3d.mat.Texture;
	public var w:Int;
	public var h:Int;
	public var pooled:Bool;
	public var used = 0;

	public function new(mask, scratch, w, h, pooled) {
		this.mask = mask;
		this.scratch = scratch;
		this.w = w;
		this.h = h;
		this.pooled = pooled;
	}

	public function dispose():Void {
		if (mask != null) mask.dispose();
		if (scratch.depthBuffer != null) scratch.depthBuffer.dispose();
		scratch.dispose();
	}
}

private class FillPlan {
	public var start:Int;
	public var count:Int;
	public var kind = 0;
	public var color = 0;
	public var row = 0;
	public var inverse:Array<Float>;
	public var spread = 0;
	public var focal = 0.0;
	public var union = false;
	public var bitmap:h3d.mat.Texture;
	public var ctMul:Array<Float>;
	public var ctAdd:Array<Float>;

	public function new(start:Int, count:Int) {
		this.start = start;
		this.count = count;
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

private class ParityShader extends h3d.shader.ScreenShader {
	static var SRC = {
		function fragment() {
			pixelColor = vec4(1, 1, 1, 1);
		}
	};
}

private class CoverShader extends h3d.shader.ScreenShader {
	static var SRC = {
		@param var mask : Sampler2D;
		@param var color : Vec4;
		@const var kind : Int;
		@param var ramp : Sampler2D;
		@param var row : Float;
		@param var inv : Vec4;
		@param var invT : Vec2;
		@param var focal : Float;
		@param var spread : Int;
		@param var size : Vec2;
		@param var offset : Vec2;
		@param var bitmap : Sampler2D;
		@param var bitmapSize : Vec2;
		@param var ctMul : Vec4;
		@param var ctAdd : Vec4;
		function fragment() {
			if( mask.get(calculatedUV).r < 0.5 ) discard;
			if( kind == 0 ) {
				pixelColor = color;
			} else if( kind == 3 ) {
				var p = calculatedUV * size / 4 - offset;
				var g = vec2(inv.x * p.x + inv.z * p.y + invT.x, inv.y * p.x + inv.w * p.y + invT.y);
				var c = clamp(bitmap.get(g / bitmapSize) * ctMul + ctAdd, vec4(0, 0, 0, 0), vec4(1, 1, 1, 1));
				pixelColor = vec4(c.rgb * c.a, c.a);
			} else {
				var p = calculatedUV * size / 4 - offset;
				var g = vec2(inv.x * p.x + inv.z * p.y + invT.x, inv.y * p.x + inv.w * p.y + invT.y);
				var t = 0.;
				if( kind == 1 ) {
					t = (g.x + 819.2) / 1638.4;
				} else {
					var f = vec2(focal * 819.2, 0);
					var d = g - f;
					var dd = dot(d, d);
					if( dd > 1e-6 ) {
						var fd = dot(f, d);
						var s = (-fd + sqrt(max(0., fd * fd - dd * (dot(f, f) - 819.2 * 819.2)))) / dd;
						t = 1 / s;
					}
				}
				if( spread == 0 ) t = clamp(t, 0., 1.);
				else if( spread == 2 ) t = fract(t);
				else {
					t = mod(t, 2.);
					if( t > 1 ) t = 2 - t;
				}
				var c = ramp.get(vec2((floor(min(t * 256, 255.)) + 0.5) / 256, row));
				pixelColor = vec4(c.rgb * c.a, c.a);
			}
		}
	};
}

private class DownShader extends h3d.shader.ScreenShader {
	static var SRC = {
		@param var source : Sampler2D;
		@param var texel : Vec2;
		function fragment() {
			var sum = vec4(0, 0, 0, 0);
			for( j in 0...4 )
				for( i in 0...4 )
					sum += source.get(calculatedUV + vec2(float(i) - 1.5, float(j) - 1.5) * texel);
			pixelColor = vec4(sum.rgb / 16, floor(sum.a * 255 / 16 + 0.001) / 255);
		}
	};
}

private class ClearShader extends h3d.shader.ScreenShader {
	static var SRC = {
		function fragment() {
			pixelColor = vec4(0, 0, 0, 0);
		}
	};
}
