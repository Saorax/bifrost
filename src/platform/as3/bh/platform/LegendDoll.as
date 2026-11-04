package bh.platform
{
   import flash.display.MovieClip;

   public final class LegendDoll
   {
      public var doll:PaperDoll;
      public var anim:String = null;
      private var posed:Boolean = false;

      public function LegendDoll()
      {
      }

      public static function build(holder:MovieClip, costume:CostumeType, scheme:class_76, built:String, names:Array,
         item:ItemType, x:Number, y:Number, scale:Number, what:String) : LegendDoll
      {
         var out:LegendDoll = new LegendDoll();
         try
         {
            out.doll = new PaperDoll(ScreenManager.owner,holder,null,x,y,null,scale);
            PaperDoll.method_5580(costume,scheme,costume.var_7289,costume.var_15258,out.doll,built,null,null,item);
            for each(var nm:String in names)
            {
               if(nm != null && out.doll.var_11807 != null && out.doll.var_11807.var_142.var_2643.method_3355(nm) != null)
               {
                  out.anim = nm;
                  break;
               }
            }
            return out;
         }
         catch(e:Error)
         {
            ErrorLog.write(what + ": the legend's doll failed: " + e + " " + e.getStackTrace());
            out.clear();
         }
         return null;
      }

      public function play(fallback:String) : void
      {
         if(doll != null)
         {
            doll.method_39(anim != null ? anim : fallback,true,true);
            doll.method_4082();
         }
      }

      public function pose(frame:int) : void
      {
         if(doll == null || anim == null)
         {
            return;
         }
         try
         {
            var first:Boolean = !posed;
            if(first)
            {
               doll.method_1467(anim,false,true);
               posed = true;
            }
            var last:int = int(doll.var_11807.var_142.var_7804.var_14424);
            doll.method_1301(anim,uint(Math.max(0,Math.min(frame,last))),1,false);
            if(first)
            {
               doll.method_4082();
            }
         }
         catch(e:Error)
         {
         }
      }

      public function clear() : void
      {
         if(doll != null)
         {
            try
            {
               doll.method_5548();
            }
            catch(e:Error)
            {
            }
            doll = null;
         }
      }
   }
}
