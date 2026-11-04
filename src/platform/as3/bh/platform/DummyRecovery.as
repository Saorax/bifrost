package bh.platform
{
   import bh.platform.net.RemoteInput;

   public final class DummyRecovery
   {
      public static const KEY:uint = 115;
      private static const TRAINING_MODE:uint = 32768;
      private static const RECOVERY_STATE:String = "HardRecovery";
      private static const CHOSEN:uint = 8;
      private static const JUMPS:uint = 8;
      public static const LATE_DROP:Number = 150;
      public static const NAMES:Array = ["Game","Full","Late","None","Random"];
      private static const FULL:uint = 1;
      private static const LATE:uint = 2;
      private static const NONE:uint = 3;
      private static const RANDOM:uint = 4;

      private static var brain:Object = null;
      private static var level:uint = 0;
      private static var kinds:uint = 0;
      private static var episode:uint = 0;
      private static var waiting:Boolean = false;
      private static var startedAt:uint = 0;
      private static var knockedOut:Boolean = false;
      public static var episodes:uint = 0;
      public static var lastEnd:String = "";

      public function DummyRecovery()
      {
      }

      public static function init() : void
      {
         Hooks.keyDown.add(onKey);
         Hooks.simulationFrame.add(onFrame);
         Hooks.inputSampling.add(onSampling);
         Hooks.matchStarted.add(function():void
         {
            brain = null;
            waiting = false;
            episodes = 0;
         });
      }

      public static function get mode() : uint
      {
         var v:uint = uint(ModSettings.value("dummyRecovery"));
         return v < NAMES.length ? v : 0;
      }

      public static function set mode(v:uint) : void
      {
         ModSettings.setValue("dummyRecovery",v % NAMES.length);
         Platform.log("dummy recovery " + NAMES[mode]);
         DummyDrift.show("Dummy recovery: " + NAMES[mode] + "  (Shift+F4)");
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

      private static function onKey(event:Object) : Boolean
      {
         if(event == null || !event.shiftKey || event.ctrlKey || event.altKey || uint(event.keyCode) != KEY)
         {
            return false;
         }
         var core:Object = game();
         if(!Platform.matchRunning || core == null || (uint(core.var_3595) & TRAINING_MODE) == 0 || OnlineTraining.active)
         {
            return false;
         }
         mode = mode + 1;
         return true;
      }

      private static function dummyBrain(core:Object) : Object
      {
         if(core == null || (uint(core.var_3595) & TRAINING_MODE) == 0 || OnlineTraining.active)
         {
            return null;
         }
         var players:Object = core.var_7050;
         if(int(players.length) < 2 || players[1] == null)
         {
            return null;
         }
         var b:Object = players[1].var_8233;
         return b != null && b.var_15246 ? b : null;
      }

      private static function recovering(b:Object) : Boolean
      {
         return b != null && b.var_13063 != null && b.var_13063.var_13375 == RECOVERY_STATE;
      }

      public static function wantsBack(dummy:Object) : Boolean
      {
         return dummy != null && recovering(dummy.var_8233);
      }

      private static function onFrame(core:Object) : void
      {
         if(brain == null && mode == 0)
         {
            return;
         }
         var b:Object = dummyBrain(core);
         if(brain != null && (b != brain || !recovering(b)))
         {
            end(core);
         }
         if(brain == null && b != null && mode != 0 && recovering(b) && core.var_7050[1].method_458())
         {
            start(core,b);
         }
         if(brain != null && uint(core.var_7050[1].var_661) == 3)
         {
            knockedOut = true;
         }
         if(brain != null && waiting && episode == LATE)
         {
            var target:Object = brain.var_13063.var_12777;
            var dummy:Object = core.var_7050[1];
            if(target != null && Number(dummy.method_4344()) > Number(target.startY) + LATE_DROP)
            {
               waiting = false;
               setUp();
            }
         }
      }

      private static function start(core:Object, b:Object) : void
      {
         brain = b;
         level = uint(b.var_9930);
         kinds = uint(b.var_13033);
         episode = mode == RANDOM ? FULL + uint(Math.random() * 3) : mode;
         waiting = episode != FULL;
         startedAt = uint(core.var_13849);
         knockedOut = false;
         episodes++;
         if(episode == FULL)
         {
            setUp();
         }
      }

      private static function setUp() : void
      {
         brain.var_9930 = CHOSEN;
         brain.var_13033 = kinds | JUMPS;
      }

      private static function end(core:Object) : void
      {
         if(uint(brain.var_9930) == CHOSEN)
         {
            brain.var_9930 = level;
            brain.var_13033 = kinds;
         }
         var dummy:Object = core != null && core.var_7050.length > 1 ? core.var_7050[1] : null;
         lastEnd = NAMES[episode] + (knockedOut ? " KO, " : " ") + (dummy == null ? "gone" : (dummy.method_458() ? "in the air" :
            "landed") + " state " + dummy.var_661) + " +" + (uint(core.var_13849) - startedAt) + " ms";
         brain = null;
         waiting = false;
      }

      public static function loaded() : void
      {
         var core:Object = game();
         if(brain != null && core != null)
         {
            end(core);
            lastEnd += " (load)";
         }
      }

      private static function onSampling(state:Object, time:uint) : Boolean
      {
         if(brain == null || !waiting)
         {
            return false;
         }
         var core:Object = state.owner;
         if(core == null || int(core.var_7050.length) < 2 || core.var_7050[1].var_10012 !== state)
         {
            return false;
         }
         if(RemoteInput.bitsAt(state,time) != 0)
         {
            RemoteInput.feed(state,time,0);
         }
         return true;
      }

      public static function describe() : String
      {
         var core:Object = game();
         if(core == null || core.var_7050.length < 2)
         {
            return "no dummy";
         }
         var dummy:Object = core.var_7050[1];
         var b:Object = dummy.var_8233;
         var st:Object = b != null ? b.var_13063 : null;
         var s:String = Number(dummy.method_338()).toFixed(0) + "," + Number(dummy.method_4344()).toFixed(0) + " " +
            (dummy.method_458() ? "air" : "ground") + " s" + dummy.var_661 + (dummy.method_503() ? " stun" : "");
         if(st != null)
         {
            s += " " + st.var_13375;
            if(st.var_13375 == RECOVERY_STATE)
            {
               s += " phase " + st.var_752 + (st.var_12777 != null ? " ledge " + Number(st.var_12777.startX).toFixed(0) + "," +
                  Number(st.var_12777.startY).toFixed(0) + ".." + Number(st.var_12777.var_165).toFixed(0) : "");
            }
         }
         if(b != null)
         {
            s += " level " + b.var_9930 + " kinds " + b.var_13033 + " think " + b.var_5696 + " react " + b.var_8922 + "@" +
               b.var_3371 + " held " + b.var_433 + " wait " + b.var_5750 + " flag " + dummy.var_5351;
         }
         return s + (brain != null ? " [" + NAMES[episode] + (waiting ? " waiting" : "") + "]" : "");
      }
   }
}
