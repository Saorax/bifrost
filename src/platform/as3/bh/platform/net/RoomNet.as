package bh.platform.net
{
   import bh.platform.Hooks;
   import bh.platform.Modal;

   public final class RoomNet
   {
      public static const PACKET:int = 11017;

      public static var settings:Object = null;

      private static var registered:Boolean = false;

      public function RoomNet()
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

      public static function of(room:uint) : Object
      {
         return settings != null && uint(settings.room) == room ? settings : null;
      }

      public static function send(rollback:Boolean, delay:uint, smoothing:Boolean, smoothingMs:uint) : void
      {
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var packet:NetPacket = new NetPacket(PACKET);
            packet.method_5184(rollback);
            packet.writeUint(delay);
            packet.method_5184(smoothing);
            packet.writeUint(smoothingMs);
            core.sendToServer(packet);
            packet.method_839();
         }
         catch(e:Error)
         {
            PrivateServer.log("room network settings: could not send (" + e.message + ")");
         }
      }

      public static function hostStarting(core:Object) : void
      {
         try
         {
            var room:uint = uint(core.var_6244.var_13482);
            if(room == 0 || of(room) != null)
            {
               return;
            }
            PrivateServer.readP2PSettings();
            send(PrivateServer.p2pRollback,PrivateServer.p2pDelaySet ? PrivateServer.p2pDelay : 0,PrivateServer.p2pSmoothing,
               uint(PrivateServer.p2pSmoothingMs));
         }
         catch(e:Error)
         {
         }
      }

      public static function apply(room:uint) : void
      {
         var s:Object = of(room);
         if(s == null)
         {
            return;
         }
         PrivateServer.p2pRollback = s.rollback;
         PrivateServer.p2pDelaySet = uint(s.delay) != 0;
         if(PrivateServer.p2pDelaySet)
         {
            PrivateServer.p2pDelay = uint(s.delay);
         }
         PrivateServer.p2pSmoothing = s.smoothing;
         PrivateServer.p2pSmoothingMs = Number(s.smoothingMs) > 0 ? Number(s.smoothingMs) : 100;
         PrivateServer.log("P2P room " + room + ": the room's network settings: " + describe(s));
      }

      public static function describe(s:Object) : String
      {
         return "Rollback " + (s.rollback ? "On" : "Off") + ", Input delay " + (uint(s.delay) != 0 ? s.delay + " ms" : "Auto") +
            ", Smoothing " + (s.smoothing ? "On (" + s.smoothingMs + " ms)" : "Off");
      }

      private static function onPacket(packet:Object) : Boolean
      {
         if(packet == null || packet.type != PACKET)
         {
            return false;
         }
         try
         {
            var s:Object = {"room":packet.readUint(),"host":packet.readUint(),"rollback":packet.method_5885(),
               "delay":packet.readUint(),"smoothing":packet.method_5885(),"smoothingMs":packet.readUint()};
            var old:Object = of(uint(s.room));
            settings = s;
            var me:uint = uint(Object(GameApp.mainInstance).var_13259.var_14656);
            PrivateServer.log("room " + s.room + " network settings from the host " + s.host + ": " + describe(s));
            if(uint(s.host) == me || uint(s.host) == 0)
            {
               return true;
            }
            var changed:Array = [];
            if(old == null || old.rollback != s.rollback)
            {
               changed.push("Rollback: " + (s.rollback ? "On" : "Off"));
            }
            if(old == null || uint(old.delay) != uint(s.delay))
            {
               changed.push("Input delay: " + (uint(s.delay) != 0 ? s.delay + " ms" : "Auto"));
            }
            if(old == null || old.smoothing != s.smoothing || uint(old.smoothingMs) != uint(s.smoothingMs))
            {
               changed.push("Smoothing: " + (s.smoothing ? "On, " + s.smoothingMs + " ms" : "Off"));
            }
            if(changed.length > 0)
            {
               Modal.show("NETWORK SETTINGS",(old == null ? "This room's network settings:\n" : "The host changed the room's network settings:\n") +
                  changed.join("\n"),null,true);
            }
         }
         catch(e:Error)
         {
            PrivateServer.log("room network settings: bad 11017 (" + e.message + ")");
         }
         return true;
      }
   }
}
