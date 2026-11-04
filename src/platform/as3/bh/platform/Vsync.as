package bh.platform
{
   public final class Vsync
   {
      private static var stage:Object = null;

      public function Vsync()
      {
      }

      public static function init() : void
      {
         Hooks.gameCreated.add(function(main:Object):void
         {
            try
            {
               stage = main.stage;
            }
            catch(e:Error)
            {
            }
            apply();
         });
      }

      public static function get on() : Boolean
      {
         return EngineDisplay.available ? EngineDisplay.vsync : ModSettings.flag("vsync",true);
      }

      public static function set on(value:Boolean) : void
      {
         if(EngineDisplay.available)
         {
            EngineDisplay.setVsync(value);
            return;
         }
         ModSettings.setFlag("vsync",value);
         apply();
      }

      public static function get available() : Boolean
      {
         if(EngineDisplay.available)
         {
            return true;
         }
         try
         {
            return stage != null && stage.hasOwnProperty("vsyncEnabled");
         }
         catch(e:Error)
         {
         }
         return false;
      }

      private static function apply() : void
      {
         if(EngineDisplay.available || !available)
         {
            return;
         }
         try
         {
            if(Boolean(stage["vsyncEnabled"]) != on)
            {
               stage["vsyncEnabled"] = on;
               Platform.log("vsync " + (on ? "on" : "off"));
            }
         }
         catch(e:Error)
         {
            Platform.log("vsync not applied: " + e.message);
         }
      }
   }
}
