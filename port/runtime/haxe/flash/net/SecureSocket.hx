package flash.net;

import flash.utils.ByteArray;
import port.runtime.services.ByteArrayBridge;

class SecureSocket extends Socket {
    public static var isSupported(get, never):Bool;

    public static inline var PINNED_NAME = "localhost";

    public var serverCertificateStatus(get, never):String;

    #if (sys && hl)
    var anchors:Null<sys.ssl.Certificate> = null;
    #end

    public function new() {
        super();
    }

    static function get_isSupported():Bool {
        #if (sys && hl)
        return true;
        #else
        return false;
        #end
    }

    public function addBinaryChainBuildingCertificate(certificate:ByteArray, trusted:Bool):Void {
        #if (sys && hl)
        if (!trusted) return;
        var der = ByteArrayBridge.slice(certificate, 0, 0);
        try {
            if (anchors == null) anchors = sys.ssl.Certificate.fromString(pem(der)); else anchors.addDER(der);
        } catch (e:Dynamic) {
            throw new port.runtime.services.ServiceError(2004, "One of the parameters is invalid.");
        }
        #end
    }

    override public function connect(host:String, port:Int):Void {
        tcp.tls = true;
        #if (sys && hl)
        tcp.tlsCa = anchors;
        tcp.tlsName = anchors != null ? PINNED_NAME : null;
        #end
        super.connect(host, port);
    }

    function get_serverCertificateStatus():String return tcp.tlsStatus;

    public static function pem(der:haxe.io.Bytes):String {
        var text = haxe.crypto.Base64.encode(der);
        var out = new StringBuf();
        out.add("-----BEGIN CERTIFICATE-----\n");
        var at = 0;
        while (at < text.length) {
            out.add(text.substr(at, 64));
            out.add("\n");
            at += 64;
        }
        out.add("-----END CERTIFICATE-----\n");
        return out.toString();
    }
}
