package flash.display;

class Loader extends flash.display.DisplayObjectContainer {
	public static var swfsLoaded(default, null):Int = 0;
	public static var imagesStandIn(default, null):Int = 0;
	public static var imagesDecoded(default, null):Int = 0;

	public static function registerLoader(loader:flash.display.IDisplayObjectLoader):Void {}

	public var content:flash.display.DisplayObject;
	public var contentLoaderInfo:flash.display.LoaderInfo;
	public var uncaughtErrorEvents:flash.events.UncaughtErrorEvents;

	var unloaded = true;

	public function new() {
		super();
		contentLoaderInfo = flash.display.LoaderInfo.create(this);
		uncaughtErrorEvents = contentLoaderInfo.uncaughtErrorEvents;
	}

	public function close():Void {}

	public function load(request:flash.net.URLRequest, ?context:flash.system.LoaderContext):Void {
		var url = request != null ? request.url : null;
		port.runtime.services.Pump.add(function() {
			var event = new flash.events.IOErrorEvent(flash.events.IOErrorEvent.IO_ERROR);
			event.text = "No DisplayObject loader found for " + url;
			contentLoaderInfo.dispatchEvent(event);
			return false;
		});
	}

	public function loadBytes(buffer:flash.utils.ByteArray, ?context:flash.system.LoaderContext):Void {
		var info = contentLoaderInfo;
		var loaded:flash.display.DisplayObject;
		if (isSwf(buffer)) {
			info.contentType = "application/x-shockwave-flash";
			var domain = context != null && context.applicationDomain != null ? context.applicationDomain
				: new flash.system.ApplicationDomain(flash.system.ApplicationDomain.currentDomain);
			info.applicationDomain = domain;
			var source:haxe.io.Bytes = buffer;
			var job = port.runtime.swf.SwfInflate.start(source, buffer.length);
			if (job != null) {
				info.bytesLoaded = buffer.length;
				info.bytesTotal = buffer.length;
				complete(job.wait, function() {
					return swfLoaded(new port.runtime.swf.SwfLibrary(job.source, job.length, null, job.body), domain, job.length);
				});
				return;
			}
			loaded = swfLoaded(new port.runtime.swf.SwfLibrary(buffer, buffer.length), domain, buffer.length);
		} else {
			var bytes = haxe.io.Bytes.alloc(buffer.length);
			var source:haxe.io.Bytes = buffer;
			bytes.blit(0, source, 0, buffer.length);
			var kind = flash.display.BitmapData.imageKind(bytes);
			var size = port.engine.ImageDecoder.workers > 0 ? flash.display.BitmapData.imageSize(bytes) : null;
			if (size != null) {
				var job = port.engine.ImageDecoder.start(bytes, kind == "png", size.width, size.height);
				info.bytesLoaded = buffer.length;
				info.bytesTotal = buffer.length;
				complete(function() return job.done, function() {
					var bitmapData = job.ok ? flash.display.BitmapData.fromDecoded(job.width, job.height, job.out) : null;
					imageLoaded(bitmapData, kind);
					return new flash.display.Bitmap(bitmapData);
				});
				return;
			}
			var bitmapData = flash.display.BitmapData.decode(bytes);
			imageLoaded(bitmapData, kind);
			loaded = new flash.display.Bitmap(bitmapData);
		}
		info.bytesLoaded = buffer.length;
		info.bytesTotal = buffer.length;
		complete(null, function() return loaded);
	}

	function swfLoaded(library:port.runtime.swf.SwfLibrary, domain:flash.system.ApplicationDomain, length:Int):flash.display.DisplayObject {
		port.runtime.swf.SwfSymbols.register(domain, library);
		contentLoaderInfo.frameRate = library.frameRate;
		if (traceLoads) port.engine.BootLog.log("load: SWF " + swfsLoaded + ", " + length + " bytes, "
			+ library.tagCount + " tags, first symbol " + firstSymbol(library) + ", into "
			+ (domain == flash.system.ApplicationDomain.currentDomain ? "currentDomain" : "a child domain"));
		swfsLoaded++;
		return new flash.display.MovieClip();
	}

	function imageLoaded(bitmapData:flash.display.BitmapData, kind:String):Void {
		var info = contentLoaderInfo;
		if (bitmapData != null) {
			info.contentType = kind == "png" ? "image/png" : "image/jpeg";
			info.width = bitmapData.width;
			info.height = bitmapData.height;
			imagesDecoded++;
		} else {
			imagesStandIn++;
		}
	}

	static var completions:Array<{ready:() -> Bool, loader:Loader, content:() -> flash.display.DisplayObject}> = [];
	static var draining = false;

	function complete(ready:() -> Bool, content:() -> flash.display.DisplayObject):Void {
		completions.push({ready: ready, loader: this, content: content});
		if (!draining) {
			draining = true;
			port.runtime.services.Pump.add(drain);
		}
	}

	static function drain():Bool {
		port.engine.ImageDecoder.poll();
		port.runtime.swf.SwfInflate.poll();
		var n = completions.length;
		while (n-- > 0 && (completions[0].ready == null || completions[0].ready())) {
			var c = completions.shift();
			c.loader.finish(c.content());
		}
		draining = completions.length > 0;
		return draining;
	}

	function finish(loaded:flash.display.DisplayObject):Void {
		var info = contentLoaderInfo;
		unloaded = false;
		content = loaded;
		info.content = loaded;
		addChildAt(loaded, 0);
		info.dispatchEvent(new flash.events.Event(flash.events.Event.COMPLETE));
	}

	public function unload():Void {
		if (unloaded) return;
		if (content != null && content.parent == this) removeChild(content);
		content = null;
		var info = contentLoaderInfo;
		info.url = null;
		info.contentType = null;
		info.content = null;
		info.bytesLoaded = 0;
		info.bytesTotal = 0;
		info.width = 0;
		info.height = 0;
		unloaded = true;
		info.dispatchEvent(new flash.events.Event(flash.events.Event.UNLOAD));
	}

	public function unloadAndStop(gc:Bool = true):Void {
		unload();
	}

	static var traceLoads = Sys.getEnv("BH_PORT_TRACE_LOADS") == "1";

	static function firstSymbol(library:port.runtime.swf.SwfLibrary):String {
		var first:String = null;
		for (name in library.symbols.keys()) if (first == null || name < first) first = name;
		return first;
	}

	static function isSwf(bytes:flash.utils.ByteArray):Bool {
		if (bytes == null || bytes.length < 8) return false;
		var a = bytes[0], b = bytes[1], c = bytes[2];
		return (a == "F".code || a == "C".code || a == "Z".code) && b == "W".code && c == "S".code;
	}
}
