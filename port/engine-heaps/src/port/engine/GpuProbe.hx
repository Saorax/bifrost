package port.engine;

import port.engine.agal.AgalHxsl;
import port.engine.agal.AgalProgram;

class GpuProbe {
	static var VERTEX = "a001000000a1001800000000000f03000000e400000000010000e4010000000000000001000f04010000e4000000000000000000000000";
	static var FRAGMENT = "a001000000a1012800000000000f03010000e4040000000000000005000010";
	static var VC = [1, 1, 1, 1, 0.001, 0, 0, -1, 0, -0.002, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1];
	static var VERTICES = [0., 0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 1, 1, 1, 1, 1];
	static var INDEXES = [0, 1, 2, 1, 3, 2];

	var shader:hxsl.DynamicShader;
	var list:hxsl.ShaderList;
	var output = new h3d.pass.OutputShader();
	var context:h3d.impl.RenderContext;
	var pass = new h3d.mat.Pass("stage3d");
	var buffer:h3d.Buffer;
	var indexes:h3d.Indexes;
	var texture:h3d.mat.Texture;
	var vc:Array<h3d.Vector4> = [];

	public function new() {
		context = @:privateAccess new h3d.impl.RenderContext();
		var vertex = new AgalProgram(haxe.io.Bytes.ofHex(VERTEX));
		var fragment = new AgalProgram(haxe.io.Bytes.ofHex(FRAGMENT));
		shader = new hxsl.DynamicShader(AgalHxsl.build(vertex, fragment, ["float2", "float2"]));
		list = new hxsl.ShaderList(shader);
		pass.culling = None;
		pass.depth(false, Always);
		buffer = new h3d.Buffer(4, hxd.BufferFormat.make([
			new hxd.BufferFormat.BufferInput("va0", DVec2),
			new hxd.BufferFormat.BufferInput("va1", DVec2)
		]));
		var floats = new hxd.FloatBuffer(VERTICES.length);
		for (i in 0...VERTICES.length) floats[i] = VERTICES[i];
		buffer.uploadFloats(floats, 0, 4);
		indexes = new h3d.Indexes(6);
		var data = new hxd.IndexBuffer(6);
		for (i in 0...6) data[i] = INDEXES[i];
		indexes.uploadIndexes(data, 0, 6);
		texture = new h3d.mat.Texture(1, 1, null, RGBA);
		texture.uploadPixels(new hxd.Pixels(1, 1, haxe.io.Bytes.ofHex("ffffffff"), BGRA));
		texture.filter = Linear;
		texture.wrap = Clamp;
		texture.mipMap = None;
		for (i in 0...AgalHxsl.constantCount(vertex)) vc.push(new h3d.Vector4(VC[i * 4], VC[i * 4 + 1], VC[i * 4 + 2], VC[i * 4 + 3]));
	}

	static var steps = Sys.getEnv("BH_PORT_PROBE_STEPS") == "1";
	var stepFrames = 0;

	inline function step(name:String):Void {
		if (steps && stepFrames < 3) {
			Sys.println("probe frame " + stepFrames + ": " + name);
			Sys.stdout().flush();
		}
	}

	public function draw(e:h3d.Engine):Void {
		step("clear");
		e.clear(0xFF000000, 1, 0);
		shader.setVariable("vc", vc);
		shader.setVariable("fc", []);
		shader.setVariable("fs0", texture);
		pass.blend(One, Zero);
		step("compileShaders");
		var rt = output.compileShaders(context.globals, list);
		step("selectMaterial");
		e.selectMaterial(pass);
		step("selectShader");
		e.selectShader(rt);
		var buffers = context.shaderBuffers;
		buffers.grow(rt);
		context.fillGlobals(buffers, rt);
		context.fillParams(buffers, rt, list);
		step("upload Globals");
		e.uploadShaderBuffers(buffers, Globals);
		step("upload Params");
		e.uploadShaderBuffers(buffers, Params);
		step("upload Textures");
		e.uploadShaderBuffers(buffers, Textures);
		step("upload Buffers");
		e.uploadShaderBuffers(buffers, Buffers);
		step("renderIndexed");
		e.renderIndexed(buffer, indexes, 0, 2);
		step("done");
		stepFrames++;
	}
}
