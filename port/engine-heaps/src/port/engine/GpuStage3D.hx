package port.engine;

import flash.display3D.Context3D;
import flash.display3D.Context3DBlendFactor;
import flash.display3D.Context3DTriangleFace;
import flash.display3D.IndexBuffer3D;
import flash.display3D.VertexBuffer3D;
import port.engine.agal.AgalHxsl;
import port.engine.agal.AgalProgram;

class GpuStage3D implements Stage3DBackend {
	public var draws(default, null) = 0;
	public var skipped(default, null) = 0;
	public var lastSkip(default, null):String = null;
	static var trace = Sys.getEnv("BH_PORT_GPU_TRACE") == "1";
	public static var residentUploads(default, null) = 0;

	var engine:h3d.Engine;
	var output = new h3d.pass.OutputShader();
	var context = @:privateAccess new h3d.impl.RenderContext();
	var pass = new h3d.mat.Pass("stage3d");
	var programs = new Map<flash.display3D.Program3D, ProgramCache>();
	var vertexBuffers = new Map<VertexBuffer3D, Map<String, GpuBuffer>>();
	var indexBuffers = new Map<IndexBuffer3D, {indexes:h3d.Indexes, version:Int}>();
	var textures = new Map<flash.display3D.textures.TextureBase, {texture:h3d.mat.Texture, version:Int}>();

	static var current:GpuStage3D;

	public static function census():String {
		var g = current;
		if (g == null) return "stage3d off";
		var count = (m:Iterator<Dynamic>) -> {
			var n = 0;
			for (_ in m) n++;
			n;
		};
		return "stage3d textures " + count(g.textures.keys()) + ", free targets " + g.freeTargets.count + ", vertex buffers "
			+ count(g.vertexBuffers.keys()) + ", index buffers " + count(g.indexBuffers.keys());
	}

	public function new(engine:h3d.Engine) {
		this.engine = engine;
		current = this;
		flash.display3D.textures.RectangleTexture.gpuUpload = uploadResident;
		flash.display3D.textures.TextureBase.onDispose = released;
		VertexBuffer3D.onDispose = vertexReleased;
		IndexBuffer3D.onDispose = indexReleased;
		pass.culling = None;
		pass.depth(false, Always);
	}

	public function clear(c:Context3D, red:Float, green:Float, blue:Float, alpha:Float, depth:Float, stencil:Int):Void {
		if (trace && draws < 40) HeapsMain.log("stage3d: clear");
		inline function byte(v:Float):Int return Std.int(Math.max(0, Math.min(1, v)) * 255 + 0.5);
		engine.clear((byte(alpha) << 24) | (byte(red) << 16) | (byte(green) << 8) | byte(blue), depth, stencil);
	}

	public function present(c:Context3D):Void {
		if (trace && draws < 40) HeapsMain.log("stage3d: present");
	}

	public function capture(c:Context3D, destination:flash.display.BitmapData):Void {
		var target = engine.getCurrentTarget();
		if (target == null) {
			HeapsMain.log("stage3d: drawToBitmapData outside a render target: nothing copied");
			return;
		}
		var pixels = target.capturePixels();
		if (engine.driver.hasFeature(BottomLeftCoords)) pixels.flipY();
		pixels.convert(BGRA);
		copyInto(pixels.bytes, pixels.width, pixels.height, destination);
	}

	public static function copyInto(src:haxe.io.Bytes, width:Int, height:Int, dest:flash.display.BitmapData):Void {
		var w = Std.int(Math.min(width, dest.width)), h = Std.int(Math.min(height, dest.height));
		if (w <= 0 || h <= 0) return;
		var out = dest.pixels;
		for (y in 0...h) out.blit(y * dest.width * 4, src, y * width * 4, w * 4);
		if (!dest.transparent)
			for (y in 0...h) for (x in 0...w) {
				var at = (y * dest.width + x) * 4;
				out.set(at + 3, 0xFF);
			}
	}

	function skip(why:String):Void {
		skipped++;
		if (lastSkip != why) {
			lastSkip = why;
			HeapsMain.log("stage3d: draw skipped: " + why);
		}
	}

