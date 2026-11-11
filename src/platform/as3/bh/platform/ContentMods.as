package bh.platform
{
   import flash.display.DisplayObjectContainer;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.utils.Dictionary;
   import flash.utils.setTimeout;

   public final class ContentMods
   {
      public static const FOLDER:String = "mods";

      public static const REPORT:String = "bh-mods.txt";

      private static const ID:RegExp = /^[a-z0-9._-]+$/;

      private static const FILE:RegExp = /^[A-Za-z0-9_.-]+(\/[A-Za-z0-9_.-]+)*$/;

      public static var mods:Array = [];

      public static var all:Array = [];

      public static var report:Array = [];

      private static var stringsApplied:int = 0;

      public static var added:Object = {};

      public static var ids:Object = {};

      public static var copiedIds:Object = {};

      private static var rowSources:Object = new Dictionary(true);

      private static function remember(store:Object, table:String, key:String, id:String) : void
      {
         var n:Number = Number(id);
         if(id == null || id == "" || isNaN(n))
         {
            return;
         }
         if(store[table] == null)
         {
            store[table] = {};
         }
         store[table][key] = int(n);
      }

      private static var granted:Object = {};

      private static var assets:Object = {};

      private static var swfAssets:Array = null;

      public function ContentMods()
      {
      }

      public static function init() : void
      {
         mods = [];
         report = [];
         added = {};
         granted = {};
         assets = {};
         swfAssets = null;
         var root:File = File.applicationDirectory.resolvePath(FOLDER);
         var found:Array = [];
         if(root.exists && root.isDirectory)
         {
            for each(var dir:File in root.getDirectoryListing())
            {
               if(dir.isDirectory)
               {
                  found.push(dir);
               }
            }
         }
         mods = order(readAll(found));
         all = mods.concat();
         mods = withoutDisabled(mods);
         loadGameNames();
         resolveDuplicateNames();
         for each(var mod:Object in mods)
         {
            report.push("loaded " + mod.id + " " + mod.version + " (" + mod.name + ") from " + mod.folder);
         }
         report.unshift("content mods: " + mods.length + " loaded from " + root.nativePath);
         checkStringConflicts();
         writeReport();
         Hooks.stringsLoaded.add(applyStrings);
         Hooks.tableParsing.add(applyTableRows);
         ModLanguages.init();
         ModModes.init();
         Hooks.colorSchemeOwned.add(ownsAddedColor);
         Hooks.tablesRegistered.add(parseFiles);
         Hooks.keyDown.add(reloadKey);
         Hooks.loadSetLoaded.add(fillHeroAnimations);
         Hooks.loadSetLoaded.add(function(setName:String):void
         {
            saveGameNames();
         });
         Hooks.csvParsing.add(applyCsvRows);
         Hooks.costumeOwned.add(ownsAddedCostume);
         Hooks.itemOwned.add(ownsAddedItem);
         collectAssets();
         Hooks.fileResolving.add(resolveAsset);
         for each(var withPalette:Object in mods)
         {
            if(withPalette.palette != null)
            {
               report.push("palette " + withPalette.id + ": " + Palette.add(withPalette.palette) + " shades for " +
                  withPalette.palette.costume);
            }
         }
         MapArt.packs = [];
         for each(var withArt:Object in all)
         {
            if(withArt.mapArt != null && (isLive(withArt) || isLoaded(withArt.id)))
            {
               MapArt.add(withArt,report);
            }
         }
         if(MapArt.packs.length > 0)
         {
            Hooks.fileResolving.add(MapArt.resolve);
            Hooks.levelArtLoading.add(MapArt.levelLoading);
         }
         MusicPacks.packs = [];
         for each(var withMusic:Object in all)
         {
            if((withMusic.music != null || withMusic.sounds != null) && (isLive(withMusic) || isLoaded(withMusic.id)))
            {
               MusicPacks.add(withMusic,report);
            }
         }
         writeReport();
         Hooks.fileLoaded.add(checkLoadedAsset);
         Hooks.dataCheckFailed.add(waiveCheck);
         Hooks.loadSetLoaded.add(loadSoundBanks);
      }

      private static function withoutDisabled(list:Array) : Array
      {
         var off:Object = {};
         var kept:Array = [];
         for each(var mod:Object in list)
         {
            var reason:String = ModSettings.isDisabled(mod.id) ? "switched off in the Mods screen" : null;
            for each(var need:String in mod.requires)
            {
               if(reason == null && off[need])
               {
                  reason = "it requires " + need + ", which is off";
               }
            }
            if(reason != null)
            {
               off[mod.id] = true;
               report.push("off " + mod.id + ": " + reason);
               continue;
            }
            kept.push(mod);
         }
         return kept;
      }

      public static function isLive(mod:Object) : Boolean
      {
         if((mod.mapArt == null && mod.music == null && mod.sounds == null) || mod.palette != null || (mod.files is Array && mod.files.length > 0) ||
            (mod.soundBanks is Array && mod.soundBanks.length > 0))
         {
            return false;
         }
         for each(var part:Object in [mod.tables,mod.strings,mod.assets,mod.animationAliases])
         {
            for(var any:String in part)
            {
               return false;
            }
         }
         return true;
      }

      public static function isLoaded(id:String) : Boolean
      {
         for each(var mod:Object in mods)
         {
            if(mod.id == id)
            {
               return true;
            }
         }
         return false;
      }

      private static function collectAssets() : void
      {
         var from:Object = {};
         for each(var mod:Object in mods)
         {
            for(var gamePath:String in mod.assets)
            {
               var file:File = (mod.dir as File).resolvePath(mod.assets[gamePath]);
               if(!file.exists)
               {
                  report.push("asset skipped " + mod.id + ": " + mod.assets[gamePath] + " is missing");
                  continue;
               }
               if(from[gamePath] != null)
               {
                  report.push("conflict asset " + gamePath + ": " + from[gamePath] + " is overridden by " + mod.id);
               }
               assets[gamePath] = file;
               swfAssets = null;
               from[gamePath] = mod.id;
               report.push("asset " + gamePath + " from " + mod.id + " (" + file.size + " bytes)");
            }
         }
         writeReport();
      }

      public static function icon(name:String, interactive:Boolean) : Object
      {
         if(name == null)
         {
            return null;
         }
         if(swfAssets == null)
         {
            swfAssets = [];
            for(var key:String in assets)
            {
               if(key.substr(-4).toLowerCase() == ".swf")
               {
                  swfAssets.push(key);
               }
            }
         }
         for each(var path:String in swfAssets)
         {
            try
            {
               var info:Object = ArchiveLoader.method_3616(path);
               if(info == null || !info.applicationDomain.hasDefinition(name))
               {
                  continue;
               }
               var cls:Class = info.applicationDomain.getDefinition(name) as Class;
               var clip:Object = new cls();
               clip.stopAllMovieClips();
               class_687.method_5827(clip as DisplayObjectContainer,interactive);
               return clip;
            }
            catch(e:Error)
            {
               report.push("icon " + name + " from " + path + " failed: " + e.message);
               writeReport();
            }
         }
         return null;
      }

      private static function waiveCheck(message:String) : Boolean
      {
         var m:Array = /^\[CostumeType\] costume (\S+) is crossover so it needs a CrossoverGem xor ParentCrossover/.exec(message);
         if(m == null || !isAdded("costumeTypes",m[1]))
         {
            return false;
         }
         report.push("check waived for " + m[1] + " (added by " + added["costumeTypes"][m[1]] + "): a crossover without a gem");
         writeReport();
         return true;
      }

      private static function modPath(value:String, mod:Object) : String
      {
         if(value.indexOf("@mod:") != 0)
         {
            return value;
         }
         return "../../" + FOLDER + "/" + (mod.dir as File).name + "/" + value.substr(5);
      }

      private static var banksLoaded:Boolean = false;

      private static function loadSoundBanks(setName:String) : void
      {
         if(banksLoaded)
         {
            return;
         }
         banksLoaded = true;
         for each(var mod:Object in mods)
         {
            for each(var bank:String in mod.soundBanks)
            {
               var name:String = "../../" + FOLDER + "/" + (mod.dir as File).name + "/" + bank;
               try
               {
                  class_727.LoadBank(name,false);
                  report.push("sound bank " + bank + " of " + mod.id + ": " +
                     (Object(class_727.var_2582).h[name] ? "loaded" : "not loaded (the sound engine refused " + name + ")"));
               }
               catch(e:Error)
               {
                  report.push("sound bank " + bank + " of " + mod.id + " failed: " + e.message);
               }
            }
         }
         writeReport();
      }

      private static function resolveAsset(value:*, fileName:String, fileType:String) : *
      {
         if(assets[fileName] == null)
         {
            return null;
         }
         if(granted["asset:" + fileName] == null)
         {
            granted["asset:" + fileName] = true;
            report.push("asset read " + fileName + " (" + fileType + ") from " + (assets[fileName] as File).nativePath);
            writeReport();
         }
         return assets[fileName];
      }

      private static function checkLoadedAsset(file:Object) : void
      {
         var name:String = String(file["fileName"]);
         if(assets[name] == null || name.substr(-4).toLowerCase() != ".swf")
         {
            return;
         }
         try
         {
            var loader:Object = file.var_6415;
            var info:Object = loader != null ? loader.contentLoaderInfo : ArchiveLoader.method_3616(name);
            report.push("asset state " + name + ": " + file.var_6640);
            if(info == null)
            {
               report.push("asset loaded " + name + ": no LoaderInfo (the SWF didn't load)");
            }
            else
            {
               var names:Array = [];
               try
               {
                  var list:* = info.applicationDomain.getQualifiedDefinitionNames();
                  for(var i:int = 0; i < list.length; i++)
                  {
                     names.push(list[i]);
                  }
               }
               catch(e:Error)
               {
                  names.push("(definition names unavailable: " + e.message + ")");
               }
               report.push("asset loaded " + name + ": " + info.bytesTotal + " bytes, " + names.length + " classes (" +
                  names.slice(0,4).join(", ") + (names.length > 4 ? ", ..." : "") + ")");
            }
         }
         catch(err:Error)
         {
            report.push("asset loaded " + name + ": check failed: " + err.message);
         }
         writeReport();
      }

      private static function ownsAddedItem(kind:String, item:Object) : Boolean
      {
         if(item == null)
         {
            return false;
         }
         var table:String = null;
         var name:String = null;
         switch(kind)
         {
            case "WeaponSkin":
               table = "weaponSkinTypes";
               name = item.mWeaponSkinName;
               break;
            case "Avatar":
               table = "avatarTypes";
               name = item.var_12772;
               break;
            case "Taunt":
               table = "TauntTypes";
               name = item.mTauntName;
               break;
            case "Emoji":
               table = "EmojiTypes";
               name = item.var_1856;
               break;
            case "KOEffect":
               table = "TrailEffectTypes";
               name = item.var_7437;
               break;
            case "SpawnBot":
               table = "SpawnBotTypes";
               name = item.mSpawnBotName;
               break;
            case "Border":
               table = "SeasonBorderTypes";
               name = item.var_13754;
               break;
            case "Podium":
               table = "PodiumTypes";
               name = item.mPodiumName;
               break;
            case "PlayerTheme":
               table = "PlayerThemeTypes";
               name = item.var_11826;
               break;
            case "Companion":
               table = "CompanionTypes";
               name = item.var_3857;
               break;
            case "Moniker":
               table = "MonikerTypes";
               name = item.var_5322;
               break;
            case "EmitterGroup":
               table = "EmitterGroupTypes";
               name = item.var_2065;
               break;
            default:
               return false;
         }
         if(name == null || !isAdded(table,name))
         {
            return false;
         }
         if(granted[kind + ":" + name] == null)
         {
            granted[kind + ":" + name] = true;
            report.push("owned " + table + "/" + name + ": added by " + added[table][name] + ", counts as owned");
            writeReport();
         }
         return true;
      }

      private static function ownsAddedCostume(costume:Object, hero:Object) : Boolean
      {
         if(costume == null || !isAdded("costumeTypes",costume.mCostumeName))
         {
            return false;
         }
         if(hero != null && hero != costume.var_7289)
         {
            return false;
         }
         if(granted["costume:" + costume.mCostumeName] == null)
         {
            granted["costume:" + costume.mCostumeName] = true;
            report.push("owned costumeTypes/" + costume.mCostumeName + ": added by " +
               added["costumeTypes"][costume.mCostumeName] + ", counts as owned");
            writeReport();
         }
         return true;
      }

      private static function applyCsvRows(text:String, tableName:String, offset:int) : String
      {
         var wanted:Boolean = false;
         for each(var m:Object in mods)
         {
            if(m.tables[tableName] != null)
            {
               wanted = true;
            }
         }
         if(!wanted)
         {
            return null;
         }
         var lines:Array = text.substr(offset).split("\n");
         var header:Array = splitCsv(stripCr(lines[0]));
         var idCols:Array = csvIdColumns(lines,header);
         recordCsvNames(tableName,lines,header);
         var column:Object = {};
         for(var c:int = 0; c < header.length; c++)
         {
            column[header[c]] = c;
         }
         var byKey:Object = {};
         for(var i:int = 1; i < lines.length; i++)
         {
            var line:String = stripCr(lines[i]);
            if(line.length > 0)
            {
               byKey[splitCsv(line)[0]] = i;
            }
         }
         var nextIds:Object = {};
         var touched:Object = {};
         for each(var mod:Object in mods)
         {
            for each(var row:* in mod.tables[tableName])
            {
               var fields:Array;
               var base:Array = null;
               if(!(row is String) && row.add != null)
               {
                  var addFields:Array = splitCsv(String(row.add));
                  for(c = 0; c < addFields.length; c++)
                  {
                     addFields[c] = modPath(String(addFields[c]),mod);
                  }
                  var addAt:int = lines.length;
                  while(addAt > 1 && stripCr(lines[addAt - 1]) == "")
                  {
                     addAt--;
                  }
                  lines.splice(addAt,0,joinCsv(addFields));
                  report.push("row added " + tableName + ": " + addFields.slice(0,2).join(",") + " (" + mod.id + ")");
                  continue;
               }
               if(row is String)
               {
                  fields = splitCsv(String(row));
               }
               else
               {
                  if(row.copy != null)
                  {
                     if(byKey[row.copy] == null)
                     {
                        report.push("row skipped " + mod.id + " " + tableName + ": no row " + row.copy + " to copy");
                        continue;
                     }
                     base = splitCsv(stripCr(lines[byKey[row.copy]]));
                  }
                  fields = [];
                  var bad:String = null;
                  for(var name:String in row.set)
                  {
                     if(column[name] == null)
                     {
                        bad = name;
                        break;
                     }
                     fields[column[name]] = modPath(String(row.set[name]),mod);
                  }
                  if(bad != null)
                  {
                     report.push("row skipped " + mod.id + " " + tableName + ": no column " + bad);
                     continue;
                  }
               }
               for(c = 0; c < header.length; c++)
               {
                  if(fields[c] == null)
                  {
                     fields[c] = "";
                  }
               }
               var key:String = fields[0] != "" ? fields[0] : (base != null ? base[0] : "");
               if(key == "")
               {
                  report.push("row skipped " + mod.id + " " + tableName + ": no value in the first column (" + header[0] + ")");
                  continue;
               }
               var isNew:Boolean = byKey[key] == null;
               for(c = 0; c < header.length; c++)
               {
                  if(idCols[c] !== true)
                  {
                     continue;
                  }
                  var effective:String = fields[c] != "" ? fields[c] : (base != null && c < base.length ? base[c] : "");
                  if(isNew && effective == "@none" && !idCols.always[c])
                  {
                     continue;
                  }
                  if(isNew && effective == "" && !idCols.always[c])
                  {
                     continue;
                  }
                  if(isNew && fields[c] != "@id")
                  {
                     if(fields[c] != "" && fields[c].indexOf("@id/") != 0)
                     {
                        report.push("id " + tableName + "/" + header[c] + " " + fields[c] + " for " + key + " ignored: IDs are assigned (" + mod.id + ")");
                     }
                     fields[c] = "@id";
                  }
                  else if(!isNew && fields[c] != "")
                  {
                     report.push("id " + tableName + "/" + header[c] + " of " + key + " kept: a game row's ID can't change (" + mod.id + ")");
                     fields[c] = "";
                  }
               }
               for(var gcol:String in GROUP_INDEX)
               {
                  var ci:* = column[gcol], gi:* = column[GROUP_INDEX[gcol]];
                  if(!isNew || ci == null || gi == null)
                  {
                     continue;
                  }
                  var want:String = fields[ci] != "" ? fields[ci] : (base != null && ci < base.length ? base[ci] : "");
                  var owner:String = fields[gi] != "" ? fields[gi] : (base != null && gi < base.length ? base[gi] : "");
                  if(want.indexOf("@id") == 0)
                  {
                     continue;
                  }
                  if(want == "" || csvValueTaken(lines,ci,gi,owner,want))
                  {
                     if(want != "")
                     {
                        report.push("id " + tableName + "/" + gcol + " " + want + " for " + key + " is taken for " + owner + ": the next free one is used (" + mod.id + ")");
                     }
                     fields[ci] = "@id/" + GROUP_INDEX[gcol];
                  }
               }
               for(c = 0; c < header.length; c++)
               {
                  if(fields[c] == "@id" && HASHED_IDS[tableName + "/" + header[c]] != null)
                  {
                     fields[c] = String(hashedId(key,usedCsvIds(lines,c),HASHED_IDS[tableName + "/" + header[c]]));
                     report.push("id " + tableName + "/" + header[c] + " = " + fields[c] + " for " + key + " (" + mod.id + ")");
                  }
                  else if(fields[c] == "@id")
                  {
                     if(nextIds[c] == null)
                     {
                        nextIds[c] = maxCsvField(lines,c) + 1;
                     }
                     fields[c] = String(nextIds[c]++);
                     report.push("id " + tableName + "/" + header[c] + " = " + fields[c] + " for " + key + " (" + mod.id + ")");
                  }
                  else if(fields[c].indexOf("@id/") == 0)
                  {
                     var g:* = column[fields[c].substr(4)];
                     var gv:String = g == null ? "" : (fields[g] != "" ? fields[g] : (base != null && g < base.length ? base[g] : ""));
                     var gk:String = c + "/" + gv;
                     if(GROUP_INDEX[header[c]] != null && g != null)
                     {
                        nextIds[gk] = lowestFreeCsv(lines,c,int(g),gv);
                     }
                     else if(nextIds[gk] == null)
                     {
                        nextIds[gk] = maxCsvField(lines,c,g == null ? -1 : int(g),gv) + 1;
                     }
                     fields[c] = String(nextIds[gk]++);
                     report.push("id " + tableName + "/" + header[c] + " = " + fields[c] + " for " + key + " (next free for " +
                        (g == null ? "the whole table" : header[g] + " " + gv) + ", " + mod.id + ")");
                  }
               }
               if(touched[key] != null)
               {
                  report.push("conflict row " + tableName + "/" + key + ": " + touched[key] + " is overridden by " + mod.id);
               }
               touched[key] = mod.id;
               var existing:Array = byKey[key] != null ? splitCsv(stripCr(lines[byKey[key]])) : base;
               var out:Array = [];
               for(c = 0; c < header.length; c++)
               {
                  out[c] = fields[c] != "" ? fields[c] : (existing != null && c < existing.length ? existing[c] : "");
                  if(out[c] == "@none")
                  {
                     out[c] = "";
                  }
               }
               out[0] = key;
               if(byKey[key] != null)
               {
                  lines[byKey[key]] = joinCsv(out);
                  report.push("row changed " + tableName + "/" + key + " (" + mod.id + ")");
               }
               else
               {
                  var at:int = lines.length;
                  while(at > 1 && stripCr(lines[at - 1]) == "")
                  {
                     at--;
                  }
                  lines.splice(at,0,joinCsv(out));
                  byKey[key] = at;
                  if(added[tableName] == null)
                  {
                     added[tableName] = {};
                  }
                  added[tableName][key] = mod.id;
                  var idCol:int = header.indexOf(String(header[0]).replace(/Name$/,"ID"));
                  if(idCol > 0)
                  {
                     remember(ids,tableName,key,out[idCol]);
                     if(base != null && base.length > idCol && added[tableName][base[0]] == null)
                     {
                        remember(copiedIds,tableName,key,base[idCol]);
                     }
                  }
                  report.push("row added " + tableName + "/" + key + (base != null ? " (copy of " + base[0] + ")" : "") +
                     " (" + mod.id + ")");
               }
            }
         }
         writeReport();
         return text.substr(0,offset) + lines.join("\n");
      }

      private static function copyRow(root:Xml, spec:Object, modId:String, tableName:String) : Xml
      {
         if(spec.copy == null)
         {
            report.push("row skipped " + modId + " " + tableName + ": an object row needs \"copy\" in an XML table");
            return null;
         }
         var source:Xml = null;
         for each(var candidate:Xml in elements(root))
         {
            if(keyValues(candidate) == spec.copy)
            {
               source = candidate;
               break;
            }
         }
         if(source == null)
         {
            report.push("row skipped " + modId + " " + tableName + ": no row " + spec.copy + " to copy");
            return null;
         }
         var row:Xml = Xml.parse(source.toString()).method_7292();
         rowSources[row] = source;
         for(var name:String in spec.set)
         {
            var value:String = String(spec.set[name]);
            if(name.charAt(0) == "@")
            {
               row.method_65(name.substr(1),value);
               continue;
            }
            for each(var old:Xml in elements(row))
            {
               if(old.var_4402 == name)
               {
                  row.removeChild(old);
               }
            }
            row.addChild(Xml.parse("<" + name + ">" + escapeXml(value) + "</" + name + ">").method_7292());
         }
         return row;
      }

      private static function escapeXml(text:String) : String
      {
         return text.split("&").join("&amp;").split("<").join("&lt;").split(">").join("&gt;");
      }

      public static const NAMES_FILE:String = "bh-game-names.json";

      private static const KEEP_FIELDS:Object = {"WeaponSet":true};

      private static var gameNames:Object = {};

      private static var gameNamesChanged:Boolean = false;

      private static function namesFile() : File
      {
         return File.applicationStorageDirectory.resolvePath(NAMES_FILE);
      }

      private static function loadGameNames() : void
      {
         gameNames = {};
         try
         {
            if(namesFile().exists)
            {
               gameNames = JSON.parse(readText(namesFile()));
            }
         }
         catch(e:*)
         {
            gameNames = {};
         }
      }

      private static function saveGameNames() : void
      {
         if(!gameNamesChanged)
         {
            return;
         }
         try
         {
            var stream:FileStream = new FileStream();
            stream.open(namesFile(),FileMode.WRITE);
            stream.writeUTFBytes(JSON.stringify(gameNames));
            stream.close();
            gameNamesChanged = false;
         }
         catch(e:*)
         {
         }
      }

      private static function recordXmlNames(tableName:String, root:Xml) : void
      {
         var names:Object = {};
         var field:String = null;
         for each(var r:Xml in elements(root))
         {
            var keys:Array = keyAttributes(r);
            if(attributes(r).length == 0)
            {
               continue;
            }
            if(field == null && keys.length == 1)
            {
               field = keys[0];
            }
            names[keyValues(r)] = true;
         }
         setGameNames(tableName,{"kind":"xml","field":field,"names":names});
      }

      private static function recordCsvNames(tableName:String, lines:Array, header:Array) : void
      {
         var names:Object = {};
         for(var i:int = 1; i < lines.length; i++)
         {
            var first:String = splitCsv(stripCr(lines[i]))[0];
            if(first != "")
            {
               names[first] = true;
            }
         }
         setGameNames(tableName,{"kind":"csv","field":header[0],"names":names});
      }

      private static function setGameNames(tableName:String, info:Object) : void
      {
         if(JSON.stringify(gameNames[tableName]) != JSON.stringify(info))
         {
            gameNames[tableName] = info;
            gameNamesChanged = true;
         }
      }

      private static function rowName(row:*, info:Object) : String
      {
         if(!(row is String) && row.add is String)
         {
            return null;
         }
         if(!(row is String))
         {
            if(info.kind == "xml")
            {
               return info.field == null ? null : (row.set["@" + info.field] != null ? String(row.set["@" + info.field]) : row.copy);
            }
            return row.set[info.field] != null ? String(row.set[info.field]) : row.copy;
         }
         if(info.kind == "csv")
         {
            return splitCsv(String(row))[0];
         }
         try
         {
            var x:Xml = Xml.parse(String(row)).method_7292();
            return x == null || attributes(x).length == 0 ? null : keyValues(x);
         }
         catch(e:*)
         {
         }
         return null;
      }

      public static function swapToken(value:String, renames:Object) : String
      {
         if(value == null)
         {
            return value;
         }
         if(renames[value] != null)
         {
            return renames[value];
         }
         if(value.indexOf(",") < 0 && value.charAt(0) != "+")
         {
            return value;
         }
         var parts:Array = value.split(",");
         for(var i:int = 0; i < parts.length; i++)
         {
            var core:String = String(parts[i]).replace(/^\s+|\s+$/g,"");
            var plus:Boolean = core.charAt(0) == "+";
            if(plus)
            {
               core = core.substr(1);
            }
            if(renames[core] != null)
            {
               parts[i] = String(parts[i]).split(core).join(renames[core]);
            }
         }
         return parts.join(",");
      }

      private static function renameInXml(node:Xml, renames:Object) : void
      {
         for each(var a:String in attributes(node))
         {
            node.method_65(a,swapToken(node.method_4935(a),renames));
         }
         var kids:Array = elements(node);
         if(kids.length == 0 && !KEEP_FIELDS[node.var_4402] && textOf(node) != "")
         {
            setText(node,swapToken(textOf(node),renames));
         }
         for each(var k:Xml in kids)
         {
            renameInXml(k,renames);
         }
      }

      private static function renameInRow(row:*, renames:Object, kind:String) : *
      {
         if(!(row is String) && row.add is String)
         {
            return row;
         }
         if(!(row is String))
         {
            var set:Object = {};
            for(var k:String in row.set)
            {
               set[k] = KEEP_FIELDS[k] ? row.set[k] : swapToken(String(row.set[k]),renames);
            }
            return {"copy":row.copy,"set":set};
         }
         if(kind == "csv")
         {
            var cells:Array = splitCsv(String(row));
            for(var c:int = 0; c < cells.length; c++)
            {
               cells[c] = swapToken(cells[c],renames);
            }
            return joinCsv(cells);
         }
         try
         {
            var x:Xml = Xml.parse(String(row)).method_7292();
            renameInXml(x,renames);
            return x.toString();
         }
         catch(e:*)
         {
         }
         return row;
      }

      private static function resolveDuplicateNames() : void
      {
         var addedBy:Object = {};
         for each(var mod:Object in mods)
         {
            var renames:Object = {};
            var any:Boolean = false;
            for(var table:String in mod.tables)
            {
               var info:Object = gameNames[table];
               if(info == null)
               {
                  continue;
               }
               for each(var row:* in mod.tables[table])
               {
                  var name:String = rowName(row,info);
                  if(name == null || name == "" || info.names[name])
                  {
                     continue;
                  }
                  var k:String = table + "\n" + name;
                  if(addedBy[k] != null && addedBy[k] != mod.id)
                  {
                     var fresh:String = String(mod.id).replace(/[^A-Za-z0-9_]/g,"_") + "_" + name;
                     renames[name] = fresh;
                     any = true;
                     report.push("renamed " + table + "/" + name + " to " + fresh + " in " + mod.id + ": " + addedBy[k] + " added that name first");
                  }
                  else
                  {
                     addedBy[k] = mod.id;
                  }
               }
            }
            if(!any)
            {
               continue;
            }
            mod.fileRenames = renames;
            for(table in mod.tables)
            {
               var kind:String = gameNames[table] != null ? gameNames[table].kind : "xml";
               var rows:Array = [];
               for each(row in mod.tables[table])
               {
                  rows.push(renameInRow(row,renames,kind));
               }
               mod.tables[table] = rows;
               info = gameNames[table];
               for each(row in rows)
               {
                  name = info == null ? null : rowName(row,info);
                  if(name != null && !info.names[name] && addedBy[table + "\n" + name] == null)
                  {
                     addedBy[table + "\n" + name] = mod.id;
                  }
               }
            }
         }
         var known:int = 0;
         for(var t:String in gameNames)
         {
            known++;
         }
         if(known == 0 && mods.length > 1)
         {
            report.push("names: the game's own names aren't known yet (first start); duplicate names between mods are resolved from the next start");
         }
      }

      private static const GROUP_INDEX:Object = {"CostumeIndex":"OwnerHero"};

      private static const NOT_IDS:Object = {"SteamAppID":true,"AppID":true};

      private static const HASHED_IDS:Object = {"HeroTypes/HeroID":[1000,64999]};

      private static const ID_LIMITS:Object = {"TauntTypes/TauntID":1023,"SpawnBotTypes/SpawnBotID":1023,
         "TrailEffectTypes/TrailEffectID":1023,"SeasonBorderTypes/SeasonBorderID":1023,"ColorSchemeTypes/ColorSchemeID":1024};

      private static const STRICT_TABLES:Object = {"TauntTypes":true,"EmojiTypes":true,"SpawnBotTypes":true,"TrailEffectTypes":true,
         "SeasonBorderTypes":true,"MonikerTypes":true};

      private static function isIdColumn(name:String, values:Array) : Boolean
      {
         if(name.length < 3 || name.substr(name.length - 2) != "ID" || NOT_IDS[name] || values.length == 0)
         {
            return false;
         }
         var seen:Object = {};
         for each(var v:String in values)
         {
            if(!/^\s*-?\d+\s*$/.test(v) || seen[v])
            {
               return false;
            }
            seen[v] = true;
         }
         return true;
      }

      private static function csvIdColumns(lines:Array, header:Array) : Array
      {
         var values:Array = [];
         var c:int;
         for(c = 0; c < header.length; c++)
         {
            values[c] = [];
         }
         for(var i:int = 1; i < lines.length; i++)
         {
            var cells:Array = splitCsv(stripCr(lines[i]));
            if(cells.length < 2 || cells[0] == "Template" || cells[0] == "")
            {
               continue;
            }
            for(c = 0; c < header.length && c < cells.length; c++)
            {
               if(cells[c] != "")
               {
                  values[c].push(cells[c]);
               }
            }
         }
         var out:Array = [];
         var rows:int = 0;
         for(i = 1; i < lines.length; i++)
         {
            var r:Array = splitCsv(stripCr(lines[i]));
            if(r.length > 1 && r[0] != "Template" && r[0] != "")
            {
               rows++;
            }
         }
         out.always = [];
         for(c = 0; c < header.length; c++)
         {
            out[c] = isIdColumn(header[c],values[c]);
            out.always[c] = values[c].length >= rows * 0.9;
         }
         return out;
      }

      private static function csvValueTaken(lines:Array, column:int, group:int, owner:String, value:String) : Boolean
      {
         for(var i:int = 1; i < lines.length; i++)
         {
            var cells:Array = splitCsv(stripCr(lines[i]));
            if(column < cells.length && group < cells.length && cells[group] == owner && cells[column] == value)
            {
               return true;
            }
         }
         return false;
      }

      private static function xmlIdTags(root:Xml) : Object
      {
         var values:Object = {};
         for each(var row:Xml in elements(root))
         {
            if(keyValues(row) == "Template")
            {
               continue;
            }
            for each(var child:Xml in elements(row))
            {
               var t:String = textOf(child);
               if(t != "")
               {
                  if(values[child.var_4402] == null)
                  {
                     values[child.var_4402] = [];
                  }
                  values[child.var_4402].push(t);
               }
            }
         }
         var rows:int = 0;
         for each(var r:Xml in elements(root))
         {
            if(keyValues(r) != "Template")
            {
               rows++;
            }
         }
         var out:Object = {};
         for(var tag:String in values)
         {
            if(isIdColumn(tag,values[tag]))
            {
               out[tag] = values[tag].length >= rows * 0.9 ? "always" : "optional";
            }
         }
         return out;
      }

      private static function enforceXmlIds(row:Xml, isNew:Boolean, idTags:Object, tableName:String, key:String, modId:String) : void
      {
         var have:Object = {};
         for each(var child:Xml in elements(row))
         {
            var tag:String = child.var_4402;
            if(!idTags[tag])
            {
               continue;
            }
            have[tag] = true;
            var t:String = textOf(child);
            if(isNew && t != "@id")
            {
               if(t != "" && t.indexOf("@id/") != 0)
               {
                  report.push("id " + tableName + "/" + tag + " " + t + " for " + key + " ignored: IDs are assigned (" + modId + ")");
               }
               row.removeChild(child);
               row.addChild(Xml.parse("<" + tag + ">@id</" + tag + ">").method_7292());
            }
            else if(!isNew)
            {
               report.push("id " + tableName + "/" + tag + " of " + key + " kept: a game row's ID can't change (" + modId + ")");
               row.removeChild(child);
            }
         }
         if(isNew)
         {
            for(var need:String in idTags)
            {
               if(!have[need] && idTags[need] == "always")
               {
                  row.addChild(Xml.parse("<" + need + ">@id</" + need + ">").method_7292());
               }
            }
         }
      }

      private static function stripCr(line:String) : String
      {
         return line.charAt(line.length - 1) == "\r" ? line.substr(0,line.length - 1) : line;
      }

      public static function splitCsv(line:String) : Array
      {
         var out:Array = [];
         var field:String = "";
         var quoted:Boolean = false;
         for(var i:int = 0; i < line.length; i++)
         {
            var ch:String = line.charAt(i);
            if(quoted)
            {
               if(ch == "\"")
               {
                  if(line.charAt(i + 1) == "\"")
                  {
                     field += "\"";
                     i++;
                  }
                  else
                  {
                     quoted = false;
                  }
               }
               else
               {
                  field += ch;
               }
            }
            else if(ch == "\"")
            {
               quoted = true;
            }
            else if(ch == ",")
            {
               out.push(field);
               field = "";
            }
            else
            {
               field += ch;
            }
         }
         out.push(field);
         return out;
      }

      public static function joinCsv(fields:Array) : String
      {
         var out:Array = [];
         for each(var f:String in fields)
         {
            out.push(/[",\n\r]/.test(f) ? "\"" + f.split("\"").join("\"\"") + "\"" : f);
         }
         return out.join(",");
      }

      private static function maxCsvField(lines:Array, column:int, group:int = -1, groupValue:String = null) : int
      {
         var best:int = 0;
         for(var i:int = 1; i < lines.length; i++)
         {
            var cells:Array = splitCsv(stripCr(lines[i]));
            if(group >= 0 && (group >= cells.length || cells[group] != groupValue))
            {
               continue;
            }
            if(column < cells.length && /^\s*-?\d+\s*$/.test(cells[column]))
            {
               best = Math.max(best,int(cells[column]));
            }
         }
         return best;
      }

      private static function lowestFreeCsv(lines:Array, column:int, group:int, groupValue:String) : int
      {
         var used:Object = {};
         for(var i:int = 1; i < lines.length; i++)
         {
            var cells:Array = splitCsv(stripCr(lines[i]));
            if(group < cells.length && column < cells.length && cells[group] == groupValue && /^\s*-?\d+\s*$/.test(cells[column]))
            {
               used["i" + int(cells[column])] = true;
            }
         }
         var free:int = 1;
         while(used["i" + free])
         {
            free++;
         }
         return free;
      }

      internal static function nameHash(name:String) : Number
      {
         var h:Number = 2166136261;
         for(var i:int = 0; i < name.length; i++)
         {
            h = Number((uint(h) ^ name.charCodeAt(i)) >>> 0);
            h = (h * 403 + (h % 256) * 16777216) % 4294967296;
         }
         return h;
      }

      internal static function hashedId(name:String, used:Object, range:Array) : int
      {
         var low:int = int(range[0]);
         var span:int = int(range[1]) - low + 1;
         var start:int = int(nameHash(name) % span);
         for(var n:int = 0; n < span; n++)
         {
            var id:int = low + (start + n) % span;
            if(!used["i" + id])
            {
               return id;
            }
         }
         return 0;
      }

      private static function usedXmlIds(root:Xml, tag:String) : Object
      {
         var used:Object = {};
         for each(var row:Xml in elements(root))
         {
            var text:String = fieldText(row,tag);
            if(text != null && /^\s*-?\d+\s*$/.test(text))
            {
               used["i" + int(text)] = true;
            }
         }
         return used;
      }

      private static function usedCsvIds(lines:Array, column:int) : Object
      {
         var used:Object = {};
         for(var i:int = 1; i < lines.length; i++)
         {
            var cells:Array = splitCsv(stripCr(lines[i]));
            if(column < cells.length && /^\s*-?\d+\s*$/.test(cells[column]))
            {
               used["i" + int(cells[column])] = true;
            }
         }
         return used;
      }

      private static function tagsOf(root:Xml) : Object
      {
         var out:Object = {};
         for each(var row:Xml in elements(root))
         {
            for each(var child:Xml in elements(row))
            {
               out[child.var_4402] = true;
            }
         }
         return out;
      }

      private static function dropUnknownTags(row:Xml, known:Object, tableName:String, key:String, modId:String) : void
      {
         for each(var child:Xml in elements(row))
         {
            if(!known[child.var_4402])
            {
               row.removeChild(child);
               report.push("column dropped " + tableName + "/" + key + ": " + child.var_4402 + " is no column of " + tableName +
                  " (the game stops loading on one) (" + modId + ")");
            }
         }
      }

      private static function keepOneDefaultEmoji(root:Xml, row:Xml, key:String, modId:String) : void
      {
         var flag:String = fieldText(row,"DefaultUnlocked");
         if(flag == null || String(flag).toLowerCase() != "true")
         {
            return;
         }
         var category:String = fieldText(row,"Category");
         for each(var other:Xml in elements(root))
         {
            var otherFlag:String = fieldText(other,"DefaultUnlocked");
            if(otherFlag != null && String(otherFlag).toLowerCase() == "true" && fieldText(other,"Category") == category &&
               keyValues(other) != "Template")
            {
               for each(var child:Xml in elements(row))
               {
                  if(child.var_4402 == "DefaultUnlocked")
                  {
                     setText(child,"FALSE");
                  }
               }
               report.push("emoji " + key + " not a default: " + keyValues(other) + " is already the default of " + category +
                  " (two defaults in one category stop the game) (" + modId + ")");
               return;
            }
         }
      }

      private static function freeIdBelow(root:Xml, tag:String, limit:int) : int
      {
         var used:Object = {};
         for each(var row:Xml in elements(root))
         {
            var text:String = fieldText(row,tag);
            if(text != null && /^\s*-?\d+\s*$/.test(text))
            {
               used["i" + int(text)] = true;
            }
         }
         for(var id:int = 1; id < limit; id++)
         {
            if(!used["i" + id])
            {
               return id;
            }
         }
         return 0;
      }

      private static var filledAnimations:Object = {};

      private static function fillHeroAnimations(setName:String) : void
      {
         var heroes:Object = added["HeroTypes"] || {};
         var classes:Object = class_10.var_9468;
         if(classes == null)
         {
            return;
         }
         fillAnimationAliases(classes,setName);
         var filled:int = 0;
         for(var classKey:String in classes.h)
         {
            var byName:Object = classes.h[classKey] == null ? null : classes.h[classKey].var_14598;
            if(byName == null)
            {
               continue;
            }
            for(var animName:String in byName.h)
            {
               if(animName.length <= 6 || animName.substr(animName.length - 6) != "Random")
               {
                  continue;
               }
               var prefix:String = animName.substr(0,animName.length - 6);
               for(var hero:String in heroes)
               {
                  var own:String = prefix + hero;
                  if(byName.h[own] == null)
                  {
                     byName.h[own] = byName.h[animName];
                     filled++;
                     filledAnimations[own] = animName;
                  }
               }
            }
         }
         if(filled > 0)
         {
            report.push("animations after load set " + setName + ": " + filled + " per-legend animations of mod legends " +
               "use the Random ones (" + namesOf(filledAnimations).join(", ") + ")");
            writeReport();
         }
      }

      private static var aliasedAnimations:Object = {};

      private static function fillAnimationAliases(classes:Object, setName:String) : void
      {
         var filled:int = 0;
         for each(var mod:Object in mods)
         {
            for(var to:String in mod.animationAliases)
            {
               var from:String = mod.animationAliases[to];
               for(var classKey:String in classes.h)
               {
                  var byName:Object = classes.h[classKey] == null ? null : classes.h[classKey].var_14598;
                  if(byName == null)
                  {
                     continue;
                  }
                  for(var animName:String in byName.h)
                  {
                     if(animName.length <= from.length || animName.substr(animName.length - from.length) != from)
                     {
                        continue;
                     }
                     var own:String = animName.substr(0,animName.length - from.length) + to;
                     if(byName.h[own] == null)
                     {
                        byName.h[own] = byName.h[animName];
                        aliasedAnimations[own] = animName;
                        filled++;
                     }
                  }
               }
            }
         }
         if(filled > 0)
         {
            report.push("animations after load set " + setName + ": " + filled + " shared under mods' aliases (" +
               namesOf(aliasedAnimations).join(", ") + ")");
            writeReport();
         }
      }

      private static function namesOf(map:Object) : Array
      {
         var out:Array = [];
         for(var k:String in map)
         {
            out.push(k);
         }
         return out.sort();
      }

      public static const RELOAD_KEY:uint = 119;

      private static function reloadKey(event:Object) : Boolean
      {
         if(event.keyCode != RELOAD_KEY || Platform.matchRunning)
         {
            return false;
         }
         report.push("F8: reading the mod files again");
         parseFiles();
         writeReport();
         return true;
      }

      public static function reloadFiles() : void
      {
         report.push("reading the mod files again (map editor save)");
         parseFiles();
         writeReport();
      }

      public static function levelFile(levelName:String) : Object
      {
         for each(var mod:Object in mods)
         {
            for each(var path:String in mod.files)
            {
               var file:File = (mod.dir as File).resolvePath(path);
               if(!file.exists)
               {
                  continue;
               }
               var found:Array = new RegExp('<LevelDesc\\b[^>]*\\bLevelName="([^"]*)"').exec(readText(file));
               if(found != null && (mod.fileRenames != null ? swapToken(found[1],mod.fileRenames) : found[1]) == levelName)
               {
                  return {"mod":mod,"file":file,"path":path};
               }
            }
         }
         return null;
      }

      private static function parseFiles() : void
      {
         var any:Boolean = false;
         for each(var mod:Object in mods)
         {
            for each(var path:String in mod.files)
            {
               any = true;
               var file:File = (mod.dir as File).resolvePath(path);
               if(!file.exists)
               {
                  report.push("file skipped " + mod.id + "/" + path + ": not found");
                  continue;
               }
               try
               {
                  var root:Xml = Xml.parse(readText(file)).method_7292();
                  if(root != null && mod.fileRenames != null)
                  {
                     for each(var ra:String in attributes(root))
                     {
                        root.method_65(ra,swapToken(root.method_4935(ra),mod.fileRenames));
                     }
                  }
                  if(root != null && root.var_4402 == "LevelDesc" && !hasChild(root,"Background"))
                  {
                     root.addChild(Xml.parse(DEFAULT_BACKGROUND).method_7292());
                     report.push("file " + mod.id + "/" + path + ": no Background, which the game needs; added " + DEFAULT_BACKGROUND);
                  }
                  if(root != null && root.var_4402 == "LevelDesc" && !hasChild(root,"NavNode"))
                  {
                     report.push("file " + mod.id + "/" + path + ": WARNING no NavNode (bot navigation): a match with bots will crash."
                        + " Open it in tools/map-editor and use Generate bot navigation");
                  }
                  if(root == null)
                  {
                     report.push("file skipped " + mod.id + "/" + path + ": no element");
                  }
                  else if(ArchiveLoader.parseTable(root.var_4402,root))
                  {
                     report.push("file parsed " + mod.id + "/" + path + " as " + root.var_4402);
                  }
                  else
                  {
                     report.push("file skipped " + mod.id + "/" + path + ": the game has no table " + root.var_4402);
                  }
               }
               catch(e:*)
               {
                  report.push("file skipped " + mod.id + "/" + path + ": " + e);
               }
            }
         }
         if(any)
         {
            writeReport();
         }
      }

      private static const DEFAULT_BACKGROUND:String = "<Background AssetName=\"BG_SKCross.jpg\" W=\"2048\" H=\"1151\"/>";

      private static function hasChild(parent:Xml, tag:String) : Boolean
      {
         var it:* = parent.method_5430();
         while(it.hasNext())
         {
            if(Xml(it.next()).var_4402 == tag)
            {
               return true;
            }
         }
         return false;
      }

      public static function isAdded(tableName:String, key:String) : Boolean
      {
         return added[tableName] != null && added[tableName][key] != null;
      }

      private static function ownsAddedColor(costume:Object, scheme:Object) : Boolean
      {
         if(scheme == null || !isAdded("ColorSchemeTypes",scheme.mColorSchemeName))
         {
            return false;
         }
         if(granted[scheme.mColorSchemeName] == null)
         {
            granted[scheme.mColorSchemeName] = true;
            report.push("owned ColorSchemeTypes/" + scheme.mColorSchemeName + ": added by " +
               added["ColorSchemeTypes"][scheme.mColorSchemeName] + ", counts as owned");
            writeReport();
         }
         return true;
      }

      public static function readAll(folders:Array) : Array
      {
         var byId:Object = {};
         var list:Array = [];
         folders.sortOn("name");
         for each(var dir:File in folders)
         {
            var manifest:File = dir.resolvePath("mod.json");
            if(!manifest.exists)
            {
               report.push("skipped " + dir.name + ": no mod.json");
               continue;
            }
            var mod:Object = parse(dir.name,readText(manifest));
            if(mod == null)
            {
               continue;
            }
            if(byId[mod.id] != null)
            {
               report.push("skipped " + dir.name + ": id " + mod.id + " is already used by " + byId[mod.id].folder);
               continue;
            }
            byId[mod.id] = mod;
            mod.dir = dir;
            list.push(mod);
         }
         return list;
      }

      public static function parse(folder:String, text:String) : Object
      {
         var data:Object;
         try
         {
            data = JSON.parse(text);
         }
         catch(e:Error)
         {
            report.push("skipped " + folder + ": mod.json is not valid JSON (" + e.message + ")");
            return null;
         }
         if(data == null || typeof data != "object" || data is Array)
         {
            report.push("skipped " + folder + ": mod.json is not a JSON object");
            return null;
         }
         for each(var field:String in ["id","name","version"])
         {
            if(!(data[field] is String) || data[field] == "")
            {
               report.push("skipped " + folder + ": \"" + field + "\" is missing or not a string");
               return null;
            }
         }
         if(!ID.test(data.id))
         {
            report.push("skipped " + folder + ": id \"" + data.id + "\" may only use a-z, 0-9, '.', '_' and '-'");
            return null;
         }
         var requires:Array = [];
         if(data.requires != null)
         {
            if(!(data.requires is Array))
            {
               report.push("skipped " + folder + ": \"requires\" is not a list");
               return null;
            }
            for each(var req:* in data.requires)
            {
               if(!(req is String))
               {
                  report.push("skipped " + folder + ": \"requires\" holds something that isn't an id");
                  return null;
               }
               requires.push(req);
            }
         }
         var strings:Object = {};
         if(data.strings != null)
         {
            if(typeof data.strings != "object" || data.strings is Array)
            {
               report.push("skipped " + folder + ": \"strings\" is not an object of languages");
               return null;
            }
            for(var language:String in data.strings)
            {
               var table:Object = data.strings[language];
               if(table == null || typeof table != "object" || table is Array)
               {
                  report.push("skipped " + folder + ": \"strings\"." + language + " is not an object of keys");
                  return null;
               }
               for(var key:String in table)
               {
                  if(!(table[key] is String))
                  {
                     report.push("skipped " + folder + ": string " + language + "/" + key + " is not text");
                     return null;
                  }
               }
               strings[language] = table;
            }
         }
         var tables:Object = {};
         if(data.tables != null)
         {
            if(typeof data.tables != "object" || data.tables is Array)
            {
               report.push("skipped " + folder + ": \"tables\" is not an object of table names");
               return null;
            }
            for(var tableName:String in data.tables)
            {
               var rows:* = data.tables[tableName];
               if(!(rows is Array))
               {
                  report.push("skipped " + folder + ": \"tables\"." + tableName + " is not a list of rows");
                  return null;
               }
               for each(var row:* in rows)
               {
                  var isObject:Boolean = row != null && typeof row == "object" && !(row is Array);
                  if(!(row is String) && !(isObject && row.add is String) && !(isObject && row.set != null &&
                     typeof row.set == "object" && (row.copy == null || row.copy is String)))
                  {
                     report.push("skipped " + folder + ": a row of " + tableName + " is neither text (XML or a CSV line) " +
                        "nor {\"copy\": \"<row>\", \"set\": {...}}");
                     return null;
                  }
               }
               tables[tableName] = rows;
            }
         }
         var files:Array = [];
         if(data.files != null)
         {
            if(!(data.files is Array))
            {
               report.push("skipped " + folder + ": \"files\" is not a list");
               return null;
            }
            for each(var path:* in data.files)
            {
               if(!(path is String) || !FILE.test(path) || String(path).indexOf("..") >= 0)
               {
                  report.push("skipped " + folder + ": \"files\" holds " + path + ", not a plain path inside the mod folder");
                  return null;
               }
               files.push(path);
            }
         }
         var assetMap:Object = {};
         if(data.assets != null)
         {
            if(typeof data.assets != "object" || data.assets is Array)
            {
               report.push("skipped " + folder + ": \"assets\" is not an object of game file name -> file in the mod");
               return null;
            }
            for(var gameName:String in data.assets)
            {
               var local:* = data.assets[gameName];
               if(!FILE.test(gameName) || gameName.indexOf("..") >= 0 || !(local is String) || !FILE.test(local) ||
                  String(local).indexOf("..") >= 0)
               {
                  report.push("skipped " + folder + ": \"assets\" holds " + gameName + " -> " + local +
                     ", not plain paths inside the game and the mod folder");
                  return null;
               }
               assetMap[gameName] = local;
            }
         }
         var aliases:Object = {};
         if(data.animationAliases != null)
         {
            if(typeof data.animationAliases != "object" || data.animationAliases is Array)
            {
               report.push("skipped " + folder + ": \"animationAliases\" is not an object of name -> name");
               return null;
            }
            for(var aliasName:String in data.animationAliases)
            {
               if(!(data.animationAliases[aliasName] is String))
               {
                  report.push("skipped " + folder + ": \"animationAliases\" holds " + aliasName + " -> a non-text value");
                  return null;
               }
               aliases[aliasName] = data.animationAliases[aliasName];
            }
         }
         var banks:Array = [];
         if(data.soundBanks != null)
         {
            if(!(data.soundBanks is Array))
            {
               report.push("skipped " + folder + ": \"soundBanks\" is not a list");
               return null;
            }
            for each(var bank:* in data.soundBanks)
            {
               if(!(bank is String) || !FILE.test(bank) || String(bank).indexOf("..") >= 0 ||
                  String(bank).substr(-4).toLowerCase() != ".bnk")
               {
                  report.push("skipped " + folder + ": \"soundBanks\" holds " + bank + ", not a .bnk inside the mod folder");
                  return null;
               }
               banks.push(bank);
            }
         }
         if(data.palette != null && (typeof data.palette != "object" || data.palette is Array))
         {
            report.push("skipped " + folder + ": \"palette\" is not an object");
            return null;
         }
         var mapArt:Object = null;
         if(data.mapArt != null)
         {
            var bad:Boolean = typeof data.mapArt != "object" || !(data.mapArt.files is Array) ||
               data.mapArt.maps == null || typeof data.mapArt.maps != "object";
            for each(var artPath:* in (bad ? [] : data.mapArt.files))
            {
               if(!(artPath is String) || !FILE.test(artPath) || String(artPath).indexOf("..") >= 0)
               {
                  bad = true;
               }
            }
            if(bad)
            {
               report.push("skipped " + folder + ": \"mapArt\" needs \"files\" (plain paths) and \"maps\"");
               return null;
            }
            mapArt = data.mapArt;
         }
         var music:Object = null;
         if(data.music != null)
         {
            var badMusic:Boolean = typeof data.music != "object" || data.music.tracks == null ||
               typeof data.music.tracks != "object" || data.music.tracks is Array ||
               (data.music.replaces != null && (typeof data.music.replaces != "object" || data.music.replaces is Array));
            for(var trackKey:String in (badMusic ? {} : data.music.tracks))
            {
               var trackSpec:* = data.music.tracks[trackKey];
               var trackPath:* = trackSpec is String ? trackSpec : (trackSpec != null && typeof trackSpec == "object" ?
                  trackSpec.file : null);
               if(!/^[A-Za-z0-9_.-]+$/.test(trackKey) || !(trackPath is String) || !FILE.test(trackPath) ||
                  String(trackPath).indexOf("..") >= 0 || String(trackPath).substr(-4).toLowerCase() != ".mp3")
               {
                  badMusic = true;
               }
            }
            if(badMusic)
            {
               report.push("skipped " + folder + ": \"music\" needs \"tracks\" (names of letters, digits, . _ - and " +
                  ".mp3 files in the mod folder) and an optional \"replaces\" object");
               return null;
            }
            music = data.music;
         }
         var sounds:Object = null;
         if(data.sounds != null)
         {
            var badSounds:Boolean = typeof data.sounds != "object" || data.sounds is Array;
            for(var soundEvent:String in (badSounds ? {} : data.sounds))
            {
               var soundPath:* = data.sounds[soundEvent];
               if(!/^[A-Za-z0-9_]+$/.test(soundEvent) || !(soundPath is String) || !FILE.test(soundPath) ||
                  String(soundPath).indexOf("..") >= 0 || String(soundPath).substr(-4).toLowerCase() != ".mp3")
               {
                  badSounds = true;
               }
            }
            if(badSounds)
            {
               report.push("skipped " + folder + ": \"sounds\" needs sound event names and .mp3 files in the mod folder");
               return null;
            }
            sounds = data.sounds;
         }
         return {"id":data.id,"name":data.name,"version":data.version,"requires":requires,"strings":strings,"tables":tables,
                 "files":files,"assets":assetMap,"palette":data.palette,"animationAliases":aliases,"soundBanks":banks,
                 "mapArt":mapArt,"music":music,"sounds":sounds,"description":data.description is String ? data.description : "",
                 "preview":data.preview is String && FILE.test(data.preview) && String(data.preview).indexOf("..") < 0 ?
                    data.preview : null,
                 "author":data.author is String ? data.author : "","folder":folder,"manifest":text};
      }

      public static function order(list:Array) : Array
      {
         var pending:Array = list.slice();
         pending.sortOn("id");
         var placed:Object = {};
         var known:Object = {};
         for each(var m:Object in pending)
         {
            known[m.id] = true;
         }
         var out:Array = [];
         var progress:Boolean = true;
         while(pending.length > 0 && progress)
         {
            progress = false;
            for(var i:int = 0; i < pending.length; i++)
            {
               var mod:Object = pending[i];
               var missing:String = null;
               var ready:Boolean = true;
               for each(var req:String in mod.requires)
               {
                  if(!known[req])
                  {
                     missing = req;
                     break;
                  }
                  if(!placed[req])
                  {
                     ready = false;
                  }
               }
               if(missing != null)
               {
                  report.push("skipped " + mod.folder + ": requires " + missing + ", which is missing or skipped");
                  delete known[mod.id];
                  pending.splice(i,1);
                  progress = true;
                  break;
               }
               if(ready)
               {
                  placed[mod.id] = true;
                  out.push(mod);
                  pending.splice(i,1);
                  progress = true;
                  break;
               }
            }
         }
         for each(var left:Object in pending)
         {
            report.push("skipped " + left.folder + ": its requirements form a cycle (" + left.requires.join(", ") + ")");
         }
         return out;
      }

      private static function checkStringConflicts() : void
      {
         var owner:Object = {};
         for each(var mod:Object in mods)
         {
            for(var language:String in mod.strings)
            {
               for(var key:String in mod.strings[language])
               {
                  var slot:String = language + "/" + key;
                  if(owner[slot] != null)
                  {
                     report.push("conflict string " + slot + ": " + owner[slot] + " is overridden by " + mod.id);
                  }
                  owner[slot] = mod.id;
               }
            }
         }
      }

      private static function applyStrings(language:Localization) : void
      {
         var count:int = 0;
         for each(var mod:Object in mods)
         {
            var table:Object = mod.strings[language.var_14508];
            if(table == null)
            {
               continue;
            }
            for(var key:String in table)
            {
               language.var_15061.method_65(key,table[key]);
               count++;
            }
         }
         stringsApplied++;
         if(stringsApplied <= 10)
         {
            report.push("strings applied to " + language.var_14508 + ": " + count + " values");
            writeReport();
         }
      }

      private static function applyTableRows(tableName:String, root:Object) : void
      {
         var nextIds:Object = {};
         var touched:Object = {};
         var changedRows:int = 0;
         var idTags:Object = xmlIdTags(root as Xml);
         var knownTags:Object = null;
         recordXmlNames(tableName,root as Xml);
         for each(var mod:Object in mods)
         {
            var rows:Array = mod.tables[tableName];
            if(rows != null && STRICT_TABLES[tableName] && knownTags == null)
            {
               knownTags = tagsOf(root as Xml);
            }
            if(rows == null)
            {
               continue;
            }
            for each(var text:* in rows)
            {
               var row:Xml;
               if(!(text is String) && text.stance is String)
               {
                  if(setStance(root as Xml,text,mod.id,tableName))
                  {
                     changedRows++;
                  }
                  continue;
               }
               if(!(text is String) && text.add is String)
               {
                  try
                  {
                     row = Xml.parse(text.add).method_7292();
                  }
                  catch(addErr:*)
                  {
                     report.push("row skipped " + mod.id + " " + tableName + ": not valid XML (" + addErr + ")");
                     continue;
                  }
                  if(row != null)
                  {
                     (root as Xml).addChild(row);
                     report.push("row added " + tableName + "/" + rowKey(row) + " (" + mod.id + ", added as is)");
                  }
                  continue;
               }
               try
               {
                  row = text is String ? Xml.parse(text).method_7292() : copyRow(root as Xml,text,mod.id,tableName);
               }
               catch(e:*)
               {
                  report.push("row skipped " + mod.id + " " + tableName + ": not valid XML (" + e + ")");
                  continue;
               }
               if(row == null)
               {
                  if(text is String)
                  {
                     report.push("row skipped " + mod.id + " " + tableName + ": no element");
                  }
                  continue;
               }
               var key:String = rowKey(row);
               if(keyAttributes(row).length > 0)
               {
                  enforceXmlIds(row,findRow(root as Xml,row) == null,idTags,tableName,key,mod.id);
               }
               var refused:String = null;
               for each(var field:Xml in elements(row))
               {
                  if(textOf(field) == "@id" && HASHED_IDS[tableName + "/" + field.var_4402] != null)
                  {
                     var hid:int = hashedId(keyValues(row),usedXmlIds(root as Xml,field.var_4402),HASHED_IDS[tableName + "/" + field.var_4402]);
                     if(hid <= 0)
                     {
                        refused = "no free " + field.var_4402;
                        break;
                     }
                     setText(field,String(hid));
                     report.push("id " + tableName + "/" + field.var_4402 + " = " + hid + " for " + key + " (" + mod.id + ")");
                  }
                  else if(textOf(field) == "@id")
                  {
                     if(nextIds[field.var_4402] == null)
                     {
                        nextIds[field.var_4402] = maxField(root as Xml,field.var_4402) + 1;
                     }
                     var id:int = nextIds[field.var_4402]++;
                     var limit:* = ID_LIMITS[tableName + "/" + field.var_4402];
                     if(limit != null && id >= int(limit))
                     {
                        id = freeIdBelow(root as Xml,field.var_4402,int(limit));
                        if(id <= 0)
                        {
                           refused = "no free " + field.var_4402 + " below " + limit + " (the game stops loading at " + limit + " or more)";
                           break;
                        }
                     }
                     setText(field,String(id));
                     report.push("id " + tableName + "/" + field.var_4402 + " = " + id + " for " + key + " (" + mod.id + ")");
                  }
                  else if(textOf(field).indexOf("@id/") == 0)
                  {
                     var spec:String = textOf(field).substr(4);
                     var value:String = groupValue(row,spec);
                     var idKey:String = field.var_4402 + "/" + spec + "=" + value;
                     if(nextIds[idKey] == null)
                     {
                        nextIds[idKey] = maxField(root as Xml,field.var_4402,spec,value) + 1;
                     }
                     var gid:int = nextIds[idKey]++;
                     setText(field,String(gid));
                     report.push("id " + tableName + "/" + field.var_4402 + " = " + gid + " for " + key + " (next free for " +
                        spec + " " + value + ", " + mod.id + ")");
                  }
               }
               if(refused != null)
               {
                  report.push("row skipped " + mod.id + " " + tableName + "/" + key + ": " + refused);
                  continue;
               }
               if(knownTags != null)
               {
                  dropUnknownTags(row,knownTags,tableName,key,mod.id);
               }
               var appendOnly:Boolean = elements(row).length > 0;
               for each(var af:Xml in elements(row))
               {
                  if(textOf(af).charAt(0) != "+")
                  {
                     appendOnly = false;
                  }
               }
               if(keyAttributes(row).length > 0 && !appendOnly)
               {
                  if(touched[key] != null)
                  {
                     report.push("conflict row " + tableName + "/" + key + ": " + touched[key] + " is overridden by " + mod.id);
                  }
                  touched[key] = mod.id;
               }
               var existing:Xml = findRow(root as Xml,row);
               if(existing == null)
               {
                  for each(var plus:Xml in elements(row))
                  {
                     if(textOf(plus).charAt(0) == "+")
                     {
                        setText(plus,textOf(plus).substr(1));
                     }
                  }
                  if(tableName == "EmojiTypes")
                  {
                     keepOneDefaultEmoji(root as Xml,row,key,mod.id);
                  }
                  (root as Xml).addChild(row);
                  if(added[tableName] == null)
                  {
                     added[tableName] = {};
                  }
                  added[tableName][keyValues(row)] = mod.id;
                  var keyNames:Array = keyAttributes(row);
                  if(keyNames.length > 0)
                  {
                     var idTag:String = String(keyNames[0]).replace(/Name$/,"ID");
                     remember(ids,tableName,keyValues(row),fieldText(row,idTag));
                     var source:Xml = rowSources[row] as Xml;
                     if(source != null && added[tableName][keyValues(source)] == null)
                     {
                        remember(copiedIds,tableName,keyValues(row),fieldText(source,idTag));
                     }
                  }
                  changedRows++;
                  report.push("row added " + tableName + "/" + key + " (" + mod.id + ")");
               }
               else
               {
                  mergeRow(existing,row);
                  changedRows++;
                  report.push("row changed " + tableName + "/" + key + " (" + mod.id + ")");
               }
            }
         }
         if(changedRows > 0)
         {
            writeReport();
         }
      }

      private static function attributes(node:Xml) : Array
      {
         var out:Array = [];
         var it:* = node.method_5821();
         while(it.hasNext())
         {
            out.push(it.next());
         }
         out.sort();
         return out;
      }

      internal static function elements(node:Xml) : Array
      {
         var out:Array = [];
         for each(var child:Xml in node.var_5236)
         {
            if(child.var_14625 == Xml.var_11889)
            {
               out.push(child);
            }
         }
         return out;
      }

      internal static function fieldText(node:Xml, tag:String) : String
      {
         for each(var f:Xml in elements(node))
         {
            if(f.var_4402 == tag)
            {
               return textOf(f);
            }
         }
         return null;
      }

      private static function keyAttributes(node:Xml) : Array
      {
         var all:Array = attributes(node);
         var named:Array = all.filter(function(a:String, i:int, arr:Array):Boolean { return /Name$/.test(a); });
         return named.length == 1 ? named : all;
      }

      private static function rowKey(node:Xml) : String
      {
         var children:Array = elements(node);
         if(attributes(node).length == 0 && children.length > 0)
         {
            return node.var_4402 + "[" + children[0].var_4402 + "=" + textOf(children[0]) + "]";
         }
         return node.var_4402 + "[" + keyValues(node) + "]";
      }

      private static function keyValues(node:Xml) : String
      {
         var parts:Array = [];
         for each(var a:String in keyAttributes(node))
         {
            parts.push(node.method_4935(a));
         }
         return parts.join(",");
      }

      private static function findRow(root:Xml, row:Xml) : Xml
      {
         var keys:Array = keyAttributes(row);
         if(keys.length == 0)
         {
            return null;
         }
         for each(var candidate:Xml in elements(root))
         {
            if(candidate.var_4402 != row.var_4402)
            {
               continue;
            }
            var same:Boolean = true;
            for each(var a:String in keys)
            {
               if(candidate.method_4935(a) != row.method_4935(a))
               {
                  same = false;
                  break;
               }
            }
            if(same)
            {
               return candidate;
            }
         }
         return null;
      }

      private static function setStance(root:Xml, spec:Object, modId:String, tableName:String) : Boolean
      {
         var label:String = tableName + "/" + spec.stance + " stance " + spec.index;
         var hero:String = null;
         for each(var r:Xml in elements(root))
         {
            var index:String = null;
            for each(var f:Xml in elements(r))
            {
               if(f.var_4402 == "HeroName")
               {
                  hero = textOf(f);
               }
               else if(f.var_4402 == "RuneIndex")
               {
                  index = textOf(f);
               }
            }
            if(hero != spec.stance || index != String(spec.index))
            {
               continue;
            }
            var change:Xml = Xml.parse("<" + r.var_4402 + "/>").method_7292();
            for(var name:String in spec.set)
            {
               if(!/^[A-Za-z]\w*$/.test(name) || name == "HeroName" || name == "RuneIndex")
               {
                  report.push("row skipped " + modId + " " + label + ": can't set " + name);
                  return false;
               }
               change.addChild(Xml.parse("<" + name + ">" + escapeXml(String(spec.set[name])) + "</" + name + ">").method_7292());
            }
            mergeRow(r,change);
            report.push("row changed " + label + " (" + modId + ")");
            return true;
         }
         report.push("row skipped " + modId + " " + label + ": no such stance");
         return false;
      }

      private static function mergeRow(target:Xml, row:Xml) : void
      {
         for each(var a:String in attributes(row))
         {
            target.method_65(a,row.method_4935(a));
         }
         for each(var field:Xml in elements(row))
         {
            var previous:String = null;
            for each(var old:Xml in elements(target))
            {
               if(old.var_4402 == field.var_4402)
               {
                  previous = textOf(old);
                  target.removeChild(old);
               }
            }
            var text:String = textOf(field);
            if(text.charAt(0) == "+")
            {
               setText(field,previous != null && previous != "" ? previous + "," + text.substr(1) : text.substr(1));
            }
            target.addChild(field);
         }
      }

      internal static function textOf(node:Xml) : String
      {
         var out:String = "";
         for each(var child:Xml in node.var_5236)
         {
            if(child.var_14625 != Xml.var_11889 && child.var_3342 != null)
            {
               out += child.var_3342;
            }
         }
         return out;
      }

      private static function setText(node:Xml, text:String) : void
      {
         for each(var child:Xml in node.var_5236)
         {
            if(child.var_14625 != Xml.var_11889)
            {
               child.var_3342 = text;
               return;
            }
         }
      }

      private static function groupValue(row:Xml, spec:String) : String
      {
         if(spec.charAt(0) == "@")
         {
            var a:String = row.method_4935(spec.substr(1));
            return a == null ? "" : a;
         }
         for each(var child:Xml in elements(row))
         {
            if(child.var_4402 == spec)
            {
               return textOf(child);
            }
         }
         return "";
      }

      private static function maxField(root:Xml, field:String, group:String = null, value:String = null) : int
      {
         var best:int = 0;
         for each(var row:Xml in elements(root))
         {
            if(group != null && groupValue(row,group) != value)
            {
               continue;
            }
            for each(var child:Xml in elements(row))
            {
               if(child.var_4402 == field)
               {
                  var text:String = textOf(child);
                  if(/^\s*-?\d+\s*$/.test(text) && int(text) > best)
                  {
                     best = int(text);
                  }
               }
            }
         }
         return best;
      }

      private static function readText(file:File) : String
      {
         var stream:FileStream = new FileStream();
         stream.open(file,FileMode.READ);
         try
         {
            var text:String = stream.readUTFBytes(stream.bytesAvailable);
            return text.charCodeAt(0) == 0xFEFF ? text.substr(1) : text;
         }
         finally
         {
            stream.close();
         }
         return null;
      }

      private static var reportQueued:Boolean = false;

      internal static function writeReport() : void
      {
         if(!reportQueued)
         {
            reportQueued = true;
            setTimeout(flushReport,0);
         }
      }

      private static function flushReport() : void
      {
         reportQueued = false;
         try
         {
            var stream:FileStream = new FileStream();
            stream.open(Platform.dataFile(REPORT),FileMode.WRITE);
            stream.writeUTFBytes(report.join("\r\n") + "\r\n");
            stream.close();
         }
         catch(e:Error)
         {
            Platform.log("content mods: can't write the report: " + e.message);
         }
      }
   }
}
