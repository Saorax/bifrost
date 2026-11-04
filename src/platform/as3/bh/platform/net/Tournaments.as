package bh.platform.net
{
   import bh.platform.Busy;
   import bh.platform.Hooks;
   import bh.platform.Notices;
   import bh.platform.TournamentsWindow;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.events.SecurityErrorEvent;
   import flash.net.URLLoader;
   import flash.net.URLRequest;

   public final class Tournaments
   {
      public static const SCREEN:String = "screenTournamentEvents";

      private static var registered:Boolean = false;

      private static var table:Xml = null;

      private static var added:Array = [];

      private static var loading:Boolean = false;
      private static const BUSY:String = "tournaments:events";

      public function Tournaments()
      {
      }

      public static function register() : void
      {
         if(registered)
         {
            return;
         }
         registered = true;
         Hooks.packetReceived.add(onListNotice);
         Hooks.tableParsing.add(function(tableName:String, root:Object):void
         {
            if(tableName == "TournamentEventTypes")
            {
               table = root as Xml;
               fetch();
            }
            else if(tableName == "TileTypes")
            {
               pointEsportsTile(root as Xml);
            }
         });
         Hooks.urlOpening.add(openLink);
         Hooks.mainMenuTilePressed.add(function(screen:Object, tile:uint):Boolean
         {
            if(tile != 2 || PrivateServer.host == null)
            {
               return false;
            }
            TournamentsWindow.open();
            return true;
         });
         Hooks.stringsLoaded.add(function(language:Object):void
         {
            language.var_15061.method_65("UI_MainMenu_ESports","Tournaments");
         });
         Hooks.screenCreated.add(function(screen:Object):void
         {
            if(screen is class_546)
            {
               hideCurrencyIcons(screen as class_546);
               fetch();
            }
         });
      }

      public static const LIST_NOTICE:int = 11096;

      private static function onListNotice(packet:Object) : Boolean
      {
         if(packet == null || packet.type != LIST_NOTICE)
         {
            return false;
         }
         try
         {
            var key:String = packet.readString();
            var title:String = packet.readString();
            var text:String = packet.readString();
            if(key.indexOf("tour:") == 0)
            {
               Notices.add(key,title,text,"Tournament",[{"label":"OPEN TOURNAMENTS","action":function():void
               {
                  TournamentsWindow.open();
               }}]);
            }
            else
            {
               Notices.add(key,title,text,"Coins");
            }
         }
         catch(e:Error)
         {
            PrivateServer.log("tournaments: could not read 11096: " + e.message);
         }
         return true;
      }

      public static const ACT:int = 11047;

      private static function openLink(url:String) : Boolean
      {
         if(PrivateServer.host == null || url == null)
         {
            return false;
         }
         var m:Array = String(url).match(/\/tournament\/(\d+)\/?$/);
         if(m != null)
         {
            TournamentsWindow.open(int(m[1]));
            return true;
         }
         if(String(url).match(/\/tournaments\/?$/) != null)
         {
            TournamentsWindow.open(-1);
            return true;
         }
         if(String(url).match(/\/cups\/?$/) != null)
         {
            return openCups();
         }
         return false;
      }

      public static function openCups() : Boolean
      {
         for each(var sc:Object in ScreenManager.allScreens)
         {
            if(sc != null && sc.clipName == "a_ScreenCupHub")
            {
               sc.Display();
               return true;
            }
         }
         return false;
      }

      public static function act(action:String, args:Object) : Boolean
      {
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var packet:NetPacket = new NetPacket(ACT);
            packet.writeString(action);
            packet.writeString(JSON.stringify(args));
            var sent:Boolean = core.sendToServer(packet);
            packet.method_839();
            return sent;
         }
         catch(e:Error)
         {
            PrivateServer.log("tournaments: could not send " + action + " (" + e.message + ")");
         }
         return false;
      }

      private static function hideCurrencyIcons(screen:class_546) : void
      {
         try
         {
            var rows:Array = [screen.var_6170];
            for each(var a:UITournamentEvent in screen.var_7678)
            {
               rows.push(a);
            }
            for each(var b:UITournamentEvent in screen.var_9292)
            {
               rows.push(b);
            }
            for each(var row:UITournamentEvent in rows)
            {
               if(row != null && row.mIconHolder != null)
               {
                  row.mIconHolder.visible = false;
               }
            }
         }
         catch(e:*)
         {
            PrivateServer.log("tournaments: icons not hidden (" + e + ")");
         }
      }

      private static function pointEsportsTile(root:Xml) : void
      {
         if(root == null)
         {
            return;
         }
         try
         {
            var rows:* = root.method_5430();
            while(rows.hasNext())
            {
               var row:Xml = rows.next();
               if(textOf(row,"Location") != "ESports")
               {
                  continue;
               }
               var fields:* = row.method_5430();
               var old:Array = [];
               while(fields.hasNext())
               {
                  var f:Xml = fields.next();
                  if(f.var_4402 == "Screen" || f.var_4402 == "LinkURLs")
                  {
                     old.push(f);
                  }
               }
               for each(var gone:Xml in old)
               {
                  row.removeChild(gone);
               }
               row.addChild(Xml.parse("<Screen>" + SCREEN + "</Screen>").method_7292());
               PrivateServer.log("tournaments: the ESPORTS button opens the Tournament Events screen");
            }
         }
         catch(e:*)
         {
            PrivateServer.log("tournaments: ESports tile not changed (" + e + ")");
         }
      }

      private static function textOf(row:Xml, name:String) : String
      {
         var fields:* = row.method_5430();
         while(fields.hasNext())
         {
            var f:Xml = fields.next();
            if(f.var_4402 == name)
            {
               var inner:Array = f.var_5236;
               return inner.length > 0 && inner[0].var_3342 != null ? String(inner[0].var_3342) : "";
            }
         }
         return null;
      }

      public static function url() : String
      {
         return PrivateServer.webUrl(PrivateServer.port + 1,"/api/tournaments/events.xml");
      }

      public static function fetch() : void
      {
         if(PrivateServer.host == null || table == null || loading)
         {
            return;
         }
         loading = true;
         Busy.start(BUSY,"LOADING TOURNAMENTS");
         var asked:String = url();
         var loader:URLLoader = new URLLoader();
         var again:Function = function():void
         {
            if(url() != asked)
            {
               fetch();
            }
         };
         loader.addEventListener(Event.COMPLETE,function(e:Event):void
         {
            loading = false;
            Busy.done(BUSY);
            apply(String(loader.data));
            again();
         });
         var failed:Function = function(e:Event):void
         {
            loading = false;
            Busy.done(BUSY);
            PrivateServer.log("tournaments: " + asked + " failed (" + e.type + ")");
            again();
         };
         loader.addEventListener(IOErrorEvent.IO_ERROR,failed);
         loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR,failed);
         try
         {
            loader.load(new URLRequest(url()));
         }
         catch(err:*)
         {
            loading = false;
            Busy.done(BUSY);
         }
      }

      public static function apply(text:String) : int
      {
         var rows:Array = [];
         try
         {
            var root:Xml = Xml.parse(text).method_7292();
            var it:* = root.method_5430();
            while(it.hasNext())
            {
               rows.push(it.next());
            }
         }
         catch(e:*)
         {
            PrivateServer.log("tournaments: the server's list isn't valid XML (" + e + ")");
            return -1;
         }
         for each(var old:Xml in added)
         {
            table.removeChild(old);
         }
         added = [];
         for each(var row:Xml in rows)
         {
            root.removeChild(row);
            table.addChild(row);
            added.push(row);
         }
         try
         {
            class_647.method_8827(table);
         }
         catch(err:*)
         {
            PrivateServer.log("tournaments: the game's parser refused the list (" + err + ")");
            return -1;
         }
         var screen:Object = ScreenManager.var_1290;
         try
         {
            if(screen != null && screen.isActive)
            {
               screen.var_8580 = true;
               screen.OnRefreshScreen();
            }
         }
         catch(err2:*)
         {
         }
         PrivateServer.log("tournaments: " + rows.length + " from the server over " + PrivateServer.webScheme);
         return rows.length;
      }
   }
}
