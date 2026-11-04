package flash.net;

import port.runtime.net.NetGuard;
import flash.events.DatagramSocketDataEvent;
import flash.events.EventDispatcher;
import flash.utils.ByteArray;
import port.runtime.services.ByteArrayBridge;
import port.runtime.services.Pump;
import port.runtime.services.UdpEndpoint;

class DatagramSocket extends EventDispatcher {
    public static var isSupported(get, never):Bool;

    public var bound(get, never):Bool;
    public var connected(get, never):Bool;
    public var localAddress(get, never):String;
    public var localPort(get, never):Int;
    public var remoteAddress(get, never):String;
    public var remotePort(get, never):Int;

    var udp:UdpEndpoint = new UdpEndpoint();
    var pumping:Bool = false;

    public function new() {
        super();
    }

    static function get_isSupported():Bool return UdpEndpoint.supported;

    function get_bound():Bool return udp.bound;

    function get_connected():Bool return udp.connected;

    function get_localAddress():String return udp.localAddress;

    function get_localPort():Int return udp.localPort;

    function get_remoteAddress():String return udp.remoteAddress;

    function get_remotePort():Int return udp.remotePort;

    public function bind(localPort:Int = 0, localAddress:String = "0.0.0.0"):Void {
        udp.bind(localPort, localAddress);
    }

    public function connect(remoteAddress:String, remotePort:Int):Void {
        if (!NetGuard.allowHost(remoteAddress, remotePort)) {
            NetGuard.refuse("UDP " + remoteAddress + ":" + remotePort);
            throw new port.runtime.services.ServiceError(2031, "refused by the port's network guard");
        }
        udp.connect(remoteAddress, remotePort);
    }

    public function receive():Void {
        udp.receive();
        if (!pumping) {
            pumping = true;
            Pump.add(pump);
        }
    }

    static var traced:Bool = Sys.getEnv("BH_PORT_TRACE_UDP") == "1";
    static var sendsLeft:Int = 12;
    static var receivesLeft:Int = 12;
    static var polls:Int = 0;

    static function traceUdp(text:String, receive:Bool = false):Void {
        if (!traced || NetGuard.log == null) return;
        if (receive ? receivesLeft-- > 0 : sendsLeft-- > 0) NetGuard.log("udp: " + text);
    }

    function pump():Bool {
        if (traced && ++polls % 600 == 0 && NetGuard.log != null)
            NetGuard.log("udp: " + polls + " polls on :" + udp.localPort + ", receiving " + udp.receiving);
        for (datagram in udp.poll()) {
            traceUdp("from " + datagram.address + ":" + datagram.port + " to :" + udp.localPort + ", "
                + datagram.data.length + " bytes", true);
            dispatchEvent(new DatagramSocketDataEvent(DatagramSocketDataEvent.DATA, false, false,
                ByteArrayBridge.wrap(datagram.data), datagram.address, datagram.port));
        }
        pumping = udp.receiving;
        return pumping;
    }

    public function send(bytes:ByteArray, offset:UInt = 0, length:UInt = 0, address:String = null, port:Int = 0):Void {
        if (address != null && !NetGuard.allowHost(address, port)) {
            NetGuard.refuse("UDP datagram to " + address + ":" + port);
            return;
        }
        try {
            var chunk = ByteArrayBridge.slice(bytes, offset, length);
            udp.send(chunk, 0, 0, address, port);
            traceUdp("to " + address + ":" + port + " from :" + udp.localPort + ", " + chunk.length + " bytes");
        } catch (e:Dynamic) {
            traceUdp("send to " + address + ":" + port + " failed: " + Std.string(e));
            throw e;
        }
    }

    public function close():Void {
        udp.close();
    }
}
