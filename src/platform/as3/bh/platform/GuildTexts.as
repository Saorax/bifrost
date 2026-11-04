package bh.platform
{
   public class GuildTexts
   {
      private static var known:Boolean = false;
      private static var filter:Boolean = false;

      public function GuildTexts()
      {
         super();
      }

      public static function notice(filtered:String, written:String) : String
      {
         if(!known)
         {
            known = true;
            filter = ModSettings.flag("guildNoticeFilter",false);
         }
         if(filter || written == null)
         {
            return filtered;
         }
         return written;
      }
   }
}
