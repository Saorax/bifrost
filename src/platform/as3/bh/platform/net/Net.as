package bh.platform.net
{
   import bh.platform.Hooks;

   public final class Net
   {
      public static var transport:Transport = null;

      public static var offered:uint = 0;
      public static var takenOver:uint = 0;
      public static var delivered:uint = 0;

      private static var started:Boolean = false;

      public function Net()
      {
      }

      public static function init() : void
      {
         if(started)
         {
            return;
         }
         started = true;
         Hooks.packetSending.add(onSending);
      }

      private static function onSending(connection:Object, packet:NetPacket) : Boolean
      {
         if(transport == null)
         {
            return false;
         }
         offered++;
         if(transport.send(connection,packet))
         {
            takenOver++;
            return true;
         }
         return false;
      }

      public static function isTcp(connection:Object) : Boolean
      {
         return connection is TcpConnection;
      }

      public static function deliver(packet:NetPacket) : Boolean
      {
         var main:Main = GameApp.mainInstance;
         if(main == null || main.game == null || main.game.linkUpdater == null)
         {
            return false;
         }
         delivered++;
         main.game.linkUpdater.dispatchPacket(packet);
         return true;
      }
   }
}
