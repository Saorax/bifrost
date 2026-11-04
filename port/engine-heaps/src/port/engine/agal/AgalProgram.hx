package port.engine.agal;

enum abstract RegisterType(Int) from Int to Int {
	var Attribute = 0;
	var Constant = 1;
	var Temporary = 2;
	var Output = 3;
	var Varying = 4;
	var Sampler = 5;
}

class Source {
	public var type:RegisterType;
	public var index:Int;
	public var swizzle:Array<Int>;
	public var indirect:Bool;
	public var indirectOffset:Int;
	public var indexType:RegisterType;
	public var indexComponent:Int;

	public function new() {}
}

class Sampler {
	public var index:Int;
	public var lodBias:Float;
	public var format:Int;
	public var dimension:Int;
	public var special:Int;
	public var wrap:Int;
	public var mipmap:Int;
	public var filter:Int;

	public function new() {}
}

class Instruction {
	public var opcode:Int;
	public var destType:RegisterType;
	public var destIndex:Int;
	public var destMask:Int;
	public var a:Source;
	public var b:Source;
	public var sampler:Sampler;

	public function new() {}
}

class AgalProgram {
	public static inline var VERTEX = 0;
	public static inline var FRAGMENT = 1;

	public static var OPCODES:Map<Int, {name:String, sources:Int}> = [
		0x00 => {name: "mov", sources: 1}, 0x01 => {name: "add", sources: 2}, 0x02 => {name: "sub", sources: 2},
		0x03 => {name: "mul", sources: 2}, 0x04 => {name: "div", sources: 2}, 0x05 => {name: "rcp", sources: 1},
		0x06 => {name: "min", sources: 2}, 0x07 => {name: "max", sources: 2}, 0x08 => {name: "frc", sources: 1},
		0x09 => {name: "sqt", sources: 1}, 0x0A => {name: "rsq", sources: 1}, 0x0B => {name: "pow", sources: 2},
		0x0C => {name: "log", sources: 1}, 0x0D => {name: "exp", sources: 1}, 0x0E => {name: "nrm", sources: 1},
		0x0F => {name: "sin", sources: 1}, 0x10 => {name: "cos", sources: 1}, 0x11 => {name: "crs", sources: 2},
		0x12 => {name: "dp3", sources: 2}, 0x13 => {name: "dp4", sources: 2}, 0x14 => {name: "abs", sources: 1},
		0x15 => {name: "neg", sources: 1}, 0x16 => {name: "sat", sources: 1}, 0x17 => {name: "m33", sources: 2},
		0x18 => {name: "m44", sources: 2}, 0x19 => {name: "m34", sources: 2}, 0x1A => {name: "ddx", sources: 1},
		0x1B => {name: "ddy", sources: 1}, 0x27 => {name: "kil", sources: 1}, 0x28 => {name: "tex", sources: 2},
		0x29 => {name: "sge", sources: 2}, 0x2A => {name: "slt", sources: 2}, 0x2B => {name: "sgn", sources: 1},
		0x2C => {name: "seq", sources: 2}, 0x2D => {name: "sne", sources: 2},
	];

	public var type(default, null):Int;
	public var version(default, null):Int;
	public var instructions(default, null):Array<Instruction> = [];

	public var used(default, null):Map<Int, Int> = new Map();

	public function new(bytes:haxe.io.Bytes) {
		if (bytes == null || bytes.length < 7 || bytes.get(0) != 0xA0 || bytes.get(5) != 0xA1)
			throw "AGAL: bad header";
		version = bytes.getInt32(1);
		type = bytes.get(6);
		var pos = 7;
		while (pos + 24 <= bytes.length) {
			var ins = new Instruction();
			ins.opcode = bytes.getInt32(pos);
			if (!OPCODES.exists(ins.opcode)) throw "AGAL: unknown opcode 0x" + StringTools.hex(ins.opcode, 2);
			ins.destIndex = bytes.getUInt16(pos + 4);
			ins.destMask = bytes.get(pos + 6) & 15;
			ins.destType = bytes.get(pos + 7);
			ins.a = source(bytes, pos + 8);
			if (ins.opcode == 0x28) ins.sampler = sampler(bytes, pos + 16)
			else if (OPCODES.get(ins.opcode).sources > 1) ins.b = source(bytes, pos + 16);
			if (ins.opcode != 0x27) use(ins.destType, ins.destIndex);
			use(ins.a.type, ins.a.index);
			if (ins.b != null) use(ins.b.type, ins.b.index + rows(ins.opcode) - 1);
			if (ins.sampler != null) use(Sampler, ins.sampler.index);
			instructions.push(ins);
			pos += 24;
		}
	}

