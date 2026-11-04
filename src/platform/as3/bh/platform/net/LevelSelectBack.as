package bh.platform.net
{
   import bh.platform.Hooks;
   import flash.utils.getTimer;

   public final class LevelSelectBack
   {
      public static const LEVEL_SELECT_BACK:int = 11091;
      private static var asked:int = -1000;

      public function LevelSelectBack()
      {
      }

      public static function register() : void
      {
         Hooks.levelSelectInput.add(onInput);
         Hooks.packetReceived.add(onPacket);
      }

      private static function onInput(screen:Object, input:int) : Boolean
      {
         if(input != 18 && input != 19)
         {
            return false;
         }
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var lobby:Object = core.var_6336;
            if(lobby == null || int(lobby.var_10085) != 4 || PrivateServer.host == null)
            {
               return false;
            }
            var now:int = getTimer();
            if(uint(now - asked) < 500)
            {
               return true;
            }
            asked = now;
            var p:NetPacket = new NetPacket(LEVEL_SELECT_BACK);
            core.sendToServer(p);
            p.method_839();
            PrivateServer.log("level select: Back, asked the server to call the vote off (11091)");
            return true;
         }
         catch(e:Error)
         {
            PrivateServer.log("level select Back: " + e.message);
         }
         return false;
      }

      private static function onPacket(packet:Object) : Boolean
      {
         if(packet == null || packet.type != LEVEL_SELECT_BACK)
         {
            return false;
         }
         try
         {
            var who:uint = packet.readUint();
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var shown:Boolean = ScreenManager.levelSelectScreen != null && ScreenManager.levelSelectScreen.isActive;
            PrivateServer.log("level select: player " + who + " went back; vote off" + (shown ? ", back to the character select" : ""));
            if(shown)
            {
               core.method_384();
               if(ScreenBase.focusedScreen === ScreenManager.levelSelectScreen)
               {
                  ScreenBase.setFocus(ScreenManager.var_4257);
               }
            }
            try
            {
               core.var_6244.method_6022();
            }
            catch(e2:Error)
            {
            }
         }
         catch(e:Error)
         {
            PrivateServer.log("level select back (11091): " + e.message);
         }
         return true;
      }
   }
}
