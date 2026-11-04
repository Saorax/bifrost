package bh.platform
{
   import flash.display.Sprite;
   import flash.display.Stage;
   import flash.text.TextField;
   import flash.utils.getTimer;

   public final class TrainingKeys
   {
      public static const KEY:uint = 120;
      private static const TRAINING_MODE:uint = 32768;
      private static const REFRESH_MS:int = 250;
      private static const HINTS:uint = 3;
      private static const HINT_AFTER:uint = 1500;
      private static const HINT_MS:int = 5000;

      private static var stage:Stage;
      private static var root:Sprite = null;
      private static var keys:TextField;
      private static var what:TextField;
      private static var shown:String = "";
      private static var nextRefresh:int = 0;
      private static var hinted:Boolean = false;

      public function TrainingKeys()
      {
      }

      public static function init() : void
      {
         Hooks.gameCreated.add(function(main:Object):void
         {
            stage = main.stage;
         });
         Hooks.keyDown.add(onKey);
         Hooks.frameStarting.add(onFrame);
         Hooks.matchStarted.add(function():void
         {
            hinted = false;
         });
         Hooks.matchEnded.add(function(state:uint):void
         {
            hide();
         });
      }

      public static function get on() : Boolean
      {
         return ModSettings.value("trainingKeys") == true;
      }

      public static function set on(v:Boolean) : void
      {
         ModSettings.setValue("trainingKeys",v);
         if(!v)
         {
            hide();
         }
         nextRefresh = 0;
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
         if(event == null || event.ctrlKey || event.shiftKey || event.altKey || uint(event.keyCode) != KEY)
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

      private static function onFrame() : void
      {
         if(stage == null || !Platform.matchRunning)
         {
            return;
         }
         var now:int = getTimer();
         if(now < nextRefresh)
         {
            return;
         }
         nextRefresh = now + REFRESH_MS;
         var core:Object = game();
         if(!inTraining(core) || BigWindow.anyOpen() || LoadingBackground.showing)
         {
            hide();
            return;
         }
         if(!on)
         {
            if(uint(core.var_13849) >= HINT_AFTER)
            {
               hint();
            }
            return;
         }
         draw(core);
      }

      private static function hint() : void
      {
         if(hinted)
         {
            return;
         }
         hinted = true;
         var count:uint = uint(ModSettings.value("trainingKeysHints"));
         if(count >= HINTS)
         {
            return;
         }
         ModSettings.setValue("trainingKeysHints",count + 1);
         DummyDrift.show("F9: Bifrost Training keys",HINT_MS);
      }

      public static function rows(core:Object) : Array
      {
         var saved:uint = TrainingState.savedAt;
         var steps:uint = TrainingDummy.length;
         return [
            ["F1 / F2","Save / load state",(saved == 0 ? "nothing saved" : "saved at " + TrainingState.clock(saved)) +
               " (slot " + (TrainingState.slot + 1) + ")"],
            ["Shift+F1","Record the dummy",(TrainingDummy.isRecording ? "RECORDING" : steps > 0 ? (steps * 16 / 1000).toFixed(1) + " s recorded" : "nothing recorded") +
               " (slot " + (TrainingDummy.slot + 1) + ")"],
            ["Shift+F2","Dummy replay, loop",TrainingDummy.playing && !TrainingDummy.once ? "on" : "off"],
            ["Ctrl+F2","Dummy replay, once",TrainingDummy.playing && TrainingDummy.once ? "playing" : ""],
            ["Ctrl+F1","Frame data",FrameData.on ? "on" : "off"],
            ["Ctrl+F3","Hitbox trail",HitboxTrail.on ? "on" : "off"],
            ["Ctrl+F4","Dummy drift after hits",String(DummyDrift.NAMES[DummyDrift.mode]).toLowerCase()],
            ["Shift+F4","Dummy recovery",String(DummyRecovery.NAMES[DummyRecovery.mode]).toLowerCase()],
            ["F5-F8","Game: frame step, power viewer",""],
            ["F11","Frame pacing",FramePacing.on ? "on" : "off"],
            ["F12","Stats overlay",""],
            ["Ctrl+F12","Screenshot",""],
            ["Shift+F12","Hide the HUD",Screenshot.hud ? "shown" : "hidden"],
            ["Ctrl+Shift+F12","Free camera (mouse)",PhotoCamera.on ? "on" : "off"],
            ["F9","Hide this list",""]];
      }

      private static function draw(core:Object) : void
      {
         var r:Array = rows(core);
         var left:Array = [];
         var right:Array = [];
         for each(var row:Array in r)
         {
            left.push(row[0]);
            right.push(row[1] + (row[2] != "" ? ":  " + row[2] : ""));
         }
         var s:String = left.join("\n") + "|" + right.join("\n");
         if(root == null)
         {
            root = new Sprite();
            root.mouseEnabled = root.mouseChildren = false;
            UiKit.text(root,"TRAINING KEYS",10,6,13,UiKit.TEAL,UiKit.BOLD);
            keys = UiKit.text(root,"",10,26,13,UiKit.LIGHT,UiKit.BOLD);
            what = UiKit.text(root,"",96,26,13,UiKit.WHITE,UiKit.BOLD);
         }
         if(root.parent == null)
         {
            stage.addChild(root);
            shown = "";
         }
         if(s == shown)
         {
            return;
         }
         shown = s;
         keys.text = left.join("\n");
         what.text = right.join("\n");
         what.x = keys.x + keys.width + 14;
         root.graphics.clear();
         root.graphics.beginFill(0x000000,0.55);
         root.graphics.drawRoundRect(0,0,what.x + what.width + 10,what.y + what.height + 8,10,10);
         root.graphics.endFill();
         root.x = 16;
         root.y = Math.round(stage.stageHeight * 0.16);
      }

      private static function hide() : void
      {
         if(root != null && root.parent != null)
         {
            root.parent.removeChild(root);
         }
         shown = "";
      }
   }
}
