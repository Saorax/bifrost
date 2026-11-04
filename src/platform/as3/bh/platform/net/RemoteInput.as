package bh.platform.net
{
   public final class RemoteInput
   {
      public function RemoteInput()
      {
      }

      public static function feed(state:Object, time:uint, bits:uint) : void
      {
         var history:Array = state.var_11813;
         var last:Object = history.length > 0 ? history[history.length - 1] : null;
         if(last != null && last.var_5941 == time)
         {
            last.var_1212 = bits;
         }
         else if(last != null && last.var_5941 > time)
         {
            state.method_6960(new class_224(time,bits));
         }
         else
         {
            history.push(new class_224(time,bits));
         }
      }

      public static function bitsAt(state:Object, time:uint) : uint
      {
         var history:Array = state.var_11813;
         for(var i:int = history.length - 1; i >= 0; i--)
         {
            if(history[i].var_5941 <= time)
            {
               return history[i].var_1212;
            }
         }
         return 0;
      }
   }
}
