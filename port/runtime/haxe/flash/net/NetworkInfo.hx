package flash.net;

class NetworkInfo {
    public static var isSupported:Bool = #if hl true #else false #end;
    public static var networkInfo:NetworkInfo = new NetworkInfo();

    public function new() {}

    public function findInterfaces():Array<Dynamic> {
        #if hl
        var out:Array<Dynamic> = [];
        try {
            socketInit();
            var name = Sys.getEnv("COMPUTERNAME");
            if (name == null || name == "") name = Sys.getEnv("HOSTNAME");
            if (name == null || name == "") return out;
            var host = new sys.net.Host(name);
            var address = host.toString();
            if (address != null && address != "" && address != "0.0.0.0") {
                out.push({
                    active: true,
                    name: "primary",
                    displayName: "primary",
                    hardwareAddress: "",
                    mtu: -1,
                    parent: null,
                    subInterfaces: null,
                    addresses: [{address: address, ipVersion: "IPv4", prefixLength: -1, broadcast: ""}]
                });
            }
        } catch (e:Dynamic) {}
        return out;
        #else
        return [];
        #end
    }

    #if hl
    @:hlNative("std", "socket_init") static function socketInit():Void {}
    #end
}
