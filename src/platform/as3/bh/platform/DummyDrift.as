package bh.platform
{
   import bh.platform.net.RemoteInput;
   import flash.display.Sprite;
   import flash.display.Stage;
   import flash.utils.getTimer;

   public final class DummyDrift
   {
      public static const KEY:uint = 115;
      private static const TRAINING_MODE:uint = 32768;
      private static const DRIFT_MS:uint = 600;
      public static const NAMES:Array = ["Off","Away","Toward","Up","Down","Up+Away","Down+Away","Random"];
      private static const UP:uint = 1;
      private static const DOWN:uint = 2;
      private static const LEFT:uint = 4;
      private static const RIGHT:uint = 8;

      private static var stage:Stage;
      private static var holding:Boolean = false;
      private static var stunEnd:int = -1;
      private static var bits:uint = 0;
      private static var lastY:Number = NaN;
      private static var lastT:uint = 0;
      private static var still:int = 0;
      public static var lastRelease:String = "";
      private static var note:Sprite = null;
      private static var noteUntil:int = 0;
      public static var held:uint = 0;
      public static var lastBits:uint = 0;

      public function DummyDrift()
      {
      }

      public static function init() : void
      {
         Hooks.gameCreated.add(function(main:Object):void
         {
            stage = main.stage;
         });
         Hooks.keyDown.add(onKey);
         Hooks.inputSampling.add(onSampling);
         Hooks.frameStarting.add(fadeNote);
         Hooks.matchStarted.add(function():void
         {
            holding = false;
            held = 0;
         });
      }

      public static function get mode() : uint
      {
         var v:uint = uint(ModSettings.value("dummyDrift"));
         return v < NAMES.length ? v : 0;
      }

      public static function set mode(v:uint) : void
      {
         ModSettings.setValue("dummyDrift",v % NAMES.length);
         Platform.log("dummy drift " + NAMES[mode]);
         show("Dummy DI and drift: " + NAMES[mode] + "  (Ctrl+F4)");
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
         if(event == null || !event.ctrlKey || event.shiftKey || event.altKey || uint(event.keyCode) != KEY)
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

      private static function bitsFor(m:uint, attackerX:Number, x:Number) : uint
      {
         if(m == 7)
         {
            m = 1 + uint(Math.random() * 6);
         }
         var away:uint = attackerX <= x ? RIGHT : LEFT;
         var toward:uint = away == RIGHT ? LEFT : RIGHT;
         switch(m)
         {
            case 1:
               return away;
            case 2:
               return toward;
            case 3:
               return UP;
            case 4:
               return DOWN;
            case 5:
               return UP | away;
            case 6:
               return DOWN | away;
         }
         return 0;
      }

      private static function onSampling(state:Object, time:uint) : Boolean
      {
         var m:uint = mode;
         if(m == 0 && !holding)
         {
            return false;
         }
         var core:Object = state.owner;
         if(core == null || (uint(core.var_3595) & TRAINING_MODE) == 0 || OnlineTraining.active)
         {
            return false;
         }
         var players:Object = core.var_7050;
         if(int(players.length) < 2 || players[1].var_10012 !== state)
         {
            return false;
         }
         var dummy:Object = players[1];
         if(m != 0 && dummy.method_503())
         {
            if(!holding)
            {
               holding = true;
               bits = lastBits = bitsFor(m,Number(players[0].method_338()),Number(dummy.method_338()));
               held++;
            }
            stunEnd = -1;
         }
         else if(!holding)
         {
            return false;
         }
         else
         {
            if(stunEnd < 0)
            {
               stunEnd = int(time);
               lastY = NaN;
               still = 0;
            }
            var y:Number = Number(dummy.method_4344());
            if(time != lastT)
            {
               still = y == lastY ? still + 1 : 0;
               lastY = y;
               lastT = time;
            }
            var back:Boolean = DummyRecovery.wantsBack(dummy);
            if(m == 0 || still >= 2 || back || time >= uint(stunEnd) + DRIFT_MS || time < uint(stunEnd))
            {
               lastRelease = (still >= 2 ? "landed" : (back ? "recovering" : "time")) + " +" + (int(time) - stunEnd) + " ms";
               holding = false;
               bits = 0;
            }
         }
         if(RemoteInput.bitsAt(state,time) != bits)
         {
            RemoteInput.feed(state,time,bits);
         }
         return true;
      }

      public static function show(text:String, ms:int = 1800) : void
      {
         if(stage == null)
         {
            return;
         }
         if(note != null && note.parent != null)
         {
            note.parent.removeChild(note);
         }
         note = new Sprite();
         note.mouseEnabled = note.mouseChildren = false;
         var w:Number = stage.stageWidth;
         var t:Object = UiKit.text(note,text,w / 2,stage.stageHeight * 0.22,Math.max(18,Math.round(w / 70)),UiKit.WHITE,UiKit.BOLD,0,true);
         note.graphics.beginFill(0,0.55);
         note.graphics.drawRect(t.x - 14,t.y - 6,t.width + 28,t.height + 12);
         note.graphics.endFill();
         stage.addChild(note);
         noteUntil = getTimer() + ms;
      }

      private static function fadeNote() : void
      {
         if(note != null && getTimer() > noteUntil)
         {
            if(note.parent != null)
            {
               note.parent.removeChild(note);
            }
            note = null;
         }
      }
   }
}
