package bh.platform
{
   import bh.platform.net.RemoteInput;
   import flash.display.Sprite;
   import flash.display.Stage;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.utils.getTimer;

   public final class TrainingDummy
   {
      public static const RECORD_KEY:uint = 112;
      public static const PLAY_KEY:uint = 113;
      private static const TRAINING_MODE:uint = 32768;
      private static const STEP:uint = 16;
      public static const MAX_STEPS:uint = 1875;

      private static var stage:Stage;
      private static var recording:Boolean = false;
      private static var recordWanted:Boolean = false;
      private static var steps:Array = [];
      private static var taken:Array = null;
      private static var takenAt:Array = null;
      private static var startAt:Object = null;
      private static var skipPlace:Boolean = false;
      private static var startFromDummy:Boolean = false;
      private static var lastTime:uint = 0;
      private static var held:uint = 0;
      public static var playing:Boolean = false;
      public static var once:Boolean = false;
      private static var playFrom:int = -1;
      public static var passes:uint = 0;
      public static var lastPassHash:String = "";
      private static var note:Sprite = null;
      private static var noteUntil:int = 0;
      private static const LEFT:uint = 4;
      private static const RIGHT:uint = 8;
      private static var recordedSide:int = 0;
      private static var flipped:Boolean = false;
      public static var mirroredPasses:uint = 0;
      public static const SLOTS:int = 5;
      private static var slotAt:int = -1;

      public function TrainingDummy()
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
         Hooks.inputSampled.add(onSampled);
         Hooks.frameStarting.add(fadeNote);
         Hooks.matchStarted.add(stopAll);
         Hooks.matchEnded.add(function(state:uint):void
         {
            stopAll();
         });
      }

      public static function get length() : uint
      {
         readSlotOnce();
         return steps.length;
      }

      public static function get slot() : int
      {
         readSlotOnce();
         return slotAt;
      }

      private static function readSlotOnce() : void
      {
         if(slotAt < 0)
         {
            slotAt = Math.max(0,Math.min(SLOTS - 1,int(ModSettings.value("dummySlot"))));
            readSlot();
         }
      }

      public static function set slot(i:int) : void
      {
         readSlotOnce();
         if(recording || recordWanted)
         {
            endRecord();
         }
         playing = once = false;
         slotAt = (i % SLOTS + SLOTS) % SLOTS;
         ModSettings.setValue("dummySlot",slotAt);
         readSlot();
         show("Recording slot " + (slotAt + 1) + ":  " + describeSlot());
      }

      public static function describeSlot() : String
      {
         return length > 0 ? (steps.length * STEP / 1000).toFixed(1) + " s" : "empty";
      }

      public static function slotSummary(i:int) : String
      {
         readSlotOnce();
         if(i == slotAt)
         {
            return describeSlot();
         }
         try
         {
            var f:File = slotFile(i);
            if(f.exists)
            {
               var s:FileStream = new FileStream();
               s.open(f,FileMode.READ);
               var n:int = int(parseRecording(s.readUTFBytes(s.bytesAvailable)).steps.length);
               s.close();
               if(n > 0)
               {
                  return (n * STEP / 1000).toFixed(1) + " s";
               }
            }
         }
         catch(e:Error)
         {
         }
         return "empty";
      }

      private static function slotFile(i:int) : File
      {
         return Platform.dataFile("training/dummy-" + (i + 1) + ".xml");
      }

      private static function readSlot() : void
      {
         steps = [];
         recordedSide = 0;
         startAt = null;
         startFromDummy = false;
         try
         {
            var f:File = slotFile(slotAt);
            if(!f.exists)
            {
               return;
            }
            var s:FileStream = new FileStream();
            s.open(f,FileMode.READ);
            var got:Object = parseRecording(s.readUTFBytes(s.bytesAvailable));
            s.close();
            steps = got.steps;
            recordedSide = got.side;
            startAt = got.at;
         }
         catch(e:Error)
         {
            steps = [];
            Platform.log("training dummy: slot " + (slotAt + 1) + ": " + e.message);
         }
      }

      private static function writeSlot() : void
      {
         try
         {
            var f:File = slotFile(slotAt);
            f.parent.createDirectory();
            var s:FileStream = new FileStream();
            s.open(f,FileMode.WRITE);
            s.writeUTFBytes(formatRecording(steps,recordedSide,startAt));
            s.close();
         }
         catch(e:Error)
         {
            Platform.log("training dummy: slot " + (slotAt + 1) + " not written: " + e.message);
         }
      }

      public static function formatRecording(list:Array, side:int, at:Object = null) : String
      {
         var pairs:Array = [];
         var prev:Number = -1;
         for(var i:int = 0; i < list.length; i++)
         {
            if(Number(list[i]) != prev)
            {
               prev = Number(list[i]);
               pairs.push(String(i * STEP) + "," + uint(list[i]));
            }
         }
         return "<dummyRecording version=\"1\" steps=\"" + list.length + "\" side=\"" + side + "\"" +
            (at != null ? " x=\"" + Number(at.x) + "\" y=\"" + Number(at.y) + "\"" : "") + ">\n<botRecording>" +
            pairs.join(",") + "</botRecording>\n</dummyRecording>\n";
      }

      public static function parseRecording(text:String) : Object
      {
         var out:Array = [];
         var body:Array = /<botRecording>([^<]*)<\/botRecording>/.exec(text);
         var total:Array = /\bsteps="(\d+)"/.exec(text);
         var sideMatch:Array = /\bside="(-?\d+)"/.exec(text);
         var xMatch:Array = /\bx="(-?[\d.]+)"/.exec(text);
         var yMatch:Array = /\by="(-?[\d.]+)"/.exec(text);
         if(body != null && String(body[1]) != "")
         {
            var parts:Array = String(body[1]).split(",");
            var bits:uint = 0;
            for(var i:int = 0; i + 1 < parts.length; i += 2)
            {
               var at:int = Math.min(MAX_STEPS,int(int(parts[i]) / STEP));
               while(out.length < at)
               {
                  out.push(bits);
               }
               bits = uint(parts[i + 1]);
            }
            var n:int = total != null ? Math.min(MAX_STEPS,int(total[1])) : out.length + 1;
            while(out.length < n)
            {
               out.push(bits);
            }
         }
         return {"steps":out,"side":sideMatch != null ? int(sideMatch[1]) : 0,
            "at":xMatch != null && yMatch != null ? {"x":Number(xMatch[1]),"y":Number(yMatch[1])} : null};
      }

      public static function get isRecording() : Boolean
      {
         return recording || recordWanted;
      }

      public static function toggleRecord() : void
      {
         if(recording || recordWanted)
         {
            endRecord();
            return;
         }
         playing = false;
         recordWanted = true;
         show("Recording the dummy  (Shift+F1 to stop)");
      }

      public static function playOnce() : void
      {
         readSlotOnce();
         if(recording || recordWanted)
         {
            endRecord();
         }
         if(steps.length == 0)
         {
            show("Nothing recorded  (Shift+F1 to record)");
            return;
         }
         playing = once = true;
         playFrom = -1;
         if(startFromDummy)
         {
            startAt = null;
            startFromDummy = false;
         }
         passes = 0;
         show("Dummy replay  (once, " + (steps.length * STEP / 1000).toFixed(1) + " s)");
      }

      public static function togglePlay() : void
      {
         readSlotOnce();
         if(recording || recordWanted)
         {
            endRecord();
         }
         if(playing && once)
         {
            once = false;
            show("Dummy replay on  (" + (steps.length * STEP / 1000).toFixed(1) + " s loop, Shift+F2 to stop)");
            return;
         }
         if(playing)
         {
            playing = false;
            show("Dummy replay off");
            return;
         }
         if(steps.length == 0)
         {
            show("Nothing recorded  (Shift+F1 to record)");
            return;
         }
         playing = true;
         once = false;
         playFrom = -1;
         if(startFromDummy)
         {
            startAt = null;
            startFromDummy = false;
         }
         passes = 0;
         show("Dummy replay on  (" + (steps.length * STEP / 1000).toFixed(1) + " s loop, Shift+F2 to stop)");
      }

      public static function loaded(time:uint) : void
      {
         if(playing)
         {
            playFrom = int(time);
            passes = 0;
            skipPlace = true;
            try
            {
               var core:Object = game();
               var state:Object = core.var_7050[1].var_10012;
               flipped = mirror && recordedSide != 0 && side(core) == -recordedSide;
               if(flipped && uint(core.var_5692) > 0)
               {
                  mirroredPasses++;
               }
               for(var t:uint = time; t < time + uint(core.var_5692); t += STEP)
               {
                  RemoteInput.feed(state,t,mirrored(steps[((t - time) / STEP) % steps.length]));
               }
            }
            catch(e:Error)
            {
            }
         }
         if(recording)
         {
            endRecord();
         }
      }

      private static function stopAll() : void
      {
         recording = recordWanted = playing = once = false;
         taken = null;
         takenAt = null;
         noteUntil = 0;
         playFrom = -1;
         if(startFromDummy)
         {
            startAt = null;
            startFromDummy = false;
         }
      }

      private static function endRecord() : void
      {
         var was:Boolean = recording;
         recording = recordWanted = false;
         if(!was || taken == null)
         {
            show("Recording cancelled");
            return;
         }
         var first:int = 0;
         while(first < taken.length && taken[first] == 0)
         {
            first++;
         }
         if(first >= taken.length)
         {
            show("Nothing recorded  (no input)");
            taken = null;
            return;
         }
         readSlotOnce();
         steps = taken.slice(first);
         startAt = takenAt != null && first < takenAt.length ? takenAt[first] : null;
         startFromDummy = false;
         taken = null;
         takenAt = null;
         writeSlot();
         show("Recorded " + (steps.length * STEP / 1000).toFixed(1) + " s in slot " + (slotAt + 1) + "  (Shift+F2 to replay)");
         Platform.log("training dummy: recorded " + steps.length + " steps (" + first + " idle steps dropped), slot " + (slotAt + 1));
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
         return core != null && (uint(core.var_3595) & TRAINING_MODE) != 0 && !OnlineTraining.active;
      }

      private static function onKey(event:Object) : Boolean
      {
         if(event == null || event.altKey || event.shiftKey == event.ctrlKey)
         {
            return false;
         }
         var code:uint = uint(event.keyCode);
         if(code != RECORD_KEY && code != PLAY_KEY || !Platform.matchRunning || !inTraining(game()))
         {
            return false;
         }
         if(event.ctrlKey)
         {
            if(code != PLAY_KEY)
            {
               return false;
            }
            playOnce();
         }
         else if(code == RECORD_KEY)
         {
            toggleRecord();
         }
         else
         {
            togglePlay();
         }
         return true;
      }

      private static function slotOf(state:Object) : int
      {
         var core:Object = state.owner;
         if(!inTraining(core))
         {
            return -1;
         }
         var players:Object = core.var_7050;
         if(int(players.length) < 2)
         {
            return -1;
         }
         if(players[0].var_10012 === state)
         {
            return 0;
         }
         if(players[1].var_10012 === state)
         {
            return 1;
         }
         return -1;
      }

      private static function onSampling(state:Object, time:uint) : Boolean
      {
         if(!recording && !recordWanted && !playing)
         {
            return false;
         }
         var slot:int = slotOf(state);
         if(slot == 0 && recordWanted)
         {
            recordWanted = false;
            recording = true;
            recordedSide = side(state.owner);
            taken = [];
            takenAt = [];
            lastTime = 0;
            held = 0;
         }
         if(slot != 1)
         {
            return false;
         }
         var bits:uint;
         if(recording)
         {
            bits = held;
            if(time != lastTime)
            {
               lastTime = time;
               taken.push(held);
               takenAt.push(positionOf(state.owner,0));
               if(taken.length >= MAX_STEPS)
               {
                  endRecord();
               }
            }
         }
         else
         {
            if(playFrom < 0 || uint(playFrom) > time)
            {
               playFrom = int(time);
            }
            var at:uint = (time - uint(playFrom)) / STEP;
            if(once && at >= steps.length)
            {
               playing = once = false;
               passes = 1;
               passHash(state.owner,time);
               if(note != null)
               {
                  noteUntil = 0;
               }
               return false;
            }
            var index:uint = at % steps.length;
            if(index == 0 && at > 0)
            {
               passes++;
               passHash(state.owner,time);
            }
            if(index == 0)
            {
               if(startAt == null)
               {
                  startAt = positionOf(state.owner,1);
                  startFromDummy = startAt != null;
                  show("This recording has no start point: record it again (Shift+F1) to replay it from where you recorded");
               }
               if(skipPlace)
               {
                  skipPlace = false;
               }
               else if(startAt != null)
               {
                  placeDummy(state.owner);
               }
               if(startFromDummy)
               {
                  flipped = mirror && recordedSide != 0 && side(state.owner) == -recordedSide;
                  if(flipped)
                  {
                     mirroredPasses++;
                  }
               }
               else
               {
                  flipped = false;
               }
            }
            bits = mirrored(steps[index]);
         }
         if(RemoteInput.bitsAt(state,time) != bits)
         {
            RemoteInput.feed(state,time,bits);
         }
         return true;
      }

      private static function positionOf(core:Object, i:int) : Object
      {
         try
         {
            var p:Object = core.var_7050[i];
            return {"x":Number(p.method_338()),"y":Number(p.method_4344())};
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private static function placeDummy(core:Object) : void
      {
         try
         {
            var dummy:Object = core.var_7050[1];
            dummy.method_6277(Number(startAt.x),Number(startAt.y));
            dummy.var_10228.method_3135(dummy.var_6005,0);
            dummy.var_10228.method_3135(dummy.var_4126,0);
         }
         catch(e:Error)
         {
            Platform.log("training dummy: not placed: " + e.message);
         }
      }

      private static function mirrored(bits:uint) : uint
      {
         var lr:uint = bits & (LEFT | RIGHT);
         return flipped && lr != 0 && lr != (LEFT | RIGHT) ? bits ^ (LEFT | RIGHT) : bits;
      }

      private static function get mirror() : Boolean
      {
         return ModSettings.value("dummyMirror") !== false;
      }

      private static function side(core:Object) : int
      {
         try
         {
            var d:Number = Number(core.var_7050[1].method_338()) - Number(core.var_7050[0].method_338());
            return d > 0 ? 1 : d < 0 ? -1 : 0;
         }
         catch(e:Error)
         {
         }
         return 0;
      }

      private static function onSampled(state:Object, time:uint, bits:uint) : void
      {
         if(!recording || slotOf(state) != 0)
         {
            return;
         }
         held = bits;
         if(RemoteInput.bitsAt(state,time) != 0)
         {
            RemoteInput.feed(state,time,0);
         }
      }

      private static function passHash(core:Object, time:uint) : void
      {
         try
         {
            var one:Object = new class_362(core.var_7050[1]);
            var bytes:Object = one.var_5133;
            var h:uint = 2166136261;
            var n:int = int(bytes.length);
            for(var i:int = 0; i < n; i++)
            {
               h = uint((h ^ uint(bytes[i])) * 16777619);
            }
            one.method_470();
            lastPassHash = h.toString(16) + "/" + n;
            Platform.log("training dummy: pass " + passes + " ended at " + time + " ms, dummy " + lastPassHash);
         }
         catch(e:Error)
         {
            Platform.log("training dummy hash: " + e.message);
         }
      }

      private static function show(text:String) : void
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
         noteUntil = getTimer() + (recording || recordWanted || playing && !once ? 600000 : 1800);
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
