package port.engine.art;

class VectorRecord {}

typedef PathNumbers = Array<Single>;

typedef PathCommands = #if hl Array<hl.UI16> #else Array<Int> #end;

class Paint {
	public static inline var SOLID = 0;
	public static inline var LINEAR = 1;
	public static inline var RADIAL = 2;
	public static inline var BITMAP = 3;

	public var kind:Int;
	public var color:Int = 0;
	public var alpha:Float = 1;
	public var colors:Array<Int>;
	public var alphas:Array<Float>;
	public var ratios:Array<Int>;
	public var spread:String = "pad";
	public var interpolation:String = "rgb";
	public var focal:Float = 0;
	public var matrix:Array<Float>;
	public var bitmap:flash.display.BitmapData;
	public var repeat:Bool = true;
	public var smooth:Bool = false;
	public var ramp:Array<Int>;

	public function new(kind:Int) {
		this.kind = kind;
	}

	public static function solid(color:Int, alpha:Float):Paint {
		var p = new Paint(SOLID);
		p.color = color & 0xFFFFFF;
		p.alpha = alpha < 0 ? 0 : alpha > 1 ? 1 : alpha;
		return p;
	}
}

class FillRecord {
	public var paint:Paint;
	public var commands:PathCommands = [];
	public var data:PathNumbers = [];

	public function new(paint:Paint) {
		this.paint = paint;
	}

	public function copy():FillRecord {
		var c = new FillRecord(paint);
		c.commands = commands.copy();
		c.data = data.copy();
		return c;
	}
}

class StrokeRecord {
	public var thickness:Float;
	public var paint:Paint;
	public var pixelHinting:Bool;
	public var scaleMode:String;
	public var caps:String;
	public var joints:String;
	public var miterLimit:Float;
	public var commands:PathCommands = [];
	public var data:PathNumbers = [];

	public function new(thickness:Float, paint:Paint) {
		this.thickness = thickness;
		this.paint = paint;
	}

	public function copy():StrokeRecord {
		var c = new StrokeRecord(thickness, paint);
		c.pixelHinting = pixelHinting;
		c.scaleMode = scaleMode;
		c.caps = caps;
		c.joints = joints;
		c.miterLimit = miterLimit;
		c.commands = commands.copy();
		c.data = data.copy();
		return c;
	}
}
