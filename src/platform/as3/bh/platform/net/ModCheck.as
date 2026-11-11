package bh.platform.net
{
   import bh.platform.ContentMods;
   import bh.platform.Hooks;
   import bh.platform.Modal;
   import flash.utils.ByteArray;

   public final class ModCheck
   {
      private static var entries:Array = null;
      private static var print:uint = 0;

      public static const MODS_LIST:int = 11013;
      public static const START_REFUSED:int = 11014;
      public static const LOGIN_OK:int = 2431;
      private static const SENT_WITH:Array = [38,41,83,84,11006];

      public function ModCheck()
      {
      }

      public static function register() : void
      {
         Hooks.packetSending.add(function(connection:Object, packet:Object):Boolean
         {
            if(packet != null && SENT_WITH.indexOf(int(packet.type)) >= 0)
            {
               sendList();
            }
            return false;
         });
         Hooks.packetReceived.add(function(packet:Object):Boolean
         {
            if(packet != null && packet.type == LOGIN_OK)
            {
               sendList();
               return false;
            }
            if(packet == null || packet.type != START_REFUSED)
            {
               return false;
            }
            try
            {
               var why:String = packet.readString();
               PrivateServer.log("start refused by the server: " + why);
               try
               {
                  Object(GameApp.mainInstance).var_13259.var_6244.method_6022();
               }
               catch(e2:Error)
               {
                  PrivateServer.log("could not reset the lobby's start: " + e2.message);
               }
               Modal.show("Can't start",why,null,true);
            }
            catch(e:Error)
            {
            }
            return true;
         });
      }

      private static function sendList() : void
      {
         try
         {
            refresh();
            var p:NetPacket = new NetPacket(MODS_LIST);
            p.writeUint(print);
            var list:Array = entries.slice(0,60);
            p.writeUint(list.length);
            for each(var entry:String in list)
            {
               p.writeString(entry);
            }
            Object(GameApp.mainInstance).var_13259.sendToServer(p);
            p.method_839();
         }
         catch(e:Error)
         {
            PrivateServer.log("could not send the mods list: " + e.message);
         }
      }

      public static function refresh() : void
      {
         entries = [];
         for each(var mod:Object in ContentMods.mods)
         {
            if(!isGameplay(mod))
            {
               continue;
            }
            entries.push(entryOf(mod));
         }
         print = fnv(entries.join("\n"));
      }

      public static const VISUAL_TABLES:Array = ["costumeTypes","ColorSchemeTypes","weaponSkinTypes","avatarTypes",
         "TauntTypes","EmojiTypes","SpawnBotTypes","SeasonBorderTypes","TrailEffectTypes","PodiumTypes","PlayerThemeTypes","CompanionTypes",
         "EmitterTypes","EmitterGroupTypes","SplashArtTypes","ClientThemeTypes","MonikerTypes","MusicTypes",
         "EndMatchVoicelineTypes","SoundVolumes","LanguageTypes","MasterFileList","BoneSources","BoneTypes","colorExceptionTypes",
         "manualBoneSpriteData","manualSpriteData","spriteData"];

      public static function isGameplay(mod:Object) : Boolean
      {
         if(mod.files is Array && mod.files.length > 0)
         {
            return true;
         }
         for(var table:String in mod.tables)
         {
            if(table == "PowerSwapTypes")
            {
               if(/(<|")(CastAnim|GrabAnim|HitReactAnim|AsymRight)(>|"\s*:\s*")[^<"\s]/.test(JSON.stringify(mod.tables[table])))
               {
                  return true;
               }
               continue;
            }
            if(VISUAL_TABLES.indexOf(table) < 0)
            {
               return true;
            }
         }
         for(var path:String in mod.assets)
         {
            if(/(^|\/)anim/i.test(path))
            {
               return true;
            }
         }
         return false;
      }

      public static function entryOf(mod:Object) : String
      {
         var content:String = mod.manifest is String ? String(mod.manifest) : "";
         if(content.charCodeAt(0) == 0xFEFF)
         {
            content = content.substr(1);
         }
         content = content.split("\r\n").join("\n");
         return mod.id + "@" + mod.version + "#" + hex(fnv(content));
      }

      public static function list() : Array
      {
         return entries != null ? entries.concat() : [];
      }

      public static function get count() : uint
      {
         return entries != null ? entries.length : 0;
      }

      public static function write(b:ByteArray) : void
      {
         b.writeUnsignedInt(print);
         var list:Array = [];
         var size:int = 0;
         for each(var entry:String in entries)
         {
            size += entry.length + 2;
            if(size > 1100)
            {
               break;
            }
            list.push(entry);
         }
         b.writeShort(list.length);
         for each(entry in list)
         {
            b.writeUTF(entry);
         }
      }

      public static function compare(b:ByteArray) : String
      {
         var theirs:uint = b.readUnsignedInt();
         if(theirs == print)
         {
            return null;
         }
         var n:int = b.readUnsignedShort();
         var other:Object = {};
         for(var i:int = 0; i < n; i++)
         {
            var entry:String = b.readUTF();
            other[entry.split("#")[0]] = entry;
         }
         var mine:Object = {};
         for each(entry in entries)
         {
            mine[entry.split("#")[0]] = entry;
         }
         var here:Array = [];
         var there:Array = [];
         var changed:Array = [];
         for(var key:String in mine)
         {
            if(other[key] == null)
            {
               here.push(key);
            }
            else if(other[key] != mine[key])
            {
               changed.push(key);
            }
         }
         for(key in other)
         {
            if(mine[key] == null)
            {
               there.push(key);
            }
         }
         var parts:Array = [];
         if(here.length > 0)
         {
            parts.push("only here: " + here.sort().join(", "));
         }
         if(there.length > 0)
         {
            parts.push("only there: " + there.sort().join(", "));
         }
         if(changed.length > 0)
         {
            parts.push("different contents: " + changed.sort().join(", "));
         }
         return parts.length > 0 ? parts.join("; ") : "the same list, in a different order or cut short";
      }

      public static function fnv(s:String) : uint
      {
         var h:uint = 2166136261;
         var bytes:ByteArray = new ByteArray();
         bytes.writeUTFBytes(s);
         for(var i:int = 0; i < int(bytes.length); i++)
         {
            h = h ^ bytes[i];
            h = uint((h << 24) + h * 403);
         }
         return h;
      }

      private static function hex(n:uint) : String
      {
         var s:String = n.toString(16);
         while(s.length < 8)
         {
            s = "0" + s;
         }
         return s;
      }
   }
}
