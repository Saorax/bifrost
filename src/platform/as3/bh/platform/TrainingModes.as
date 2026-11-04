package bh.platform
{
   public final class TrainingModes
   {
      private static const MODES:Array = [["DefaultBrawlball","a_ScoringIcon_BRAWLBALL"],["DefaultSoccer","a_ScoringIcon_SOCCER"],
         ["DefaultCTF","a_ScoringIcon_CTF"],["BOUNTY_V2","a_ScoringIcon_BOUNTYHUNTER"],
         ["DefaultBombsketball","a_ScoringIcon_BOMBSKETBALL"],["DefaultVolleyball","a_ScoringIcon_VOLLEYBALL"],
         ["DefaultVolleyBattle","a_ScoringIcon_VOLLEYBRAWL"],["DefaultColorPlatforms","a_ScoringIcon_CLIMB"],
         ["DefaultRicochet","a_ScoringIcon_RICOCHET"],["DefaultHorde","a_ScoringIcon_HORDE"],
         ["DefaultRing","a_ScoringIcon_RING"],["DefaultTag","a_ScoringIcon_TAG"],["DefaultBuddy","a_ScoringIcon_BUDDY"],
         ["DefaultSnowball","a_ScoringIcon_SNOWBALL"],["DefaultOddBrawl","a_ScoringIcon_ODDBRAWL"],
         ["DefaultTableTop","a_ScoringIcon_TABLETOP"],["DefaultFixedStaminaGamemode","a_ScoringIcon_STREETFIGHT"]];
      public static const PREFIX:String = "BHTraining_";

      public static function trainingBot(menu:Object) : Object
      {
         try
         {
            var core:Object = menu.owner;
            for each(var p:Object in core.var_7050)
            {
               if(p != null && p != core.var_9499 && p.var_8233 != null && !p.method_5882())
               {
                  return p;
               }
            }
         }
         catch(e:Error)
         {
         }
         return null;
      }

      public static function dummyOf(core:Object) : Object
      {
         if(core == null || core.var_7050 == null || int(core.var_7050.length) < 2)
         {
            return null;
         }
         for(var i:int = 1; i < int(core.var_7050.length); i++)
         {
            var p:Object = core.var_7050[i];
            if(p != null && !p.method_5882())
            {
               return p;
            }
         }
         return core.var_7050[1];
      }

      public static function init() : void
      {
         if(!ModSettings.flag("trainingModes",true))
         {
            return;
         }
         Hooks.tableParsing.add(tableParsing);
      }

      private static function elements(node:Xml) : Array
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

      private static function field(row:Xml, name:String) : Xml
      {
         for each(var child:Xml in elements(row))
         {
            if(child.var_4402 == name)
            {
               return child;
            }
         }
         return null;
      }

      private static function setField(row:Xml, name:String, value:String) : void
      {
         var old:Xml = field(row,name);
         if(old != null)
         {
            row.removeChild(old);
         }
         row.addChild(Xml.parse("<" + name + ">" + value + "</" + name + ">").method_7292());
      }

      private static function tableParsing(tableName:String, root:Object) : void
      {
         if(tableName != "GameModeTypes")
         {
            return;
         }
         try
         {
            var xml:Xml = root as Xml;
            var byName:Object = {};
            var maxId:int = 0;
            for each(var row:Xml in elements(xml))
            {
               byName[row.method_4935("GameModeName")] = row;
               var idField:Xml = field(row,"GameModeID");
               var id:int = idField != null ? int(idField.var_5236[0] != null ? idField.var_5236[0].toString() : "0") : 0;
               maxId = Math.max(maxId,id);
            }
            var added:Array = [];
            for each(var m:Array in MODES)
            {
               var source:Xml = byName[m[0]];
               if(source == null || byName[PREFIX + m[0]] != null)
               {
                  continue;
               }
               var copy:Xml = Xml.parse(source.toString()).method_7292();
               copy.method_65("GameModeName",PREFIX + m[0]);
               setField(copy,"GameModeID",String(++maxId));
               setField(copy,"TrainingIcon",m[1]);
               setField(copy,"MaxPlayers","2");
               setField(copy,"Teams","FALSE");
               setField(copy,"Duration","0");
               setField(copy,"ScoreToWin","0");
               setField(copy,"StartingLives","0");
               var isDefault:Xml = field(copy,"IsDefaultForScoringType");
               if(isDefault != null)
               {
                  copy.removeChild(isDefault);
               }
               xml.addChild(copy);
               added.push(m[0] + " #" + maxId);
            }
            Platform.log("training modes: " + added.length + " added (" + added.join(", ") + ")");
         }
         catch(e:Error)
         {
            ErrorLog.write("training modes: " + e + " " + e.getStackTrace());
         }
      }
   }
}
