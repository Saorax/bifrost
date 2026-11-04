package bh.mods.examplescreen
{
   import bh.platform.Hooks;
   import flash.events.MouseEvent;

   public final class ExampleScreenMod
   {
      public static const KEY_BUTTON:String = "BH_ExampleScreen_Button";
      public static const KEY_BUTTON_DESC:String = "BH_ExampleScreen_Button_Desc";
      public static const KEY_HEADER:String = "BH_ExampleScreen_Header";
      public static const KEYS_BODY:Array = ["BH_ExampleScreen_Line1","BH_ExampleScreen_Line2","BH_ExampleScreen_Line3"];

      private static const STRINGS:Object = {
         "BH_ExampleScreen_Button":"Mods",
         "BH_ExampleScreen_Button_Desc":"Bifrost mods",
         "BH_ExampleScreen_Header":"Example screen",
         "BH_ExampleScreen_Line1":"This screen was added by the example mod (bh.mods.examplescreen).",
         "BH_ExampleScreen_Line2":"It is a ScreenBase subclass using the game's own art, text and input handling.",
         "BH_ExampleScreen_Line3":"Press Back to return to the main menu."
      };

      public static const STORE:uint = 7;

      private static var screen:ModsScreen;
      private static var menu:ScreenMainMenu;

      public function ExampleScreenMod()
      {
      }

      public static function register() : void
      {
         Hooks.mainMenuButtonsBuilt.add(onButtonsBuilt);
         Hooks.mainMenuInput.add(onInput);
      }

      private static function addStrings() : void
      {
         if(Localization.var_14676 == null)
         {
            return;
         }
         for(var key:String in STRINGS)
         {
            if(!Localization.var_14676.var_15061.exists(key))
            {
               Localization.var_14676.var_15061.method_65(key,STRINGS[key]);
            }
         }
      }

      private static function onButtonsBuilt(m:ScreenMainMenu) : void
      {
         addStrings();
         menu = m;
         if(m.var_9668 != null && m.var_5281 != null && m.var_9668[STORE] != KEY_BUTTON)
         {
            m.var_9668[STORE] = KEY_BUTTON;
            m.var_5281[STORE] = KEY_BUTTON_DESC;
            m.rebuildButtons();
            return;
         }
         var store:UiClip = m.buttons[STORE];
         if(store != null)
         {
            store.var_15122 = onClick;
         }
      }

      private static function onClick(e:MouseEvent, id:uint) : void
      {
         if(menu != null)
         {
            ScreenBase.setFocus(menu);
         }
         open();
      }

      private static function onInput(m:ScreenMainMenu, input:int, device:class_223) : Boolean
      {
         if((input == 11 || input == 17 || input == 23) && m.method_688() == STORE && device != null)
         {
            class_112.method_3429();
            if(class_112.method_8187(device.mType,device.mControllerID) != null)
            {
               open();
            }
            return true;
         }
         return false;
      }

      public static function open() : void
      {
         if(screen == null || ScreenManager.allScreens.indexOf(screen) < 0)
         {
            screen = new ModsScreen(ScreenManager.owner);
            ScreenManager.registerScreen(screen);
            if(ScreenManager.var_14744 != null)
            {
               screen.registrationIndex = ScreenManager.var_14744.registrationIndex;
            }
         }
         screen.Display();
      }
   }
}