	public function drawTriangles(c:Context3D, indexBuffer:IndexBuffer3D, firstIndex:Int, numTriangles:Int):Void {
		var program = c.program;
		if (program == null || program.vertexAgal == null) return skip("no program");
		var cache = programs.get(program);
		if (cache == null) {
			try {
				cache = new ProgramCache(new AgalProgram(program.vertexAgal), new AgalProgram(program.fragmentAgal));
			} catch (e:Dynamic) {
				return skip("AGAL " + Std.string(e));
			}
			programs.set(program, cache);
		}
		var attributes = cache.attributes;
		var buffer:VertexBuffer3D = null;
		var same = cache.lastKey != null && cache.lastFormats.length == attributes;
		for (i in 0...attributes) {
			var s = c.streams[i];
			if (s == null) return skip("attribute va" + i + " not bound");
			if (buffer == null) buffer = s.buffer else if (buffer != s.buffer) return skip("streams from several buffers");
			if (same && ((s.format : String) != cache.lastFormats[i] || s.offset != cache.lastOffsets[i])) same = false;
		}
		if (buffer == null || buffer.data == null) return skip("no vertex buffer");
		if (!same) {
			var formats:Array<String> = [];
			var offsets:Array<Int> = [];
			for (i in 0...attributes) {
				var s = c.streams[i];
				formats.push((s.format : String));
				offsets.push(s.offset);
			}
			cache.lastFormats = formats;
			cache.lastOffsets = offsets;
			cache.lastKey = formats.join(",") + "@" + offsets.join(",");
			cache.lastShader = cache.shaders.get(cache.lastKey);
		}
		var formats = cache.lastFormats, offsets = cache.lastOffsets;
		var key = cache.lastKey;
		var shader = cache.lastShader;
		if (shader == null) {
			try {
				shader = new hxsl.DynamicShader(AgalHxsl.build(cache.vertex, cache.fragment, formats));
			} catch (e:Dynamic) {
				return skip("translation: " + Std.string(e));
			}
			cache.shaders.set(key, shader);
			cache.lists.set(key, new hxsl.ShaderList(shader));
			cache.lastShader = shader;
		}
		shader.setVariable("vc", constants(c.vertexConstants, cache.vcCount, cache.vc));
		shader.setVariable("fc", constants(c.fragmentConstants, cache.fcCount, cache.fc));
		for (ins in cache.fragment.instructions) if (ins.sampler != null) {
			var s = ins.sampler;
			var source = c.textures[s.index];
			if (source == null) return skip("fs" + s.index + " not bound");
			var texture = texture(source);
			texture.filter = s.filter == 1 ? Linear : Nearest;
			texture.wrap = s.wrap == 1 ? Repeat : Clamp;
			texture.mipMap = None;
			shader.setVariable(cache.samplerName(s.index), texture);
		}
		if (trace && draws < 40) HeapsMain.log("stage3d: draw " + draws + ": layout " + key + " of " + buffer.data32PerVertex
			+ " floats x " + buffer.numVertices + " vertices, indexes " + indexBuffer.numIndices + " from " + firstIndex
			+ " triangles " + numTriangles + ", textures " + [for (t in c.textures) if (t != null) t.width + "x" + t.height]);
		if (trace && draws < 2) HeapsMain.log("stage3d: vc " + [for (i in 0...20) Math.round(c.vertexConstants[i] * 1000) / 1000]
			+ " fc " + [for (i in 0...16) Math.round(c.fragmentConstants[i] * 1000) / 1000] + " vertices "
			+ [for (i in 0...buffer.data.length) Math.round(buffer.data[i] * 1000) / 1000] + " indexes "
			+ [for (i in 0...indexBuffer.numIndices) indexBuffer.data[i]] + "
" + cache.vertex + "
" + cache.fragment);
		var gpu = vertexBuffer(buffer, key, formats, offsets);
		var indexes = indexBuffer3D(indexBuffer);
		pass.blend(blend(c.blend.source), blend(c.blend.destination));
		pass.culling = switch (c.culling) {
			case Context3DTriangleFace.BACK: Back;
			case Context3DTriangleFace.FRONT: Front;
			case Context3DTriangleFace.FRONT_AND_BACK: Both;
			default: None;
		};
		var list = cache.lastList;
		if (list == null || cache.lastListKey != key) {
			list = cache.lastList = cache.lists.get(key);
			cache.lastListKey = key;
		}
		var rt = output.compileShaders(context.globals, list);
		if (trace && draws == 0) {
			HeapsMain.log("stage3d: AGAL vertex " + program.vertexAgal.toHex() + " fragment " + program.fragmentAgal.toHex());
			#if hldx
			HeapsMain.log("stage3d: HLSL\n" + new hxsl.HlslOut().run(rt.vertex.data) + "\n" + new hxsl.HlslOut().run(rt.fragment.data));
			#end
		}
		engine.selectMaterial(pass);
		engine.selectShader(rt);
		var buffers = context.shaderBuffers;
		buffers.grow(rt);
		context.fillGlobals(buffers, rt);
		context.fillParams(buffers, rt, list);
		engine.uploadShaderBuffers(buffers, Globals);
		engine.uploadShaderBuffers(buffers, Params);
		engine.uploadShaderBuffers(buffers, Textures);
		engine.uploadShaderBuffers(buffers, Buffers);
		if (firstIndex % 3 == 0) {
			engine.renderIndexed(gpu, indexes, Std.int(firstIndex / 3), numTriangles);
		} else {
			if (@:privateAccess engine.selectBuffer(gpu)) engine.driver.draw(indexes, firstIndex, numTriangles);
		}
		if (trace && draws < 4) HeapsMain.log("stage3d: draw " + draws + " made");
		draws++;
	}

	static function constants(source:haxe.ds.Vector<Float>, count:Int, into:Array<h3d.Vector4>):Array<h3d.Vector4> {
		while (into.length < count) into.push(new h3d.Vector4());
		for (i in 0...count) into[i].set(source[i * 4], source[i * 4 + 1], source[i * 4 + 2], source[i * 4 + 3]);
		return into;
	}

	static function blend(f:Context3DBlendFactor):h3d.mat.Data.Blend {
		return switch (f) {
			case Context3DBlendFactor.ZERO: Zero;
			case Context3DBlendFactor.ONE: One;
			case Context3DBlendFactor.SOURCE_ALPHA: SrcAlpha;
			case Context3DBlendFactor.SOURCE_COLOR: SrcColor;
			case Context3DBlendFactor.DESTINATION_ALPHA: DstAlpha;
			case Context3DBlendFactor.DESTINATION_COLOR: DstColor;
			case Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA: OneMinusSrcAlpha;
			case Context3DBlendFactor.ONE_MINUS_SOURCE_COLOR: OneMinusSrcColor;
			case Context3DBlendFactor.ONE_MINUS_DESTINATION_ALPHA: OneMinusDstAlpha;
			case Context3DBlendFactor.ONE_MINUS_DESTINATION_COLOR: OneMinusDstColor;
			default: One;
		}
	}

	function vertexBuffer(buffer:VertexBuffer3D, key:String, formats:Array<String>, offsets:Array<Int>):h3d.Buffer {
		var layouts = vertexBuffers.get(buffer);
		if (layouts == null) vertexBuffers.set(buffer, layouts = new Map());
		var gpu = layouts.get(key);
		if (gpu == null) {
			var order = [for (i in 0...formats.length) i];
			order.sort((a, b) -> offsets[a] - offsets[b]);
			var inputs:Array<hxd.BufferFormat.BufferInput> = [];
			var at = 0, pad = 0;
			function padding(n:Int) {
				while (n > 0) {
					var take = n >= 4 ? 4 : n;
					inputs.push(new hxd.BufferFormat.BufferInput("pad" + pad++, size(take)));
					n -= take;
				}
			}
			for (i in order) {
				if (offsets[i] < at) throw "stage3d: overlapping attributes";
				padding(offsets[i] - at);
				var floats = Std.parseInt(formats[i].substr(5));
				inputs.push(new hxd.BufferFormat.BufferInput("va" + i, size(floats)));
				at = offsets[i] + floats;
			}
			padding(buffer.data32PerVertex - at);
			gpu = new GpuBuffer(new h3d.Buffer(buffer.numVertices, hxd.BufferFormat.make(inputs)));
			layouts.set(key, gpu);
		}
		if (gpu.version != buffer.version) {
			var floats = new hxd.FloatBuffer(buffer.data.length);
			for (i in 0...buffer.data.length) floats[i] = buffer.data[i];
			UploadStats.add("stage3d vertices", buffer.data.length * 4.0);
			gpu.buffer.uploadFloats(floats, 0, buffer.numVertices);
			gpu.version = buffer.version;
		}
		return gpu.buffer;
	}

	static function size(floats:Int):hxd.BufferFormat.InputFormat {
		return switch (floats) {
			case 1: DFloat;
			case 2: DVec2;
			case 3: DVec3;
			default: DVec4;
		}
	}

	function indexBuffer3D(buffer:IndexBuffer3D):h3d.Indexes {
		var entry = indexBuffers.get(buffer);
		if (entry == null) {
			entry = {indexes: new h3d.Indexes(buffer.numIndices), version: -1};
			indexBuffers.set(buffer, entry);
		}
		if (entry.version != buffer.version) {
			var data = new hxd.IndexBuffer(buffer.numIndices);
			for (i in 0...buffer.numIndices) data[i] = buffer.data[i];
			UploadStats.add("stage3d indexes", buffer.numIndices * 2.0);
			entry.indexes.uploadIndexes(data, 0, buffer.numIndices);
			entry.version = buffer.version;
		}
		return entry.indexes;
	}

	var freeTargets = new port.engine.art.TexturePool(64, 64);
	public static var targetsReused(default, null) = 0;

	function targetTexture(w:Int, h:Int):h3d.mat.Texture {
		var kept = freeTargets.take(w, h);
		if (kept != null) {
			targetsReused++;
			return kept;
		}
		return new h3d.mat.Texture(w, h, [Target], RGBA);
	}

	function recycle(t:h3d.mat.Texture):Void {
		if (!t.flags.has(Target) || t.format != RGBA || t.isDisposed()) {
			t.dispose();
			return;
		}
		freeTargets.put(t);
	}

	function vertexReleased(buffer:VertexBuffer3D):Void {
		var layouts = vertexBuffers.get(buffer);
		if (layouts == null) return;
		for (gpu in layouts) gpu.buffer.dispose();
		vertexBuffers.remove(buffer);
	}

	function indexReleased(buffer:IndexBuffer3D):Void {
		var entry = indexBuffers.get(buffer);
		if (entry == null) return;
		entry.indexes.dispose();
		indexBuffers.remove(buffer);
	}

	function released(source:flash.display3D.textures.TextureBase):Void {
		var entry = textures.get(source);
		if (entry != null) {
			recycle(entry.texture);
			textures.remove(source);
		}
		if (Std.isOfType(source, flash.display3D.textures.RectangleTexture)) {
			var snapshot = (cast source : flash.display3D.textures.RectangleTexture).source;
			if (snapshot != null) snapshot.dispose();
		}
	}

	function uploadResident(r:flash.display3D.textures.RectangleTexture, bitmap:flash.display.BitmapData):Bool {
		if (!port.engine.art.GpuBitmaps.ready()) return false;
		var entry = textures.get(r);
		if (entry == null || entry.texture.width != r.width || entry.texture.height != r.height) {
			if (entry != null) recycle(entry.texture);
			entry = {texture: targetTexture(r.width, r.height), version: -1};
			textures.set(r, entry);
		}
		return copyResident(r, bitmap, entry);
	}

	function copyResident(source:flash.display3D.textures.TextureBase, bitmap:flash.display.BitmapData,
			entry:{texture:h3d.mat.Texture, version:Int}):Bool {
		if (bitmap.width < source.width || bitmap.height < source.height) return false;
		if (!entry.texture.flags.has(Target)) {
			entry.texture.dispose();
			entry.texture = targetTexture(source.width, source.height);
		}
		port.engine.art.GpuBitmaps.region(bitmap.__gpu, entry.texture, source.width / bitmap.width,
			source.height / bitmap.height);
		entry.version = source.version;
		residentUploads++;
		return true;
	}

	function texture(source:flash.display3D.textures.TextureBase):h3d.mat.Texture {
		var entry = textures.get(source);
		if (entry == null || entry.texture.width != source.width || entry.texture.height != source.height) {
			if (entry != null) entry.texture.dispose();
			entry = {texture: new h3d.mat.Texture(source.width, source.height, null, RGBA), version: -1};
			textures.set(source, entry);
		}
		var resident = Std.isOfType(source, flash.display3D.textures.RectangleTexture)
			? (cast source : flash.display3D.textures.RectangleTexture).source : null;
		if (entry.version != source.version && resident != null && resident.__gpu != null
			&& copyResident(source, resident, entry)) {
			resident.dispose();
		}
		if (entry.version != source.version) {
			var w = source.width, h = source.height;
			var bytes = haxe.io.Bytes.alloc(w * h * 4);
			if (Std.isOfType(source, flash.display3D.textures.RectangleTexture)) {
				var r:flash.display3D.textures.RectangleTexture = cast source;
				if (r.source != null) {
					var src = r.source, pixels = r.source.pixels;
					var cw = src.width < w ? src.width : w, ch = src.height < h ? src.height : h;
					if (pixels != null) {
						for (y in 0...ch) bytes.blit(y * w * 4, pixels, y * src.width * 4, cw * 4);
					} else {
						var c = @:privateAccess src.fill;
						for (y in 0...ch) for (x in 0...cw) bytes.setInt32((y * w + x) * 4, c);
					}
				} else if (r.bytes != null) {
					bytes.blit(0, r.bytes, 0, Std.int(Math.min(r.bytes.length, bytes.length)));
				}
			}
			premultiply(bytes);
			UploadStats.add("stage3d texture " + (Std.isOfType(source, flash.display3D.textures.RectangleTexture) && (cast source : flash.display3D.textures.RectangleTexture).source != null ? "from bitmap" : "from bytes"), w * h * 4.0);
			entry.texture.uploadPixels(new hxd.Pixels(w, h, bytes, BGRA));
			entry.version = source.version;
		}
		return entry.texture;
	}

	static var premultiplied:haxe.io.Bytes;

	static function premultiply(b:haxe.io.Bytes):Void {
		var table = premultiplied;
		if (table == null) {
			table = haxe.io.Bytes.alloc(65536);
			for (a in 0...256) for (c in 0...256) table.set(a << 8 | c, Std.int(c * a / 255 + 0.5));
			premultiplied = table;
		}
		var i = 0, n = b.length & ~3;
		while (i < n) {
			var p = b.getInt32(i);
			var a = p >>> 24;
			if (a < 255) {
				var row = a << 8;
				b.setInt32(i, (a << 24) | (table.get(row | ((p >> 16) & 255)) << 16)
					| (table.get(row | ((p >> 8) & 255)) << 8) | table.get(row | (p & 255)));
			}
			i += 4;
		}
	}
}

private class ProgramCache {
	public var vertex:AgalProgram;
	public var fragment:AgalProgram;
	public var shaders = new Map<String, hxsl.DynamicShader>();
	public var lists = new Map<String, hxsl.ShaderList>();
	public var vc:Array<h3d.Vector4> = [];
	public var fc:Array<h3d.Vector4> = [];
	public var lastFormats:Array<String> = [];
	public var lastOffsets:Array<Int> = [];
	public var lastKey:String = null;
	public var lastShader:hxsl.DynamicShader = null;
	public var lastList:hxsl.ShaderList = null;
	public var lastListKey:String = null;
	public var attributes:Int;
	public var vcCount:Int;
	public var fcCount:Int;
	var samplerNames:Array<String> = [];

	public function new(vertex:AgalProgram, fragment:AgalProgram) {
		this.vertex = vertex;
		this.fragment = fragment;
		attributes = vertex.used.exists(RegisterType.Attribute) ? vertex.used.get(RegisterType.Attribute) : 0;
		vcCount = AgalHxsl.constantCount(vertex);
		fcCount = AgalHxsl.constantCount(fragment);
	}

	public inline function samplerName(index:Int):String {
		var name = samplerNames[index];
		if (name == null) samplerNames[index] = name = "fs" + index;
		return name;
	}
}

private class GpuBuffer {
	public var buffer:h3d.Buffer;
	public var version = -1;

	public function new(buffer:h3d.Buffer) {
		this.buffer = buffer;
	}
}
