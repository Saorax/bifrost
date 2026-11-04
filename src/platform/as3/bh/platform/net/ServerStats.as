package bh.platform.net
{
   import bh.platform.Busy;
   import bh.platform.Hooks;

   public final class ServerStats
   {
      public static const ASK:int = 11042;
      public static const ANSWER:int = 11043;
      public static const PROFILE:int = 11044;
      public static const LEGEND_NAMES:int = 11045;

      public static var lockIn:Array = [0,0,0];

      private static var lastProfile:String = null;
      private static var namesSent:Boolean = false;

      public static var answered:Function = null;

      public static var listeners:Array = [];

      private static var answers:Object = {};
      private static var asked:Object = {};
      private static var parts:Object = {};
      private static var registered:Boolean = false;

      public function ServerStats()
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

      public static function get(query:String) : Object
      {
         if(answers[query] == null && !asked[query])
         {
            ask(query);
         }
         return answers[query];
      }

      public static function ask(query:String) : void
      {
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var packet:NetPacket = new NetPacket(ASK);
            packet.writeString(query);
            if(core.sendToServer(packet))
            {
               asked[query] = true;
               var label:String = busyLabel(query);
               if(label != null)
               {
                  Busy.start("stats:" + query,label);
               }
            }
            packet.method_839();
         }
         catch(e:Error)
         {
            PrivateServer.log("server stats: could not ask " + query + " (" + e.message + ")");
         }
      }

      public static function busyLabel(query:String) : String
      {
         switch(query.split(":")[0])
         {
            case "activity":
               return null;
            case "profile":
            case "me":
               return "LOADING THE PROFILE";
            case "player":
            case "team":
               return "LOADING THE PLAYER";
            case "tournaments":
            case "tournament":
            case "tmatch":
            case "tpool":
               return "LOADING TOURNAMENTS";
            case "ranked":
               return "LOADING RANKS";
            case "recent":
               return "LOADING RECENT MATCHES";
            default:
               return "LOADING THE LEADERBOARD";
         }
      }

      public static function sendProfile(force:Boolean = false) : void
      {
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var inv:Object = core != null ? core.var_8329 : null;
            if(inv == null || PrivateServer.host == null)
            {
               return;
            }
            var podiums:Object = inv.var_5174 != null ? inv.var_5174.method_2469() : [];
            var avatarId:uint = uint(inv.var_13799) != 0 ? uint(inv.var_13799) : uint(class_16.var_13871.var_9656);
            var values:Array = [avatarId,uint(inv.var_15092),podiums.length > 0 ? uint(podiums[0]) : 0,
               uint(lockIn[0]),uint(lockIn[1]),uint(lockIn[2])];
            var key:String = values.join(",");
            if(!force && key == lastProfile)
            {
               return;
            }
            var packet:NetPacket = new NetPacket(PROFILE);
            packet.writeUint(1);
            for each(var v:uint in values)
            {
               packet.writeUint(v);
            }
            if(core.sendToServer(packet))
            {
               lastProfile = key;
            }
            packet.method_839();
            if(!namesSent)
            {
               var names:Array = [];
               for each(var hero:Object in HeroType.var_1273)
               {
                  if(hero != null && uint(hero.var_12172) > 0 && hero.var_4421)
                  {
                     names.push([uint(hero.var_12172),String(hero.var_4421).substr(0,40)]);
                  }
               }
               packet = new NetPacket(LEGEND_NAMES);
               packet.writeUint(names.length);
               for each(var n:Array in names)
               {
                  packet.writeUint(n[0]);
                  packet.writeString(n[1]);
               }
               namesSent = core.sendToServer(packet);
               packet.method_839();
            }
         }
         catch(e:Error)
         {
            PrivateServer.log("server stats: could not send the profile (" + e.message + ")");
         }
      }

      public static const REGION:int = 11046;

      public static function setRegion(index:uint) : void
      {
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var packet:NetPacket = new NetPacket(REGION);
            packet.writeUint(index);
            core.sendToServer(packet);
            packet.method_839();
            forget();
         }
         catch(e:Error)
         {
            PrivateServer.log("server stats: could not set the region (" + e.message + ")");
         }
      }

      public static const BIO:int = 11026;

      public static function setBio(text:String) : void
      {
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var packet:NetPacket = new NetPacket(BIO);
            packet.writeString(text);
            core.sendToServer(packet);
            packet.method_839();
         }
         catch(e:Error)
         {
            PrivateServer.log("server stats: could not set the bio (" + e.message + ")");
         }
      }

      public static function matchPlayed(pl:Object) : void
      {
         try
         {
            lockIn = [pl.var_13881 != null ? uint(pl.var_13881.var_12172) : 0,pl.var_108 != null ? uint(pl.var_108.var_14823) : 0,
               pl.var_14421 != null ? uint(pl.var_14421.var_9518) : 0];
         }
         catch(e:Error)
         {
         }
         sendProfile();
      }

      public static function forget() : void
      {
         answers = {};
         asked = {};
      }

      private static function onPacket(packet:Object) : Boolean
      {
         if(packet == null || packet.type != ANSWER)
         {
            return false;
         }
         try
         {
            var query:String = packet.readString();
            var json:String = packet.readString();
            if(json.length > 0 && json.charCodeAt(0) == 1)
            {
               var close:int = json.indexOf(String.fromCharCode(1),1);
               var head:Array = json.substring(1,close).split(" ");
               var k:int = int(head[0]);
               var n:int = int(head[1]);
               var got:Array = k == 1 || parts[query] == null ? [] : parts[query] as Array;
               got[k - 1] = json.substring(close + 1);
               parts[query] = got;
               for(var i:int = 0; i < n; i++)
               {
                  if(got[i] == null)
                  {
                     return true;
                  }
               }
               delete parts[query];
               json = got.join("");
            }
            Busy.done("stats:" + query);
            answers[query] = JSON.parse(json);
            asked[query] = false;
            if(answered != null)
            {
               answered(query);
            }
            for each(var f:Function in listeners.concat())
            {
               f(query);
            }
         }
         catch(e:Error)
         {
            PrivateServer.log("server stats: bad answer (" + e.message + ")");
         }
         return true;
      }
   }
}
