package bh.platform
{
   import flash.events.IOErrorEvent;
   import flash.events.TimerEvent;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.media.Sound;
   import flash.media.SoundChannel;
   import flash.media.SoundTransform;
   import flash.net.URLRequest;
   import flash.utils.Timer;
   import flash.utils.getTimer;

   public final class MusicPacks
   {
      public static const PREFIX:String = "bhmusic:";
      public static const STOP_PREFIX:String = "bhmusic-stop:";
      public static const BATTLE:String = "*battle";

      public static const MAIN_SLOTS:Array = [["DefaultUI","Main menu"],["DefaultCharacterSelect","Character select"],
         [BATTLE,"Every map"],["DefaultWinTheme","Victory"]];

      private static const PLAYING_ID:uint = 0x7B000001;

      public static var packs:Array = [];

      private static var soundMap:Object = null;
      private static var soundCache:Object = {};
      private static var soundsLogged:Object = {};
      private static var nextSoundId:uint = 0x7C000000;

      private static var musicSound:Sound;
      private static var channel:SoundChannel;
      private static var track:Object;
      private static var volumeTimer:Timer;
      private static var appliedVolume:Number = -1;
      private static var hooked:Boolean = false;

      public function MusicPacks()
      {
      }

      public static function add(mod:Object, report:Array) : void
      {
         var sounds:Object = {};
         var soundCount:int = 0;
         for(var event:String in mod.sounds)
         {
            var soundFile:File = (mod.dir as File).resolvePath(String(mod.sounds[event]));
            if(!soundFile.exists)
            {
               report.push("sound skipped " + mod.id + "/" + event + ": " + mod.sounds[event] + " is missing");
               continue;
            }
            sounds[event] = soundFile;
            soundCount++;
         }
         var music:Object = mod.music != null ? mod.music : {"tracks":{}};
         var tracks:Array = [];
         var byKey:Object = {};
         for(var key:String in music.tracks)
         {
            var spec:* = music.tracks[key];
            var path:String = spec is String ? spec : spec.file;
            var file:File = (mod.dir as File).resolvePath(path);
            if(!file.exists)
            {
               report.push("music track skipped " + mod.id + "/" + key + ": " + path + " is missing");
               continue;
            }
            var volume:Number = !(spec is String) && spec.volume is Number ? Math.max(0,Math.min(1,spec.volume)) : 1;
            var t:Object = {"key":key,"id":mod.id + "/" + key,"title":!(spec is String) && spec.title is String ? spec.title : key,
                            "file":file,"volume":volume,"pack":mod.id};
            tracks.push(t);
            byKey[key] = t;
         }
         tracks.sortOn("key");
         var replaces:Object = {};
         for(var slot:String in music.replaces)
         {
            var target:String = String(music.replaces[slot]);
            if(byKey[target] != null)
            {
               replaces[slot] = byKey[target].id;
            }
            else
            {
               report.push("music " + mod.id + ": \"replaces\" " + slot + " names " + target + ", not one of its tracks");
            }
         }
         packs.push({"id":mod.id,"name":mod.name,"tracks":tracks,"replaces":replaces,"sounds":sounds,"soundCount":soundCount});
         report.push("music " + mod.id + ": " + tracks.length + " tracks" + (soundCount > 0 ? ", " + soundCount + " sounds" : ""));
         if(!hooked)
         {
            hooked = true;
            Hooks.tableParsing.add(addRows);
            Hooks.musicStopping.add(stopping);
            dropOldChoices();
         }
         rebuildSounds();
      }

      public static function on() : Array
      {
         var list:Array = [];
         for each(var pack:Object in packs)
         {
            if(!ModSettings.isDisabled(pack.id))
            {
               list.push(pack);
            }
         }
         return list;
      }

      public static function tracksOn() : Array
      {
         var list:Array = [];
         for each(var pack:Object in on())
         {
            list = list.concat(pack.tracks);
         }
         return list;
      }

      public static function trackById(id:String) : Object
      {
         for each(var pack:Object in packs)
         {
            for each(var t:Object in pack.tracks)
            {
               if(t.id == id)
               {
                  return t;
               }
            }
         }
         return null;
      }

      public static function slotLabel(slot:String) : String
      {
         for each(var main:Array in MAIN_SLOTS)
         {
            if(main[0] == slot)
            {
               return main[1];
            }
         }
         try
         {
            var type:MusicType = MusicType.method_2373(slot);
            if(type != null && type.mDisplayName != null && type.mDisplayName != "")
            {
               return type.mDisplayName;
            }
         }
         catch(e:Error)
         {
         }
         return slot;
      }

      public static function replacement(slot:String) : String
      {
         var out:String = null;
         for each(var pack:Object in on())
         {
            if(pack.replaces[slot] != null)
            {
               out = pack.replaces[slot];
            }
         }
         return out;
      }

      public static function choiceName(value:String) : String
      {
         if(value == null || value == "default")
         {
            return "The game's music";
         }
         var t:Object = trackById(value);
         if(t == null)
         {
            return value;
         }
         for each(var pack:Object in packs)
         {
            if(pack.id == t.pack)
            {
               return t.title + " (" + pack.name + ")";
            }
         }
         return t.title;
      }

      public static function changes() : Array
      {
         var music:Array = [];
         var sounds:Array = [];
         var added:Array = [];
         for each(var pack:Object in packs)
         {
            var isOn:Boolean = !ModSettings.isDisabled(pack.id);
            var used:Object = {};
            for(var slot:String in pack.replaces)
            {
               var t:Object = trackById(pack.replaces[slot]);
               used[pack.replaces[slot]] = true;
               var main:int = 0;
               while(main < MAIN_SLOTS.length && MAIN_SLOTS[main][0] != slot)
               {
                  main++;
               }
               music.push({"kind":"music","pack":pack,"slot":slot,"label":slotLabel(slot),"main":main,
                  "line":(t != null ? t.title : pack.replaces[slot]) + " - " + pack.name,"on":isOn,
                  "wins":isOn && replacement(slot) == pack.replaces[slot]});
            }
            if(pack.soundCount > 0)
            {
               var events:Array = [];
               var lost:int = 0;
               for(var event:String in pack.sounds)
               {
                  events.push(event);
                  if(isOn && soundMap != null && soundMap[event] != null && soundMap[event].pack != pack.id)
                  {
                     lost++;
                  }
               }
               events.sort(Array.CASEINSENSITIVE);
               sounds.push({"kind":"sounds","pack":pack,"label":pack.name + " sounds","events":events,"on":isOn,
                  "wins":isOn && lost < events.length,"lost":lost,"line":events.length + (events.length == 1 ? " sound" :
                  " sounds") + " - " + pack.name});
            }
            var titles:Array = [];
            for each(t in pack.tracks)
            {
               if(!used[t.id])
               {
                  titles.push(t.title);
               }
            }
            if(titles.length > 0)
            {
               added.push({"kind":"tracks","pack":pack,"label":pack.name + " tracks","titles":titles,"on":isOn,"wins":isOn,
                  "line":titles.length + (titles.length == 1 ? " track" : " tracks") + " for mod maps - " + pack.name});
            }
         }
         music.sort(function(a:Object, b:Object):int
         {
            if(a.main != b.main)
            {
               return a.main - b.main;
            }
            var x:String = String(a.label).toLowerCase();
            var y:String = String(b.label).toLowerCase();
            return x < y ? -1 : (x > y ? 1 : 0);
         });
         return music.concat(sounds,added);
      }

      public static function soundsOn(id:String) : Boolean
      {
         return !ModSettings.isDisabled(id);
      }

      private static function dropOldChoices() : void
      {
         if(ModSettings.value("music") != null || ModSettings.value("soundPacks") != null)
         {
            ModSettings.remove("music");
            ModSettings.remove("soundPacks");
            Platform.log("music: the old AUDIO tab choices were dropped (switched-on mods apply their music and sounds)");
         }
      }

      public static function rebuildSounds() : void
      {
         var map:Object = null;
         for each(var pack:Object in packs)
         {
            if(pack.soundCount == 0 || !soundsOn(pack.id))
            {
               continue;
            }
            map = map || {};
            for(var event:String in pack.sounds)
            {
               map[event] = {"file":pack.sounds[event],"pack":pack.id};
            }
         }
         soundMap = map;
      }

      public static function sound(event:String, delay:uint) : uint
      {
         if(ReplayExport.active)
         {
            return nextSoundId;
         }
         if(logState != 0 && event != null)
         {
            logEvent(event);
         }
         if(soundMap == null || delay != 0 || event == null)
         {
            return 0;
         }
         var entry:Object = soundMap[event];
         if(entry == null)
         {
            return 0;
         }
         try
         {
            if(class_727.var_1732)
            {
               return nextSoundId;
            }
            var file:File = entry.file;
            var snd:Sound = soundCache[file.nativePath];
            if(snd == null)
            {
               snd = new Sound();
               snd.addEventListener(IOErrorEvent.IO_ERROR,function(e:IOErrorEvent):void
               {
                  Platform.log("sound " + event + " couldn't be read: " + e.text);
               });
               snd.load(new URLRequest(file.url));
               soundCache[file.nativePath] = snd;
            }
            snd.play(0,0,new SoundTransform(class_727.var_7091 / 100));
            if(!soundsLogged[event])
            {
               soundsLogged[event] = true;
               Platform.log("sound: " + event + " from " + entry.pack + " (" + file.name + ")");
            }
            soundsPlayed++;
            return ++nextSoundId;
         }
         catch(e:Error)
         {
            Platform.log("sound " + event + ": " + e.message);
         }
         return 0;
      }

      private static var logState:int = -1;
      private static var logSeen:Object = {};
      private static var logLines:int = 0;

      private static function logEvent(event:String) : void
      {
         if(logState < 0)
         {
            logState = ModSettings.value("soundLog") == true ? 1 : 0;
            if(logState == 0)
            {
               return;
            }
         }
         if(logSeen[event] || logLines >= 5000)
         {
            return;
         }
         logSeen[event] = true;
         try
         {
            var stream:FileStream = new FileStream();
            stream.open(Platform.dataFile("bh-sounds.txt"),logLines == 0 ? FileMode.WRITE : FileMode.APPEND);
            stream.writeUTFBytes("[" + getTimer() + "] " + event + "\r\n");
            stream.close();
         }
         catch(e:Error)
         {
         }
         logLines++;
      }

      public static var soundsPlayed:int = 0;

      private static function musicNamed(start:String) : MusicType
      {
         for each(var type:MusicType in MusicType.var_7016)
         {
            if(type.var_4366 == start)
            {
               return type;
            }
         }
         return null;
      }

      private static function isLevelMusic(type:MusicType) : Boolean
      {
         for each(var level:LevelType in LevelType.var_9426)
         {
            if(level.var_7718 == type || level.var_731 == type)
            {
               return true;
            }
         }
         return false;
      }

      private static function trackFor(start:String) : Object
      {
         if(start.indexOf(PREFIX) == 0)
         {
            return trackById(start.substr(PREFIX.length));
         }
         if(packs.length == 0)
         {
            return null;
         }
         var type:MusicType = musicNamed(start);
         if(type == null)
         {
            return null;
         }
         var value:String = replacement(type.var_8440);
         if(value == null && isLevelMusic(type))
         {
            value = replacement(BATTLE);
         }
         return value == null ? null : trackById(value);
      }

      public static function play(start:String, stop:String) : uint
      {
         if(start == null || stop == null || start == class_727.var_2141)
         {
            return 0;
         }
         try
         {
            var t:Object = trackFor(start);
            if(t == null)
            {
               return 0;
            }
            if(class_727.var_9091 != null)
            {
               class_727.method_7661();
            }
            startTrack(t);
            class_727.var_2141 = start;
            class_727.var_9091 = stop;
            return PLAYING_ID;
         }
         catch(e:Error)
         {
            Platform.log("music: " + e.message);
         }
         return 0;
      }

      private static function stopping(stop:String) : Boolean
      {
         if(track == null)
         {
            return false;
         }
         if(stop != null && stop != class_727.var_9091)
         {
            return true;
         }
         stopTrack();
         class_727.var_9091 = null;
         class_727.var_2141 = null;
         return true;
      }

      private static function startTrack(t:Object) : void
      {
         stopTrack();
         track = t;
         musicSound = new Sound();
         musicSound.addEventListener(IOErrorEvent.IO_ERROR,function(e:IOErrorEvent):void
         {
            Platform.log("music track " + t.id + " couldn't be read: " + e.text);
         });
         musicSound.load(new URLRequest((t.file as File).url));
         appliedVolume = volume();
         channel = musicSound.play(0,int.MAX_VALUE,new SoundTransform(appliedVolume));
         if(volumeTimer == null)
         {
            volumeTimer = new Timer(250);
            volumeTimer.addEventListener(TimerEvent.TIMER,followVolume);
         }
         volumeTimer.start();
         Platform.log("music: " + t.id + " (" + (t.file as File).name + ")");
      }

      private static function stopTrack() : void
      {
         if(channel != null)
         {
            channel.stop();
         }
         if(musicSound != null)
         {
            try
            {
               musicSound.close();
            }
            catch(e:Error)
            {
            }
         }
         if(volumeTimer != null)
         {
            volumeTimer.stop();
         }
         channel = null;
         musicSound = null;
         track = null;
      }

      private static function volume() : Number
      {
         return track == null ? 0 : class_727.var_13292 / 100 * Number(track.volume);
      }

      private static function followVolume(e:TimerEvent) : void
      {
         var v:Number = volume();
         if(channel != null && v != appliedVolume)
         {
            appliedVolume = v;
            channel.soundTransform = new SoundTransform(v);
         }
      }

      public static function restartIfPlaying() : void
      {
         var start:String = class_727.var_2141;
         var stop:String = class_727.var_9091;
         if(start == null || stop == null)
         {
            return;
         }
         class_727.method_7661();
         class_727.method_4888(start,stop);
      }

      public static function nowPlaying() : String
      {
         if(track != null)
         {
            return track.id + " vol " + Math.round(appliedVolume * 100) + (channel != null ? " at " +
               Math.round(channel.position) + " ms" : "");
         }
         return class_727.var_2141 != null ? "game:" + class_727.var_2141 : "none";
      }

      private static function addRows(tableName:String, root:Object) : void
      {
         if(tableName != "MusicTypes")
         {
            return;
         }
         var next:int = 0;
         var names:Object = {};
         for each(var row:Xml in elementsOf(root as Xml))
         {
            names[row.method_4935("MusicName")] = true;
            for each(var field:Xml in elementsOf(row))
            {
               if(field.var_4402 == "MusicID")
               {
                  next = Math.max(next,int(textOf(field)));
               }
            }
         }
         var added:int = 0;
         for each(var pack:Object in packs)
         {
            for each(var t:Object in pack.tracks)
            {
               if(names[t.id])
               {
                  Platform.log("music: a MusicTypes row is already named " + t.id);
                  continue;
               }
               (root as Xml).addChild(Xml.parse("<MusicType MusicName=\"" + escape(t.id) + "\"><DisplayName>" + escape(t.title) +
                  "</DisplayName><MusicID>" + (++next) + "</MusicID><StartEvent>" + escape(PREFIX + t.id) +
                  "</StartEvent><StopEvent>" + escape(STOP_PREFIX + t.id) + "</StopEvent></MusicType>").method_7292());
               added++;
            }
         }
         Platform.log("music: " + added + " MusicTypes rows added for mod tracks");
      }

      private static function elementsOf(x:Xml) : Array
      {
         var list:Array = [];
         for each(var child:Xml in x.var_5236)
         {
            if(child.var_14625 == Xml.var_11889)
            {
               list.push(child);
            }
         }
         return list;
      }

      private static function textOf(x:Xml) : String
      {
         var out:String = "";
         for each(var child:Xml in x.var_5236)
         {
            if(child.var_14625 != Xml.var_11889 && child.var_3342 != null)
            {
               out += child.var_3342;
            }
         }
         return out;
      }

      private static function escape(s:String) : String
      {
         return s.split("&").join("&amp;").split("<").join("&lt;").split(">").join("&gt;").split("\"").join("&quot;");
      }
   }
}
