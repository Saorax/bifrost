package port.runtime.services;

import port.runtime.net.NetGuard;

class Browser {
    public static var opened:Array<String> = [];

    public static function open(request:Dynamic):String {
        var url = request == null ? "" : Std.isOfType(request, String) ? (request : String) : Std.string(Reflect.field(request, "url"));
        url = StringTools.trim(url);
        var host = hostOf(url);
        if (host == null || NetGuard.official(host)) {
            NetGuard.refuse("browser link " + url);
            return "refused";
        }
        opened.push(url);
        #if sys
        var mode = Sys.getEnv("BH_PORT_BROWSER");
        if (mode == "off") return "dropped";
        if (mode != null && mode != "") {
            try {
                var out = sys.io.File.append(mode, false);
                out.writeString(url + "\n");
                out.close();
            } catch (e:Dynamic) {}
            return "logged";
        }
        try {
            if (Sys.systemName() == "Windows") new sys.io.Process("explorer.exe", [url]);
            else new sys.io.Process(Sys.systemName() == "Mac" ? "open" : "xdg-open", [url]);
        } catch (e:Dynamic) {
            note("could not open a browser link: " + Std.string(e));
            return "refused";
        }
        #end
        note("browser link opened (" + hostOf(url) + ")");
        return "opened";
    }

    static function note(text:String):Void {
        if (NetGuard.log != null) NetGuard.log(text);
    }

    public static function hostOf(url:String):Null<String> {
        var lower = url.toLowerCase();
        var rest = lower.indexOf("https://") == 0 ? url.substr(8) : lower.indexOf("http://") == 0 ? url.substr(7) : null;
        if (rest == null) return null;
        var end = rest.length;
        for (c in ["/", "?", "#"]) {
            var at = rest.indexOf(c);
            if (at >= 0 && at < end) end = at;
        }
        var authority = rest.substr(0, end);
        var at = authority.lastIndexOf("@");
        if (at >= 0) authority = authority.substr(at + 1);
        var colon = authority.lastIndexOf(":");
        if (colon > 0 && authority.indexOf("]") < colon) authority = authority.substr(0, colon);
        return authority == "" ? null : authority.toLowerCase();
    }
}
