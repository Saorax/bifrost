package bh.platform
{
   import flash.display.DisplayObject;
   import flash.display.DisplayObjectContainer;
   import flash.display.Shape;

   public final class HitboxTrail
   {
      public static const KEY:uint = 114;
      private static const TRAINING_MODE:uint = 32768;
      private static const TRAIL_MS:uint = 400;
      private static const ALPHA:Number = 0.7;
      private static const MAX_SHAPES:int = 96;

      private static var listening:Boolean = false;
      private static var trail:Array = [];
      private static var lastStep:uint = 0;
      public static var copies:uint = 0;

      public function HitboxTrail()
      {
      }

      public static function init() : void
      {
         Hooks.keyDown.add(onKey);
         Hooks.matchStarted.add(start);
         Hooks.matchEnded.add(function(state:uint):void
         {
            stop();
         });
      }

      public static function get on() : Boolean
      {
         return ModSettings.value("hitboxTrail") == true;
      }

      public static function set on(v:Boolean) : void
      {
         ModSettings.setValue("hitboxTrail",v);
         Platform.log("hitbox trail " + (v ? "on" : "off"));
         if(v)
         {
            start();
         }
         else
         {
            stop();
         }
      }

      private static function game() : Object
      {
         try
         {
            return ScreenManager.owner;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private static function inTraining(core:Object) : Boolean
      {
         return core != null && (uint(core.var_3595) & TRAINING_MODE) != 0;
      }

      private static function onKey(event:Object) : Boolean
      {
         if(event == null || !event.ctrlKey || event.shiftKey || event.altKey || uint(event.keyCode) != KEY)
         {
            return false;
         }
         if(!Platform.matchRunning || !inTraining(game()))
         {
            return false;
         }
         on = !on;
         return true;
      }

      private static function start() : void
      {
         if(!on || listening)
         {
            return;
         }
         clear();
         copies = 0;
         Hooks.frameRendering.add(onFrame);
         listening = true;
      }

      private static function stop() : void
      {
         if(listening)
         {
            Hooks.frameRendering.remove(onFrame);
            listening = false;
         }
         clear();
      }

      private static function clear() : void
      {
         for each(var e:Object in trail)
         {
            if(e.shape.parent != null)
            {
               e.shape.parent.removeChild(e.shape);
            }
         }
         trail = [];
         lastStep = 0;
      }

      private static function onFrame() : void
      {
         var core:Object = game();
         if(!Platform.matchRunning || !inTraining(core) || !core.var_5429)
         {
            if(trail.length != 0)
            {
               clear();
            }
            return;
         }
         try
         {
            update(core);
         }
         catch(e:Error)
         {
            Platform.log("hitbox trail: " + e.message);
            stop();
         }
      }

      private static function update(core:Object) : void
      {
         var now:uint = uint(core.var_13849);
         var span:uint = uint(ModSettings.value("hitboxTrailMs")) || TRAIL_MS;
         if(now < lastStep)
         {
            clear();
         }
         if(now != lastStep)
         {
            lastStep = now;
            var clips:Object = core.var_331;
            var used:int = Math.min(int(core.var_11526),int(clips.length));
            for(var i:int = 0; i < used; i++)
            {
               var clip:Object = clips[i];
               var parent:DisplayObjectContainer = clip.parent as DisplayObjectContainer;
               if(parent == null || clip.width == 0)
               {
                  continue;
               }
               var s:Shape = new Shape();
               s.graphics.copyFrom(clip.graphics);
               s.transform.matrix = clip.transform.matrix;
               parent.addChildAt(s,parent.getChildIndex(clip as DisplayObject));
               trail.push({"shape":s,"time":now});
               copies++;
            }
         }
         var keep:Array = [];
         var excess:int = trail.length - MAX_SHAPES;
         for each(var e:Object in trail)
         {
            var age:uint = now - uint(e.time);
            if(excess-- > 0 || age >= span)
            {
               if(e.shape.parent != null)
               {
                  e.shape.parent.removeChild(e.shape);
               }
               continue;
            }
            e.shape.alpha = age == 0 ? 0 : ALPHA * (1 - age / span);
            keep.push(e);
         }
         trail = keep;
      }

      public static function describe() : String
      {
         return (on ? "on" : "off") + ", " + trail.length + " shapes, " + copies + " copied";
      }
   }
}
