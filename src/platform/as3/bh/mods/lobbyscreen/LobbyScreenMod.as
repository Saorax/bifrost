package bh.mods.lobbyscreen
{
   import bh.platform.GameMenus;
   import bh.platform.Hooks;
   import bh.platform.SettingsWindow;

   public final class LobbyScreenMod
   {
      private static var screen:LobbySettingsScreen;
      private static var training:TrainingSettingsScreen;

      public function LobbyScreenMod()
      {
      }

      public static function register() : void
      {
         Hooks.settingsScreenShown.add(onShown);
         GameMenus.reshow = onShown;
      }

      private static function onShown(settings:Object) : void
      {
         var page:String = settings === ScreenManager.var_14303 ? GameMenus.LOBBY : (settings === ScreenManager.var_14532 ? GameMenus.TRAINING : null);
         if(page != null && GameMenus.own(page))
         {
            GameMenus.offer(settings,page);
            return;
         }
         GameMenus.withdraw(settings);
         if(settings === ScreenManager.var_14303 && !LobbySettingsScreen.closing)
         {
            if(screen == null || ScreenManager.allScreens.indexOf(screen) < 0)
            {
               screen = new LobbySettingsScreen(ScreenManager.owner);
               place(screen);
            }
            show(screen,settings);
         }
         else if(settings === ScreenManager.var_14532 && !TrainingSettingsScreen.closing)
         {
            if(training == null || ScreenManager.allScreens.indexOf(training) < 0)
            {
               training = new TrainingSettingsScreen(ScreenManager.owner);
               place(training);
            }
            show(training,settings);
         }
      }

      private static function place(window:SettingsWindow) : void
      {
         ScreenManager.registerScreen(window);
         if(ScreenManager.var_14744 != null)
         {
            window.registrationIndex = ScreenManager.var_14744.registrationIndex;
         }
      }

      private static function show(window:SettingsWindow, settings:Object) : void
      {
         window.attach(settings);
         if(!window.isActive)
         {
            window.Display();
         }
      }
   }
}
