package bh.platform.net
{
   import bh.platform.Hooks;

   public final class Cosmetics
   {
      public static const PACKET:int = 11018;

      private static const FIELDS:Array = ["var_4349","var_11159","var_11804","var_2464","var_2379","var_15112","var_6061"];

      private static const TABLES:Array = ["avatarTypes","SeasonBorderTypes","PlayerThemeTypes","TrailEffectTypes","TauntTypes",
         "TauntTypes","MonikerTypes"];

      private static const ROOM:int = 2445;

      private static var known:Object = {};

      private static var registered:Boolean = false;

      public function Cosmetics()
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

      public static function mine() : Array
      {
         var core:Object = Object(GameApp.mainInstance).var_13259;
         var l:class_294 = new class_294();
         core.var_8329.method_206(l);
         var out:Array = [];
         for each(var f:String in FIELDS)
         {
            out.push(uint(l[f]));
         }
         for(var i:int = 0; i < 8; i++)
         {
            out.push(uint(l.var_7882[i]));
         }
         out.push(uint(core.var_8329.method_7366()));
         return out;
      }

      private static function defaults() : Array
      {
         var out:Array = [uint(class_16.var_13871.var_9656),uint(class_559.var_12515.var_6438),
            uint(class_297.var_11954.var_11804),uint(class_650.var_3690.var_4967),uint(class_629.var_1295.var_13006),
            uint(class_629.var_6374.var_13006),0];
         for(var i:int = 0; i < 8; i++)
         {
            out.push(0);
         }
         return out;
      }

      public static function sendMine() : void
      {
         try
         {
            var values:Array = mine();
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var packet:NetPacket = new NetPacket(PACKET);
            packet.writeUint(uint(values.length));
            for each(var v:uint in values)
            {
               packet.writeUint(v);
            }
            core.sendToServer(packet);
            packet.method_839();
         }
         catch(e:Error)
         {
            PrivateServer.log("cosmetics: could not send ours (" + e.message + ")");
         }
      }

      public static function filled(member:Object, loadout:Object) : void
      {
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var id:uint = uint(member.var_14656);
            if(id == uint(core.var_14656) || !P2PSession.active)
            {
               return;
            }
            var v:Array = known[id];
            if(v == null)
            {
               v = defaults();
               PrivateServer.log("cosmetics: none from player " + id + "; the game's defaults");
            }
            for(var i:int = 0; i < FIELDS.length && i < v.length; i++)
            {
               loadout[FIELDS[i]] = TABLES[i] != null ? ModItems.id(TABLES[i],id,uint(v[i])) : uint(v[i]);
            }
            for(var j:int = 0; j < 8 && FIELDS.length + j < v.length; j++)
            {
               loadout.var_7882[j] = ModItems.id("TauntTypes",id,uint(v[FIELDS.length + j]));
            }
         }
         catch(e:Error)
         {
            PrivateServer.log("cosmetics: could not apply player " + member.var_14656 + "'s (" + e.message + ")");
         }
      }

      private static function onPacket(packet:Object) : Boolean
      {
         if(packet == null)
         {
            return false;
         }
         if(packet.type == ROOM || packet.type == P2PMatch.MATCH_FOUND)
         {
            sendMine();
            return false;
         }
         if(packet.type != PACKET)
         {
            return false;
         }
         try
         {
            var id:uint = packet.readUint();
            var n:uint = Math.min(64,packet.readUint());
            var v:Array = [];
            for(var i:uint = 0; i < n; i++)
            {
               v.push(packet.readUint());
            }
            known[id] = v;
         }
         catch(e:Error)
         {
            PrivateServer.log("cosmetics: bad 11018 (" + e.message + ")");
         }
         return true;
      }
   }
}
