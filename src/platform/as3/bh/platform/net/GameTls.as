package bh.platform.net
{
   import bh.platform.EngineTls;
   import bh.platform.Platform;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.events.SecurityErrorEvent;
   import flash.net.SecureSocket;
   import flash.utils.ByteArray;

   public final class GameTls
   {
      public static var setting:* = undefined;

      public function GameTls()
      {
      }

      public static function wanted(host:String) : Boolean
      {
         if(setting === false || !host || !SecureSocket.isSupported)
         {
            return false;
         }
         return setting === true || EngineTls.twinPem(host) != null;
      }

      public static function connecting(connection:TcpConnection, host:String, port:int) : void
      {
         var step:String = "checking";
         try
         {
            if(connection == null || host != PrivateServer.host || uint(port) != PrivateServer.port || !wanted(host))
            {
               return;
            }
            if(connection.var_13035 is SecureSocket)
            {
               return;
            }
            step = "making the socket";
            var secure:SecureSocket = new SecureSocket();
            step = "trusting the kept certificate";
            trust(host,secure);
            step = "listening";
            secure.addEventListener(Event.CONNECT,connection.method_4281);
            secure.addEventListener(IOErrorEvent.IO_ERROR,connection.method_7570);
            secure.addEventListener(SecurityErrorEvent.SECURITY_ERROR,connection.method_8242);
            secure.addEventListener(Event.CLOSE,connection.method_5194);
            secure.addEventListener(Event.CONNECT,function(e:Event):void
            {
               Platform.log("game tls: connected to " + host + ":" + port + " in TLS");
            });
            secure.addEventListener(IOErrorEvent.IO_ERROR,function(e:IOErrorEvent):void
            {
               Platform.log("game tls: " + host + ":" + port + " failed (" + e.text + "; certificate " + secure.serverCertificateStatus + "), not retried in plain");
            });
            connection.var_13035 = secure;
            Platform.log("game tls: connecting to " + host + ":" + port + " in TLS");
         }
         catch(e:Error)
         {
            Platform.log("game tls: " + step + ": " + e.name + " " + e.message);
         }
      }

      private static function trust(host:String, secure:SecureSocket) : void
      {
         var pem:String = EngineTls.twinPem(host);
         if(pem == null)
         {
            return;
         }
         var der:ByteArray = pemToDer(pem);
         if(der == null)
         {
            Platform.log("game tls: " + EngineTls.fileName(host) + " isn't a certificate");
            return;
         }
         secure.addBinaryChainBuildingCertificate(der,true);
      }

      public static function pemToDer(pem:String) : ByteArray
      {
         var begin:String = "-----BEGIN CERTIFICATE-----";
         var at:int = pem.indexOf(begin);
         var end:int = pem.indexOf("-----END CERTIFICATE-----");
         if(at < 0 || end < at)
         {
            return null;
         }
         return base64(pem.substring(at + begin.length,end));
      }

      private static const LETTERS:String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

      public static function base64(text:String) : ByteArray
      {
         var out:ByteArray = new ByteArray();
         var bits:uint = 0;
         var count:int = 0;
         for(var i:int = 0; i < text.length; i++)
         {
            var c:String = text.charAt(i);
            if(c == "=")
            {
               break;
            }
            if(c == "\r" || c == "\n" || c == " " || c == "\t")
            {
               continue;
            }
            var v:int = LETTERS.indexOf(c);
            if(v < 0)
            {
               return null;
            }
            bits = (bits << 6 | v) & 0xFFFFFF;
            count += 6;
            if(count >= 8)
            {
               count -= 8;
               out.writeByte(bits >> count & 0xFF);
            }
         }
         out.position = 0;
         return out;
      }
   }
}
