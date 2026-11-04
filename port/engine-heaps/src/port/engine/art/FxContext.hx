package port.engine.art;

class FxContext {
	static var shared:h3d.impl.RenderContext;

	public static function enter():Bool {
		if (h3d.impl.RenderContext.get() != null) return false;
		if (shared == null) shared = @:privateAccess new h3d.impl.RenderContext();
		shared.setCurrent();
		return true;
	}

	public static function leave(entered:Bool):Void {
		if (entered && h3d.impl.RenderContext.get() == shared) shared.clearCurrent();
	}
}
