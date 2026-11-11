package bh.platform.net
{
   import bh.platform.Modal;
   import flash.events.TimerEvent;
   import flash.utils.Timer;
   import flash.utils.getTimer;

   public final class P2PChoice
   {
      public static const P2P_CHOICE:int = 11025;
      public static const ASK_MARK:uint = 256;
      public static const TITLE:String = "Direct connection?";
      public static const WAIT_MS:int = 1500;

      private static var askedRoom:uint = 0;
      private static var begunRoom:uint = 0;
      private static var room:uint = 0;
      private static var ids:Array = null;
      private static var askAt:int = 0;
      private static var timer:Timer = null;
      private static var open:Boolean = false;
      private static var answeredAt:int = -100000;
      public static var last:String = "";

      public function P2PChoice()
      {
      }

      public static function readAsk(packet:Object) : Array
      {
         var out:Array = [];
         try
         {
            var bytes:Object = packet.var_5085.var_15327;
            if(int(bytes.length) * 8 - int(packet.var_5085.var_11198) < 8)
            {
               return out;
            }
            var mark:uint = packet.readUint();
            if((mark & ASK_MARK) == 0)
            {
               return out;
            }
            var n:uint = mark & 255;
            for(var i:uint = 0; i < n; i++)
            {
               out.push(packet.readUint());
            }
         }
         catch(e:Error)
         {
         }
         return out;
      }

      public static function asked(roomNumber:uint, players:Array) : void
      {
         if(players == null || players.length == 0 || askedRoom == roomNumber)
         {
            return;
         }
         if(begunRoom == roomNumber)
         {
            PrivateServer.log("P2P room " + roomNumber + ": the DIRECT or RELAY question came after the start; the relay");
            return;
         }
         if(PrivateServer.p2pRelayOnly)
         {
            askedRoom = room = roomNumber;
            ids = players;
            PrivateServer.log("P2P room " + roomNumber + ": \"p2p\": \"relay\" in bh-server.json; not asked, the relay");
            answer(false);
            return;
         }
         askedRoom = room = roomNumber;
         ids = players;
         askAt = getTimer() + WAIT_MS;
         stopTimer();
         timer = new Timer(250);
         timer.addEventListener(TimerEvent.TIMER,onTick);
         timer.start();
         PrivateServer.log("P2P room " + room + ": not friends with " + names().join(", ") + "; asking DIRECT or RELAY");
      }

      public static function warmStarts() : void
      {
         begunRoom = 0;
      }

      public static function matchStarts(roomNumber:uint) : void
      {
         begunRoom = roomNumber;
         if(ids == null || roomNumber != room)
         {
            return;
         }
         stopTimer();
         if(open)
         {
            Modal.close(TITLE);
            answeredAt = getTimer();
         }
         open = false;
         ids = null;
         last = "relay (no answer)";
         PrivateServer.log("P2P room " + room + ": no answer before the start; the match uses the relay");
      }

      private static function onTick(e:TimerEvent) : void
      {
         if(ids == null)
         {
            stopTimer();
            return;
         }
         var measured:Boolean = true;
         for each(var id:uint in ids)
         {
            measured = measured && P2PSession.relayPingOf(id) >= 0;
         }
         if(measured || getTimer() >= askAt)
         {
            stopTimer();
            show();
         }
      }

      private static function show() : void
      {
         var pings:Array = [];
         for each(var id:uint in ids)
         {
            var ms:int = P2PSession.relayPingOf(id);
            pings.push(ms >= 0 ? ms + " ms" : "not measured yet");
         }
         var who:Array = names();
         var text:String = who.join(", ") + (who.length == 1 ? " isn't" : " aren't") + " on your friends list.\n" +
            "Through a relay: " + pings.join(", ") + ". It hides your IP address.\n" +
            "DIRECT can be faster, but shows each of you the other's IP address. It is used only if both choose it; " +
            "the direct ping is measured then.\n" +
            "The match starts once everyone answers, or after 12 seconds with the relay.";
         open = Modal.show(TITLE,text,[{"label":"Direct","action":function():void
         {
            answer(true);
         }},{"label":"Relay","action":function():void
         {
            answer(false);
         }}],true);
         if(!open)
         {
            answer(false);
         }
      }

      public static function get busy() : Boolean
      {
         return open || getTimer() - answeredAt < 1000;
      }

      private static function answer(direct:Boolean) : void
      {
         answeredAt = getTimer();
         open = false;
         ids = null;
         last = direct ? "direct" : "relay";
         try
         {
            var core:Object = ScreenManager.owner;
            var p:NetPacket = new NetPacket(P2P_CHOICE);
            p.writeUint(room);
            p.writeUint(direct ? 1 : 0);
            core.sendToServer(p);
            p.method_839();
         }
         catch(e:Error)
         {
            PrivateServer.log("P2P: could not send the DIRECT/RELAY answer: " + e.message);
            return;
         }
         PrivateServer.log("P2P room " + room + ": chose " + (direct ? "DIRECT (addresses only if the other player chooses it too)" : "the relay"));
      }

      public static function press(direct:Boolean) : Boolean
      {
         return open && Modal.press(direct ? 0 : 1);
      }

      private static function names() : Array
      {
         var out:Array = [];
         var members:Object = null;
         try
         {
            members = Object(GameApp.mainInstance).var_13259.var_6244.var_1751;
         }
         catch(e:Error)
         {
         }
         for each(var id:uint in ids)
         {
            var name:String = "player " + id;
            try
            {
               for(var i:int = 0; members != null && i < int(members.length); i++)
               {
                  if(uint(members[i].var_14656) == id && members[i].var_6307.var_14792)
                  {
                     name = String(members[i].var_6307.var_14792);
                  }
               }
            }
            catch(e2:Error)
            {
            }
            out.push(name);
         }
         return out;
      }

      private static function stopTimer() : void
      {
         if(timer != null)
         {
            timer.stop();
            timer.removeEventListener(TimerEvent.TIMER,onTick);
            timer = null;
         }
      }
   }
}
