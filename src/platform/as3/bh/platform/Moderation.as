package bh.platform
{
   public final class Moderation
   {
      public static const ASK:int = 11097;
      public static const ANSWER:int = 11098;
      public static const STATE:int = 11099;
      private static const BUSY:String = "moderation";

      public static var admin:Boolean = false;
      public static var last:Object = null;

      private static var waiting:Object = {};

      public function Moderation()
      {
         super();
      }

      public static function init() : void
      {
         Hooks.packetReceived.add(onPacket);
      }

      public static function ask(action:String, args:Object, done:Function = null) : String
      {
         var core:Object = ScreenManager.owner;
         if(core == null || core.serverConnection == null || !core.serverConnection.isConnected())
         {
            return "not connected to a server";
         }
         waiting[action] = done;
         var p:NetPacket = new NetPacket(ASK);
         p.writeString(action);
         p.writeString(JSON.stringify(args || {}));
         core.sendToServer(p);
         p.method_839();
         Busy.start(BUSY,"ASKING THE SERVER",10000);
         return null;
      }

      private static function onPacket(packet:Object) : Boolean
      {
         if(packet == null || packet.type != STATE && packet.type != ANSWER)
         {
            return false;
         }
         if(packet.type == STATE)
         {
            try
            {
               admin = packet.method_5885();
               Platform.log("moderation: this account is " + (admin ? "" : "not ") + "a server admin (11099)");
            }
            catch(e:Error)
            {
            }
            return true;
         }
         Busy.done(BUSY);
         var answer:Object;
         try
         {
            answer = JSON.parse(packet.readString());
         }
         catch(e:Error)
         {
            answer = {"ok":false,"message":"The server's answer couldn't be read."};
         }
         last = answer;
         var done:Function = waiting[answer.action] as Function;
         delete waiting[answer.action];
         if(done != null)
         {
            try
            {
               done(answer);
            }
            catch(e:Error)
            {
               Platform.log("moderation: " + e.message);
            }
         }
         return true;
      }
   }
}
