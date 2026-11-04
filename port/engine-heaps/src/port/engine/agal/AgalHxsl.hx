package port.engine.agal;

import hxsl.Ast;
import port.engine.agal.AgalProgram;

class AgalHxsl {
	static var V4 = TVec(4, VFloat);
	static var COMPONENTS = [X, Y, Z, W];

	public static var built(default, null):Int = 0;

	public static function build(vertex:AgalProgram, fragment:AgalProgram, formats:Array<String>,
			name = "agal"):hxsl.SharedShader {
		var t = new AgalHxsl(vertex, fragment, formats);
		var shader = new hxsl.SharedShader("");
		shader.data = {
			name: name,
			vars: t.vars,
			funs: [
				t.func(Vertex, "vertex", vertex),
				t.func(Fragment, "fragment", fragment)
			]
		};
		@:privateAccess shader.initialize();
		built++;
		return shader;
	}

	public static function constantCount(program:AgalProgram):Int {
		var n = program.used.exists(RegisterType.Constant) ? program.used.get(RegisterType.Constant) : 0;
		return n < 1 ? 1 : n;
	}

	var vars:Array<TVar> = [];
	var inputs:Map<Int, TVar> = new Map();
	var formats:Array<String>;
	var varyings:Map<Int, TVar> = new Map();
	var samplers:Map<Int, TVar> = new Map();
	var vc:TVar;
	var fc:TVar;
	var position:TVar;
	var color:TVar;
	var temps:Map<Int, TVar>;
	var program:AgalProgram;
	var written:Map<Int, Bool>;

	function new(vertex:AgalProgram, fragment:AgalProgram, formats:Array<String>) {
		if (vertex.type != AgalProgram.VERTEX || fragment.type != AgalProgram.FRAGMENT) throw "AGAL: not a vertex/fragment pair";
		this.formats = formats;
		var output = variable("output", TStruct([]), Local);
		position = variable("position", V4, Local, output);
		color = variable("color", V4, Local, output);
		output.type = TStruct([position, color]);
		vars.push(output);
		vc = variable("vc", TArray(V4, SConst(constantCount(vertex))), Param);
		fc = variable("fc", TArray(V4, SConst(constantCount(fragment))), Param);
		vars.push(vc);
		vars.push(fc);
	}

	static function variable(name:String, type:Type, kind:VarKind, ?parent:TVar):TVar {
		return {id: Tools.allocVarId(), name: name, type: type, kind: kind, parent: parent};
	}

	static inline function ex(d:TExprDef, t:Type):TExpr return {e: d, t: t, p: null};

	static inline function float(v:Float):TExpr return ex(TConst(CFloat(v)), TFloat);

	static function call(g:TGlobal, args:Array<TExpr>, t:Type):TExpr return ex(TCall(ex(TGlobal(g), TVoid), args), t);

	static function swiz(e:TExpr, comps:Array<Component>):TExpr {
		var t = comps.length == 1 ? TFloat : TVec(comps.length, VFloat);
		return ex(TSwiz(e, comps), t);
	}

	static inline function splat(f:TExpr):TExpr return call(Vec4, [f], V4);

	function func(kind:FunctionKind, name:String, program:AgalProgram):TFunction {
		this.program = program;
		temps = new Map();
		written = new Map();
		var body:Array<TExpr> = [];
		for (ins in program.instructions) instruction(ins, body);
		var decls = [for (index => v in temps) ex(TVarDecl(v, splat(float(0))), TVoid)];
		var ref = variable(name, TFun([{args: [], ret: TVoid}]), Function);
		return {kind: kind, ref: ref, args: [], ret: TVoid, expr: ex(TBlock(decls.concat(body)), TVoid)};
	}

	function input(index:Int):TExpr {
		var v = inputs.get(index);
		var format = index < formats.length ? formats[index] : null;
		if (v == null) {
			var type = switch (format) {
				case "float1": TFloat;
				case "float2": TVec(2, VFloat);
				case "float3": TVec(3, VFloat);
				case "float4" | null: V4;
				default: throw "AGAL: attribute format " + format + " not translated";
			}
			v = variable("va" + index, type, Input);
			inputs.set(index, v);
			vars.push(v);
		}
		var read = ex(TVar(v), v.type);
		return switch (v.type) {
			case TFloat: call(Vec4, [read, float(0), float(0), float(1)], V4);
			case TVec(2, _): call(Vec4, [read, float(0), float(1)], V4);
			case TVec(3, _): call(Vec4, [read, float(1)], V4);
			default: read;
		}
	}

	function varying(index:Int):TVar {
		var v = varyings.get(index);
		if (v == null) {
			v = variable("v" + index, V4, Var);
			varyings.set(index, v);
			vars.push(v);
		}
		return v;
	}

	function temp(index:Int):TVar {
		var v = temps.get(index);
		if (v == null) {
			v = variable((program.type == AgalProgram.VERTEX ? "vt" : "ft") + index, V4, Local);
			temps.set(index, v);
		}
		return v;
	}

	function sampler(index:Int):TVar {
		var v = samplers.get(index);
		if (v == null) {
			v = variable("fs" + index, TSampler(T2D, false), Param);
			samplers.set(index, v);
			vars.push(v);
		}
		return v;
	}

