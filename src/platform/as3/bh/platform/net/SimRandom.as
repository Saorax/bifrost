package bh.platform.net
{
   public final class SimRandom
   {
      private static const KEEP:uint = 64000;

      private static var sim:Random = null;
      private static var outside:Random = null;
      private static var swapped:Boolean = false;
      private static var brain:Random = null;
      private static var inBrain:Boolean = false;
      public static var brainCalls:uint = 0;
      private static var states:Object = {};
      public static var savedCount:uint = 0;
      public static var restoredCount:uint = 0;
      public static var missing:uint = 0;

      public function SimRandom()
      {
      }

      public static function start(seed:uint) : void
      {
         stop();
         sim = new Random();
         sim.method_4224(uint(seed ^ 0x5EED5EED));
         brain = new Random();
         brain.method_4224(uint(seed ^ 0xB4A1B4A1));
         states = {};
         savedCount = restoredCount = missing = brainCalls = 0;
      }

      public static function stop() : void
      {
         frameEnd();
         sim = null;
         brain = null;
         states = {};
      }

      public static function get active() : Boolean
      {
         return sim != null;
      }

      public static function frameStart() : void
      {
         if(sim == null || swapped)
         {
            return;
         }
         outside = class_50.var_5617;
         class_50.var_5617 = sim;
         swapped = true;
      }

      public static function frameEnd() : void
      {
         inBrain = false;
         if(!swapped)
         {
            return;
         }
         class_50.var_5617 = outside;
         outside = null;
         swapped = false;
      }

      public static function brainIn() : void
      {
         if(!swapped || inBrain || brain == null)
         {
            return;
         }
         class_50.var_5617 = brain;
         inBrain = true;
         brainCalls++;
      }

      public static function brainOut() : void
      {
         if(!inBrain)
         {
            return;
         }
         class_50.var_5617 = sim;
         inBrain = false;
      }

      public static function saved(time:uint) : void
      {
         if(sim == null)
         {
            return;
         }
         var v:Vector.<uint> = states[time];
         if(v == null)
         {
            v = new Vector.<uint>(17,true);
            states[time] = v;
         }
         v[0] = sim.var_12730;
         for(var i:int = 0; i < 16; i++)
         {
            v[i + 1] = sim.var_12512[i];
         }
         savedCount++;
         if(time > KEEP)
         {
            delete states[time - KEEP];
         }
      }

      public static function restored(time:uint) : void
      {
         if(sim == null)
         {
            return;
         }
         var v:Vector.<uint> = states[time];
         if(v == null)
         {
            missing++;
            return;
         }
         sim.var_12730 = v[0];
         for(var i:int = 0; i < 16; i++)
         {
            sim.var_12512[i] = v[i + 1];
         }
         restoredCount++;
      }

      public static function summary() : String
      {
         return "match generator " + savedCount + " saved, " + restoredCount + " restored" + (missing > 0 ? ", " + missing + " MISSING" : "") + ", " + brainCalls + " bot thinks on their own";
      }
   }
}
