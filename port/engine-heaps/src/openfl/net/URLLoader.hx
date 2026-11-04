package openfl.net;

import flash.events.Event;
import flash.events.HTTPStatusEvent;
import flash.events.IOErrorEvent;
import flash.net.URLRequest;
import port.runtime.services.ByteArrayBridge;
import port.runtime.services.Pump;

class URLLoader extends flash.events.EventDispatcher {
	public var bytesLoaded:Int = 0;
	public var bytesTotal:Int = 0;
	public var data:Dynamic;
	public var dataFormat:flash.net.URLLoaderDataFormat = flash.net.URLLoaderDataFormat.TEXT;

	public static var active(default, null):Int = 0;

	var generation:Int = 0;

	public function new(?request:URLRequest) {
		super();
		if (request != null) load(request);
	}

	public function close():Void {
		generation++;
	}

	public function load(request:URLRequest):Void {
		var url = request == null ? null : request.url;
		var lower = url == null ? "" : StringTools.trim(url).toLowerCase();
		if (!StringTools.startsWith(lower, "http://") && !StringTools.startsWith(lower, "https://")) return;
		var ticket = ++generation;
		var job = HttpJob.of(request);
		var done = new sys.thread.Deque<HttpResult>();
		active++;
		var opened = false;
		sys.thread.Thread.create(function() done.add(job.run()));
		Pump.add(function():Bool {
			if (ticket != generation) {
				var dropped = done.pop(false);
				if (dropped != null) active--;
				return dropped == null;
			}
			if (!opened) {
				opened = true;
				dispatchEvent(new Event("open"));
			}
			var result = done.pop(false);
			if (result == null) return true;
			active--;
			deliver(result);
			return false;
		});
	}

	function deliver(result:HttpResult):Void {
		var body = result.body == null ? haxe.io.Bytes.alloc(0) : result.body;
		bytesLoaded = bytesTotal = body.length;
		data = switch (Std.string(dataFormat)) {
			case "binary": ByteArrayBridge.wrap(body);
			case "variables": new flash.net.URLVariables(body.toString());
			default: body.toString();
		};
		if (result.status > 0) dispatchEvent(new HTTPStatusEvent("httpStatus", false, false, result.status));
		if (result.error == null && result.status >= 200 && result.status < 300) {
			dispatchEvent(new Event("complete"));
		} else {
			var text = "Error #2032: Stream Error. URL: " + result.url + (result.error != null ? " (" + result.error + ")" : "");
			dispatchEvent(new IOErrorEvent("ioError", false, false, text, 2032));
		}
	}
}

class HttpJob {
	public var url:String;
	public var post:Bool;
	public var body:Null<haxe.io.Bytes>;
	public var headers:Array<{name:String, value:String}> = [];

	function new() {}

	public static function of(request:URLRequest):HttpJob {
		var job = new HttpJob();
		job.url = request.url;
		job.post = request.method != null && request.method.toUpperCase() == "POST";
		var payload:Dynamic = request.data;
		var text:Null<String> = null;
		if (payload == null) {
			job.body = null;
		} else if (Std.isOfType(payload, String)) {
			text = payload;
		} else if (Std.isOfType(payload, haxe.io.Bytes)) {
			job.body = ByteArrayBridge.slice(payload, 0, 0);
		} else {
			var parts = [];
			for (name in Reflect.fields(payload))
				parts.push(StringTools.urlEncode(name) + "=" + StringTools.urlEncode(Std.string(Reflect.field(payload, name))));
			text = parts.join("&");
		}
		if (text != null) {
			if (job.post) {
				job.body = haxe.io.Bytes.ofString(text);
			} else if (text != "") {
				job.url += (job.url.indexOf("?") >= 0 ? "&" : "?") + text;
			}
		}
		if (job.post) {
			var type = request.contentType != null ? request.contentType : "application/x-www-form-urlencoded";
			job.headers.push({name: "Content-Type", value: type});
		}
		if (request.requestHeaders != null)
			for (h in request.requestHeaders) job.headers.push({name: h.name, value: h.value});
		return job;
	}

	public function run():HttpResult {
		var result = new HttpResult(url);
		try {
			var http = new sys.Http(url);
			for (h in headers) http.setHeader(h.name, h.value);
			if (post && body != null) http.setPostBytes(body);
			http.onStatus = function(status) result.status = status;
			http.onBytes = function(bytes) result.body = bytes;
			http.onError = function(message) {
				result.error = message;
				result.body = http.responseBytes;
			};
			var sock = port.engine.Tls.socketFor(url);
			if (sock == null) {
				http.request(post);
			} else {
				var output = new haxe.io.BytesOutput();
				var failed = false;
				http.onError = function(message) {
					failed = true;
					result.error = message;
					result.body = output.getBytes();
				};
				http.customRequest(post, output, sock);
				if (!failed) result.body = output.getBytes();
			}
		} catch (e:Dynamic) {
			if (result.error == null) result.error = Std.string(e);
		}
		return result;
	}
}

class HttpResult {
	public var url:String;
	public var status:Int = 0;
	public var body:Null<haxe.io.Bytes>;
	public var error:Null<String>;

	public function new(url:String) {
		this.url = url;
	}
}