	function register(type:Int, index:Int):TExpr {
		return switch (type) {
			case RegisterType.Attribute: input(index);
			case RegisterType.Constant:
				var c = program.type == AgalProgram.VERTEX ? vc : fc;
				ex(TArray(ex(TVar(c), c.type), ex(TConst(CInt(index)), TInt)), V4);
			case RegisterType.Temporary: var v = temp(index); ex(TVar(v), V4);
			case RegisterType.Varying: var v = varying(index); ex(TVar(v), V4);
			default: throw "AGAL: register type " + type + " cannot be read";
		}
	}

	function source(s:Source, ?rowOffset:Int = 0):TExpr {
		if (s.indirect) throw "AGAL: indirect addressing not translated";
		var e = register(s.type, s.index + rowOffset);
		var identity = s.swizzle[0] == 0 && s.swizzle[1] == 1 && s.swizzle[2] == 2 && s.swizzle[3] == 3;
		return identity ? e : swiz(e, [for (c in s.swizzle) COMPONENTS[c]]);
	}

	function destination(ins:Instruction):TVar {
		return switch (ins.destType) {
			case RegisterType.Output: program.type == AgalProgram.VERTEX ? position : color;
			case RegisterType.Temporary: temp(ins.destIndex);
			case RegisterType.Varying: varying(ins.destIndex);
			default: throw "AGAL: register type " + ins.destType + " cannot be written";
		}
	}

	function instruction(ins:Instruction, body:Array<TExpr>):Void {
		var a = source(ins.a);
		inline function b():TExpr return source(ins.b);
		inline function xyz(e:TExpr):TExpr return swiz(e, [X, Y, Z]);
		function binop(op:haxe.macro.Expr.Binop, l:TExpr, r:TExpr):TExpr return ex(TBinop(op, l, r), V4);
		function rows(n:Int, three:Bool):TExpr {
			var dots = [for (i in 0...n) {
				var row = source(ins.b, i);
				three ? call(Dot, [xyz(a), xyz(row)], TFloat) : call(Dot, [a, row], TFloat);
			}];
			while (dots.length < 4) dots.push(float(0));
			return call(Vec4, dots, V4);
		}
		var value:TExpr = switch (ins.opcode) {
			case 0x00: a;
			case 0x01: binop(OpAdd, a, b());
			case 0x02: binop(OpSub, a, b());
			case 0x03: binop(OpMult, a, b());
			case 0x04: binop(OpDiv, a, b());
			case 0x05: binop(OpDiv, splat(float(1)), a);
			case 0x06: call(Min, [a, b()], V4);
			case 0x07: call(Max, [a, b()], V4);
			case 0x08: call(Fract, [a], V4);
			case 0x09: call(Sqrt, [a], V4);
			case 0x0A: call(Inversesqrt, [a], V4);
			case 0x0B: call(Pow, [a, b()], V4);
			case 0x0C: call(Log2, [a], V4);
			case 0x0D: call(Exp2, [a], V4);
			case 0x0E: call(Vec4, [call(Normalize, [xyz(a)], TVec(3, VFloat)), float(0)], V4);
			case 0x0F: call(Sin, [a], V4);
			case 0x10: call(Cos, [a], V4);
			case 0x11: call(Vec4, [call(Cross, [xyz(a), xyz(b())], TVec(3, VFloat)), float(1)], V4);
			case 0x12: splat(call(Dot, [xyz(a), xyz(b())], TFloat));
			case 0x13: splat(call(Dot, [a, b()], TFloat));
			case 0x14: call(Abs, [a], V4);
			case 0x15: ex(TUnop(OpNeg, a), V4);
			case 0x16: call(Saturate, [a], V4);
			case 0x17: rows(3, true);
			case 0x18: rows(4, false);
			case 0x19: rows(3, false);
			case 0x1A: call(DFdx, [a], V4);
			case 0x1B: call(DFdy, [a], V4);
			case 0x27:
				var cond = ex(TBinop(OpLt, swiz(a, [X]), float(0)), TBool);
				body.push(ex(TIf(cond, ex(TDiscard, TVoid), null), TVoid));
				return;
			case 0x28:
				var s = ins.sampler;
				if (s.dimension != 0) throw "AGAL: only 2D samplers are translated";
				var fs = sampler(s.index);
				call(Texture, [ex(TVar(fs), fs.type), swiz(a, [X, Y])], V4);
			case 0x29: call(Step, [b(), a], V4);
			case 0x2A: binop(OpSub, splat(float(1)), call(Step, [b(), a], V4));
			default: throw "AGAL: opcode " + AgalProgram.OPCODES.get(ins.opcode).name + " not translated";
		}
		var dest = destination(ins);
		var target = ex(TVar(dest), V4);
		if (ins.destMask == 15) {
			body.push(ex(TBinop(OpAssign, target, value), V4));
		} else {
			if (ins.destType != RegisterType.Temporary && !written.exists(dest.id)) {
				body.push(ex(TBinop(OpAssign, target, splat(float(0))), V4));
			}
			var comps = [for (i in 0...4) if (ins.destMask & (1 << i) != 0) COMPONENTS[i]];
			body.push(ex(TBinop(OpAssign, swiz(target, comps), swiz(value, comps)), comps.length == 1 ? TFloat : TVec(comps.length, VFloat)));
		}
		written.set(dest.id, true);
	}
}