	public static function rows(opcode:Int):Int {
		return switch (opcode) {
			case 0x17: 3;
			case 0x18: 4;
			case 0x19: 3;
			default: 1;
		}
	}

	function use(type:Int, index:Int):Void {
		var n = used.exists(type) ? used.get(type) : 0;
		if (index + 1 > n) used.set(type, index + 1);
	}

	static function source(b:haxe.io.Bytes, p:Int):Source {
		var s = new Source();
		s.index = b.getUInt16(p);
		var offset = b.get(p + 2);
		s.indirectOffset = offset > 127 ? offset - 256 : offset;
		var swizzle = b.get(p + 3);
		s.swizzle = [for (i in 0...4) (swizzle >> (i * 2)) & 3];
		s.type = b.get(p + 4);
		s.indexType = b.get(p + 5);
		var select = b.getUInt16(p + 6);
		s.indirect = select & 0x8000 != 0;
		s.indexComponent = select & 3;
		return s;
	}

	static function sampler(b:haxe.io.Bytes, p:Int):Sampler {
		var s = new Sampler();
		s.index = b.getUInt16(p);
		var bias = b.get(p + 2);
		s.lodBias = (bias > 127 ? bias - 256 : bias) / 8;
		var flags = b.getInt32(p + 4);
		s.format = (flags >>> 8) & 15;
		s.dimension = (flags >>> 12) & 15;
		s.special = (flags >>> 16) & 15;
		s.wrap = (flags >>> 20) & 15;
		s.mipmap = (flags >>> 24) & 15;
		s.filter = (flags >>> 28) & 15;
		return s;
	}

	public function registerName(type:Int, index:Int):String {
		var v = this.type == VERTEX;
		return switch (type) {
			case Attribute: "va" + index;
			case Constant: (v ? "vc" : "fc") + index;
			case Temporary: (v ? "vt" : "ft") + index;
			case Output: v ? "op" : "oc";
			case Varying: "v" + index;
			case Sampler: "fs" + index;
			default: "?" + type + ":" + index;
		}
	}

	static var COMPONENTS = ["x", "y", "z", "w"];

	function sourceText(s:Source):String {
		var name = s.indirect
			? registerName(s.type, 0).substr(0, 2) + "[" + registerName(s.indexType, s.index) + "." + COMPONENTS[s.indexComponent]
				+ (s.indirectOffset != 0 ? "+" + s.indirectOffset : "") + "]"
			: registerName(s.type, s.index);
		var sw = [for (c in s.swizzle) COMPONENTS[c]].join("");
		return sw == "xyzw" ? name : name + "." + sw;
	}

	public function toString():String {
		var lines = [];
		for (ins in instructions) {
			var op = OPCODES.get(ins.opcode);
			var parts = [];
			if (ins.opcode != 0x27) {
				var mask = [for (i in 0...4) if (ins.destMask & (1 << i) != 0) COMPONENTS[i]].join("");
				parts.push(registerName(ins.destType, ins.destIndex) + (mask == "xyzw" ? "" : "." + mask));
			}
			parts.push(sourceText(ins.a));
			if (ins.b != null) parts.push(sourceText(ins.b));
			if (ins.sampler != null) {
				var s = ins.sampler;
				var flags = [["2d", "cube", "3d"][s.dimension], ["clamp", "repeat"][s.wrap],
					["nearest", "linear"][s.filter], ["mipnone", "mipnearest", "miplinear"][s.mipmap]];
				parts.push(registerName(Sampler, s.index) + " <" + flags.join(",") + ">");
			}
			lines.push(op.name + " " + parts.join(", "));
		}
		return lines.join("\n");
	}
}
