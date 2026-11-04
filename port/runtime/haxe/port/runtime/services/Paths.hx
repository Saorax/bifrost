package port.runtime.services;

class Paths {
    public static function normalize(path:String):String {
        if (path == null || path == "") return "";
        var p = StringTools.replace(path, "/", "\\");
        var unc = StringTools.startsWith(p, "\\\\");
        var parts = p.split("\\");
        var out:Array<String> = [];
        var head = "";
        var start = 0;
        if (unc) {
            head = "\\\\";
            start = 2;
        } else if (isDriveRoot(parts[0])) {
            head = parts[0].toUpperCase().charAt(0) + ":\\";
            start = 1;
        } else if (StringTools.startsWith(p, "\\")) {
            head = "\\";
            start = 1;
        }
        for (i in start...parts.length) {
            var part = parts[i];
            if (part == "" || part == ".") continue;
            if (part == "..") {
                if (out.length > 0 && out[out.length - 1] != "..") out.pop();
                else if (head == "") out.push("..");
                continue;
            }
            out.push(part);
        }
        if (unc) return head + out.join("\\");
        if (head != "") return head + out.join("\\");
        return out.join("\\");
    }

    static function isDriveRoot(part:String):Bool {
        return part != null && part.length == 2 && part.charAt(1) == ":" && ~/^[A-Za-z]$/.match(part.charAt(0));
    }

    public static function isAbsolute(path:String):Bool {
        if (path == null || path == "") return false;
        var p = StringTools.replace(path, "/", "\\");
        return StringTools.startsWith(p, "\\") || (p.length >= 2 && isDriveRoot(p.substr(0, 2)));
    }

    public static function resolve(base:String, path:String):String {
        if (path == null || path == "") return normalize(base);
        if (isAbsolute(path) || base == null || base == "") return normalize(path);
        return normalize(base + "\\" + path);
    }

    public static function name(path:String):String {
        var p = normalize(path);
        if (isRoot(p)) return "";
        var i = p.lastIndexOf("\\");
        return i >= 0 ? p.substr(i + 1) : p;
    }

    public static function extension(path:String):Null<String> {
        var n = name(path);
        var i = n.lastIndexOf(".");
        return i >= 0 ? n.substr(i + 1) : null;
    }

    public static function parent(path:String):Null<String> {
        var p = normalize(path);
        if (p == "" || isRoot(p)) return null;
        var i = p.lastIndexOf("\\");
        if (i < 0) return null;
        var up = p.substr(0, i);
        if (isDriveRoot(up)) return up + "\\";
        if (up == "") return "\\";
        return up;
    }

    public static function isRoot(path:String):Bool {
        var p = normalize(path);
        return p == "\\" || (p.length == 3 && isDriveRoot(p.substr(0, 2)) && p.charAt(2) == "\\");
    }

    public static function url(path:String):String {
        var p = normalize(path);
        var segments = StringTools.replace(p, "\\", "/").split("/");
        var encoded = [for (s in segments) isDriveRoot(s) ? s : StringTools.urlEncode(s)];
        return "file:///" + encoded.join("/");
    }
}
