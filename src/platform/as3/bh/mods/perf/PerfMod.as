package bh.mods.perf
{
   import bh.platform.Hooks;
   import bh.platform.Platform;
   import bh.platform.net.P2PSession;
   import flash.display.Stage;
   import flash.events.Event;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.system.Capabilities;
   import flash.system.System;
   import flash.text.TextField;
   import flash.text.TextFormat;
   import flash.utils.getDefinitionByName;
   import flash.utils.getTimer;

   public final class PerfMod
   {
      public static const LOG:String = "bh-perf.txt";
      public static const MAX_FRAMES:int = 60 * 60 * 30;
      private static const SPARE:int = 2048;

      private static var stage:Stage;
      private static var inMatch:Boolean = false;
      private static var menuReached:Boolean = false;
      private static var matchStart:int = 0;
      private static var playStart:int = -1;

      private static var frameStart:int = -1;
      private static var simStart:int = -1;
      private static const SLOW_UPDATE:int = 12;
      private static const SLOW_FRAME:int = 50;
      private static const SLOW_PLAY_FRAME:int = 15;
      private static var renderStart:int = -1;
      private static var lastEnd:int = -1;
      private static var steps:int = -1;
      private static var lastResimulated:uint = 0;
      private static var lastMemory:Number = 0;

      private static var memFrame:Number = -1;
      private static var memSim:Number = -1;
      private static var memDraw:Number = -1;
      private static var memEnd:Number = -1;
      private static var allocPre:Number = 0;
      private static var allocSim:Number = 0;
      private static var allocDraw:Number = 0;
      private static var allocOutside:Number = 0;
      private static var allocFrames:int = 0;
      private static var loadsThisFrame:Array = [];
      private static var precacheDoneAt:int = -1;
      private static var precacheItems:int = 0;

      private static var frames:Vector.<FrameRecord> = new Vector.<FrameRecord>();
      private static var frameCount:int = 0;
      private static var spare:Vector.<FrameRecord> = new Vector.<FrameRecord>();
      private static var spareNext:int = 0;
      private static var loads:Array = [];
      private static var gcCount:int = 0;
      private static var gcFreed:Number = 0;

      private static var overlay:TextField;
      private static var recent:Vector.<FrameRecord> = new Vector.<FrameRecord>();
      private static var lastOverlay:int = 0;

      public function PerfMod()
      {
      }

      public static function register() : void
      {
         Hooks.frameStarting.add(function():void
         {
            frameStart = getTimer();
            memFrame = System.totalMemoryNumber;
            if(memEnd >= 0 && inMatch)
            {
               allocOutside += grown(memEnd,memFrame);
            }
            simStart = renderStart = -1;
         });
         Hooks.simulationFrame.add(onSimulation);
         Hooks.frameRendering.add(function():void
         {
            renderStart = getTimer();
            memDraw = System.totalMemoryNumber;
            if(inMatch && simStart >= 0 && renderStart - simStart >= SLOW_UPDATE)
            {
               telemetryMark("bh.slow",simStart + "," + renderStart);
            }
         });
         Hooks.fileLoaded.add(function(file:Object):void
         {
            if(inMatch)
            {
               loadsThisFrame.push(String(file.fileName));
            }
         });
         Hooks.gameCreated.add(function(main:Object):void
         {
            stage = main.stage;
            stage.addEventListener(Event.EXIT_FRAME,onExitFrame,false,-1000);
            write("perf: measuring; F3 shows the overlay");
         });
         Hooks.mainMenuButtonsBuilt.add(function(menu:Object):void
         {
            if(!menuReached)
            {
               menuReached = true;
               write("startup: main menu after " + (getTimer() / 1000).toFixed(1) + " s, memory " +
                  (System.totalMemoryNumber / 1048576).toFixed(0) + " MB, process " + (System.privateMemory / 1048576).toFixed(0) + " MB");
            }
         });
         Hooks.matchStarted.add(function():void
         {
            inMatch = true;
            matchStart = getTimer();
            playStart = -1;
            frameCount = 0;
            recent.length = 0;
            precacheDoneAt = -1;
            precacheItems = 0;
            loads = [];
            gcCount = 0;
            gcFreed = 0;
            allocPre = allocSim = allocDraw = allocOutside = 0;
            allocFrames = 0;
         });
         Hooks.matchEnded.add(function(to:uint):void
         {
            if(inMatch)
            {
               inMatch = false;
               telemetryMark("bh.play.end");
               report();
            }
         });
         Hooks.keyDown.add(function(event:Object):Boolean
         {
            if(event.keyCode == 114)
            {
               toggleOverlay();
               return true;
            }
            return false;
         });
      }

      private static function onSimulation(core:Object) : void
      {
         simStart = getTimer();
         memSim = System.totalMemoryNumber;
         try
         {
            var mode:uint = uint(core.var_3595);
            var online:Boolean = (mode & (4 | 2 | 4194304 | 1024 | 2048 | 8192 | 262144 | 524288)) != 0;
            online = online || P2PSession.rollbackOn;
            var to:uint = online ? uint(core.var_12659) : uint(core.var_11938);
            var from:uint = online ? uint(core.var_13849) : uint(core.var_1171);
            to -= to % 16;
            from -= from % 16;
            steps = to > from ? int((to - from) / 16) : 0;
         }
         catch(e:Error)
         {
            steps = -1;
         }
      }

      private static function onExitFrame(e:Event) : void
      {
         var now:int = getTimer();
         var memory:Number = System.totalMemoryNumber;
         if(inMatch && memFrame >= 0)
         {
            var afterPre:Number = memSim >= 0 ? memSim : (memDraw >= 0 ? memDraw : memory);
            allocPre += grown(memFrame,afterPre);
            if(memSim >= 0)
            {
               allocSim += grown(memSim,memDraw >= 0 ? memDraw : memory);
            }
            if(memDraw >= 0)
            {
               allocDraw += grown(memDraw,memory);
            }
            allocFrames++;
         }
         memEnd = memory;
         memFrame = memSim = memDraw = -1;
         var freed:Number = lastMemory - memory;
         var gc:Boolean = lastMemory > 0 && freed > 1048576;
         lastMemory = memory;
         if(inMatch && precacheDoneAt < 0)
         {
            try
            {
               var queued:int = class_266.var_14062 != null ? int(class_266.var_14062.length) : 0;
               precacheItems = Math.max(precacheItems,queued);
               if(class_266.var_2356 == 3 || (queued > 0 && class_266.var_316.var_9692 >= queued))
               {
                  precacheDoneAt = now;
               }
            }
            catch(err:Error)
            {
               precacheDoneAt = now;
            }
         }
         if(lastEnd >= 0)
         {
            var kept:Boolean = inMatch && frameCount < MAX_FRAMES;
            var f:FrameRecord;
            if(kept)
            {
               if(frameCount == frames.length)
               {
                  frames.push(new FrameRecord());
               }
               f = frames[frameCount++];
            }
            else
            {
               if(spare.length < SPARE)
               {
                  spare.push(new FrameRecord());
               }
               f = spare[spareNext];
               spareNext = (spareNext + 1) % SPARE;
            }
            f.at = now;
            f.ms = now - lastEnd;
            f.pre = frameStart >= 0 ? (simStart >= 0 ? simStart : (renderStart >= 0 ? renderStart : now)) - frameStart : 0;
            f.sim = simStart >= 0 ? (renderStart >= 0 ? renderStart : now) - simStart : 0;
            f.draw = renderStart >= 0 ? now - renderStart : 0;
            f.steps = steps;
            f.gc = gc ? freed : 0;
            f.mem = memory;
            f.loads = loadsThisFrame.length > 0 ? loadsThisFrame.join(", ") : null;
            f.resim = P2PSession.resimulatedSteps >= lastResimulated ? P2PSession.resimulatedSteps - lastResimulated : 0;
            f.tool = Platform.toolTime;
            lastResimulated = P2PSession.resimulatedSteps;
            f.work = f.pre + f.sim + f.draw;
            f.outside = Math.max(0,f.ms - f.work - f.tool);
            if(inMatch && (f.ms >= SLOW_FRAME || playStart >= 0 && f.ms >= SLOW_PLAY_FRAME && f.outside * 2 >= f.ms))
            {
               telemetryMark("bh.slow",lastEnd + "," + now);
            }
            if(inMatch && playStart < 0 && f.steps > 0)
            {
               playStart = now;
               telemetryMark("bh.play.start");
            }
            if(kept)
            {
               if(gc)
               {
                  gcCount++;
                  gcFreed += freed;
               }
               if(f.loads != null)
               {
                  loads.push(f.loads);
               }
            }
            recent.push(f);
            while(recent.length > 0 && now - recent[0].at > 1000)
            {
               recent.shift();
            }
            if(overlay != null && now - lastOverlay > 250)
            {
               lastOverlay = now;
               updateOverlay();
            }
         }
         Platform.toolTime = 0;
         lastEnd = now;
         frameStart = simStart = renderStart = steps = -1;
         if(loadsThisFrame.length > 0)
         {
            loadsThisFrame = [];
         }
      }

      private static function report() : void
      {
         var n:int = frameCount;
         if(n < 10)
         {
            return;
         }
         var reportStart:int = getTimer();
         var target:Number = stage != null ? stage.frameRate : 60;
         var budget:Number = 1000 / target;
         var ms:Array = [];
         var stepCounts:Array = [0,0,0,0];
         var sum:Object = {"pre":0,"sim":0,"draw":0,"outside":0,"ms":0};
         var hitches:int = 0;
         var bigHitches:int = 0;
         var hitchWithGc:int = 0;
         var hitchWithLoad:int = 0;
         var hitchWithSteps:int = 0;
         var hitchWithDraw:int = 0;
         var f:FrameRecord;
         for(var j:int = 0; j < n; j++)
         {
            f = frames[j];
            ms.push(f.ms);
            for(var k:String in sum)
            {
               sum[k] += f[k];
            }
            if(f.steps >= 0)
            {
               stepCounts[Math.min(3,f.steps)]++;
            }
            if(f.ms > budget * 1.5)
            {
               hitches++;
               if(f.ms > budget * 2.5)
               {
                  bigHitches++;
               }
               if(f.gc > 0)
               {
                  hitchWithGc++;
               }
               if(f.loads != null)
               {
                  hitchWithLoad++;
               }
               if(f.steps >= 2)
               {
                  hitchWithSteps++;
               }
               if(f.draw > budget)
               {
                  hitchWithDraw++;
               }
            }
         }
         ms = sortedInts(ms);
         var seconds:Number = (frames[n - 1].at - frames[0].at) / 1000;
         var lines:Array = [];
         lines.push("");
         lines.push("=== match " + new Date().toLocaleString() + ": " + n + " frames in " + seconds.toFixed(1) + " s = " +
            (n / Math.max(0.001,seconds)).toFixed(1) + " fps (target " + target + ", " + budget.toFixed(1) + " ms per frame)");
         lines.push("system: " + systemLine());
         lines.push("frame time: median " + pct(ms,50) + " ms, 95% " + pct(ms,95) + ", 99% " + pct(ms,99) + ", 99.9% " +
            pct(ms,99.9) + ", worst " + ms[n - 1]);
         lines.push("hitches (over 1.5x a frame): " + hitches + " (" + (100 * hitches / n).toFixed(2) + "%), over 2.5x: " + bigHitches);
         lines.push("  of the hitches: " + hitchWithGc + " with a garbage collection, " + hitchWithLoad + " with a file load, " +
            hitchWithSteps + " ran 2+ match steps, " + hitchWithDraw + " spent over a frame drawing");
         lines.push("match steps per frame: 0: " + stepCounts[0] + ", 1: " + stepCounts[1] + ", 2: " + stepCounts[2] + ", 3+: " +
            stepCounts[3] + " (steady 1 = smooth; 0s and 2s mean the 16 ms step and the display's frame drift apart)");
         lines.push("average ms per frame: before the match update " + avg(sum.pre,n) + ", match update " + avg(sum.sim,n) +
            ", drawing + present " + avg(sum.draw,n) + ", outside the game's code " + avg(sum.outside,n));
         var perSecond:Function = function(bytes:Number):String
         {
            return (bytes / 1048576 / Math.max(0.001,seconds)).toFixed(2);
         };
         lines.push("allocated (MB per second): before the match update " + perSecond(allocPre) + ", match update " +
            perSecond(allocSim) + ", drawing + present " + perSecond(allocDraw) + ", outside the game's code " +
            perSecond(allocOutside) + " (growth of totalMemoryNumber between the frame's phases; intervals with a " +
            "collection left out)");
         lines.push("garbage collections: " + gcCount + " (" + (gcFreed / 1048576).toFixed(1) + " MB freed), memory at the end " +
            (System.totalMemoryNumber / 1048576).toFixed(1) + " MB, process " + (System.privateMemory / 1048576).toFixed(1) + " MB");
         lines.push("files loaded during the match: " + loads.length + (loads.length ? " (" + loads.slice(0,10).join("; ") +
            (loads.length > 10 ? "; ..." : "") + ")" : ""));
         var worst:Array = slowest(n,15);
         lines.push("worst frames (ms: before / update / drawing / outside, steps, other):");
         for(var i:int = 0; i < Math.min(15,worst.length); i++)
         {
            f = worst[i];
            lines.push("  " + f.ms + " ms at " + ((int(f.at) - matchStart) / 1000).toFixed(1) + " s: " + f.pre + " / " + f.sim +
               " / " + f.draw + " / " + f.outside + ", " + f.steps + " steps" + (f.gc > 0 ? ", GC " + (f.gc / 1048576).toFixed(1) +
               " MB" : "") + (f.resim > 0 ? ", rollback redid " + f.resim + " steps" : "") +
               (f.tool > 0 ? ", test tool " + f.tool + " ms" : "") + (f.loads != null ? ", loaded " + f.loads : ""));
         }
         lines.push("precacher: " + precacheItems + " items, " + (precacheDoneAt < 0 ? "not done by the match's end" :
            "done at " + ((precacheDoneAt - matchStart) / 1000).toFixed(1) + " s") + (playStart >= 0 ? " (first step at " +
            ((playStart - matchStart) / 1000).toFixed(1) + " s)" : ""));
         playReport(lines,budget);
         write(lines.join("\r\n"));
         Platform.log("perf report: " + n + " frames in " + (getTimer() - reportStart) + " ms");
      }

      private static function playReport(lines:Array, budget:Number) : void
      {
         if(playStart < 0)
         {
            return;
         }
         var play:Array = [];
         var tools:int = 0;
         var f:FrameRecord;
         for(var j:int = 0; j < frameCount; j++)
         {
            f = frames[j];
            if(f.at <= playStart)
            {
               continue;
            }
            if(f.tool >= 2)
            {
               tools++;
               continue;
            }
            play.push(f);
         }
         var n:int = play.length;
         if(n < 10)
         {
            return;
         }
         var ms:Array = [];
         for each(f in play)
         {
            ms.push(f.ms);
         }
         ms = sortedInts(ms);
         var median:int = Math.max(1,pct(ms,50));
         var limit:int = Math.max(int(budget * 2),median * 5 / 2);
         var drops:Array = [];
         var kinds:Object = {};
         for each(f in play)
         {
            if(f.ms <= limit)
            {
               continue;
            }
            var kind:String = f.gc > 0 ? "collection" : (f.loads != null ? "load" : (f.sim >= f.ms / 2 ? "match update" :
               (f.draw >= f.ms / 2 ? "drawing" : "outside the game's code")));
            kinds[kind] = int(kinds[kind]) + 1;
            drops.push(f);
         }
         lines.push("during play (from the first match step, " + tools + " test-tool frames left out): " + n + " frames, median " +
            median + " ms, 99% " + pct(ms,99) + ", 99.9% " + pct(ms,99.9) + ", worst " + ms[n - 1]);
         var kindText:Array = [];
         for(var k:String in kinds)
         {
            kindText.push(kinds[k] + " " + k);
         }
         lines.push("  drops over " + limit + " ms: " + drops.length + (drops.length ? " (" + kindText.join(", ") + ")" : ""));
         var tens:Array = [];
         for each(f in play)
         {
            if(f.ms > budget * 1.5)
            {
               var slot:int = int((f.at - play[0].at) / 10000);
               while(tens.length <= slot)
               {
                  tens.push(0);
               }
               tens[slot]++;
            }
         }
         lines.push("  hitches (over 1.5x a frame) per 10 s of play: " + (tens.length ? tens.join(" ") : "none"));
         var fixed:Array = [8,12,17];
         var over:Array = [0,0,0];
         for each(f in play)
         {
            for(var q:int = 0; q < fixed.length; q++)
            {
               if(f.ms > fixed[q])
               {
                  over[q]++;
               }
            }
         }
         var playSeconds:Number = Math.max(0.001,(play[n - 1].at - play[0].at) / 1000);
         lines.push("  frames over " + fixed.join(" / ") + " ms: " + over.join(" / ") + " (" + (100 * over[0] / n).toFixed(2) +
            "% of frames over 8 ms, " + (over[0] / playSeconds).toFixed(1) + " per second; " + (n / playSeconds).toFixed(0) +
            " frames per second in play)");
         var redo:Array = [];
         var redone:int = 0;
         for each(f in play)
         {
            if(f.resim > 0)
            {
               redo.push(f.ms);
               redone += f.resim;
            }
         }
         if(redo.length > 0)
         {
            redo = sortedInts(redo);
            lines.push("  rollback frames: " + redo.length + " (" + redone + " steps redone), median " + pct(redo,50) +
               " ms, 90% " + pct(redo,90) + ", worst " + redo[redo.length - 1] + "; over " + limit + " ms: " +
               redo.filter(function(v:*, i:int, a:Array):Boolean
               {
                  return v > limit;
               }).length);
         }
         for(var i:int = 0; i < Math.min(40,drops.length); i++)
         {
            f = drops[i];
            lines.push("    " + f.ms + " ms at " + ((int(f.at) - matchStart) / 1000).toFixed(1) + " s: " + f.pre + " / " + f.sim +
               " / " + f.draw + " / " + f.outside + ", " + f.steps + " steps" + (f.gc > 0 ? ", GC " + (f.gc / 1048576).toFixed(1) +
               " MB" : "") + (f.resim > 0 ? ", rollback redid " + f.resim + " steps" : "") +
               (f.loads != null ? ", loaded " + f.loads : ""));
         }
      }

      private static function telemetryMark(name:String, value:* = null) : void
      {
         try
         {
            var t:Object = getDefinitionByName("flash.profiler.Telemetry");
            if(t.connected)
            {
               t.sendMetric(name,value != null ? value : getTimer());
            }
         }
         catch(e:Error)
         {
         }
      }

      private static function grown(from:Number, to:Number) : Number
      {
         return to > from ? to - from : 0;
      }

      private static function sortedInts(values:Array) : Array
      {
         var max:int = 0;
         var v:int;
         for each(v in values)
         {
            if(v > max)
            {
               max = v;
            }
         }
         var counts:Vector.<int> = new Vector.<int>(max + 1);
         for each(v in values)
         {
            counts[v > 0 ? v : 0]++;
         }
         var out:Array = new Array(values.length);
         var j:int = 0;
         for(var i:int = 0; i <= max; i++)
         {
            for(var c:int = counts[i]; c > 0; c--)
            {
               out[j++] = i;
            }
         }
         return out;
      }

      private static function slowest(n:int, count:int) : Array
      {
         var out:Array = [];
         for(var j:int = 0; j < n; j++)
         {
            var f:FrameRecord = frames[j];
            if(out.length == count && f.ms <= out[count - 1].ms)
            {
               continue;
            }
            var at:int = out.length;
            while(at > 0 && out[at - 1].ms < f.ms)
            {
               at--;
            }
            out.splice(at,0,f);
            if(out.length > count)
            {
               out.pop();
            }
         }
         return out;
      }

      private static function pct(sorted:Array, p:Number) : int
      {
         return sorted[Math.min(sorted.length - 1,int(Math.floor(sorted.length * p / 100)))];
      }

      private static function avg(total:Number, n:int) : String
      {
         return (total / n).toFixed(2);
      }

      private static function toggleOverlay() : void
      {
         if(stage == null)
         {
            return;
         }
         if(overlay != null)
         {
            stage.removeChild(overlay);
            overlay = null;
            return;
         }
         overlay = new TextField();
         overlay.defaultTextFormat = new TextFormat("_typewriter",13,0xFFFFFF);
         overlay.background = true;
         overlay.backgroundColor = 0x000000;
         overlay.alpha = 0.75;
         overlay.selectable = false;
         overlay.mouseEnabled = false;
         overlay.width = 360;
         overlay.height = 96;
         overlay.x = 8;
         overlay.y = 8;
         stage.addChild(overlay);
         updateOverlay();
      }

      private static function updateOverlay() : void
      {
         var n:int = recent.length;
         if(n == 0)
         {
            overlay.text = "measuring...";
            return;
         }
         var worst:int = 0;
         var total:Object = {"pre":0,"sim":0,"draw":0,"outside":0};
         var two:int = 0;
         for each(var f:FrameRecord in recent)
         {
            worst = Math.max(worst,f.ms);
            for(var k:String in total)
            {
               total[k] += f[k];
            }
            if(f.steps >= 2 || f.steps == 0)
            {
               two++;
            }
         }
         var span:Number = (recent[n - 1].at - recent[0].at + recent[0].ms) / 1000;
         overlay.text = (n / Math.max(0.001,span)).toFixed(0) + " fps (target " + (stage ? stage.frameRate : 0) + "), worst " + worst +
            " ms\nbefore " + avg(total.pre,n) + "  update " + avg(total.sim,n) + "  draw " + avg(total.draw,n) + "  outside " +
            avg(total.outside,n) + " ms\nuneven steps " + two + " in the last second\nmemory " +
            (System.totalMemoryNumber / 1048576).toFixed(0) + " MB, collections this match " + gcCount + "\nF3 hides this";
      }

      private static function systemLine() : String
      {
         var gpu:String = "unknown";
         try
         {
            var context:Object = class_582.var_3189.method_1662();
            if(context != null)
            {
               gpu = String(context.driverInfo);
            }
         }
         catch(e:Error)
         {
         }
         return "AIR " + Capabilities.version + ", screen " + Capabilities.screenResolutionX + "x" + Capabilities.screenResolutionY +
            ", frame rate target " + (stage ? stage.frameRate : 0) + ", renderer " + gpu;
      }

      private static function write(text:String) : void
      {
         try
         {
            var stream:FileStream = new FileStream();
            stream.open(Platform.dataFile(LOG),FileMode.APPEND);
            stream.writeUTFBytes(new Date().toLocaleTimeString() + " " + text + "\r\n");
            stream.close();
         }
         catch(e:Error)
         {
         }
      }
   }
}
