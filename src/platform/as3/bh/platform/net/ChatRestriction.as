package bh.platform.net
{
   import flash.utils.setTimeout;
   import bh.platform.Hooks;

   public final class ChatRestriction
   {
      public static const PACKET:int = 2550;

      private static var registered:Boolean = false;

      public function ChatRestriction()
      {
      }

      public static function register() : void
      {
         if(registered)
         {
            return;
         }
         registered = true;
         Hooks.packetReceived.add(function(packet:Object):Boolean
         {
            if(packet != null && packet.type == PACKET)
            {
               setTimeout(afterRead,0);
            }
            return false;
         });
      }

      private static function afterRead() : void
      {
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var chat:Object = ScreenManager.var_3257;
            if(core == null || core.var_5688 || chat == null || chat.panelClip == null)
            {
               return;
            }
            chat.panelClip.visible = GameApp.var_3689 != 2;
            PrivateServer.log("chat: the server lifted its mute; chat box shown again");
         }
         catch(e:Error)
         {
            PrivateServer.log("chat: could not show the chat box again (" + e.message + ")");
         }
      }
   }
}
