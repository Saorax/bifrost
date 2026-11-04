package flash.filters;

class BlurFilter extends flash.filters.BitmapFilter {
	public var blurX:Float;
	public var blurY:Float;
	public var quality:Int;

	public function new(blurX:Float = 4, blurY:Float = 4, quality:Int = 1) {
		super();
		this.blurX = blurX;
		this.blurY = blurY;
		this.quality = quality;
	}

	override public function clone():flash.filters.BitmapFilter {
		return new BlurFilter(blurX, blurY, quality);
	}
}
