package bh.platform.net
{
   import bh.platform.Hooks;

   public final class LegendLevels
   {
      public static const PACKET:int = 11019;

      private static var registered:Boolean = false;

      public function LegendLevels()
      {
      }

      public static function register() : void
      {
         if(registered)
         {
            return;
         }
         registered = true;
         Hooks.packetReceived.add(onPacket);
      }

      private static function onPacket(packet:Object) : Boolean
      {
         if(packet == null || packet.type != PACKET)
         {
            return false;
         }
         try
         {
            var inventory:Object = Object(GameApp.mainInstance).var_13259.var_8329;
            var n:uint = Math.min(4096,packet.readUint());
            for(var i:uint = 0; i < n; i++)
            {
               var hero:uint = packet.readUint();
               var level:uint = packet.readUint();
               var xp:uint = packet.readUint();
               var start:uint = packet.readUint();
               var next:uint = packet.readUint();
               if(HeroType.var_1273[hero] != null)
               {
                  inventory.method_4336(hero,level,xp,start,next);
               }
            }
            PrivateServer.log("legend levels: " + n + " from the server");
         }
         catch(e:Error)
         {
            PrivateServer.log("legend levels: bad 11019 (" + e.message + ")");
         }
         return true;
      }
   }
}
