package bh.platform
{
   import bh.platform.net.ModCheck;
   import bh.platform.net.ModShare;
   import flash.desktop.Clipboard;
   import flash.desktop.ClipboardFormats;
   import flash.display.Sprite;
   import flash.events.MouseEvent;

   public class ModServerWindow extends BigWindow
   {
      private static const TABS:Array = ["MY MODS","SEND","BY KEY","REVIEW"];
      private static const COLS:int = 2;
      private static const CARD_H:Number = 92;
      private static const REJECT_REASONS:Array = ["NOT A WORKING MOD","HOLDS CODE OR A SCRIPT","ART OR SOUND IT MAY NOT SHARE",
         "A COPY OF ANOTHER MOD","OTHER"];

      private static var window:ModServerWindow;
      private static var afterClose:Function;

      private var said:String = "";
      private var firstTab:int = 0;

      public function ModServerWindow(core:GameCore)
      {
         super(core);
      }

      public static function open(at:int = 0, closed:Function = null) : void
      {
         if(closed != null)
         {
            afterClose = closed;
         }
         if(window == null || ScreenManager.allScreens.indexOf(window) < 0)
         {
            window = new ModServerWindow(ScreenManager.owner);
            ScreenManager.registerScreen(window);
            if(ScreenManager.var_14744 != null)
            {
               window.registrationIndex = ScreenManager.var_14744.registrationIndex;
            }
         }
         window.firstTab = at;
         if(!window.isActive)
         {
            window.Display();
         }
         else
         {
            window.showTab(at);
         }
      }

      public static function get shown() : ModServerWindow
      {
         return window != null && window.isActive ? window : null;
      }

      override protected function get fullPage() : Boolean
      {
         return true;
      }

      override protected function get title() : String
      {
         return "MODS ON THE SERVER";
      }

      override protected function get tabNames() : Array
      {
         return TABS;
      }

      override protected function get tabLayout() : Array
      {
         return [-500,190,0.85];
      }

      override protected function get confirmLabel() : String
      {
         return "DONE";
      }

      override protected function tabOff(i:int) : Boolean
      {
         return i == 3 && !(ModShare.mine != null && ModShare.mine.reviewer);
      }

      override public function Display() : void
      {
         ModShare.mineChanged = arrived;
         ModShare.keyChanged = arrived;
         ModShare.shareDone = sendEnded;
         if(!ModShare.askingMine())
         {
            ModShare.askMine();
         }
         if(!isActive)
         {
            tab = firstTab;
            said = "";
         }
         super.Display();
      }

      private function arrived() : void
      {
         if(!isActive)
         {
            return;
         }
         if(ModShare.mine != null && ModShare.mine.message)
         {
            said = String(ModShare.mine.message);
            ModShare.mine.message = "";
         }
         build();
      }

      private function sendEnded(entry:String, why:String) : void
      {
         var name:String = entry.split("#")[0];
         said = why == null ? name + " is on the server." : name + " not sent: " + why + ".";
         if(isActive)
         {
            build();
         }
      }

      override protected function statusText() : String
      {
         if(said)
         {
            return said.toUpperCase();
         }
         var m:Object = ModShare.mine;
         if(m == null)
         {
            return ModShare.askingMine() ? "ASKING THE SERVER..." : "";
         }
         if(m.error)
         {
            return "";
         }
         return int(m.used) + " OF " + int(m.max) + " MODS · " + mb(Number(m.bytes)) + " OF " + mb(Number(m.max_bytes));
      }

      override protected function back() : void
      {
         Hide();
         var then:Function = afterClose;
         afterClose = null;
         if(then != null)
         {
            try
            {
               then();
            }
            catch(e:Error)
            {
               ErrorLog.write("mods on the server: reopening the Mods window failed: " + e);
            }
         }
      }

      private static function mb(bytes:Number) : String
      {
         return bytes >= 1048576 ? Math.round(bytes / 104857.6) / 10 + " MB" : Math.max(bytes > 0 ? 1 : 0,Math.round(bytes / 1024)) + " KB";
      }

      private function get CARD_W() : Number
      {
         return Math.floor((area.width - 30) / COLS);
      }

      override protected function buildTab(i:int) : void
      {
         var p:Sprite = panel(area.x,area.y,area.width,area.height);
         var m:Object = ModShare.mine;
         if(i != 2 && (m == null || m.error))
         {
            var why:String = m == null ? (ModShare.askingMine() ? "Asking the server..." : "Not connected to a server: " +
               "mods go to the project's server you play on (Options > Servers).") : String(m.error);
            UiKit.text(p,why,20,20,16,UiKit.LIGHT,UiKit.BOLD,area.width - 40);
            return;
         }
         var content:Sprite = scroller(p,10,10,area.width - 20,area.height - 20);
         switch(i)
         {
            case 0:
               buildMine(content,m);
               break;
            case 1:
               buildSend(content);
               break;
            case 2:
               buildKey(content);
               break;
            case 3:
               buildReview(content,m);
         }
      }

      private function at(n:int) : Array
      {
         return [(n % COLS) * (CARD_W + 10),int(n / COLS) * (CARD_H + 8)];
      }

      private function card(parent:Sprite, n:int, lines:Array, badge:String, badgeColour:uint, act:Function,
                            menu:Function) : Sprite
      {
         var xy:Array = at(n);
         var c:Sprite = new Sprite();
         c.x = xy[0];
         c.y = xy[1];
         c.buttonMode = true;
         parent.addChild(c);
         UiKit.rect(c,0,0,CARD_W,CARD_H,UiKit.BODY,6);
         var y:Number = 8;
         for(var k:int = 0; k < lines.length; k++)
         {
            var size:int = k == 0 ? 16 : 12;
            UiKit.fit(UiKit.text(c,String(lines[k]),14,y,size,k == 0 ? UiKit.WHITE : (k == 1 ? UiKit.TEAL : UiKit.GREY),
               k == 0 ? UiKit.XBOLD : UiKit.MEDIUM),CARD_W - (k == 0 && badge ? 190 : 28));
            y += k == 0 ? 24 : 18;
         }
         if(badge)
         {
            var t:* = UiKit.text(c,badge,0,10,12,badgeColour,UiKit.XBOLD);
            t.x = CARD_W - 14 - t.width;
         }
         var index:int = items.length;
         c.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            focus = index;
            paintFocus();
            if(act != null)
            {
               act();
            }
         });
         items.push({"sprite":c,"width":CARD_W,"height":CARD_H,"parent":parent,"use":act,"menu":menu});
         return c;
      }

      private static function visibilityText(v:String) : String
      {
         switch(v)
         {
            case "private":
               return "PRIVATE";
            case "review":
               return "WAITING FOR REVIEW";
            case "public":
               return "PUBLIC";
            case "rejected":
               return "REJECTED";
         }
         return String(v).toUpperCase();
      }

      private static function visibilityColour(v:String) : uint
      {
         return v == "public" ? UiKit.TEAL : (v == "rejected" ? UiKit.RED : (v == "review" ? UiKit.GOLD : UiKit.LIGHT));
      }

      private function empty(parent:Sprite, s:String) : void
      {
         UiKit.text(parent,s,10,10,15,UiKit.LIGHT,UiKit.BOLD,area.width - 60);
      }

      private function buildMine(parent:Sprite, m:Object) : void
      {
         var rows:Array = m.mods is Array ? m.mods : [];
         if(rows.length == 0)
         {
            empty(parent,"You have no mods on the server. SEND puts one of your installed mods there: private (only " +
               "people you give its key get it) or for review (once the server's owner checks it, it is on everyone's " +
               "Community tab).");
            return;
         }
         for(var n:int = 0; n < rows.length; n++)
         {
            var r:Object = rows[n];
            var state:String = String(r.visibility);
            card(parent,n,[String(r.name) + "  " + versionText(r.version),"KEY  " + r.key,
               mb(Number(r.size)) + " · sent " + String(r.at).substr(0,10) + (state == "rejected" && r.review_note ? " · " +
               r.review_note : (state == "public" ? " · on the Community tab" : (state == "private" ? " · only with its key" : "")))],
               visibilityText(state),visibilityColour(state),mineMenuOpener(r),mineMenu(r));
         }
      }

      private function mineMenu(r:Object) : Function
      {
         var self:ModServerWindow = this;
         return function():Array
         {
            var out:Array = [["COPY KEY " + r.key,function():void
            {
               copy(String(r.key));
               self.said = "Key " + r.key + " copied.";
               self.build();
            }]];
            if(r.visibility == "private")
            {
               out.push(["ASK TO MAKE PUBLIC",function():void
               {
                  self.askPublic(r);
               }]);
            }
            else if(r.visibility == "review" || r.visibility == "public")
            {
               out.push(["MAKE PRIVATE",function():void
               {
                  ModShare.act(String(r.pid),"private");
               }]);
            }
            out.push(["DELETE FROM THE SERVER",function():void
            {
               Modal.show("Delete " + r.name + "?","It is deleted from the server for good: its key stops working and " +
                  "it leaves the Community tab. Your installed copy stays.",[{"label":"Delete","action":function():void
               {
                  ModShare.act(String(r.pid),"delete");
               }},{"label":"Cancel"}]);
            }]);
            return out;
         };
      }

      private function mineMenuOpener(r:Object) : Function
      {
         var self:ModServerWindow = this;
         return function():void
         {
            self.openContext(self.items[self.focus]);
         };
      }

      private function askPublic(r:Object) : void
      {
         Modal.show("Make " + r.name + " public?","It goes to the server's review: once the server's owner checks it, it " +
            "is on every player's Community tab. Make public only mods you may pass on (made by you, or whose makers " +
            "allow it).",[{"label":"Ask","action":function():void
         {
            ModShare.act(String(r.pid),"public");
         }},{"label":"Cancel"}]);
      }

      private function buildSend(parent:Sprite) : void
      {
         var seen:Object = {};
         var mods:Array = [];
         for each(var mod:Object in ContentMods.mods.concat(ContentMods.all))
         {
            var entry:String = ModCheck.entryOf(mod);
            if(mod.dir != null && !seen[entry])
            {
               seen[entry] = true;
               mods.push(mod);
            }
         }
         mods.sortOn("name",Array.CASEINSENSITIVE);
         if(mods.length == 0)
         {
            empty(parent,"No mods are installed. Put a mod's folder in the mods folder (Mods window > OPEN MODS FOLDER), " +
               "restart the game, then send it from here.");
            return;
         }
         for(var n:int = 0; n < mods.length; n++)
         {
            var m:Object = mods[n];
            var st:String = ModShare.shareState(m);
            var badge:String = st == "share" ? "SEND" : (st == "sending" ? "SENDING..." : visibilityText(st));
            card(parent,n,[String(m.name || m.id) + "  " + versionText(m.version),(m.author ? "by " + m.author : String(m.id)),
               st == "share" ? "Not on the server" : (st == "sending" ? "Sending..." : "On the server: " + visibilityText(st).toLowerCase())],
               badge,st == "share" ? UiKit.WHITE : visibilityColour(st),sender(m),null);
         }
      }

      private function sender(mod:Object) : Function
      {
         var self:ModServerWindow = this;
         return function():void
         {
            self.askSend(mod);
         };
      }

      public function askSend(mod:Object) : void
      {
         var st:String = ModShare.shareState(mod);
         var copy:Object = ModShare.mineOf(ModCheck.entryOf(mod));
         if(st == "sending")
         {
            return;
         }
         if(copy != null)
         {
            showTab(0);
            said = mod.name + " is on the server already (" + visibilityText(st).toLowerCase() + ", key " + copy.key + ").";
            build();
            return;
         }
         var self:ModServerWindow = this;
         Modal.show("Send " + (mod.name || mod.id) + " to the server?","PRIVATE: it gets a key; only people you give the " +
            "key to can get it.\nPUBLIC: the same, and it asks the server's owner to check it; once checked it is on " +
            "every player's Community tab.\nSend only mods you may pass on (made by you, or whose makers allow it). The " +
            "server takes only mod files, and no game files holding code.",[{"label":"Private","action":function():void
         {
            self.startSend(mod,false);
         }},{"label":"Public","action":function():void
         {
            self.startSend(mod,true);
         }},{"label":"Cancel"}],true);
      }

      private function startSend(mod:Object, asPublic:Boolean) : void
      {
         said = ModShare.share(mod,asPublic) ? "Sending " + (mod.name || mod.id) + "..." : "Not connected to a server.";
         build();
      }

      private var keyTyped:String = "";

      private function buildKey(parent:Sprite) : void
      {
         var self:ModServerWindow = this;
         var typeIt:Function = function():void
         {
            self.typeText("MOD KEY",self.keyTyped,9,function(v:String):void
            {
               self.keyTyped = String(v || "").toUpperCase();
               if(self.keyTyped.replace(/[^A-Z0-9]/g,"").length > 0)
               {
                  self.said = ModShare.askKey(self.keyTyped) ? "Looking up " + self.keyTyped + "..." : "Not connected to a server.";
               }
               self.build();
            },true);
         };
         card(parent,0,["TYPE A KEY",keyTyped ? "Key: " + keyTyped : "Someone gave you a key such as ABCD-2345?",
            "Select to type it"],"",UiKit.WHITE,typeIt,null);
         var got:Object = ModShare.keyResult;
         if(got == null)
         {
            return;
         }
         if(got.error)
         {
            UiKit.text(parent,String(got.error),0,CARD_H + 20,15,UiKit.RED,UiKit.BOLD,area.width - 60);
            return;
         }
         var m:Object = got.mod;
         var st:String = ModShare.stateOf(String(m.entry));
         var action:String = st == "new" ? "GET" : (st == "other" ? "GET THIS VERSION" : (st == "off" ? "SWITCH ON" : "INSTALLED"));
         var get:Function = function():void
         {
            if(st == "loaded" || st == "on")
            {
               return;
            }
            self.said = "Getting " + m.name + "...";
            self.build();
            ModShare.getByKey(String(m.entry),function(why:String):void
            {
               self.said = why == null ? m.name + " installed: restart the game to load it." : m.name + " not installed: " + why + ".";
               self.build();
            });
         };
         card(parent,COLS,[String(m.name) + "  " + versionText(m.version),(m.author ? "by " + m.author + " · " : "") + mb(Number(m.size)) +
            " · " + m.files + " files",String(m.description || "").replace(/\s+/g," ").substr(0,120)],action,
            st == "new" || st == "other" ? UiKit.TEAL : UiKit.GREY,get,null);
      }

      private function buildReview(parent:Sprite, m:Object) : void
      {
         var rows:Array = m.review is Array ? m.review : [];
         if(rows.length == 0)
         {
            empty(parent,"No mods are waiting for review.");
            return;
         }
         for(var n:int = 0; n < rows.length; n++)
         {
            var r:Object = rows[n];
            var files:Array = r.file_list is Array ? r.file_list : [];
            card(parent,n,[String(r.name) + "  " + versionText(r.version),"from " + r.owner_name + " · " + mb(Number(r.size)) + " · " +
               r.files + " files · " + String(r.at).substr(0,10),files.slice(0,6).join("  ") + (files.length > 6 ? "  ..." : "")],
               "REVIEW",UiKit.GOLD,mineMenuOpener(r),reviewMenu(r));
         }
      }

      private function reviewMenu(r:Object) : Function
      {
         var self:ModServerWindow = this;
         return function():Array
         {
            return [["TRY IT (INSTALL HERE)",function():void
            {
               self.said = "Getting " + r.name + "...";
               self.build();
               ModShare.getMine(String(r.entry),function(why:String):void
               {
                  self.said = why == null ? r.name + " installed: restart the game to try it." : r.name + " not installed: " + why + ".";
                  self.build();
               });
            }],["APPROVE (MAKE PUBLIC)",function():void
            {
               ModShare.act(String(r.pid),"approve");
            }],["REJECT",function():void
            {
               self.pickFrom("REJECT " + String(r.name).toUpperCase(),REJECT_REASONS,0,function(i:int):void
               {
                  if(i >= 0)
                  {
                     ModShare.act(String(r.pid),"reject",String(REJECT_REASONS[i]).toLowerCase());
                  }
               });
            }]];
         };
      }

      private static function versionText(version:Object) : String
      {
         var v:String = String(version);
         return v.charAt(0) == "v" || v.charAt(0) == "V" ? v : "v" + v;
      }

      private static function copy(s:String) : void
      {
         try
         {
            Clipboard.generalClipboard.setData(ClipboardFormats.TEXT_FORMAT,s);
         }
         catch(e:Error)
         {
         }
      }

      override protected function moveIn(it:Object, dir:int) : Boolean
      {
         var to:int = focus + dir * COLS;
         if(to >= 0 && to < items.length)
         {
            focus = to;
            paintFocus();
         }
         return true;
      }

      override protected function useItem(it:Object, dir:int) : void
      {
         if(dir != 0)
         {
            var to:int = focus + dir;
            if(to >= 0 && to < items.length)
            {
               focus = to;
               paintFocus();
            }
            return;
         }
         if(it.use != null)
         {
            it.use();
         }
      }

      override protected function showTab(i:int) : void
      {
         said = "";
         super.showTab(i);
      }

   }
}
