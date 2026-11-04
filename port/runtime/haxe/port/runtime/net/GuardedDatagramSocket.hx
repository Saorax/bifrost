package port.runtime.net;

class GuardedDatagramSocket extends flash.net.DatagramSocket {
    public function new() {
        super();
    }

    override public function connect(remoteAddress:String, remotePort:Int):Void {
        if (!NetGuard.allowHost(remoteAddress, remotePort)) {
            NetGuard.refuse("UDP " + remoteAddress + ":" + remotePort);
            throw new flash.errors.IOError("Error #2031: refused by the port's network guard");
        }
        super.connect(remoteAddress, remotePort);
    }

    override public function send(bytes:flash.utils.ByteArray, offset:UInt = 0, length:UInt = 0, address:String = null,
            port:Int = 0):Void {
        if (address != null && !NetGuard.allowHost(address, port)) {
            NetGuard.refuse("UDP datagram to " + address + ":" + port);
            return;
        }
        super.send(bytes, offset, length, address, port);
    }
}
