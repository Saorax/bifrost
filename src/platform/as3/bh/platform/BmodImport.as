package bh.platform
{
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.net.FileFilter;
   import flash.events.Event;
   import flash.utils.ByteArray;
   import flash.utils.Endian;
   import flash.utils.getTimer;
   import flash.utils.setTimeout;

   public final class BmodImport
   {
      public static const CONVERTER:int = 2;

      public static const MEMORY:String = "bh-bmod-imports.json";

      private static const COSTUME_ART:Array = ["GfxType.CustomArt","GfxType.CustomArt2","GfxType.CustomArt3","GfxType.CustomArt4",
         "GfxType.CustomArt5","GfxType.CustomArt6","GfxType.CustomArt7","GfxType.CustomArt8","GfxType.CustomArt9",
         "GfxType.CustomArt10"];

      private static const COSTUME_SWAP:Array = ["SwapCustomArt","SwapCustomArt2","SwapCustomArt3","SwapCustomArt4","SwapCustomArt5"];

      private static const WEAPON_ART:Array = ["CustomArt","CustomArt2","CustomArt3"];

      private static const FAMILIES:Array = [["Hair",["HairLt","Hair","HairDk"]],
         ["Body1",["Body1VL","Body1Lt","Body1","Body1Dk","Body1VD"]],
         ["Body2",["Body2VL","Body2Lt","Body2","Body2Dk","Body2VD"]],
         ["Special",["SpecialVL","SpecialLt","Special","SpecialDk","SpecialVD"]],
         ["Cloth",["ClothVL","ClothLt","Cloth","ClothDk"]],
         ["Weapon",["WeaponVL","WeaponLt","Weapon","WeaponDk"]]];

      private static const MAP_TYPES:Array = [["1v1",["Standard1v1","Ranked1v1"]],["2v2",["Standard2v2","Ranked2v2","Unranked2v2"]],
         ["FFA",["StandardFFA","AltFFA"]],["Big",["StandardBig","Standard3v3"]],
         ["Game modes",["GameModeAll","BrawlballSmall","BrawlballBig","SoccerAll","HordeAll","CTF3v3","Showdown","VolleyBattle",
         "ClimbAll","BuddyAll","RingAll"]]];

      private static const CSV_TABLES:Array = ["costumetypes","weaponskintypes","powertypes","avatartypes","spritedata"];

      public static var lines:Array = [];

      public static var results:Array = [];

      private static var csvTexts:Object = {};

      private static var csvCache:Object = {};

      private static var boneNames:Array = null;

      private static var powerSwapRows:Array = [];

      private static var heroSwapRows:Array = [];

      private static var levelDescs:Array = [];

      private static var levelTypes:Array = [];

      private static var levelSets:Array = [];

      private static var english:Object = null;

      private static var scanned:Boolean = false;

      private static var effectNames:Object = null;

      private static var report:Array;

      private static var madeFolder:File = null;

      private static var movedAside:Array = null;

      public function BmodImport()
      {
      }

      public static function init() : void
      {
         Hooks.csvParsing.add(captureCsv);
         Hooks.tableParsing.add(captureTable);
         Hooks.stringsLoaded.add(captureStrings);
         Hooks.mainMenuButtonsBuilt.add(onMainMenu);
      }

      private static function captureCsv(text:String, tableName:String, offset:int) : String
      {
         var key:String = String(tableName).toLowerCase();
         if(CSV_TABLES.indexOf(key) >= 0 && !(key in csvTexts))
         {
            csvTexts[key] = text.substr(offset);
         }
         return null;
      }

      private static function captureTable(tableName:String, root:Object) : void
      {
         var xml:Xml = root as Xml;
         if(xml == null)
         {
            return;
         }
         var row:Xml;
         if(tableName == "LevelDesc")
         {
            levelDescs.push(xml);
         }
         else if(tableName == "BoneTypes" && boneNames == null)
         {
            boneNames = [];
            for each(row in ContentMods.elements(xml))
            {
               if(row.var_4402 == "Bone")
               {
                  boneNames.push(ContentMods.textOf(row));
               }
            }
         }
         else if(tableName == "PowerSwapTypes")
         {
            for each(row in ContentMods.elements(xml))
            {
               if(row.exists("OwnerCostume"))
               {
                  powerSwapRows.push(row);
               }
               else if(row.exists("OwnerHero") && !row.exists("OwnerSpawnBot"))
               {
                  heroSwapRows.push(row);
               }
            }
         }
         else if(tableName == "LevelTypes")
         {
            for each(row in ContentMods.elements(xml))
            {
               if(row.var_4402 != "LevelType" || !row.exists("LevelName"))
               {
                  continue;
               }
               levelTypes.push({"name":row.method_4935("LevelName"),"devOnly":row.method_4935("DevOnly") == "true",
                  "testLevel":row.method_4935("TestLevel") == "true","display":ContentMods.fieldText(row,"DisplayName"),
                  "thumb":ContentMods.fieldText(row,"ThumbnailPNGFile")});
            }
         }
         else if(tableName == "LevelSetTypes")
         {
            for each(row in ContentMods.elements(xml))
            {
               if(row.var_4402 != "LevelSetType" || !row.exists("LevelSetName"))
               {
                  continue;
               }
               var levels:String = ContentMods.fieldText(row,"LevelTypes");
               levelSets.push({"name":row.method_4935("LevelSetName"),"levels":levels == null ? [] : levels.split(",")});
            }
         }
      }

      private static function captureStrings(language:Localization) : void
      {
         if(language != null && language.var_14508 == "English")
         {
            english = language.var_15061;
         }
      }

      private static function gameString(key:String) : String
      {
         if(key == null || key == "")
         {
            return null;
         }
         var map:Object = english;
         if(map == null && Localization.var_14676 != null)
         {
            map = Localization.var_14676.var_15061;
         }
         if(map == null)
         {
            return null;
         }
         try
         {
            var s:* = map.method_4935(key);
            return s == null ? null : String(s);
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private static function onMainMenu(menu:Object) : void
      {
         if(scanned)
         {
            return;
         }
         scanned = true;
         if(pendingFiles().length == 0)
         {
            return;
         }
         Hooks.frameStarting.add(waitForMenu);
      }

      private static var menuFrames:int = 0;

      private static function menuFree() : Boolean
      {
         if(!(ScreenBase.focusedScreen is ScreenMainMenu))
         {
            return false;
         }
         try
         {
            for each(var screen:Object in [ScreenManager.var_11898,ScreenManager.var_14744,ScreenManager.var_13854])
            {
               if(screen != null && screen.isActive)
               {
                  return false;
               }
            }
         }
         catch(e:Error)
         {
         }
         return true;
      }

      private static function waitForMenu() : void
      {
         if(!menuFree())
         {
            menuFrames = 0;
            return;
         }
         menuFrames++;
         if(menuFrames == 290)
         {
            Busy.start("bmod","Converting .bmod mods",120000);
         }
         if(menuFrames < 300)
         {
            return;
         }
         Hooks.frameStarting.remove(waitForMenu);
         try
         {
            scanFolder();
         }
         catch(e:Error)
         {
            lines.push("bmod scan failed: " + e.message);
         }
         Busy.done("bmod");
      }

      public static function state() : String
      {
         var tables:Array = [];
         for each(var name:String in CSV_TABLES)
         {
            tables.push(name + " " + (name in csvTexts ? String(csvTexts[name]).length : -1));
         }
         return "bmod tables: " + tables.join(", ") + "; bones " + (boneNames != null ? boneNames.length : -1) + ", power swaps " +
            powerSwapRows.length + ", level descs " + levelDescs.length + ", level types " + levelTypes.length + ", level sets " +
            levelSets.length + ", english " + (english != null) + "; pending " + pendingFiles().length + "; results " + results.length;
      }

      public static function modsFolder() : File
      {
         return new File(File.applicationDirectory.resolvePath(ContentMods.FOLDER).nativePath);
      }

      public static function pendingFiles() : Array
      {
         var out:Array = [];
         var root:File = modsFolder();
         if(!root.exists || !root.isDirectory)
         {
            return out;
         }
         for each(var f:File in root.getDirectoryListing())
         {
            if(!f.isDirectory && lower(f.name).substr(-5) == ".bmod")
            {
               out.push(f);
            }
         }
         out.sortOn("name");
         return out;
      }

      public static function scanFolder() : Array
      {
         var done:Array = [];
         var files:Array = pendingFiles();
         if(files.length == 0)
         {
            return done;
         }
         var told:Array = [];
         for each(var f:File in files)
         {
            var r:Object = process(f,false);
            done.push(r);
            if(r.tell)
            {
               told.push(r);
            }
         }
         if(told.length > 0)
         {
            waiting = waiting.concat(told);
            Hooks.frameStarting.add(tellWhenFree);
         }
         return done;
      }

      public static function browse(after:Function = null) : void
      {
         var f:File = File.documentsDirectory;
         try
         {
            f.addEventListener(Event.SELECT,function(e:Event):void
            {
               var picked:File = e.target as File;
               var r:Object = importFile(picked);
               if(after != null)
               {
                  after(r);
               }
            });
            f.browseForOpen("A .bmod mod",[new FileFilter("Brawlhalla mods (*.bmod)","*.bmod"),new FileFilter("All files","*.*")]);
         }
         catch(e:Error)
         {
            Modal.show("Import .bmod","The file dialog couldn't open: " + e.message);
         }
      }

      public static function importFile(picked:File) : Object
      {
         var r:Object;
         try
         {
            var root:File = modsFolder();
            if(!root.exists)
            {
               root.createDirectory();
            }
            var target:File = picked;
            if(picked.parent == null || picked.parent.nativePath != root.nativePath)
            {
               target = root.resolvePath(picked.name);
               if(target.exists)
               {
                  if(sameBytes(readFile(target),readFile(picked)))
                  {
                     target = root.resolvePath(picked.name);
                  }
                  else
                  {
                     var base:String = picked.name.substr(0,picked.name.length - 5);
                     for(var k:int = 2; target.exists; k++)
                     {
                        target = root.resolvePath(base + " (" + k + ").bmod");
                     }
                     picked.copyTo(target,false);
                  }
               }
               else
               {
                  picked.copyTo(target,false);
               }
            }
            r = process(target,true);
         }
         catch(e:Error)
         {
            r = {"file":picked.name,"ok":false,"tell":true,"why":"it couldn't be copied into the mods folder (" + e.message + ")"};
         }
         tell([r]);
         return r;
      }

      private static var waiting:Array = [];

      private static function tellWhenFree() : void
      {
         if(!menuFree() || Busy.waiting("bmod"))
         {
            return;
         }
         Hooks.frameStarting.remove(tellWhenFree);
         var told:Array = waiting;
         waiting = [];
         tell(told);
      }

      private static function tell(told:Array) : void
      {
         if(told.length == 0)
         {
            return;
         }
         var good:Array = [];
         var bad:Array = [];
         var restart:int = 0;
         var ready:int = 0;
         for each(var r:Object in told)
         {
            if(r.ok)
            {
               good.push(r.message);
               if(!r.live)
               {
                  restart++;
               }
               else
               {
                  ready++;
               }
            }
            else
            {
               bad.push(r.file + " wasn't converted: " + r.why + ".");
            }
         }
         var text:String = good.join(" ");
         if(restart > 0)
         {
            text += ready > 0 ? " The rest load when the game restarts." :
               (restart > 1 ? " They load when the game restarts." : " It loads when the game restarts.");
         }
         if(bad.length > 0)
         {
            text += (text != "" ? " " : "") + bad.join(" ") + (bad.length > 1 ?
               " They stay in the mods folder and aren't tried again until they change." :
               " It stays in the mods folder and isn't tried again until it changes.");
         }
         Modal.show(good.length + bad.length > 1 ? "Mods imported" : (good.length > 0 ? "Mod imported" : "Mod not imported"),text,null,
            told.length > 2);
      }

      private static function memory() : Object
      {
         try
         {
            var f:File = Platform.dataFile(MEMORY);
            if(f.exists)
            {
               var data:Object = JSON.parse(readText(f));
               if(data != null && typeof data == "object")
               {
                  return data;
               }
            }
         }
         catch(e:Error)
         {
         }
         return {};
      }

      private static function remember(hash:String, entry:Object) : void
      {
         try
         {
            var data:Object = memory();
            data[hash] = entry;
            writeText(Platform.dataFile(MEMORY),JSON.stringify(data));
         }
         catch(e:Error)
         {
         }
      }

      public static function hashOf(data:ByteArray) : String
      {
         var h:int = 17;
         var g:int = 0;
         data.position = 0;
         data.endian = Endian.LITTLE_ENDIAN;
         while(data.bytesAvailable >= 4)
         {
            var v:int = data.readInt();
            h = ((h << 5) - h) + v;
            g = (g ^ v) + ((g << 3) | (g >>> 29));
         }
         while(data.bytesAvailable > 0)
         {
            h = ((h << 5) - h) + data.readUnsignedByte();
         }
         data.position = 0;
         return hex8(h) + hex8(g) + "-" + data.length;
      }

      private static function hexDigits(v:int, count:int) : String
      {
         var s:String = "";
         for(var i:int = count - 1; i >= 0; i--)
         {
            s += "0123456789abcdef".charAt((v >>> (i * 4)) & 0xF);
         }
         return s;
      }

      private static function hex8(v:int) : String
      {
         return hexDigits(v,8);
      }

      private static function sourceOf(dir:File) : Object
      {
         try
         {
            var m:File = dir.resolvePath("mod.json");
            if(m.exists)
            {
               var data:Object = JSON.parse(readText(m));
               return data != null ? data.source : null;
            }
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private static function importedAs(hash:String) : File
      {
         var root:File = modsFolder();
         if(!root.exists)
         {
            return null;
         }
         for each(var dir:File in root.getDirectoryListing())
         {
            if(!dir.isDirectory)
            {
               continue;
            }
            var src:Object = sourceOf(dir);
            if(src != null && src.hash == hash)
            {
               return dir;
            }
         }
         return null;
      }

      private static function asideOf(dir:File, folder:String) : File
      {
         var root:File = new File(modsFolder().parent.nativePath).resolvePath(folder);
         if(!root.exists)
         {
            root.createDirectory();
         }
         var target:File = root.resolvePath(dir.name);
         for(var n:int = 2; target.exists; n++)
         {
            target = root.resolvePath(dir.name + "-" + n);
         }
         return target;
      }

      public static function process(file:File, explicit:Boolean) : Object
      {
         var started:int = getTimer();
         var name:String = file.name;
         var r:Object = {"file":name,"ok":false,"tell":true,"live":false};
         report = [];
         madeFolder = null;
         movedAside = null;
         var data:ByteArray;
         try
         {
            data = readFile(file);
         }
         catch(e:Error)
         {
            r.why = "it couldn't be read (" + e.message + ")";
            finish(r,started);
            return r;
         }
         var hash:String = hashOf(data);
         r.hash = hash;
         var already:File = importedAs(hash);
         if(already != null)
         {
            r.ok = true;
            r.already = true;
            r.tell = explicit;
            r.folder = already.name;
            r.message = name + " is already imported.";
            r.live = true;
            moveInto(file,already);
            finish(r,started);
            return r;
         }
         var past:Object = memory()[hash];
         if(!explicit && past != null && int(past.converter) == CONVERTER)
         {
            r.why = String(past.why);
            r.tell = false;
            r.skipped = true;
            finish(r,started);
            return r;
         }
         try
         {
            var out:Object = convert(file,data,hash);
            r.ok = true;
            r.folder = out.folder.name;
            r.id = out.id;
            r.kind = out.kind;
            r.message = out.message;
            r.live = out.live;
            moveInto(file,out.folder);
            if(ModSettings.isDisabled(out.id))
            {
               ModSettings.setDisabled(out.id,false);
            }
         }
         catch(e2:Error)
         {
            r.why = e2.message;
            undo();
            remember(hash,{"file":name,"why":e2.message,"converter":CONVERTER});
            report.push("bmod " + name + " error: " + e2.getStackTrace());
         }
         csvCache = {};
         effectNames = null;
         finish(r,started);
         return r;
      }

      private static function undo() : void
      {
         try
         {
            if(madeFolder != null && madeFolder.exists)
            {
               madeFolder.deleteDirectory(true);
               report.push("the half-written mods\\" + madeFolder.name + " removed");
            }
            if(movedAside != null)
            {
               (movedAside[0] as File).moveTo(movedAside[1] as File,false);
               report.push("the earlier mods\\" + (movedAside[1] as File).name + " put back");
            }
         }
         catch(e:Error)
         {
            report.push("couldn't undo: " + e.message);
         }
         madeFolder = null;
         movedAside = null;
      }

      private static function finish(r:Object, started:int) : void
      {
         var ms:int = getTimer() - started;
         r.ms = ms;
         var line:String = "bmod " + r.file + ": " + (r.skipped ? "not converted before (" + r.why + "), not tried again" :
            (r.already ? "already imported as mods\\" + r.folder : (r.ok ? "converted to mods\\" + r.folder + " (" + r.kind + ") in " + ms +
            " ms" : "not converted: " + r.why)));
         lines.push(line);
         results.push(r);
         ContentMods.report.push(line);
         for each(var more:String in report)
         {
            ContentMods.report.push("  " + more);
            lines.push("  " + more);
         }
         ContentMods.writeReport();
      }

      private static function moveInto(file:File, folder:File) : void
      {
         try
         {
            var target:File = folder.resolvePath(file.name);
            if(target.exists)
            {
               target.deleteFile();
            }
            file.moveTo(target,false);
         }
         catch(e:Error)
         {
            report.push("the .bmod stays in the mods folder: " + e.message);
         }
      }

      private static function convert(file:File, data:ByteArray, hash:String) : Object
      {
         var mod:Object;
         try
         {
            mod = BmodSwf.readBmod(data);
         }
         catch(e:Error)
         {
            throw new Error("it isn't a .bmod this can read (" + e.message + ")");
         }
         mod.fileName = file.name;
         mod.stem = file.name.substr(0,file.name.length - 5);
         mod.source = {"file":file.name,"hash":hash,"size":data.length,"converter":"Bifrost " + CONVERTER};
         var meta:Object = mod.meta;
         var names:Array = spriteNames(meta);
         var files:Object = meta.files != null ? meta.files : {};
         var fileNames:Array = [];
         for(var k:String in files)
         {
            fileNames.push(String(files[k]));
         }
         var avatar:Boolean = false;
         for each(var n:String in names)
         {
            if(starts(n,"a_AvatarIcon_"))
            {
               avatar = true;
            }
         }
         if(names.length == 0)
         {
            for each(n in fileNames)
            {
               if(starts(n,"a_AvatarIcon_") || starts(n,"a_Flag"))
               {
                  avatar = true;
               }
            }
         }
         if(avatar)
         {
            return importAvatars(mod);
         }
         if(names.length == 0 && fileNames.length > 0)
         {
            return importMapArt(mod);
         }
         if(names.length == 0)
         {
            throw new Error("it redraws no sprites and has no files; only skins, weapon skins, map art and avatars can be imported");
         }
         return importItem(mod,names);
      }

      private static function spriteNames(meta:Object) : Array
      {
         var seen:Object = {};
         var out:Array = [];
         var swfs:Object = meta.swfs != null ? meta.swfs : {};
         for(var swf:String in swfs)
         {
            for each(var s:String in swfs[swf].sprites)
            {
               if(!(("n" + s) in seen))
               {
                  seen["n" + s] = true;
                  out.push(s);
               }
            }
         }
         out.sort();
         return out;
      }

      private static function starts(s:String, prefix:String) : Boolean
      {
         return s != null && s.substr(0,prefix.length) == prefix;
      }

      private static function ends(s:String, suffix:String) : Boolean
      {
         return s != null && s.length >= suffix.length && s.substr(s.length - suffix.length) == suffix;
      }

      private static function lower(s:String) : String
      {
         return s == null ? "" : s.toLowerCase();
      }

      private static function trim(s:String) : String
      {
         if(s == null)
         {
            return "";
         }
         var a:int = 0;
         var b:int = s.length;
         while(a < b && " \t\r\n".indexOf(s.charAt(a)) >= 0)
         {
            a++;
         }
         while(b > a && " \t\r\n".indexOf(s.charAt(b - 1)) >= 0)
         {
            b--;
         }
         return s.substring(a,b);
      }

      private static function replaceAll(s:String, from:String, to:String) : String
      {
         return s.split(from).join(to);
      }

      private static function hex6(c:int) : String
      {
         return hexDigits(c,6);
      }

      private static function upperHex(c:int) : String
      {
         return "0x" + hex6(c).toUpperCase();
      }

      private static function splitLine(line:String) : Array
      {
         if(line.indexOf("\"") < 0)
         {
            return line.split(",");
         }
         return ContentMods.splitCsv(line);
      }

      private static function csvLines(name:String) : Array
      {
         var text:String = csvTexts[lower(name)];
         if(text == null)
         {
            throw new Error("the game's " + name + " table wasn't read at start-up");
         }
         var out:Array = text.split("\n");
         for(var i:int = 0; i < out.length; i++)
         {
            var line:String = out[i];
            if(line.length > 0 && line.charAt(line.length - 1) == "\r")
            {
               out[i] = line.substr(0,line.length - 1);
            }
         }
         return out;
      }

      private static function table(name:String) : Object
      {
         if(name in csvCache)
         {
            return csvCache[name];
         }
         var raw:Array = csvLines(name);
         var header:Array = splitLine(raw[0]);
         var rows:Array = [];
         for(var i:int = 1; i < raw.length; i++)
         {
            var line:String = raw[i];
            if(line == "")
            {
               continue;
            }
            var fields:Array = splitLine(line);
            if(fields[0] == "" || fields[0] == "Template")
            {
               continue;
            }
            rows.push(rowOf(header,fields));
         }
         var t:Object = {"header":header,"rows":rows};
         csvCache[name] = t;
         return t;
      }

      private static function rowOf(header:Array, fields:Array) : Object
      {
         var row:Object = {};
         var count:int = header.length < fields.length ? header.length : fields.length;
         for(var c:int = 0; c < count; c++)
         {
            row["c" + header[c]] = fields[c];
         }
         return row;
      }

      private static function cell(row:Object, column:String) : String
      {
         var v:* = row["c" + column];
         return v == null ? "" : String(v);
      }

      private static function clearCell(sets:BmodMap, header:Array, row:Object, column:String) : Boolean
      {
         if(header.indexOf(column) < 0 || trim(cell(row,column)) == "")
         {
            return false;
         }
         sets.set(column,"@none");
         return true;
      }

      private static function hasCell(row:Object, column:String) : Boolean
      {
         var k:String = "c" + column;
         var found:Boolean = k in row;
         return found;
      }

      private static function suffixes(row:Object, columns:Array) : BmodMap
      {
         var out:BmodMap = new BmodMap();
         for each(var col:String in columns)
         {
            var value:String = trim(cell(row,col));
            if(value.indexOf("/") >= 0)
            {
               var parts:Array = value.split(":");
               var last:String = parts[parts.length - 1];
               var slash:int = last.indexOf("/");
               if(slash < 0)
               {
                  continue;
               }
               var s:String = last.substr(slash + 1);
               if(!out.has(s))
               {
                  out.set(s,col);
               }
            }
         }
         return out;
      }

      private static function commonPart(words:Array) : String
      {
         var first:String = words[0];
         for each(var w:String in words)
         {
            if(w.length < first.length)
            {
               first = w;
            }
         }
         for(var size:int = first.length; size > 0; size--)
         {
            for(var start:int = 0; start <= first.length - size; start++)
            {
               var part:String = first.substr(start,size);
               var all:Boolean = true;
               for each(w in words)
               {
                  if(w.indexOf(part) < 0)
                  {
                     all = false;
                     break;
                  }
               }
               if(all)
               {
                  return part;
               }
            }
         }
         return first;
      }

      public static function tokenFor(name:String) : String
      {
         var joined:String = "";
         var word:String = "";
         for(var i:int = 0; i <= name.length; i++)
         {
            var ch:String = i < name.length ? name.charAt(i) : "";
            if(ch != "" && ((ch >= "A" && ch <= "Z") || (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9")))
            {
               word += ch;
               continue;
            }
            if(word != "")
            {
               joined += word.substr(0,1).toUpperCase() + word.substr(1);
               word = "";
            }
         }
         return "BH" + joined.substr(0,40);
      }

      public static function modIdOf(token:String) : String
      {
         var id:String = ("bmod-" + token.substr(2)).toLowerCase().replace(/[^a-z0-9._-]+/g,"-");
         while(id.charAt(0) == "-")
         {
            id = id.substr(1);
         }
         while(id.length > 0 && id.charAt(id.length - 1) == "-")
         {
            id = id.substr(0,id.length - 1);
         }
         return id;
      }

      private static function compareKeys(a:Array, b:Array) : int
      {
         for(var i:int = 0; i < a.length; i++)
         {
            var x:* = a[i];
            var y:* = b[i];
            if(x is String)
            {
               if(String(x) < String(y))
               {
                  return -1;
               }
               if(String(x) > String(y))
               {
                  return 1;
               }
            }
            else
            {
               if(Number(x) < Number(y))
               {
                  return -1;
               }
               if(Number(x) > Number(y))
               {
                  return 1;
               }
            }
         }
         return 0;
      }

      private static function stableSort(list:Array, keys:Array, reverse:Boolean) : Array
      {
         var idx:Array = [];
         for(var i:int = 0; i < list.length; i++)
         {
            idx.push(i);
         }
         idx.sort(function(a:int, b:int):int
         {
            var c:int = compareKeys(keys[a],keys[b]);
            if(reverse)
            {
               c = -c;
            }
            return c != 0 ? c : a - b;
         });
         var out:Array = [];
         for each(var j:int in idx)
         {
            out.push(list[j]);
         }
         return out;
      }

      private static function findItem(names:Array) : Object
      {
         var candidates:Array = [];
         var keys:Array = [];
         for each(var spec:Array in [["costumeTypes",COSTUME_ART,COSTUME_SWAP],["weaponSkinTypes",WEAPON_ART,[]]])
         {
            var tname:String = spec[0];
            var t:Object = table(tname);
            var header:Array = t.header;
            var columns:Array = (spec[1] as Array).concat(spec[2] as Array);
            for each(var row:Object in t.rows)
            {
               var found:BmodMap = suffixes(row,columns);
               if(found.length == 0)
               {
                  continue;
               }
               var hits:BmodMap = new BmodMap();
               var score:int = 0;
               for each(var s:String in found.keys)
               {
                  var list:Array = [];
                  for each(var n:String in names)
                  {
                     if(ends(n,"_" + s))
                     {
                        list.push(n);
                     }
                  }
                  if(list.length > 0)
                  {
                     hits.set(s,list);
                     score += list.length;
                  }
               }
               if(hits.length == 0)
               {
                  continue;
               }
               var weapon:String = cell(row,"BaseWeapon");
               var bonus:int = 0;
               if(tname == "weaponSkinTypes" && weapon != "")
               {
                  for each(n in names)
                  {
                     if(n.indexOf(weapon) >= 0)
                     {
                        bonus++;
                     }
                  }
               }
               var isCostume:int = tname == "costumeTypes" ? 1 : 0;
               candidates.push({"table":tname,"key":cell(row,header[0]),"row":row,"header":header,"hits":hits,"columns":found});
               keys.push([score,isCostume,bonus]);
            }
         }
         if(candidates.length == 0)
         {
            throw new Error("no skin or weapon skin uses the suffixes of its sprites, so it isn't a skin or weapon skin this game has");
         }
         return stableSort(candidates,keys,true)[0];
      }

      private static function gameFile(name:String) : File
      {
         var app:File = File.applicationDirectory;
         var f:File = app.resolvePath(name);
         if(f.exists)
         {
            return f;
         }
         f = app.resolvePath("bones/" + name);
         return f.exists ? f : null;
      }

      private static function gameColours(swfNames:Array) : Object
      {
         var into:Object = {};
         for each(var name:String in swfNames)
         {
            var f:File = gameFile(name);
            if(f == null)
            {
               continue;
            }
            try
            {
               BmodSwf.abcClasses(BmodSwf.read(readFile(f)).tags,into);
            }
            catch(e:Error)
            {
               report.push("game colours from " + name + " not read: " + e.message);
            }
         }
         return into;
      }

      private static function hls(c:int) : Array
      {
         var r:Number = ((c >> 16) & 0xFF) / 255;
         var g:Number = ((c >> 8) & 0xFF) / 255;
         var b:Number = (c & 0xFF) / 255;
         var maxc:Number = Math.max(r,Math.max(g,b));
         var minc:Number = Math.min(r,Math.min(g,b));
         var sumc:Number = maxc + minc;
         var rangec:Number = maxc - minc;
         var l:Number = sumc / 2;
         if(minc == maxc)
         {
            return [0,l,0];
         }
         var s:Number = l <= 0.5 ? rangec / sumc : rangec / (2 - maxc - minc);
         var rc:Number = (maxc - r) / rangec;
         var gc:Number = (maxc - g) / rangec;
         var bc:Number = (maxc - b) / rangec;
         var h:Number;
         if(r == maxc)
         {
            h = bc - gc;
         }
         else if(g == maxc)
         {
            h = 2 + rc - bc;
         }
         else
         {
            h = 4 + gc - rc;
         }
         h = mod1(h / 6);
         return [h,l,s];
      }

      private static function mod1(x:Number) : Number
      {
         return x - Math.floor(x);
      }

      private static function hueGap(a:Number, b:Number) : Number
      {
         var d:Number = mod1(Math.abs(a - b));
         return Math.min(d,1 - d);
      }

      private static function isSkin(c:int) : Boolean
      {
         var v:Array = hls(c);
         return v[0] <= 50 / 360 && v[2] >= 0.2 && v[1] >= 0.45 && v[1] <= 0.97;
      }

      private static function partOf(bone:String) : String
      {
         return starts(bone,"a_") ? bone.substr(2) : bone;
      }

      private static function skinTones(spriteColours:BmodMap) : Array
      {
         var useMap:BmodMap = new BmodMap();
         for each(var bone:String in spriteColours.keys)
         {
            var part:String = partOf(bone);
            if(starts(part,"Eyes") || starts(part,"Mouth") || starts(part,"Weapon"))
            {
               continue;
            }
            var colours:BmodMap = spriteColours.get(bone);
            for each(var c:* in colours.keys)
            {
               if(isSkin(int(c)))
               {
                  useMap.add(c,Number(colours.get(c)));
               }
            }
         }
         if(useMap.length == 0)
         {
            return null;
         }
         var light:int = -1;
         var bestUse:Number = -1;
         var bestTie:Number = 0;
         for each(c in useMap.keys)
         {
            var u:Number = useMap.get(c);
            var tie:Number = -Math.abs(hls(int(c))[1] - 0.75);
            if(light < 0 || u > bestUse || (u == bestUse && tie > bestTie))
            {
               light = int(c);
               bestUse = u;
               bestTie = tie;
            }
         }
         var dark:int = 0;
         for each(var shift:int in [16,8,0])
         {
            dark = dark | (int(BmodSwf.pyRound(((light >> shift) & 0xFF) * 0.8)) << shift);
         }
         return [light,dark];
      }

      private static function levelsFor(family:Array, count:int) : Array
      {
         var names:Array = family[1];
         var base:int = names.indexOf(family[0]);
         count = int(Math.min(count,names.length));
         var start:int = int(Math.max(0,Math.min(base - Math.floor((count - 1) / 2),names.length - count)));
         return names.slice(start,start + count);
      }

      private static function buildPalette(spriteColours:BmodMap) : Object
      {
         var useMap:BmodMap = new BmodMap();
         var hair:BmodMap = new BmodMap();
         var parts:Object = {};
         for each(var bone:String in spriteColours.keys)
         {
            var part:String = partOf(bone);
            if(starts(part,"Weapon"))
            {
               continue;
            }
            var colours:BmodMap = spriteColours.get(bone);
            for each(var c:* in colours.keys)
            {
               var n:Number = colours.get(c);
               useMap.add(c,n);
               if(!(("p" + c) in parts))
               {
                  parts["p" + c] = [];
               }
               if((parts["p" + c] as Array).indexOf(part) < 0)
               {
                  (parts["p" + c] as Array).push(part);
               }
               if(starts(part,"Hair"))
               {
                  hair.add(c,n);
               }
            }
         }
         var familyOf:BmodMap = new BmodMap();
         var saturated:Array = [];
         for each(c in useMap.keys)
         {
            var v:Array = hls(int(c));
            if(v[1] < 0.1 || (v[1] > 0.93 && v[2] < 0.25) || isSkin(int(c)))
            {
               continue;
            }
            var faceOnly:Boolean = true;
            for each(var p:String in parts["p" + c])
            {
               if(!(starts(p,"Eyes") || starts(p,"Mouth")))
               {
                  faceOnly = false;
               }
            }
            if(faceOnly)
            {
               continue;
            }
            if(v[2] < 0.15)
            {
               familyOf.set(c,"Cloth");
            }
            else if((hair.has(c) ? Number(hair.get(c)) : 0) * 2 > Number(useMap.get(c)))
            {
               familyOf.set(c,"Hair");
            }
            else
            {
               saturated.push(c);
            }
         }
         var keys:Array = [];
         for each(c in saturated)
         {
            keys.push([-Number(useMap.get(c))]);
         }
         saturated = stableSort(saturated,keys,false);
         var groups:Array = [];
         for each(c in saturated)
         {
            var h:Number = hls(int(c))[0];
            var placed:Boolean = false;
            for each(var g:Array in groups)
            {
               if(hueGap(h,hls(int(g[0]))[0]) <= 35 / 360)
               {
                  g.push(c);
                  placed = true;
                  break;
               }
            }
            if(!placed)
            {
               groups.push([c]);
            }
         }
         keys = [];
         for each(g in groups)
         {
            var sum:Number = 0;
            for each(c in g)
            {
               sum += Number(useMap.get(c));
            }
            keys.push([-sum]);
         }
         groups = stableSort(groups,keys,false);
         var roles:Array = ["Body1","Body2","Special"];
         for(var gi:int = 0; gi < groups.length && gi < roles.length; gi++)
         {
            for each(c in groups[gi])
            {
               familyOf.set(c,roles[gi]);
            }
         }
         var defines:BmodMap = new BmodMap();
         var table:BmodMap = new BmodMap();
         var notes:Array = [];
         for each(var family:Array in FAMILIES)
         {
            var members:Array = [];
            for each(c in familyOf.keys)
            {
               if(familyOf.get(c) == family[0])
               {
                  members.push(c);
               }
            }
            if(members.length == 0)
            {
               continue;
            }
            keys = [];
            for each(c in members)
            {
               keys.push([hls(int(c))[1]]);
            }
            members = stableSort(members,keys,true);
            var distinct:int = 0;
            var last:Number = NaN;
            for each(c in members)
            {
               var l:Number = hls(int(c))[1];
               if(isNaN(last) || last - l >= 0.08)
               {
                  distinct++;
                  last = l;
               }
            }
            var levels:Array = levelsFor(family,distinct > 1 ? distinct : 1);
            var anchors:Array = [];
            for(var i:int = 0; i < levels.length; i++)
            {
               var lo:int = int(Math.floor(i * members.length / levels.length));
               var hi:int = int(Math.floor((i + 1) * members.length / levels.length));
               var anchor:* = null;
               for(var j:int = lo; j < hi; j++)
               {
                  if(anchor == null || Number(useMap.get(members[j])) > Number(useMap.get(anchor)))
                  {
                     anchor = members[j];
                  }
               }
               anchors.push(anchor);
               defines.set(levels[i],int(anchor));
            }
            for each(c in members)
            {
               var cv:Array = hls(int(c));
               var best:* = null;
               var bestScore:Number = 0;
               for each(var a:* in anchors)
               {
                  var av:Array = hls(int(a));
                  var score:Number = Math.abs(av[1] - cv[1]) + 2 * hueGap(av[0],cv[0]);
                  if(best == null || score < bestScore)
                  {
                     best = a;
                     bestScore = score;
                  }
               }
               var bv:Array = hls(int(best));
               var dh:Number = mod1(cv[0] - bv[0] + 0.5) - 0.5;
               table.set(int(c),[int(best),dh,cv[1] - bv[1],cv[2] - bv[2]]);
            }
            var described:Array = [];
            for(i = 0; i < levels.length; i++)
            {
               described.push(levels[i] + " " + hex6(int(anchors[i])));
            }
            notes.push(family[0] + ": " + members.length + " shades on " + described.join(", "));
         }
         var left:int = 0;
         for each(c in useMap.keys)
         {
            if(!familyOf.has(c))
            {
               left++;
            }
         }
         if(notes.length > 0 || left > 0)
         {
            notes.push("left as drawn: " + left + " colours (outlines, whites, skin, eyes and mouths)");
         }
         return {"defines":defines,"table":table,"notes":notes};
      }

      private static function headshotPose() : Array
      {
         if(boneNames == null)
         {
            return [];
         }
         var f:File = File.applicationDirectory.resolvePath("anims/Animation_Player.anm");
         if(!f.exists)
         {
            return [];
         }
         var bones:Array = BmodSwf.headshotFrame(readFile(f));
         if(bones == null)
         {
            return [];
         }
         var known:Object = {};
         for each(var bn:String in boneNames)
         {
            known["b" + bn] = true;
         }
         var pose:Array = [];
         var m:Array = [1,0,0,1];
         var pos:Array = [0,0];
         for each(var bone:Object in bones)
         {
            if(bone.dup)
            {
               return [];
            }
            if(bone.transform != "prev" && bone.m is Array)
            {
               m = bone.m;
            }
            if(bone.pos != "prev")
            {
               pos = bone.pos;
            }
            var index:int = int(bone.id) - 1;
            if(index < 0 || index >= boneNames.length)
            {
               return [];
            }
            var name:String = boneNames[index];
            if(ends(name,"R") && (("b" + name.substr(0,name.length - 1)) in known))
            {
               continue;
            }
            if(m.length < 4)
            {
               return [];
            }
            pose.push([name,[m[0],m[1],m[2],m[3],pos[0],pos[1]]]);
         }
         return pose;
      }

      private static function sfxHas(name:String) : Boolean
      {
         if(effectNames == null)
         {
            effectNames = {};
            var app:File = File.applicationDirectory;
            for each(var f:File in app.getDirectoryListing())
            {
               if(f.isDirectory || f.name.substr(0,4) != "SFX_" || lower(f.name).substr(-4) != ".swf")
               {
                  continue;
               }
               try
               {
                  for each(var entry:Array in BmodSwf.symbols(BmodSwf.read(readFile(f)).tags))
                  {
                     effectNames["e" + entry[1]] = true;
                  }
               }
               catch(e:Error)
               {
               }
            }
         }
         var k:String = "e" + name;
         var found:Boolean = k in effectNames;
         return found;
      }

      private static function modSwf(mod:Object, art:Array, classes:Array, colours:Object, symbols:ByteArray) : ByteArray
      {
         var attrs:ByteArray = new ByteArray();
         attrs.writeByte(0x08);
         attrs.writeByte(0);
         attrs.writeByte(0);
         attrs.writeByte(0);
         var white:ByteArray = new ByteArray();
         white.writeByte(255);
         white.writeByte(255);
         white.writeByte(255);
         var abc:ByteArray = new ByteArray();
         abc.writeByte(1);
         abc.writeByte(0);
         abc.writeByte(0);
         abc.writeByte(0);
         abc.writeByte(0);
         abc.writeBytes(BmodSwf.abcBlock(classes,colours));
         var tags:Array = [BmodSwf.tag(BmodSwf.FILE_ATTRIBUTES,attrs),BmodSwf.tag(BmodSwf.SET_BACKGROUND,white)];
         tags = tags.concat(art);
         tags.push(BmodSwf.tag(BmodSwf.DO_ABC,abc));
         tags.push(BmodSwf.tag(BmodSwf.SYMBOL_CLASS,symbols));
         tags.push(BmodSwf.tag(BmodSwf.SHOW_FRAME,new ByteArray()));
         tags.push(BmodSwf.tag(BmodSwf.END,new ByteArray()));
         var header:Object = {"version":int(mod.version) > 15 ? int(mod.version) : 15,"rect":mod.rect,"rate":mod.rate,"count":1};
         return BmodSwf.write(header,tags);
      }

      private static function copiedArt(mod:Object) : Array
      {
         var art:Array = [];
         for each(var t:Object in mod.tags)
         {
            if(BmodSwf.NOT_COPIED.indexOf(int(t.code)) < 0)
            {
               art.push(t);
            }
         }
         return BmodSwf.fixShapes(art);
      }

      private static function modFiles(mod:Object) : Array
      {
         var data:Object = BmodSwf.binaryData(mod.tags);
         var files:Object = mod.meta.files != null ? mod.meta.files : {};
         var ids:Array = [];
         for(var k:String in files)
         {
            ids.push(int(k));
         }
         ids.sort(Array.NUMERIC);
         var out:Array = [];
         for each(var id:int in ids)
         {
            if(("b" + id) in data)
            {
               out.push([id,String(files[String(id)]),data["b" + id]]);
            }
         }
         return out;
      }

      private static function writePreview(mod:Object, folder:File, manifest:BmodMap) : void
      {
         var previews:Object = mod.meta.previewsIds != null ? mod.meta.previewsIds : {};
         var data:Object = BmodSwf.binaryData(mod.tags);
         var ids:Array = [];
         for(var k:String in previews)
         {
            ids.push(int(k));
         }
         ids.sort(Array.NUMERIC);
         for each(var id:int in ids)
         {
            var ext:String = String(previews[String(id)]);
            if(("b" + id) in data && (ext == "png" || ext == "jpg" || ext == "jpeg"))
            {
               var name:String = "preview." + ext;
               writeTag(folder,name,data["b" + id]);
               manifest.set("preview",name);
               return;
            }
         }
      }

      private static function cleanText(text:String) : String
      {
         text = (text != null ? text : "").replace(/<el>\s*/g,"- ");
         text = text.replace(/<\/el>/g,"\n");
         text = text.replace(/<[^>]+>/g,"");
         text = text.replace(/\n{3,}/g,"\n\n");
         return trim(text);
      }

      private static function newFolder(id:String) : File
      {
         var root:File = modsFolder();
         if(!root.exists)
         {
            root.createDirectory();
         }
         var folder:File = root.resolvePath(id);
         if(folder.exists)
         {
            var aside:File = asideOf(folder,"mods-replaced");
            folder.moveTo(aside,false);
            movedAside = [aside,root.resolvePath(id)];
            report.push("the earlier mods\\" + folder.name + " moved to " + aside.nativePath);
            folder = root.resolvePath(id);
         }
         folder.createDirectory();
         madeFolder = folder;
         return folder;
      }

      private static function importItem(mod:Object, names:Array) : Object
      {
         var meta:Object = mod.meta;
         var swfs:Object = meta.swfs != null ? meta.swfs : {};
         var item:Object = findItem(names);
         var hits:BmodMap = item.hits;
         var matched:int = 0;
         var s:String;
         var n:String;
         for each(s in hits.keys)
         {
            matched += (hits.get(s) as Array).length;
         }
         if(matched * 2 < names.length)
         {
            throw new Error("only " + matched + " of its " + names.length + " sprites are named after one item (" + item.table + "/" +
               item.key + "), so it doesn't look like a skin or weapon skin");
         }
         var isCostume:Boolean = item.table == "costumeTypes";
         var core:String = commonPart(hits.keys);
         var display:String = meta.name != null && meta.name != "" ? String(meta.name) : String(mod.stem);
         var token:String = tokenFor(display);
         var newSuffix:BmodMap = new BmodMap();
         for each(s in hits.keys)
         {
            newSuffix.set(s,replaceAll(s,core,token));
         }
         var rename:BmodMap = new BmodMap();
         for each(s in hits.keys)
         {
            for each(n in hits.get(s))
            {
               if(!rename.has(n))
               {
                  rename.set(n,n.substr(0,n.length - s.length) + newSuffix.get(s));
               }
            }
         }
         var bodySuffix:String = null;
         for each(s in hits.keys)
         {
            if(!starts(s,"Swap"))
            {
               bodySuffix = s;
               break;
            }
         }
         var bodyNew:String = bodySuffix != null ? newSuffix.get(bodySuffix) : null;
         var rosterPose:String = null;
         var rosterGem:String = null;
         if(isCostume)
         {
            for each(n in names)
            {
               if(starts(n,"a_Roster_Pose_"))
               {
                  rename.set(n,"a_Roster_Pose_" + token + (ends(n,"M") ? "M" : ""));
                  rosterPose = "a_Roster_Pose_" + token;
               }
               else if(starts(n,"a_Roster_Gem_"))
               {
                  rosterGem = "a_Roster_Gem_" + token;
                  rename.set(n,rosterGem);
               }
            }
         }
         if(isCostume && bodyNew != null)
         {
            for each(n in names)
            {
               if(!rename.has(n) && n.indexOf("_Swap") < 0)
               {
                  rename.set(n,n + "_" + bodyNew);
               }
            }
         }
         var skipped:Array = [];
         for each(n in names)
         {
            if(!rename.has(n))
            {
               skipped.push(n);
            }
         }
         var byId:Object = {};
         for each(var sym:Array in mod.symbols)
         {
            byId["n" + sym[1]] = int(sym[0]);
         }
         var missing:Array = [];
         for each(n in rename.keys.concat())
         {
            if(!(("n" + n) in byId))
            {
               missing.push(n);
               rename.remove(n);
            }
         }
         var swfNames:Array = [];
         for(var swfName:String in swfs)
         {
            swfNames.push(swfName);
         }
         var colours:Object = gameColours(swfNames);
         var row:Object = item.row;
         var newDefines:BmodMap = new BmodMap();
         var paletteTable:BmodMap = new BmodMap();
         var handColours:Array = [];
         var animationAliases:BmodMap = null;
         var crossoverName:String = null;
         var weaponRows:Array = [];
         var weaponStrings:BmodMap = new BmodMap();
         var modSymbols:BmodMap = BmodSwf.symbolColours(mod.tags);
         var body:BmodMap = new BmodMap();
         for each(var old:String in rename.keys)
         {
            if(colours["c" + old] != null && modSymbols.has(old))
            {
               var suffix:String = null;
               for each(s in hits.keys)
               {
                  if(ends(old,"_" + s))
                  {
                     suffix = s;
                     break;
                  }
               }
               if(suffix != null)
               {
                  body.set(old.substr(0,old.length - suffix.length - 1),modSymbols.get(old));
               }
            }
         }
         if(body.length > 0)
         {
            var built:Object = buildPalette(body);
            newDefines = built.defines;
            paletteTable = built.table;
            for each(var note:String in built.notes)
            {
               report.push("palette " + note);
            }
         }
         var skin:Array = skinTones(body);
         if(skin != null && isCostume)
         {
            handColours = [["HandsLt_Swap",skin[0]],["HandsDk_Swap",skin[1]],["HandsSkinLt_Swap",skin[0]],["HandsSkinDk_Swap",skin[1]]];
            report.push("hands in the skin tone " + hex6(skin[0]) + " / " + hex6(skin[1]));
         }
         var classNames:Array = [];
         var classColours:Object = {};
         var sortedOld:Array = rename.keys.concat();
         sortedOld.sort();
         for each(old in sortedOld)
         {
            var cls:String = rename.get(old);
            classNames.push(cls);
            if(colours["c" + old] == null)
            {
               classColours["c" + cls] = null;
               continue;
            }
            var anchors:Array = [];
            var oldColours:BmodMap = modSymbols.has(old) ? modSymbols.get(old) : new BmodMap();
            for each(var c:* in oldColours.keys)
            {
               if(paletteTable.has(c))
               {
                  var anchor:int = int(paletteTable.get(c)[0]);
                  if(anchors.indexOf(anchor) < 0)
                  {
                     anchors.push(anchor);
                  }
               }
            }
            anchors.sort(Array.NUMERIC);
            classColours["c" + cls] = anchors;
         }
         var swfFile:String = "Bones_" + token + ".swf";
         var fixedArt:Array = copiedArt(mod);
         var art:Array = fixedArt[0];
         if(int(fixedArt[1]) > 0)
         {
            report.push(fixedArt[1] + " shapes declare styles mid-shape as DefineShape; made DefineShape2");
         }
         var symbolList:Array = [];
         for each(old in sortedOld)
         {
            symbolList.push([byId["n" + old],rename.get(old)]);
         }
         var iconName:String = null;
         if(isCostume)
         {
            var pose:Array = [];
            try
            {
               pose = bodySuffix != null ? headshotPose() : [];
            }
            catch(poseErr:Error)
            {
               pose = [];
            }
            var parts:Array = [];
            for each(var bp:Array in pose)
            {
               var oldBone:String = bp[0] + "_" + bodySuffix;
               if(rename.has(oldBone) && (("n" + oldBone) in byId))
               {
                  parts.push([byId["n" + oldBone],bp[1]]);
               }
            }
            var originalIcon:String = trim(cell(row,"CostumeIcon"));
            var target:Array = null;
            var icons:File = File.applicationDirectory.resolvePath("UI_Icons.swf");
            if(originalIcon != "" && icons.exists && parts.length > 0)
            {
               try
               {
                  var iconTags:Array = BmodSwf.read(readFile(icons)).tags;
                  for each(var ie:Array in BmodSwf.symbols(iconTags))
                  {
                     if(ie[1] == originalIcon)
                     {
                        target = BmodSwf.boundsReader(iconTags).boundsOf(int(ie[0]));
                     }
                  }
               }
               catch(iconErr:Error)
               {
                  report.push("UI_Icons.swf not read: " + iconErr.message);
               }
            }
            if(parts.length > 0)
            {
               var iconId:int = BmodSwf.maxCharacterId(art) + 1;
               var face:Object = null;
               var jawKey:String = "n" + "a_Jaw_" + bodySuffix;
               if(jawKey in byId)
               {
                  for each(bp in parts)
                  {
                     if(int(bp[0]) == int(byId[jawKey]))
                     {
                        face = {};
                        face["s" + byId[jawKey]] = true;
                     }
                  }
               }
               var sprite:ByteArray = BmodSwf.iconSprite(iconId,parts,BmodSwf.boundsReader(art),target != null ? target : [-40,-40,40,40],
                  face,0.95,0,[0,0]);
               if(sprite != null)
               {
                  iconName = "a_SkinIcon_" + token;
                  art.push(BmodSwf.tag(39,sprite));
                  symbolList.push([iconId,iconName]);
                  classNames.push(iconName);
                  classColours["c" + iconName] = null;
                  report.push("skin icon " + iconName + ": " + parts.length + " head parts in the head-shot pose");
               }
            }
         }
         var swf:ByteArray = modSwf(mod,art,classNames,classColours,BmodSwf.symbolClassTag(symbolList));
         var modId:String = modIdOf(token);
         var folder:File = newFolder(modId);
         writeBytes(folder.resolvePath("bones/" + swfFile),swf);
         var header:Array = item.header;
         var keyCol:String = header[0];
         var artCols:Array = isCostume ? COSTUME_ART.concat(COSTUME_SWAP) : WEAPON_ART;
         var used:Object = {};
         for each(var col:String in artCols)
         {
            if(trim(cell(row,col)) != "")
            {
               used[col] = true;
            }
         }
         var stringKey:String = token + "_DisplayName";
         var newKey:String = isCostume ? token : cell(row,"BaseWeapon") + token;
         var sets:BmodMap = new BmodMap();
         sets.set(keyCol,newKey);
         sets.set("DisplayNameKey",stringKey);
         sets.set(isCostume ? "CostumeID" : "WeaponSkinID","@id");
         if(clearCell(sets,header,row,"UpgradesTo"))
         {
            report.push("not an upgrade of anything (UpgradesTo " + trim(cell(row,"UpgradesTo")) + " cleared: an item can be the upgrade of only one)");
         }
         var roles:Array = newDefines.keys.concat();
         roles.sort();
         for each(var role:String in roles)
         {
            if(header.indexOf(role + "_Define") >= 0)
            {
               sets.set(role + "_Define",upperHex(int(newDefines.get(role))));
            }
         }
         for each(var hc:Array in handColours)
         {
            if(header.indexOf(hc[0]) >= 0)
            {
               sets.set(hc[0],upperHex(int(hc[1])));
            }
         }
         var weaponSet:String = isCostume ? trim(cell(row,"WeaponSet")) : "";
         var drawsWeapon:Boolean = false;
         for each(n in names)
         {
            if(starts(n,"a_Weapon") && rename.has(n))
            {
               drawsWeapon = true;
            }
         }
         var weaponKey:String = null;
         if(weaponSet != "" && bodySuffix != null && drawsWeapon)
         {
            var wt:Object = table("weaponSkinTypes");
            weaponKey = wt.header[0];
            for each(var w:Object in wt.rows)
            {
               var baseWeapon:String = trim(cell(w,"BaseWeapon"));
               if(cell(w,weaponKey) != baseWeapon + weaponSet)
               {
                  continue;
               }
               var wSets:BmodMap = new BmodMap();
               wSets.set(weaponKey,baseWeapon + token);
               wSets.set("WeaponSkinID","@id");
               wSets.set("DisplayNameKey",token + "_" + baseWeapon + "_DisplayName");
               clearCell(wSets,wt.header,w,"UpgradesTo");
               for each(col in WEAPON_ART)
               {
                  var value:String = trim(cell(w,col));
                  if(ends(value,"/" + bodySuffix))
                  {
                     wSets.set(col,value.substr(0,value.length - bodySuffix.length) + newSuffix.get(bodySuffix));
                  }
               }
               var wRow:BmodMap = new BmodMap();
               wRow.set("copy",cell(w,weaponKey));
               wRow.set("set",wSets);
               weaponRows.push(wRow);
               weaponStrings.set(token + "_" + baseWeapon + "_DisplayName",display + " " + baseWeapon);
            }
            if(weaponRows.length > 0)
            {
               sets.set("WeaponSet",token);
               if(clearCell(sets,header,row,"DoesNotOwnWeaponSet"))
               {
                  report.push("owns its new weapon set (DoesNotOwnWeaponSet cleared: " + item.key + " borrows another legend's)");
               }
               var wDesc:Array = [];
               for each(wRow in weaponRows)
               {
                  wDesc.push(wRow.get("set").get(weaponKey) + " (copy of " + wRow.get("copy") + ")");
               }
               report.push("weapons: " + wDesc.join(", "));
            }
         }
         var drawsHands:Boolean = false;
         for each(n in names)
         {
            if(n.indexOf("Hand") >= 0)
            {
               drawsHands = true;
            }
         }
         if(isCostume && !drawsHands)
         {
            for each(col in COSTUME_ART)
            {
               var handArt:String = cell(row,col);
               if(starts(handArt,"Gfx_Hands.swf/") && handArt != "Gfx_Hands.swf/Bare")
               {
                  sets.set(col,"Gfx_Hands.swf/Bare");
                  report.push("bare hands (Gfx_Hands.swf/Bare instead of " + handArt + "): the mod draws none");
               }
            }
         }
         if(isCostume)
         {
            sets.set("CostumeIndex","@id/OwnerHero");
            if(iconName != null)
            {
               sets.set("CostumeIcon",iconName);
            }
            if(rosterPose != null)
            {
               sets.set("IsCrossover","TRUE");
               sets.set("RosterOrderID","@id");
               if(rosterGem != null)
               {
                  sets.set("CrossoverGem",rosterGem);
                  sets.set("CrossoverGemFileName","UI_Roster");
               }
               else
               {
                  for each(col in ["CrossoverGem","CrossoverGemFileName"])
                  {
                     if(header.indexOf(col) >= 0 && trim(cell(row,col)) != "")
                     {
                        sets.set(col,"@none");
                     }
                  }
               }
               sets.set("ReplacementPortrait",rosterPose);
               sets.set("ReplacementPortraitFileName","UI_Icons");
               if(trim(cell(row,"ParentCrossover")) != "")
               {
                  sets.set("ParentCrossover","@none");
               }
               crossoverName = "Generated|CostumeType_" + token + "_DisplayNameWRTCrossover";
               report.push("a crossover with the mod's roster portrait " + rosterPose);
            }
            else
            {
               if(header.indexOf("ReplacementHeroName") >= 0)
               {
                  sets.set("ReplacementHeroName",display);
               }
               if(lower(trim(cell(row,"IsCrossover"))) == "true")
               {
                  sets.set("IsCrossover","FALSE");
                  for each(col in ["CrossoverGem","CrossoverGemFileName","ReplacementPortrait","ReplacementPortraitFileName","ParentCrossover",
                     "RosterOrderID"])
                  {
                     if(header.indexOf(col) >= 0 && trim(cell(row,col)) != "")
                     {
                        sets.set(col,"@none");
                     }
                  }
                  report.push("a normal skin named " + display + " (not a crossover like " + item.key + ")");
               }
            }
            if(lower(trim(cell(row,"OverrideSelectAnims"))) == "true")
            {
               animationAliases = new BmodMap();
               animationAliases.set(token,item.key);
               report.push("character select plays " + item.key + "'s animations");
            }
         }
         else
         {
            sets.set("DbID","@id");
         }
         var columns:BmodMap = item.columns;
         for each(s in columns.keys)
         {
            if(!newSuffix.has(s))
            {
               continue;
            }
            col = columns.get(s);
            var newValue:String = replaceAll(cell(row,col),"/" + s,"/" + newSuffix.get(s));
            var group:Array = COSTUME_SWAP.indexOf(col) >= 0 ? COSTUME_SWAP : (COSTUME_ART.indexOf(col) >= 0 ? COSTUME_ART : WEAPON_ART);
            var free:String = null;
            for(var gi:int = group.length - 1; gi >= 0; gi--)
            {
               if(!(group[gi] in used) && header.indexOf(group[gi]) >= 0)
               {
                  free = group[gi];
                  break;
               }
            }
            if(free != null && group.indexOf(free) > group.indexOf(col))
            {
               sets.set(free,newValue);
               used[free] = true;
            }
            else
            {
               sets.set(col,newValue);
               report.push("no free art column after " + col + ": parts the mod doesn't redraw won't show the original's");
            }
         }
         var sizeKb:int = int(Math.max(1,Math.floor((swf.length + 1023) / 1024)));
         var powerRows:Array = [];
         if(isCostume)
         {
            powerRows = powerSwaps(item,row,newKey,rename,hits,sets,newSuffix);
            if(powerRows.length > 0)
            {
               report.push("powers: " + powerRows.length + " PowerSwapTypes rows, their effects drawn with the new skin's art");
            }
         }
         var bones:String = "";
         var newNames:Array = [];
         for each(old in rename.keys)
         {
            newNames.push(rename.get(old));
         }
         newNames.sort();
         for each(n in newNames)
         {
            bones += "<Bone>" + n + "</Bone>";
         }
         var manifest:BmodMap = new BmodMap();
         manifest.set("id",modId);
         manifest.set("name",display);
         manifest.set("version",meta.version != null && String(meta.version) != "" ? String(meta.version) : "1.0");
         manifest.set("description","Imported from " + mod.fileName + " (" + (meta.author ? String(meta.author) : "unknown author") +
            ") by Bifrost: a new " + (isCostume ? "skin" : "weapon skin") + " made from " + item.table + "/" + item.key +
            " with the mod's art; the original is unchanged.");
         var englishStrings:BmodMap = new BmodMap();
         englishStrings.set(stringKey,display);
         for each(var wk:String in weaponStrings.keys)
         {
            englishStrings.set(wk,weaponStrings.get(wk));
         }
         if(crossoverName != null)
         {
            englishStrings.set(crossoverName,display + " (Crossover)");
         }
         var strings:BmodMap = new BmodMap();
         strings.set("English",englishStrings);
         manifest.set("strings",strings);
         var assets:BmodMap = new BmodMap();
         assets.set("bones/" + swfFile,"bones/" + swfFile);
         manifest.set("assets",assets);
         if(paletteTable.length > 0)
         {
            var pal:BmodMap = new BmodMap();
            pal.set("costume",newKey);
            var shades:BmodMap = new BmodMap();
            var shadeKeys:Array = paletteTable.keys.concat();
            shadeKeys.sort(Array.NUMERIC);
            for each(c in shadeKeys)
            {
               var entry:Array = paletteTable.get(c);
               shades.set(hex6(int(c)),[hex6(int(entry[0])),{"pyFloat":entry[1]},{"pyFloat":entry[2]},{"pyFloat":entry[3]}]);
            }
            pal.set("colours",shades);
            manifest.set("palette",pal);
         }
         var tables:BmodMap = new BmodMap();
         var mainRow:BmodMap = new BmodMap();
         mainRow.set("copy",item.key);
         mainRow.set("set",sets);
         tables.set(item.table,[mainRow]);
         if(weaponRows.length > 0)
         {
            tables.set("weaponSkinTypes",weaponRows);
         }
         if(powerRows.length > 0)
         {
            tables.set("PowerSwapTypes",powerRows);
         }
         tables.set("MasterFileList",["<File Stage=\"Game\" ExcludedPlatforms=\"\" Size=\"" + sizeKb + "\" Name=\"bones/" + swfFile +
            "\" Load=\"\" />"]);
         tables.set("BoneSources",["<Original name=\"" + token + "\"><Target name=\"" + swfFile + "\">" + bones + "</Target></Original>"]);
         manifest.set("tables",tables);
         if(animationAliases != null)
         {
            manifest.set("animationAliases",animationAliases);
         }
         manifest.set("author",meta.author ? String(meta.author) : "");
         writePreview(mod,folder,manifest);
         manifest.set("source",mod.source);
         writeText(folder.resolvePath("mod.json"),toJson(manifest,"") + "\n");
         if(skipped.length + missing.length > 0)
         {
            report.push("left out (" + (skipped.length + missing.length) + ", not named after the item, so shared by everyone): " +
               skipped.concat(missing).slice(0,12).join(", "));
         }
         var uncoloured:Array = [];
         for each(old in sortedOld)
         {
            if(!(("c" + old) in colours))
            {
               uncoloured.push(old);
            }
         }
         if(uncoloured.length > 0)
         {
            report.push("not in the game's SWFs, so no palette colours (" + uncoloured.length + "): " + uncoloured.slice(0,8).join(", "));
         }
         report.push(item.table + "/" + newKey + " (a copy of " + item.table + "/" + item.key + ") with " + rename.length + " sprites");
         register(folder);
         var original:String = gameString(cell(row,"DisplayNameKey"));
         var what:String = isCostume ? "skin" : "weapon skin";
         return {"folder":folder,"id":modId,"kind":item.table + "/" + newKey,"live":false,
            "message":display + ": a new " + what + " next to " + (original != null && original != "" ? original : item.key) + "."};
      }

      private static function listHas(list:String, name:String) : Boolean
      {
         if(list == null || name == null || name == "")
         {
            return false;
         }
         for each(var part:String in list.split(","))
         {
            if(trim(part) == name)
            {
               return true;
            }
         }
         return false;
      }

      private static function ownedBy(x:Xml, attr:String, key:String) : String
      {
         var text:String = x.toString();
         var from:String = attr + "=\"" + x.method_4935(attr) + "\"";
         var at:int = text.indexOf(from);
         if(at < 0)
         {
            return null;
         }
         return text.substr(0,at) + "OwnerCostume=\"" + key + "\"" + text.substr(at + from.length);
      }

      private static function tagged(text:String, tag:String) : String
      {
         var open:String = "<" + tag + ">";
         var a:int = text.indexOf(open);
         if(a < 0)
         {
            return null;
         }
         var b:int = text.indexOf("<",a + open.length);
         return b < 0 ? null : text.substring(a + open.length,b);
      }

      private static function powerSwaps(item:Object, row:Object, newKey:String, rename:BmodMap, hits:BmodMap, sets:BmodMap,
         newSuffix:BmodMap) : Array
      {
         var key:String = item.key;
         var ownByPower:BmodMap = new BmodMap();
         var ownCount:int = 0;
         var x:Xml;
         var target:String;
         var text:String;
         for each(x in powerSwapRows)
         {
            if(!listHas(x.method_4935("OwnerCostume"),key))
            {
               continue;
            }
            target = ContentMods.fieldText(x,"TargetPower");
            text = ownedBy(x,"OwnerCostume",key);
            if(target != null && text != null)
            {
               ownCount++;
               ownByPower.set(target,text);
            }
         }
         var legend:String = trim(cell(row,"OwnerHero"));
         var wasCrossover:Boolean = lower(trim(cell(row,"IsCrossover"))) == "true";
         var isCrossover:Boolean = sets.has("IsCrossover") ? sets.get("IsCrossover") == "TRUE" : wasCrossover;
         var legendRows:BmodMap = new BmodMap();
         for each(x in heroSwapRows)
         {
            target = ContentMods.fieldText(x,"TargetPower");
            if(legend != "" && target != null && listHas(x.method_4935("OwnerHero"),legend))
            {
               legendRows.set(target,x);
            }
         }
         var legendCopied:Array = [];
         var legendCovered:Array = [];
         var legendDropped:Array = [];
         if(isCrossover && !wasCrossover)
         {
            for each(target in legendRows.keys)
            {
               text = ownedBy(legendRows.get(target),"OwnerHero",key);
               if(!ownByPower.has(target) && text != null)
               {
                  ownByPower.set(target,text);
                  legendCopied.push(target);
               }
            }
         }
         else if(!isCrossover)
         {
            for each(target in legendRows.keys)
            {
               legendCovered.push(target);
               if(ownByPower.has(target))
               {
                  legendDropped.push(target);
                  ownByPower.remove(target);
               }
            }
         }
         var swapSuffixes:Array = [];
         for each(var s:String in hits.keys)
         {
            if(starts(s,"Swap"))
            {
               swapSuffixes.push(s);
            }
         }
         if(swapSuffixes.length == 0)
         {
            swapSuffixes = hits.keys.concat();
         }
         var artEntries:Array = [];
         var newSuffixes:Array = [];
         for each(s in newSuffix.keys)
         {
            newSuffixes.push(newSuffix.get(s));
         }
         for each(var col:String in sets.keys)
         {
            var v:String = String(sets.get(col));
            if((COSTUME_ART.indexOf(col) >= 0 || COSTUME_SWAP.indexOf(col) >= 0) && v.indexOf("/") >= 0 &&
               newSuffixes.indexOf(v.substr(v.lastIndexOf("/") + 1)) >= 0)
            {
               artEntries.push(v);
            }
         }
         var hero:String = trim(cell(row,"OwnerHero"));
         var baseGfx:BmodMap = new BmodMap();
         if(hero != "")
         {
            var raw:Array = csvLines("powerTypes");
            var pHeader:Array = splitLine(raw[0]);
            var nameCol:int = pHeader.indexOf("PowerName");
            for(var i:int = 1; i < raw.length; i++)
            {
               var line:String = raw[i];
               var comma:int = line.indexOf(",");
               var first:String = comma < 0 ? line : line.substr(0,comma);
               if(nameCol == 0 && !ends(first,hero) && first.indexOf("\"") < 0)
               {
                  continue;
               }
               var fields:Array = splitLine(line);
               var pname:String = nameCol >= 0 && nameCol < fields.length ? fields[nameCol] : "";
               if(!ends(pname,hero))
               {
                  continue;
               }
               var kinds:BmodMap = new BmodMap();
               var any:Boolean = false;
               for each(var kind:String in ["Cast","Fire","Hit"])
               {
                  var g:BmodMap = new BmodMap();
                  for(var c:int = 0; c < pHeader.length && c < fields.length; c++)
                  {
                     var hcol:String = pHeader[c];
                     if(starts(hcol,kind + "Gfx.") && trim(fields[c]) != "")
                     {
                        g.set(hcol.substr(hcol.indexOf(".") + 1),fields[c]);
                     }
                  }
                  if(g.has("AnimClass") && g.get("AnimClass") != "")
                  {
                     any = true;
                  }
                  kinds.set(kind,g);
               }
               if(any)
               {
                  baseGfx.set(pname,kinds);
               }
            }
         }
         var powers:Array = ownByPower.keys.concat();
         for each(var bp:String in baseGfx.keys)
         {
            if(legendCovered.indexOf(bp) >= 0)
            {
               if(legendDropped.indexOf(bp) < 0)
               {
                  legendDropped.push(bp);
               }
            }
            else if(powers.indexOf(bp) < 0)
            {
               powers.push(bp);
            }
         }
         if(legendCopied.length > 0)
         {
            report.push("powers: " + legendCopied.length + " of " + legend + "'s own swaps copied (a crossover doesn't get them): " +
               legendCopied.slice(0,8).join(", "));
         }
         if(legendDropped.length > 0)
         {
            report.push("powers: " + legendDropped.length + " left to " + legend + "'s own swaps (a normal skin gets them): " +
               legendDropped.slice(0,8).join(", "));
         }
         powers.sort();
         var out:Array = [];
         for each(var power:String in powers)
         {
            var own:String = ownByPower.has(power) ? ownByPower.get(power) : "<PowerSwapType OwnerCostume=\"" + key + "\"><TargetPower>" +
               power + "</TargetPower><CastGfx/><FireGfx/><HitGfx/></PowerSwapType>";
            var from:String = "OwnerCostume=\"" + key + "\"";
            var at:int = own.indexOf(from);
            var r2:String = at < 0 ? own : own.substr(0,at) + "OwnerCostume=\"" + newKey + "\"" + own.substr(at + from.length);
            for each(kind in ["Cast","Fire","Hit"])
            {
               var base:BmodMap = baseGfx.has(power) && baseGfx.get(power).has(kind) ? baseGfx.get(power).get(kind) : new BmodMap();
               var empty:String = "<" + kind + "Gfx/>";
               var open:String = "<" + kind + "Gfx>";
               var close:String = "</" + kind + "Gfx>";
               var e:int = r2.indexOf(empty);
               var o:int = r2.indexOf(open);
               var closeAt:int = o >= 0 ? r2.indexOf(close,o + open.length) : -1;
               if(o >= 0 && closeAt < 0)
               {
                  o = -1;
               }
               var start:int = -1;
               var stop:int = -1;
               var inner:String = null;
               if(e >= 0 && (o < 0 || e < o))
               {
                  start = e;
                  stop = e + empty.length;
               }
               else if(o >= 0)
               {
                  start = o;
                  stop = closeAt + close.length;
                  inner = r2.substring(o + open.length,closeAt);
               }
               var gfx:String = gfxXml(kind,inner,base,rename,swapSuffixes,artEntries);
               if(start >= 0)
               {
                  r2 = r2.substr(0,start) + gfx + r2.substr(stop);
               }
               else
               {
                  r2 = replaceAll(r2,"</PowerSwapType>",gfx + "</PowerSwapType>");
               }
            }
            var add:BmodMap = new BmodMap();
            add.set("add",r2);
            out.push(add);
         }
         if(out.length > 0)
         {
            report.push("powers: " + ownCount + " of them copied from " + key + "'s rows");
         }
         return out;
      }

      private static function effect(name:String, rename:BmodMap, swapSuffixes:Array) : String
      {
         if(rename.has(name))
         {
            return rename.get(name);
         }
         for each(var suffix:String in swapSuffixes)
         {
            if(ends(name,"_" + suffix))
            {
               var base:String = name.substr(0,name.length - suffix.length - 1);
               if(sfxHas(name) && sfxHas(base))
               {
                  return base;
               }
            }
         }
         return name;
      }

      private static function gfxXml(kind:String, inner:String, base:BmodMap, rename:BmodMap, swapSuffixes:Array, artEntries:Array) : String
      {
         if(inner == null || trim(inner) == "")
         {
            if(!base.has("AnimClass") || base.get("AnimClass") == "")
            {
               return "<" + kind + "Gfx/>";
            }
            inner = "";
            for each(var k:String in base.keys)
            {
               inner += "<" + k + ">" + base.get(k) + "</" + k + ">";
            }
         }
         var out:String = "";
         var pos:int = 0;
         var open:String = "<AnimClass>";
         var close:String = "</AnimClass>";
         while(true)
         {
            var a:int = inner.indexOf(open,pos);
            if(a < 0)
            {
               break;
            }
            var b:int = inner.indexOf("<",a + open.length);
            if(b < 0 || inner.substr(b,close.length) != close)
            {
               out += inner.substring(pos,a + open.length);
               pos = a + open.length;
               continue;
            }
            out += inner.substring(pos,a) + open + effect(inner.substring(a + open.length,b),rename,swapSuffixes) + close;
            pos = b + close.length;
         }
         inner = out + inner.substr(pos);
         if(inner.indexOf(open) >= 0)
         {
            var taken:int = 0;
            var from:int = 0;
            while(true)
            {
               var t:int = inner.indexOf("<CustomArt",from);
               if(t < 0)
               {
                  break;
               }
               var j:int = t + 10;
               while(j < inner.length && inner.charAt(j) >= "0" && inner.charAt(j) <= "9")
               {
                  j++;
               }
               if(inner.charAt(j) == ">")
               {
                  taken++;
               }
               from = t + 10;
            }
            for(var i:int = 0; i < artEntries.length; i++)
            {
               inner += "<CustomArt" + (taken + i + 1) + ">" + artEntries[i] + "</CustomArt" + (taken + i + 1) + ">";
            }
         }
         return "<" + kind + "Gfx>" + inner + "</" + kind + "Gfx>";
      }

      private static function levelArt() : Object
      {
         var refs:BmodMap = new BmodMap();
         var names:Object = {};
         var thumbs:BmodMap = new BmodMap();
         for each(var root:Xml in levelDescs)
         {
            if(!root.exists("LevelName"))
            {
               continue;
            }
            var level:String = root.method_4935("LevelName");
            var dir:String = root.exists("AssetDir") ? root.method_4935("AssetDir") : "";
            var base:String = "mapArt/" + (dir != null && dir != "" ? dir + "/" : "");
            var stack:Array = [root];
            while(stack.length > 0)
            {
               var node:Xml = stack.shift();
               if(node.exists("AssetName"))
               {
                  var name:String = node.method_4935("AssetName");
                  if(name != null && name != "" && !starts(name,".png"))
                  {
                     var path:String = node.var_4402 == "Background" ? "mapArt/Backgrounds/" + name :
                        (starts(name,"../") ? "mapArt/" + name.substr(3) : base + name);
                     addTo(refs,path,level);
                  }
               }
               var kids:Array = ContentMods.elements(node);
               for(var k:int = kids.length - 1; k >= 0; k--)
               {
                  stack.unshift(kids[k]);
               }
            }
         }
         for each(var lt:Object in levelTypes)
         {
            if(lt.devOnly || lt.testLevel)
            {
               continue;
            }
            names["l" + lt.name] = lt.display != null ? lt.display : lt.name;
            var thumb:String = trim(lt.thumb);
            if(thumb != "")
            {
               var tp:String = "images/thumbnails/" + thumb;
               addTo(thumbs,tp,lt.name);
               addTo(refs,tp,lt.name);
            }
         }
         return {"refs":refs,"names":names,"thumbs":thumbs};
      }

      private static function addTo(map:BmodMap, key:String, value:String) : void
      {
         if(!map.has(key))
         {
            map.set(key,[]);
         }
         var list:Array = map.get(key);
         if(list.indexOf(value) < 0)
         {
            list.push(value);
         }
      }

      private static function mapTypes() : Object
      {
         var sets:Object = {};
         for each(var ls:Object in levelSets)
         {
            for each(var level:String in ls.levels)
            {
               level = trim(level);
               if(!(("l" + level) in sets))
               {
                  sets["l" + level] = [];
               }
               sets["l" + level].push(ls.name);
            }
         }
         var out:Object = {};
         for(var key:String in sets)
         {
            var kinds:Array = [];
            for each(var mt:Array in MAP_TYPES)
            {
               for each(var member:String in mt[1])
               {
                  if((sets[key] as Array).indexOf(member) >= 0)
                  {
                     kinds.push(mt[0]);
                     break;
                  }
               }
            }
            out[key] = kinds.length > 0 ? kinds : ["Other"];
         }
         return out;
      }

      private static function folderOf(ref:String) : String
      {
         return ref.substr(0,ref.lastIndexOf("/"));
      }

      private static function sameBytes(a:Object, b:Object) : Boolean
      {
         var as_:ByteArray = a is ByteArray ? a as ByteArray : BmodSwf.copy(a);
         var bs:ByteArray = b is ByteArray ? b as ByteArray : BmodSwf.copy(b);
         if(as_.length != bs.length)
         {
            return false;
         }
         as_.position = 0;
         bs.position = 0;
         while(as_.bytesAvailable >= 4)
         {
            if(as_.readInt() != bs.readInt())
            {
               return false;
            }
         }
         while(as_.bytesAvailable > 0)
         {
            if(as_.readUnsignedByte() != bs.readUnsignedByte())
            {
               return false;
            }
         }
         return true;
      }

      private static function importMapArt(mod:Object) : Object
      {
         var meta:Object = mod.meta;
         if(levelDescs.length == 0)
         {
            throw new Error("the game's maps (LevelDesc) weren't read at start-up");
         }
         var la:Object = levelArt();
         var refs:BmodMap = la.refs;
         var byName:Object = {};
         for each(var ref:String in refs.keys)
         {
            var key:String = "f" + lower(ref.substr(ref.lastIndexOf("/") + 1));
            if(!(key in byName))
            {
               byName[key] = [];
            }
            byName[key].push(ref);
         }
         var files:Array = modFiles(mod);
         var found:Array = [];
         var placed:Array = [];
         for each(var f:Array in files)
         {
            var cands:Array = ("f" + lower(f[1])) in byName ? byName["f" + lower(f[1])] : [];
            found.push(cands);
            placed.push(cands.length == 1 ? cands[0] : null);
         }
         var i:int = 0;
         var j:int = 0;
         for(i = 0; i < found.length; i++)
         {
            var c:Array = found[i];
            if(c.length < 2)
            {
               continue;
            }
            var order:Array = [];
            var dist:Array = [];
            for(j = 0; j < files.length; j++)
            {
               order.push(j);
               dist.push([Math.abs(j - i)]);
            }
            order = stableSort(order,dist,false);
            var pick:String = null;
            for each(j in order)
            {
               if(j == i || placed[j] == null)
               {
                  continue;
               }
               var d:String = folderOf(placed[j]);
               if(!starts(d,"mapArt/") || ends(d,"Backgrounds"))
               {
                  continue;
               }
               for each(var cand:String in c)
               {
                  if(folderOf(cand) == d)
                  {
                     pick = cand;
                     break;
                  }
               }
               if(pick != null)
               {
                  break;
               }
            }
            if(pick == null)
            {
               var sorted:Array = c.concat();
               sorted.sort();
               pick = sorted[0];
               report.push(f[1] + " could be " + sorted.join(", ") + ": took " + pick);
            }
            placed[i] = pick;
         }
         var display:String = meta.name != null && meta.name != "" ? String(meta.name) : String(mod.stem);
         var modId:String = modIdOf(tokenFor(display));
         var primary:BmodMap = new BmodMap();
         var variants:BmodMap = new BmodMap();
         var unused:Array = [];
         for(i = 0; i < files.length; i++)
         {
            f = files[i];
            ref = placed[i];
            if(ref == null)
            {
               unused.push(f[1]);
               continue;
            }
            if(primary.has(ref))
            {
               if(sameBytes(primary.get(ref),f[2]))
               {
                  continue;
               }
               if(!variants.has(ref))
               {
                  variants.set(ref,[]);
               }
               variants.get(ref).push([f[0],primary.get(ref)]);
            }
            primary.set(ref,f[2]);
         }
         if(primary.length == 0)
         {
            throw new Error("none of its " + files.length + " files is art a map of this game reads");
         }
         var target:File = newFolder(modId);
         for each(ref in primary.keys)
         {
            writeTag(target,ref,primary.get(ref));
         }
         var variantFiles:BmodMap = new BmodMap();
         for each(ref in variants.keys)
         {
            for each(var item:Array in variants.get(ref))
            {
               var local:String = "variants/" + item[0] + "_" + ref.substr(ref.lastIndexOf("/") + 1);
               writeTag(target,local,item[1]);
               addTo(variantFiles,ref,local);
            }
         }
         var own:Object = {};
         for each(ref in refs.keys)
         {
            if(starts(ref,"mapArt/"))
            {
               for each(var lvl:String in refs.get(ref))
               {
                  if(!(("l" + lvl) in own))
                  {
                     own["l" + lvl] = [];
                  }
                  own["l" + lvl].push(ref);
               }
            }
         }
         var names:Object = la.names;
         var levelList:Array = [];
         for each(ref in primary.keys)
         {
            for each(lvl in refs.get(ref))
            {
               if(levelList.indexOf(lvl) < 0)
               {
                  levelList.push(lvl);
               }
            }
         }
         levelList.sort();
         var maps:BmodMap = new BmodMap();
         for each(lvl in levelList)
         {
            var mine:Array = ("l" + lvl) in own ? own["l" + lvl] : [];
            var has:int = 0;
            var background:Boolean = false;
            for each(ref in mine)
            {
               if(primary.has(ref))
               {
                  has++;
                  if(starts(ref,"mapArt/Backgrounds/"))
                  {
                     background = true;
                  }
               }
            }
            if((("l" + lvl) in names) && (background || (mine.length > 0 && has * 2 >= mine.length)))
            {
               maps.set(lvl,names["l" + lvl]);
            }
         }
         var kinds:Object = mapTypes();
         var manifest:BmodMap = new BmodMap();
         manifest.set("id",modId);
         manifest.set("name",display);
         manifest.set("version",meta.version != null && String(meta.version) != "" ? String(meta.version) : "1.0");
         manifest.set("author",meta.author ? String(meta.author) : "");
         manifest.set("description",(meta.description ? cleanText(String(meta.description)) + "\n\n" : "") + "Imported from " +
            mod.fileName + " by Bifrost: art for " + maps.length + " maps, picked per map in the Mods screen; the game's own art is unchanged.");
         var mapArt:BmodMap = new BmodMap();
         var fileList:Array = primary.keys.concat();
         fileList.sort();
         mapArt.set("files",fileList);
         mapArt.set("maps",maps);
         var thumbs:BmodMap = la.thumbs;
         var thumbOut:BmodMap = new BmodMap();
         for each(ref in fileList)
         {
            if(thumbs.has(ref))
            {
               var lv:Array = [];
               for each(lvl in thumbs.get(ref))
               {
                  if(maps.has(lvl))
                  {
                     lv.push(lvl);
                  }
               }
               lv.sort();
               thumbOut.set(ref,lv);
            }
         }
         mapArt.set("thumbnails",thumbOut);
         var typesOut:BmodMap = new BmodMap();
         for each(lvl in maps.keys)
         {
            typesOut.set(lvl,("l" + lvl) in kinds ? kinds["l" + lvl] : ["Other"]);
         }
         mapArt.set("mapTypes",typesOut);
         if(variantFiles.length > 0)
         {
            var vSorted:BmodMap = new BmodMap();
            var vKeys:Array = variantFiles.keys.concat();
            vKeys.sort();
            for each(ref in vKeys)
            {
               vSorted.set(ref,variantFiles.get(ref));
            }
            mapArt.set("variants",vSorted);
         }
         manifest.set("mapArt",mapArt);
         writePreview(mod,target,manifest);
         manifest.set("source",mod.source);
         writeText(target.resolvePath("mod.json"),toJson(manifest,"") + "\n");
         if(unused.length > 0)
         {
            report.push("left out (" + unused.length + ", no map reads them): " + unused.slice(0,12).join(", ") + (unused.length > 12 ? " ..." : ""));
         }
         var shown:Array = [];
         for each(lvl in maps.keys)
         {
            if(shown.indexOf(maps.get(lvl)) < 0)
            {
               shown.push(maps.get(lvl));
            }
         }
         shown.sort();
         report.push("map art: " + primary.length + " files for " + maps.length + " maps (" + shown.slice(0,10).join(", ") + ")");
         var live:Boolean = register(target);
         return {"folder":target,"id":modId,"kind":"map art for " + maps.length + " maps","live":live,
            "message":display + ": art for " + maps.length + (maps.length == 1 ? " map" : " maps") + " (" + shown.slice(0,3).join(", ") +
            (shown.length > 3 ? ", ..." : "") + "), picked per map in Mods, Map art" + (live ? ", ready now." : ".")};
      }

      private static function register(folder:File) : Boolean
      {
         try
         {
            var mod:Object = ContentMods.parse(folder.name,readText(folder.resolvePath("mod.json")));
            if(mod == null)
            {
               return false;
            }
            mod.dir = folder;
            var replaced:Boolean = false;
            for(var i:int = 0; i < ContentMods.all.length; i++)
            {
               if(ContentMods.all[i].id == mod.id)
               {
                  ContentMods.all[i] = mod;
                  replaced = true;
               }
            }
            if(!replaced)
            {
               ContentMods.all.push(mod);
            }
            if(replaced || mod.mapArt == null || !ContentMods.isLive(mod))
            {
               return false;
            }
            var first:Boolean = MapArt.packs.length == 0;
            MapArt.add(mod,ContentMods.report);
            if(first && MapArt.packs.length > 0)
            {
               Hooks.fileResolving.add(MapArt.resolve);
               Hooks.levelArtLoading.add(MapArt.levelLoading);
            }
            return true;
         }
         catch(e:Error)
         {
            report.push("not listed in the Mods screen yet: " + e.message);
         }
         return false;
      }

      private static function norm(text:String) : String
      {
         return lower(text).replace(/[^a-z0-9]/g,"");
      }

      private static function importAvatars(mod:Object) : Object
      {
         var meta:Object = mod.meta;
         var at:Object = table("avatarTypes");
         var raw:Array = csvLines("spriteData");
         var sHeader:Array = splitLine(raw[0]);
         var sRows:Array = [];
         for(var i:int = 1; i < raw.length; i++)
         {
            if(raw[i] == "")
            {
               continue;
            }
            var fields:Array = splitLine(raw[i]);
            if(fields.length >= 3)
            {
               sRows.push(rowOf(sHeader,fields));
            }
         }
         var byIcon:Object = {};
         var byFlag:Object = {};
         var row:Object;
         for each(row in at.rows)
         {
            if(cell(row,"IconName") != "")
            {
               byIcon["i" + cell(row,"IconName")] = row;
            }
            if(!(("f" + cell(row,"FlagArt")) in byFlag))
            {
               byFlag["f" + cell(row,"FlagArt")] = row;
            }
         }
         var spriteRows:Object = {};
         var fileSet:Object = {};
         for each(row in sRows)
         {
            var setName:String = cell(row,"SetName");
            if(!(("s" + setName) in spriteRows))
            {
               spriteRows["s" + setName] = [];
            }
            spriteRows["s" + setName].push(row);
            var fileName:String = cell(row,"File");
            fileSet["f" + lower(fileName.substr(fileName.lastIndexOf("/") + 1))] = [setName,cell(row,"BoneName")];
         }
         var touched:BmodMap = new BmodMap();
         var sprites:Array = [];
         var swfs:Object = meta.swfs != null ? meta.swfs : {};
         for(var swf:String in swfs)
         {
            for each(var sn:String in swfs[swf].sprites)
            {
               sprites.push(sn);
            }
         }
         var unused:Array = [];
         var entry:Object;
         for each(sn in sprites)
         {
            if(("i" + sn) in byIcon)
            {
               entry = touchedEntry(touched,byIcon["i" + sn]);
               entry.iconSprite = sn;
            }
            else
            {
               unused.push(sn);
            }
         }
         for each(var mf:Array in modFiles(mod))
         {
            var name:String = mf[1];
            var stem:String = name.lastIndexOf(".") >= 0 ? name.substr(0,name.lastIndexOf(".")) : name;
            var fs:Array = fileSet["f" + lower(name)];
            if(("i" + stem) in byIcon)
            {
               entry = touchedEntry(touched,byIcon["i" + stem]);
               entry.iconPng = mf;
            }
            else if(fs != null && (("f" + fs[0]) in byFlag))
            {
               entry = touchedEntry(touched,byFlag["f" + fs[0]]);
               entry.flags["b" + fs[1]] = mf;
            }
            else
            {
               unused.push(name);
            }
         }
         if(touched.length == 0)
         {
            throw new Error("it redraws no avatar of this game");
         }
         var labels:Object = {};
         var desc:Array = cleanText(meta.description ? String(meta.description) : "").split("\n");
         var re:RegExp = /^\s*(.+?)\s*=\s*(.+?)(?:\s+Avatar)?\s*$/;
         for each(var line:String in desc)
         {
            var m:Array = re.exec(line.split("\r").join(""));
            if(m == null)
            {
               continue;
            }
            var wanted:String = norm(m[2]);
            for each(var tn:String in touched.keys)
            {
               var tr:Object = touched.get(tn).row;
               var shownName:String = gameString(cell(tr,"DisplayNameKey"));
               if(shownName == null)
               {
                  shownName = "";
               }
               var iconWord:String = replaceAll(cell(tr,"IconName"),"a_AvatarIcon_","");
               var same:Boolean = wanted == norm(tn);
               if(wanted == norm(shownName))
               {
                  same = true;
               }
               if(wanted == norm(iconWord))
               {
                  same = true;
               }
               if(same)
               {
                  labels["l" + tn] = m[1];
               }
            }
         }
         var modName:String = meta.name != null && meta.name != "" ? String(meta.name) : String(mod.stem);
         var prefix:String = tokenFor(modName);
         var modId:String = modIdOf(prefix);
         var target:File = newFolder(modId);
         var rows:Array = [];
         var spriteAdds:Array = [];
         var assets:BmodMap = new BmodMap();
         var englishStrings:BmodMap = new BmodMap();
         var rename:BmodMap = new BmodMap();
         var pngIcons:Object = {};
         for each(row in ("s" in spriteRows ? spriteRows["s"] : []))
         {
            pngIcons["b" + cell(row,"BoneName")] = row;
         }
         var bare:String = modName;
         while(bare.length > 0 && bare.charAt(bare.length - 1) == "!")
         {
            bare = bare.substr(0,bare.length - 1);
         }
         var touchedNames:Array = touched.keys.concat();
         touchedNames.sort();
         var dims:Array;
         var c:int;
         for each(tn in touchedNames)
         {
            var t:Object = touched.get(tn);
            row = t.row;
            var shown:String = gameString(cell(row,"DisplayNameKey"));
            if(shown == null)
            {
               shown = tn;
            }
            var labelled:Boolean = ("l" + tn) in labels;
            var label:String = labelled ? labels["l" + tn] : shown + " (" + bare + ")";
            var token:String = tokenFor(labelled ? label : tn + " " + modName);
            var icon:String = "a_AvatarIcon_" + token;
            var sets:BmodMap = new BmodMap();
            sets.set("AvatarName",token);
            sets.set("AvatarID","@id");
            sets.set("DisplayNameKey",token + "_DisplayName");
            sets.set("IconName",icon);
            sets.set("FlagArt",token);
            if(trim(cell(row,"SpriteFilePath")) != "")
            {
               sets.set("SpriteFilePath","@none");
            }
            englishStrings.set(token + "_DisplayName",label);
            if(t.iconSprite != null)
            {
               rename.set(t.iconSprite,icon);
            }
            else if(t.iconPng != null || (("b" + cell(row,"IconName")) in pngIcons))
            {
               var orig:Object = ("b" + cell(row,"IconName")) in pngIcons ? pngIcons["b" + cell(row,"IconName")] : null;
               var gamePath:String = orig != null ? cell(orig,"File") : "";
               if(t.iconPng != null)
               {
                  gamePath = "sprites/AutoGenerated/Sprites_Avatars/" + icon + ".png";
                  writeTag(target,"sprites/" + icon + ".png",t.iconPng[2]);
                  assets.set(gamePath,"sprites/" + icon + ".png");
               }
               dims = [];
               if(orig != null)
               {
                  for(c = 3; c < sHeader.length; c++)
                  {
                     dims.push(cell(orig,sHeader[c]));
                  }
               }
               else
               {
                  dims = ["128","128","1","1"];
               }
               var addIcon:BmodMap = new BmodMap();
               addIcon.set("add",["",icon,gamePath].concat(dims).join(","));
               spriteAdds.push(addIcon);
            }
            else
            {
               sets.set("IconName",cell(row,"IconName"));
               report.push(token + ": the mod has no icon for it, so it shows " + tn + "'s");
            }
            var flagRows:Array = ("s" + cell(row,"FlagArt")) in spriteRows ? spriteRows["s" + cell(row,"FlagArt")] : [];
            var flagCount:int = 0;
            for each(var fr:Object in flagRows)
            {
               var bone:String = cell(fr,"BoneName");
               var filePath:String = cell(fr,"File");
               if(("b" + bone) in t.flags)
               {
                  filePath = "sprites/AutoGenerated/Sprites_Emote/" + bone + "_" + token + ".png";
                  writeTag(target,"sprites/" + bone + "_" + token + ".png",t.flags["b" + bone][2]);
                  assets.set(filePath,"sprites/" + bone + "_" + token + ".png");
                  flagCount++;
               }
               dims = [];
               for(c = 3; c < sHeader.length; c++)
               {
                  dims.push(cell(fr,sHeader[c]));
               }
               var addFlag:BmodMap = new BmodMap();
               addFlag.set("add",[token,bone,filePath].concat(dims).join(","));
               spriteAdds.push(addFlag);
            }
            var avatarRow:BmodMap = new BmodMap();
            avatarRow.set("copy",tn);
            avatarRow.set("set",sets);
            rows.push(avatarRow);
            report.push(token + " \"" + label + "\": copy of " + tn + (t.iconSprite != null || t.iconPng != null ? " with the mod's icon" : "") +
               (flagCount > 0 ? ", " + flagCount + " flag pictures" : ""));
         }
         var manifest:BmodMap = new BmodMap();
         manifest.set("id",modId);
         manifest.set("name",modName);
         manifest.set("version",meta.version != null && String(meta.version) != "" ? String(meta.version) : "1.0");
         manifest.set("author",meta.author ? String(meta.author) : "");
         manifest.set("description","Imported from " + mod.fileName + " by Bifrost: " + rows.length +
            " new avatars next to the ones the mod redrew; the originals are unchanged.");
         var strings:BmodMap = new BmodMap();
         strings.set("English",englishStrings);
         manifest.set("strings",strings);
         manifest.set("assets",assets);
         var tables:BmodMap = new BmodMap();
         tables.set("avatarTypes",rows);
         if(spriteAdds.length > 0)
         {
            tables.set("spriteData",spriteAdds);
         }
         manifest.set("tables",tables);
         if(rename.length > 0)
         {
            var byId:Object = {};
            for each(var sym:Array in mod.symbols)
            {
               byId["n" + sym[1]] = int(sym[0]);
            }
            var art:Array = copiedArt(mod)[0];
            var oldNames:Array = rename.keys.concat();
            oldNames.sort();
            var symbolList:Array = [];
            for each(var o:String in oldNames)
            {
               if(("n" + o) in byId)
               {
                  symbolList.push([byId["n" + o],rename.get(o)]);
               }
            }
            var classNames:Array = [];
            var classColours:Object = {};
            for each(o in rename.keys)
            {
               classNames.push(rename.get(o));
               classColours["c" + rename.get(o)] = null;
            }
            var swfBytes:ByteArray = modSwf(mod,art,classNames,classColours,BmodSwf.symbolClassTag(symbolList));
            var swfName:String = "UI_" + prefix + ".swf";
            writeBytes(target.resolvePath(swfName),swfBytes);
            assets.set(swfName,swfName);
            tables.set("MasterFileList",["<File Stage=\"Required\" ExcludedPlatforms=\"\" Size=\"" +
               int(Math.max(1,Math.floor(swfBytes.length / 1024))) + "\" Name=\"" + swfName + "\" Load=\"\" />"]);
         }
         writePreview(mod,target,manifest);
         manifest.set("source",mod.source);
         writeText(target.resolvePath("mod.json"),toJson(manifest,"") + "\n");
         if(unused.length > 0)
         {
            report.push("left out (" + unused.length + ", not an avatar's icon or flag): " + unused.slice(0,12).join(", "));
         }
         register(target);
         return {"folder":target,"id":modId,"kind":rows.length + " avatars","live":false,
            "message":modName + ": " + rows.length + (rows.length == 1 ? " new avatar." : " new avatars.")};
      }

      private static function touchedEntry(touched:BmodMap, row:Object) : Object
      {
         var name:String = cell(row,"AvatarName");
         if(!touched.has(name))
         {
            touched.set(name,{"row":row,"iconSprite":null,"iconPng":null,"flags":{}});
         }
         return touched.get(name);
      }

      private static function jsonString(s:String) : String
      {
         var out:String = "\"";
         for(var i:int = 0; i < s.length; i++)
         {
            var ch:String = s.charAt(i);
            var code:int = s.charCodeAt(i);
            if(ch == "\"")
            {
               out += "\\\"";
            }
            else if(ch == "\\")
            {
               out += "\\\\";
            }
            else if(ch == "\n")
            {
               out += "\\n";
            }
            else if(ch == "\r")
            {
               out += "\\r";
            }
            else if(ch == "\t")
            {
               out += "\\t";
            }
            else if(code == 8)
            {
               out += "\\b";
            }
            else if(code == 12)
            {
               out += "\\f";
            }
            else if(code < 0x20)
            {
               out += "\\u" + hexDigits(code,4);
            }
            else
            {
               out += ch;
            }
         }
         return out + "\"";
      }

      private static function pyFloat(x:Number) : String
      {
         var k:Number = BmodSwf.pyRound(x * 10000);
         if(k == 0)
         {
            return x < 0 ? "-0.0" : "0.0";
         }
         var neg:Boolean = k < 0;
         if(neg)
         {
            k = -k;
         }
         var whole:Number = Math.floor(k / 10000);
         var frac:String = String(k - whole * 10000);
         while(frac.length < 4)
         {
            frac = "0" + frac;
         }
         while(frac.length > 1 && frac.charAt(frac.length - 1) == "0")
         {
            frac = frac.substr(0,frac.length - 1);
         }
         return (neg ? "-" : "") + whole + "." + frac;
      }

      public static function toJson(v:*, indent:String) : String
      {
         var inner:String = indent + "  ";
         var parts:Array = [];
         if(v == null)
         {
            return "null";
         }
         if(v is BmodMap)
         {
            var m:BmodMap = v as BmodMap;
            if(m.length == 0)
            {
               return "{}";
            }
            for each(var k:* in m.keys)
            {
               parts.push(inner + jsonString(String(k)) + ": " + toJson(m.get(k),inner));
            }
            return "{\n" + parts.join(",\n") + "\n" + indent + "}";
         }
         if(v is Array)
         {
            var a:Array = v as Array;
            if(a.length == 0)
            {
               return "[]";
            }
            for each(var item:* in a)
            {
               parts.push(inner + toJson(item,inner));
            }
            return "[\n" + parts.join(",\n") + "\n" + indent + "]";
         }
         if(v is String)
         {
            return jsonString(v as String);
         }
         if(v is Boolean)
         {
            return v ? "true" : "false";
         }
         if(v is Number)
         {
            return String(v);
         }
         if("pyFloat" in v)
         {
            return pyFloat(Number(v.pyFloat));
         }
         var keys:Array = [];
         for(var key:String in v)
         {
            keys.push(key);
         }
         keys.sort();
         if(keys.length == 0)
         {
            return "{}";
         }
         for each(key in keys)
         {
            parts.push(inner + jsonString(key) + ": " + toJson(v[key],inner));
         }
         return "{\n" + parts.join(",\n") + "\n" + indent + "}";
      }

      public static function readFile(f:File) : ByteArray
      {
         var stream:FileStream = new FileStream();
         stream.open(f,FileMode.READ);
         var out:ByteArray = new ByteArray();
         try
         {
            stream.readBytes(out,0,stream.bytesAvailable);
         }
         finally
         {
            stream.close();
         }
         out.position = 0;
         return out;
      }

      private static function readText(f:File) : String
      {
         var bytes:ByteArray = readFile(f);
         var text:String = bytes.readUTFBytes(bytes.length);
         return text.charCodeAt(0) == 0xFEFF ? text.substr(1) : text;
      }

      private static function ensureParent(f:File) : void
      {
         var parent:File = f.parent;
         if(parent != null && !parent.exists)
         {
            parent.createDirectory();
         }
      }

      private static function writeBytes(f:File, data:ByteArray) : void
      {
         ensureParent(f);
         var stream:FileStream = new FileStream();
         stream.open(f,FileMode.WRITE);
         try
         {
            stream.writeBytes(data,0,data.length);
         }
         finally
         {
            stream.close();
         }
      }

      private static function writeTag(folder:File, rel:String, t:Object) : void
      {
         writeBytes(folder.resolvePath(rel),t is ByteArray ? t as ByteArray : BmodSwf.copy(t));
      }

      private static function writeText(f:File, text:String) : void
      {
         ensureParent(f);
         var stream:FileStream = new FileStream();
         stream.open(f,FileMode.WRITE);
         try
         {
            stream.writeUTFBytes(text);
         }
         finally
         {
            stream.close();
         }
      }
   }
}
