package bh.platform
{
   public final class Branding
   {
      public static const PROJECT:String = "Bifrost";

      public static const KEYS:Array = ["UI_PHASE_DESCRIPTION_CONNECTING_TO_BRAWLHALLA", "UI_PHASE_DESCRIPTION_SUCCESS_CONNECTING_TO_BRAWLHALLA",
         "Error_FAILED_TO_CONNECT_TO_USERSERVER_MESSAGE"];

      public static const NAMES:Array = ["Brawlhalla", "BRAWLHALLA", "ブロウルハラ"];

      public function Branding()
      {
      }

      public static function init() : void
      {
         Hooks.stringsLoaded.add(function(language:Localization):void
         {
            for each(var key:String in KEYS)
            {
               var text:* = language.var_15061.method_4935(key);
               if(text != null)
               {
                  var t:String = String(text);
                  for each(var name:String in NAMES)
                  {
                     t = t.split(name).join(name == "BRAWLHALLA" ? PROJECT.toUpperCase() : PROJECT);
                  }
                  language.var_15061.method_65(key,t);
               }
            }
         });
      }
   }
}
