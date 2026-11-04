package bh.platform
{
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.utils.ByteArray;
   import flash.utils.Endian;

   public final class ModLanguages
   {
      public static var added:Object = {};

      public static function init() : void
      {
         Hooks.tableParsing.add(tableParsing);
         Hooks.languageLoading.add(languageLoading);
      }

      private static function tableParsing(tableName:String, root:Object) : void
      {
         if(tableName == "LanguageTypes")
         {
            languageTypes(root as Xml);
         }
         else if(tableName == "FontTypes")
         {
            fontTypes(root as Xml);
         }
      }

      private static function languageTypes(root:Xml) : void
      {
         var bases:Object = {};
         for each(var mod:Object in ContentMods.mods)
         {
            for each(var row:* in (mod.tables != null ? mod.tables["LanguageTypes"] : null))
            {
               if(!(row is String) && row.copy is String && row.set != null && row.set["@LanguageName"] != null)
               {
                  bases[String(row.set["@LanguageName"])] = row.copy;
               }
            }
         }
         var ids:Object = {};
         var enabled:Object = {};
         for each(var lang:Xml in elements(root))
         {
            var name:String = lang.method_4935("LanguageName");
            ids[name] = uint(field(lang,"LanguageID"));
            if(field(lang,"Enabled").toLowerCase() == "true" && name != "Template")
            {
               enabled[ids[name]] = name;
            }
         }
         var table:Object = ContentMods.added["LanguageTypes"] || {};
         for(var modName:String in table)
         {
            var base:String = bases[modName] != null && ids[bases[modName]] != null ? bases[modName] : "English";
            added[modName] = {"base":base,"baseId":ids[base],"id":ids[modName]};
            ContentMods.report.push("language " + modName + " (" + table[modName] + "): LanguageID " + ids[modName] +
               ", text and fonts from " + base);
         }
         if(enabled[GameApp.var_3705] == null)
         {
            ContentMods.report.push("saved language " + GameApp.var_3705 + " isn't there (its mod is off or gone): English");
            GameApp.var_3705 = 1;
         }
         ContentMods.writeReport();
      }

      private static function fontTypes(root:Xml) : void
      {
         var filled:int = 0;
         for(var name:String in added)
         {
            var base:String = added[name].base;
            for each(var row:Xml in elements(root))
            {
               for each(var suffix:String in ["Family","Size"])
               {
                  if(child(row,name + suffix) == null && child(row,base + suffix) != null)
                  {
                     row.addChild(Xml.parse("<" + name + suffix + ">" + escape(field(row,base + suffix)) + "</" + name +
                        suffix + ">").method_7292());
                     filled++;
                  }
               }
            }
         }
         if(filled > 0)
         {
            ContentMods.report.push("font columns filled for mod languages: " + filled);
            ContentMods.writeReport();
         }
      }

      private static function languageLoading(language:Localization) : Boolean
      {
         var info:Object = added[language.var_14508];
         if(info == null || info.baseId == null)
         {
            return false;
         }
         try
         {
            var bytes:ByteArray = new ByteArray();
            var stream:FileStream = new FileStream();
            stream.endian = Endian.LITTLE_ENDIAN;
            stream.open(File.applicationDirectory.resolvePath("languages/language." + info.baseId + ".bin"),FileMode.READ);
            stream.readUnsignedInt();
            stream.readBytes(bytes);
            stream.close();
            bytes.uncompress();
            language.method_7158(bytes);
            language.var_10997 = false;
            Platform.log("language " + language.var_14508 + ": text from " + info.base + " (language." + info.baseId +
               ".bin) and the mods");
            return true;
         }
         catch(e:Error)
         {
            Platform.log("language " + language.var_14508 + ": can't read " + info.base + "'s text: " + e.message);
         }
         return false;
      }

      private static function elements(node:Xml) : Array
      {
         var out:Array = [];
         for each(var c:Xml in node.var_5236)
         {
            if(c.var_14625 == Xml.var_11889)
            {
               out.push(c);
            }
         }
         return out;
      }

      private static function child(node:Xml, name:String) : Xml
      {
         for each(var c:Xml in elements(node))
         {
            if(c.var_4402 == name)
            {
               return c;
            }
         }
         return null;
      }

      private static function field(node:Xml, name:String) : String
      {
         var c:Xml = child(node,name);
         if(c == null)
         {
            return "";
         }
         var out:String = "";
         for each(var t:Xml in c.var_5236)
         {
            if(t.var_14625 != Xml.var_11889 && t.var_3342 != null)
            {
               out += t.var_3342;
            }
         }
         return out;
      }

      private static function escape(text:String) : String
      {
         return text.split("&").join("&amp;").split("<").join("&lt;").split(">").join("&gt;");
      }
   }
}
