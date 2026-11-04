package flash.display;

import flash.geom.Rectangle;

class Screen {
    public static var mainScreen(get, never):Screen;
    public static var screens(get, never):Array<Screen>;

    public var bounds(default, null):Rectangle;
    public var visibleBounds(get, never):Rectangle;
    public var colorDepth(default, null):Int = 32;

    static var cached:Array<Screen>;

    function new(bounds:Rectangle) {
        this.bounds = bounds;
    }

    function get_visibleBounds():Rectangle return bounds.clone();

    static function get_screens():Array<Screen> {
        if (cached == null) {
            cached = [];
            #if hlsdl
            for (d in sdl.Sdl.getDisplays())
                cached.push(new Screen(new Rectangle(d.left, d.top, d.right - d.left, d.bottom - d.top)));
            #end
            if (cached.length == 0) {
                var window = hxd.Window.getInstance();
                cached.push(new Screen(new Rectangle(0, 0, window.width, window.height)));
            }
        }
        return cached.copy();
    }

    static function get_mainScreen():Screen {
        get_screens();
        return cached[0];
    }

    public static function getScreensForRectangle(rect:Rectangle):Array<Screen> {
        return [for (s in get_screens()) if (s.bounds.intersects(rect)) s];
    }
}
