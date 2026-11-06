package bh.mods.optionsscreen
{
   import bh.platform.Hooks;
   import flash.events.Event;

   public final class OptionsScreenMod
   {
      private static var screen:OptionsScreen;
      private static var pendingHub:Object;
      private static var waitingHub:Object;
      private static const FORWARD:Array = [5,6,17,23];

      public function OptionsScreenMod()
      {
      }

      public static function register() : void
      {
         Hooks.optionsMenuShown.add(onHub);
         Hooks.optionsMenuInput.add(function(hub:Object, input:int):Boolean
         {
            if(waitingHub == null || hub !== waitingHub || !hub.isActive || FORWARD.indexOf(input) < 0)
            {
               return false;
            }
            waitingHub = null;
            open(hub);
            return true;
         });
         Hooks.keyDown.add(function(event:Object):Boolean
         {
            return screen != null && screen.isActive && (screen.typing() || screen.keyDownHook(event));
         });
         Hooks.keyUp.add(function(event:Object):Boolean
         {
            return screen != null && screen.keyUpHook(event);
         });
      }

      private static function onHub(hub:Object, list:Object) : void
      {
         if(pendingHub != null || hub == null || hub.panelClip == null || hub.panelClip.stage == null)
         {
            pendingHub = hub;
            if(hub != null && hub.panelClip != null)
            {
               hub.panelClip.addEventListener(Event.ENTER_FRAME,openSoon);
            }
            return;
         }
         pendingHub = hub;
         hub.panelClip.addEventListener(Event.ENTER_FRAME,openSoon);
      }

      private static function openSoon(e:Event) : void
      {
         e.currentTarget.removeEventListener(Event.ENTER_FRAME,openSoon);
         var hub:Object = pendingHub;
         pendingHub = null;
         if(hub == null || !hub.isActive)
         {
            return;
         }
         if(class_687.var_11971 == 2)
         {
            waitingHub = hub;
            return;
         }
         open(hub);
      }

      public static function open(hub:Object) : void
      {
         if(screen == null || ScreenManager.allScreens.indexOf(screen) < 0)
         {
            screen = new OptionsScreen(ScreenManager.owner);
            ScreenManager.registerScreen(screen);
            if(ScreenManager.var_14744 != null)
            {
               screen.registrationIndex = ScreenManager.var_14744.registrationIndex;
            }
         }
         screen.hub = hub;
         if(!screen.isActive)
         {
            screen.focusBefore = ScreenBase.previousFocusedScreen;
         }
         try
         {
            hub.panelClip.visible = false;
         }
         catch(e:Error)
         {
         }
         if(!screen.isActive)
         {
            screen.Display();
         }
      }
   }
}
