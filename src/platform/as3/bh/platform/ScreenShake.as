package bh.platform
{
   public final class ScreenShake
   {
      public static const LEVELS:Array = [100,50,25,0];

      private static var percent:int = 100;

      public static var steps:int = 0;
      public static var rawSum:Number = 0;
      public static var shownSum:Number = 0;

      public static function init() : void
      {
         var v:* = ModSettings.value("screenShake");
         percent = v is Number && LEVELS.indexOf(int(v)) >= 0 ? int(v) : 100;
         Hooks.cameraPlaced.add(placed);
      }

      public static function get strength() : int
      {
         return percent;
      }

      public static function set strength(p:int) : void
      {
         percent = LEVELS.indexOf(p) >= 0 ? p : 100;
         ModSettings.setValue("screenShake",percent);
      }

      public static function label(p:int) : String
      {
         return p == 0 ? "Off" : p + "%";
      }

      private static function placed(camera:class_52) : void
      {
         var dx:Number = camera.var_5344.x;
         var dy:Number = camera.var_5344.y;
         if(dx == 0 && dy == 0)
         {
            return;
         }
         var length:Number = Math.sqrt(dx * dx + dy * dy);
         steps++;
         rawSum += length;
         shownSum += length * percent / 100;
         if(percent >= 100)
         {
            return;
         }
         var cut:Number = (100 - percent) / 100;
         var game:GameCore = camera.owner;
         game.var_9075.x -= dx * cut;
         game.var_9075.y -= dy * cut;
         if(game.levelLayer3D != null)
         {
            game.levelLayer3D.x = game.var_9075.x;
            game.levelLayer3D.y = game.var_9075.y;
         }
      }
   }
}
