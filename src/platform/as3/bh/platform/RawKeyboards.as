package bh.platform
{
   public class RawKeyboards
   {
      private static var known:Boolean = false;
      private static var on:Boolean = true;

      public function RawKeyboards()
      {
         super();
      }

      public static function get early() : Boolean
      {
         if(!known)
         {
            known = true;
            on = ModSettings.flag("multikeyboardEarlyRead",true);
         }
         return on;
      }
   }
}
