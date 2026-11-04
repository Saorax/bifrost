package bh.platform
{
   import bh.platform.net.PrivateServer;
   import bh.platform.net.ReplayShare;
   import bh.platform.net.ServerStats;
   import flash.display.Bitmap;
   import flash.display.BitmapData;
   import flash.display.GradientType;
   import flash.display.MovieClip;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.events.MouseEvent;
   import flash.geom.Matrix;
   import flash.geom.Rectangle;
   import flash.text.TextField;
   import flash.utils.setTimeout;

   public class ProfileWindow extends BigWindow
   {
      private static const TABS:Array = ["RANK","2V2","STATS","MATCHES","BADGES"];
      private static const T_2V2:int = 1;
      private static const T_MATCHES:int = 3;
      private static const LADDERS:Array = [["1v1","RANKED 1V1"],["2v2","RANKED 2V2"]];
      private static const TOP:Number = 112;
      private static const BIO_MAX:int = 140;
      private static const GOLD:uint = 0xF2C14E;
      private static const SILVER:uint = 0xC9D3DD;
      private static const BRONZE:uint = 0xD08A4E;

      private static var window:ProfileWindow;
      private static var listening:Boolean = false;
      private static var banners:Object = {};
      private static var frames:Object = {};
      private static var frameDolls:Object = {};
      private static const FRAME:int = 100;

      private var key:String = "";
      private var fallbackName:String = "";
      private var artRetries:int = 0;

      public function ProfileWindow(core:GameCore)
      {
         super(core);
      }

      public static function open(id:uint, name:String = "") : void
      {
         openKey(String(id),name);
      }

      public static function openAccount(account:int, name:String = "") : void
      {
         openKey("a" + account,name);
      }

      private static function openKey(id:String, name:String) : void
      {
         if(window == null || ScreenManager.allScreens.indexOf(window) < 0)
         {
            window = new ProfileWindow(ScreenManager.owner);
            ScreenManager.registerScreen(window);
            if(ScreenManager.var_14744 != null)
            {
               window.registrationIndex = ScreenManager.var_14744.registrationIndex;
            }
         }
         if(!listening)
         {
            listening = true;
            ServerStats.listeners.push(function(query:String):void
            {
               if(window != null && window.isActive && query == window.query())
               {
                  window.build();
               }
            });
         }
         window.key = id;
         window.fallbackName = name;
         window.artRetries = 3;
         if(PrivateServer.host != null)
         {
            ServerStats.ask(window.query());
         }
         if(!window.isActive)
         {
            window.tab = 0;
            window.Display();
         }
         else
         {
            window.build();
         }
         Platform.log("profile: player " + id + (name ? " (" + name + ")" : ""));
      }

      public static function get shown() : ProfileWindow
      {
         return window != null && window.isActive ? window : null;
      }

      public function describe() : String
      {
         var p:Object = answer();
         if(p == null)
         {
            return "player " + key + ": waiting for the server";
         }
         if(p.error != null)
         {
            return "player " + key + ": " + p.error;
         }
         var t:Object = p.totals || {};
         var r:Object = p.ratings != null ? p.ratings["1v1"] : null;
         var b:Object = p.badges || {};
         return "player " + key + " " + p.name + ", tab " + TABS[tab] + ": " + int(t.matches) + " games, " +
            int(t.wins) + " wins" + (r != null ? ", 1v1 " + r.tier + " " + r.rating + " (peak " + r.peak + ")" : "") +
            ", " + (p.legends as Array || []).length + " legends, " + (p.weapons as Array || []).length + " weapons, " +
            (p.recent as Array || []).length + " matches, " + (p.seasons as Array || []).length + " past seasons, theme " +
            (p.look != null ? int(p.look.theme) : 0) + (themeShown ? " (drawn)" : "") + ", frame " + (p.look != null ? int(p.look.frame) : 0) +
            (frameShown ? " (drawn)" : "") + ", bio \"" + shownBio(p) + "\", " +
            (b.achievements as Array || []).length + " achievements, " + (b.tournaments as Array || []).length +
            " tournament wins" + (p.mine ? ", yours" : "");
      }

      public function showTabForTest(i:int) : void
      {
         showTab(i);
      }

      private function query() : String
      {
         return "profile:" + key;
      }

      private function answer() : Object
      {
         return PrivateServer.host != null ? ServerStats.get(query()) : null;
      }

      override protected function get fullPage() : Boolean
      {
         return true;
      }

      override protected function get title() : String
      {
         var p:Object = answer();
         var name:String = p != null && p.name != null ? String(p.name) : fallbackName;
         return name ? "PROFILE: " + name.toUpperCase() : "PROFILE";
      }

      override protected function get tabNames() : Array
      {
         return TABS;
      }

      override protected function get confirmLabel() : String
      {
         return "DONE";
      }

      override protected function hintText() : String
      {
         var p:Object = answer();
         return Prompts.KEYS.tabs + " RANK / 2V2 / STATS / MATCHES / BADGES     " + (tab == T_MATCHES ? Prompts.KEYS.select +
            " WATCH REPLAY     " + Prompts.KEYS.option + " MENU     " :(tab == T_2V2 ? Prompts.KEYS.select + " PARTNER'S PROFILE     " + Prompts.KEYS.option + " MENU     " : (p != null && p.mine ?
            Prompts.KEYS.select + " EDIT BIO     " : ""))) +
            Prompts.KEYS.back + " CLOSE";
      }

      public function setBioForTest(text:String) : void
      {
         saveBio(text);
      }

      private function saveBio(text:String) : void
      {
         ServerStats.setBio(text.substr(0,BIO_MAX));
         ServerStats.ask(query());
      }

      private static function shownBio(p:Object) : String
      {
         var bio:String = p.bio != null ? String(p.bio) : "";
         try
         {
            return bio ? class_406.method_3025(bio,false) : "";
         }
         catch(e:Error)
         {
         }
         return bio;
      }

      override protected function statusText() : String
      {
         if(PrivateServer.host == null)
         {
            return "Offline: profiles live on the project's server.";
         }
         var p:Object = answer();
         return p == null ? "Asking the server..." : (p.error != null ? String(p.error) : "");
      }

      override protected function back() : void
      {
         Hide();
      }

      override public function returnTo() : void
      {
         artRetries = 3;
         if(PrivateServer.host != null)
         {
            ServerStats.ask(query());
         }
         super.returnTo();
      }

      override protected function buildTab(i:int) : void
      {
         var p:Object = answer();
         var page:Sprite = panel(area.x,area.y,area.width,area.height);
         if(p == null || p.error != null)
         {
            UiKit.text(page,PrivateServer.host == null ? "Offline: profiles live on the project's server." :
               (p == null ? "Asking the server..." : String(p.error)),24,20,16,UiKit.LIGHT,UiKit.MEDIUM);
            return;
         }
         header(page,p);
         if(artRetries > 0)
         {
            artRetries--;
            var self:ProfileWindow = this;
            var shownKey:String = key;
            setTimeout(function():void
            {
               if(self.isActive && self.key == shownKey)
               {
                  self.build();
               }
            },800);
         }
         if(i == 0)
         {
            rankTab(page,p);
         }
         else if(i == T_2V2)
         {
            teamTab(page,p);
         }
         else if(i == 2)
         {
            statsTab(page,p);
         }
         else if(i == T_MATCHES)
         {
            matchesTab(page,p);
         }
         else
         {
            badgesTab(page,p);
         }
         if(editButton != null)
         {
            items.push({"w":"edit bio","sprite":editButton,"parent":page,"width":140,"height":30,"use":editBio});
         }
      }

      private function editBio() : void
      {
         var p:Object = answer();
         typeText("YOUR BIO",p != null && p.bio != null ? String(p.bio) : "",BIO_MAX,saveBio,true);
      }

      private var editButton:Sprite = null;
      private var themeShown:Boolean = false;
      private var frameShown:Boolean = false;

      private function header(page:Sprite, p:Object) : void
      {
         var bw:Number = area.width - 32;
         themeShown = false;
         var theme:int = p.look != null ? int(p.look.theme) : 0;
         var plate:Bitmap = theme > 0 ? banner(theme,int(bw),96) : null;
         if(plate != null)
         {
            plate.x = 16;
            plate.y = 6;
            plate.alpha = 0.75;
            page.addChild(plate);
            themeShown = true;
            var veil:Shape = new Shape();
            var vm:Matrix = new Matrix();
            vm.createGradientBox(bw,96,0,16,6);
            veil.graphics.beginGradientFill(GradientType.LINEAR,[UiKit.BODY,UiKit.BODY,UiKit.BODY],[0.85,0.7,0.35],
               [0,150,255],vm);
            veil.graphics.drawRect(16,6,bw,96);
            veil.graphics.endFill();
            page.addChild(veil);
         }
         var prof:Object = p.profile || {};
         var avSize:int = 76;
         frameShown = false;
         var frameId:int = p.look != null ? int(p.look.frame) : 0;
         var border:Bitmap = frameId > 0 ? frameArt(frameId,FRAME) : null;
         if(border != null)
         {
            border.x = 62 - FRAME / 2;
            border.y = 52 - FRAME / 2;
            page.addChild(border);
            frameShown = true;
            var inner:Rectangle = border.bitmapData.getColorBoundsRect(0xFF000000,0,false);
            avSize = Math.min(76,int(inner.width * 0.72));
         }
         try
         {
            var av:Bitmap = LeaderboardWindow.avatar(int(prof.avatar),avSize);
            if(av != null)
            {
               av.x = 62 - avSize / 2;
               av.y = 52 - avSize / 2;
               page.addChild(av);
            }
         }
         catch(e:Error)
         {
         }
         var tx:Number = 112;
         UiKit.fit(UiKit.text(page,String(p.name),tx,10,26,UiKit.WHITE,UiKit.XBOLD),420);
         var titleName:String = LeaderboardWindow.monikerName(int(prof.title));
         if(titleName)
         {
            UiKit.fit(UiKit.text(page,titleName,tx,44,13,LeaderboardWindow.monikerColour(int(prof.title)),UiKit.BOLD),420);
         }
         var t:Object = p.totals || {};
         var line:String = int(t.matches) + " GAMES   " + int(t.wins) + "-" + int(t.losses) + (int(t.draws) > 0 ? "-" +
            int(t.draws) : "") + "   " + pct(t.win_rate) + " WINS";
         if(p.streak != null && int(p.streak.count) > 1)
         {
            var kind:String = String(p.streak.kind);
            line += "   " + int(p.streak.count) + " " + (kind == "win" ? "WINS" : (kind == "loss" ? "LOSSES" :
               kind.toUpperCase() + "S")) + " IN A ROW";
         }
         UiKit.text(page,line,tx,66,14,UiKit.LIGHT,UiKit.BOLD);
         var rx:Number = Math.max(560,area.width * 0.5);
         var rw:Number = area.width - rx - 32;
         if(p.vs_you != null && int(p.vs_you.matches) > 0)
         {
            UiKit.text(page,"VS YOU: " + int(p.vs_you.wins) + "-" + int(p.vs_you.losses),rx,14,14,UiKit.TEAL,UiKit.BOLD);
         }
         editButton = null;
         if(p.mine)
         {
            editButton = button(page,"EDIT BIO",area.width - 172,12,140,editBio);
         }
         var bio:String = shownBio(p);
         var said:TextField = bio ? UiKit.text(page,"“" + bio + "”",rx,44,14,UiKit.WHITE,UiKit.MEDIUM,rw) :
            (p.mine ? UiKit.text(page,"No bio yet: EDIT BIO writes one line about you.",rx,44,13,UiKit.LIGHT,
            UiKit.MEDIUM,rw) : null);
         if(said != null)
         {
            var back:Shape = UiKit.rect(page,rx - 10,40,Math.min(said.textWidth + 26,rw + 20),said.textHeight + 12,
               UiKit.BODY,6);
            back.alpha = 0.7;
            page.setChildIndex(back,page.getChildIndex(said));
         }
      }

      private static function frameArt(id:int, size:int) : Bitmap
      {
         var k:String = id + "@" + size;
         if(frames[k] == null)
         {
            try
            {
               var d:PaperDoll = frameDolls[id];
               if(d == null)
               {
                  d = new PaperDoll(ScreenManager.owner,new MovieClip(),null,0,0,null,1);
                  PaperDoll.method_2875(d,class_559.method_7416(uint(id)));
                  frameDolls[id] = d;
               }
               var holder:Sprite = new Sprite();
               holder.addChild(d.var_219);
               var b:Rectangle = d.var_219.getBounds(holder);
               if(b.width <= 0 || b.height <= 0)
               {
                  return null;
               }
               var sc:Number = Math.min(size / b.width,size / b.height);
               var bd:BitmapData = new BitmapData(size,size,true,0);
               bd.draw(holder,new Matrix(sc,0,0,sc,(size - b.width * sc) / 2 - b.x * sc,(size - b.height * sc) / 2 -
                  b.y * sc),null,null,null,true);
               frames[k] = bd;
               holder.removeChild(d.var_219);
               d.method_5548();
               delete frameDolls[id];
            }
            catch(e:Error)
            {
               Platform.log("profile: frame " + id + ": " + e.message);
               return null;
            }
         }
         return new Bitmap(frames[k],"auto",true);
      }

      private static function banner(theme:int, w:int, h:int) : Bitmap
      {
         var k:String = theme + "@" + w + "x" + h;
         if(banners[k] == null)
         {
            try
            {
               var type:Object = class_297.var_11158 != null ? class_297.var_11158[theme] : null;
               if(type == null || !type.var_5894 || !type.clipLibrary)
               {
                  return null;
               }
               var clip:MovieClip = class_687.method_1714(String(type.var_5894),String(type.clipLibrary));
               if(clip == null)
               {
                  return null;
               }
               clip.gotoAndStop(1);
               clip.stopAllMovieClips();
               var holder:Sprite = new Sprite();
               holder.addChild(clip);
               var b:Rectangle = clip.getBounds(holder);
               if(b.width <= 0 || b.height <= 0)
               {
                  return null;
               }
               var sc:Number = Math.max(w / b.width,h / b.height);
               var m:Matrix = new Matrix(sc,0,0,sc,-b.x * sc + (w - b.width * sc) / 2,-b.y * sc + (h - b.height * sc) / 2);
               var bd:BitmapData = new BitmapData(w,h,true,0);
               bd.draw(clip,m,null,null,null,true);
               banners[k] = bd;
            }
            catch(e:Error)
            {
               Platform.log("profile: no banner for theme " + theme + " (" + e.message + ")");
               return null;
            }
         }
         var bm:Bitmap = new Bitmap(banners[k] as BitmapData);
         bm.smoothing = true;
         return bm;
      }

      private function badgesTab(page:Sprite, p:Object) : void
      {
         var b:Object = p.badges || {};
         var wins:Array = b.tournaments as Array || [];
         var y:Number = TOP;
         UiKit.text(page,"TOURNAMENT WINS",24,y,15,UiKit.TEAL,UiKit.XBOLD);
         y += 26;
         if(wins.length == 0)
         {
            UiKit.text(page,"No tournament won yet.",24,y,14,UiKit.GREY,UiKit.MEDIUM);
            y += 30;
         }
         var cx:Number = 24;
         for(var i:int = 0; i < wins.length && i < 8; i++)
         {
            var w:Object = wins[i];
            var label:String = "WON " + String(w.name).toUpperCase() + (w.mode ? "  " + String(w.mode).toUpperCase() : "");
            var cw:Number = Math.min(area.width - 48,Math.max(200,label.length * 9 + 28));
            if(cx + cw > area.width - 24)
            {
               cx = 24;
               y += 40;
            }
            UiKit.rect(page,cx,y,cw,32,GOLD,6);
            UiKit.fit(UiKit.text(page,label,cx + 14,y + 6,14,UiKit.NAVY_TEXT,UiKit.XBOLD),cw - 28);
            cx += cw + 12;
         }
         if(wins.length > 0)
         {
            y += 48;
         }
         var done:Array = b.achievements as Array || [];
         UiKit.text(page,"ACHIEVEMENTS (" + done.length + ")",24,y,15,UiKit.TEAL,UiKit.XBOLD);
         y += 26;
         if(done.length == 0)
         {
            UiKit.text(page,"None yet.",24,y,14,UiKit.GREY,UiKit.MEDIUM);
            return;
         }
         var chipW:Number = 236;
         var cols:int = Math.max(1,int((area.width - 48 + 10) / (chipW + 10)));
         for(var k:int = 0; k < done.length; k++)
         {
            var ax:Number = 24 + (k % cols) * (chipW + 10);
            var ay:Number = y + int(k / cols) * 34;
            if(ay > area.height - 34)
            {
               UiKit.text(page,"+" + (done.length - k) + " MORE",ax,ay + 4,13,UiKit.GREY,UiKit.XBOLD);
               break;
            }
            var name:String = String(done[k].name || "");
            UiKit.rect(page,ax,ay,chipW,28,stepColour(name),6);
            UiKit.fit(UiKit.text(page,spaced(name).toUpperCase(),ax + 10,ay + 5,12,UiKit.NAVY_TEXT,UiKit.XBOLD),chipW - 20);
         }
      }

      private static function stepColour(name:String) : uint
      {
         return name.indexOf("Gold") >= 0 ? GOLD : (name.indexOf("Silver") >= 0 ? SILVER : (name.indexOf("Bronze") >= 0 ?
            BRONZE : UiKit.TEAL));
      }

      private static function spaced(name:String) : String
      {
         return name.replace(/([a-z])([A-Z0-9])/g,"$1 $2").replace(/([0-9])([A-Z])/g,"$1 $2");
      }

      private function rankTab(page:Sprite, p:Object) : void
      {
         var colW:Number = (area.width - 72) / 2;
         for(var k:int = 0; k < LADDERS.length; k++)
         {
            ladderBlock(page,p,LADDERS[k][0],LADDERS[k][1],24 + k * (colW + 24),colW);
         }
         var seasons:Array = p.seasons as Array || [];
         var sy:Number = TOP + 270;
         UiKit.text(page,"PAST SEASONS",24,sy,15,UiKit.TEAL,UiKit.XBOLD);
         if(seasons.length == 0)
         {
            UiKit.text(page,"None yet: this is the first season.",24,sy + 26,14,UiKit.GREY,UiKit.MEDIUM);
            return;
         }
         sy += 26;
         for(var s:int = 0; s < seasons.length && sy < area.height - 24; s++)
         {
            UiKit.fit(UiKit.text(page,seasonLine(seasons[s]),24,sy,13,UiKit.LIGHT,UiKit.MEDIUM),area.width - 48);
            sy += 22;
         }
      }

      private static function ladderBlock(page:Sprite, p:Object, ladder:String, label:String, x:Number, colW:Number) : void
      {
         var y:Number = TOP;
         UiKit.text(page,label,x,y,15,UiKit.TEAL,UiKit.XBOLD);
         var r:Object = p.ratings != null ? p.ratings[ladder] : null;
         if(r == null || int(r.games) == 0)
         {
            UiKit.text(page,"No ranked games this season.",x,y + 26,14,UiKit.GREY,UiKit.MEDIUM);
            return;
         }
         try
         {
            var banner:Bitmap = LeaderboardWindow.tierBanner(String(r.tier),64,int(r.rating));
            if(banner != null)
            {
               banner.x = x;
               banner.y = y + 26;
               page.addChild(banner);
            }
         }
         catch(e:Error)
         {
         }
         var games:int = int(r.games);
         var placing:Boolean = games < PLACEMENT_GAMES;
         UiKit.text(page,placing ? "PLACEMENT " + games + "/" + PLACEMENT_GAMES :
            LeaderboardWindow.rankName(String(r.tier),int(r.rating)).toUpperCase(),x + 76,y + 28,18,UiKit.WHITE,UiKit.XBOLD);
         UiKit.text(page,"ELO " + int(r.rating) + "    PEAK " + int(r.peak) + (int(r.rank) > 0 ? "    #" + int(r.rank) : ""),
            x + 76,y + 54,14,UiKit.LIGHT,UiKit.BOLD);
         UiKit.text(page,int(r.wins) + " WINS, " + int(r.losses_or_draws) + " LOSSES OR DRAWS (" + games +
            " GAMES)",x + 76,y + 74,12,UiKit.GREY,UiKit.MEDIUM);
         var history:Array = p.history != null ? p.history[ladder] as Array : null;
         var gy:Number = y + 108;
         if(placing)
         {
            var heading:TextField = UiKit.text(page,"PLACEMENT MATCHES",x + 76,y + 98,11,UiKit.GREY,UiKit.XBOLD);
            var told:Array = p.results != null ? p.results[ladder] as Array : null;
            RatingExtras.placementPips(page,heading.x + heading.width + 12,y + 101,11,games,PLACEMENT_GAMES,
               told != null ? told : results(history));
            gy += 24;
         }
         if(history != null && history.length > 1)
         {
            UiKit.text(page,"ELO THIS SEASON",x,gy,11,UiKit.GREY,UiKit.XBOLD);
            graph(page,x,gy + 18,colW,110,history);
         }
      }

      public static const PLACEMENT_GAMES:int = 10;

      private static function results(points:Array) : Array
      {
         var out:Array = [];
         for(var i:int = (points != null ? points.length : 0) - 1; i >= 1; i--)
         {
            var d:Number = Number(points[i]) - Number(points[i - 1]);
            out.push(d > 0 ? "win" : (d < 0 ? "loss" : "draw"));
         }
         return out;
      }

      private function teamTab(page:Sprite, p:Object) : void
      {
         var soloW:Number = Math.round((area.width - 72) * 0.42);
         var solo:Sprite = new Sprite();
         solo.x = 16;
         solo.y = TOP - 10;
         page.addChild(solo);
         UiKit.rect(solo,0,0,soloW + 16,300,UiKit.BODY,8);
         UiKit.rect(solo,0,0,4,300,UiKit.TEAL);
         page.addChild(solo);
         ladderBlock(page,p,"2v2","SOLO RATING (2V2)",28,soloW - 8);
         var x:Number = 48 + soloW;
         var w:Number = area.width - x - 24;
         var y:Number = TOP;
         UiKit.text(page,"TEAMS",x,y,15,UiKit.TEAL,UiKit.XBOLD);
         UiKit.text(page,"TEAM RATINGS ARE SEPARATE FROM YOUR SOLO RATING",x + 80,y + 3,11,UiKit.GREY,UiKit.XBOLD);
         var partners:Array = p.partners as Array || [];
         if(partners.length == 0)
         {
            UiKit.text(page,"No 2v2 matches with a partner yet.",x,y + 30,14,UiKit.GREY,UiKit.MEDIUM);
            return;
         }
         y += 30;
         var cardW:Number = (w - 12) / 2;
         var cardH:Number = 104;
         for(var i:int = 0; i < partners.length; i++)
         {
            var cy:Number = y + int(i / 2) * (cardH + 12);
            if(cy + cardH > area.height - 16)
            {
               break;
            }
            var pt:Object = partners[i];
            var card:Sprite = new Sprite();
            card.x = x + i % 2 * (cardW + 12);
            card.y = cy;
            card.buttonMode = true;
            page.addChild(card);
            var team:Object = pt.team;
            var rated:Boolean = team != null && int(team.games) > 0;
            UiKit.rect(card,0,0,cardW,cardH,UiKit.BODY,8);
            UiKit.rect(card,0,0,4,cardH,rated ? UiKit.TEAL : UiKit.DIM);
            var item:Object = {"w":"partner " + pt.account,"sprite":card,"parent":page,"width":cardW,"height":cardH,
               "focusBox":[0,0,cardW,cardH],"use":partnerOpener(int(pt.account),String(pt.name || "")),
               "player":{"account":int(pt.account),"name":String(pt.name || "")}};
            items.push(item);
            card.addEventListener(MouseEvent.CLICK,rowClick(item));
            memberLine(card,int(pt.my_avatar),int(pt.my_legend),String(p.name || "YOU"),14,10,cardW - 150);
            memberLine(card,int(pt.avatar),int(pt.legend),String(pt.name || "?"),14,44,cardW - 150);
            var rx:Number = cardW - 128;
            if(rated)
            {
               try
               {
                  var icon:Sprite = RatingExtras.rankIcon(int(team.rating),int(team.games) < 10,30);
                  icon.x = rx;
                  icon.y = 12;
                  card.addChild(icon);
               }
               catch(e:Error)
               {
               }
               UiKit.text(card,String(int(team.rating)),rx + 38,10,20,UiKit.WHITE,UiKit.XBOLD);
               UiKit.text(card,"PEAK " + int(team.peak),rx + 38,36,11,UiKit.GREY,UiKit.XBOLD);
            }
            else
            {
               UiKit.text(card,"UNRATED",rx + 16,18,13,UiKit.GREY,UiKit.XBOLD);
            }
            var losses:int = int(pt.games) - int(pt.wins);
            var rec:TextField = UiKit.text(card,int(pt.wins) + "W",14,cardH - 24,12,UiKit.TEAL,UiKit.XBOLD);
            var rec2:TextField = UiKit.text(card," - ",rec.x + rec.width - 4,cardH - 24,12,UiKit.GREY,UiKit.XBOLD);
            UiKit.text(card,losses + "L",rec2.x + rec2.width - 4,cardH - 24,12,UiKit.RED,UiKit.XBOLD);
            UiKit.text(card,int(pt.games) + (int(pt.games) == 1 ? " GAME TOGETHER" : " GAMES TOGETHER"),cardW - 14,cardH - 24,12,
               UiKit.GREY,UiKit.XBOLD).x =
               cardW - 14 - 150;
         }
      }

      private static function memberLine(card:Sprite, avatarId:int, legend:int, name:String, x:Number, y:Number,
                                         nameW:Number) : void
      {
         try
         {
            var av:Bitmap = LeaderboardWindow.avatar(avatarId,28);
            if(av != null)
            {
               av.x = x;
               av.y = y;
               card.addChild(av);
            }
         }
         catch(e:Error)
         {
         }
         var nx:Number = x + 34;
         if(legend > 0)
         {
            try
            {
               var li:Bitmap = LeaderboardWindow.legendIcon(legend,28);
               if(li != null)
               {
                  li.x = nx;
                  li.y = y;
                  card.addChild(li);
                  nx += 34;
               }
            }
            catch(le:Error)
            {
            }
         }
         UiKit.fit(UiKit.text(card,name,nx,y + 4,15,UiKit.WHITE,UiKit.BOLD),nameW - (nx - x));
      }

      private static function replayEntry(watch:Function) : Function
      {
         return function():Array
         {
            return [["WATCH REPLAY",watch]];
         };
      }

      private static function partnerOpener(account:int, name:String) : Function
      {
         return function():void
         {
            ProfileWindow.openAccount(account,name);
         };
      }

      private static function seasonLine(s:Object) : String
      {
         return String(s.name || ("Season " + int(s.season))).toUpperCase() + "   " + String(s.ladder).toUpperCase() +
            "   " + String(s.tier || "").toUpperCase() + " " + int(s.rating) + "   PEAK " + int(s.peak) + "   " +
            int(s.wins) + " WINS IN " + int(s.games) + (s.rank != null ? "   #" + int(s.rank) : "");
      }

      private static function graph(page:Sprite, x:Number, y:Number, w:Number, h:Number, points:Array) : void
      {
         var lo:Number = Number.MAX_VALUE;
         var hi:Number = -Number.MAX_VALUE;
         for each(var v:Number in points)
         {
            lo = Math.min(lo,v);
            hi = Math.max(hi,v);
         }
         if(hi - lo < 10)
         {
            hi = lo + 10;
         }
         var g:Shape = new Shape();
         g.graphics.beginFill(UiKit.BODY,0.6);
         g.graphics.drawRect(x,y,w,h);
         g.graphics.endFill();
         g.graphics.lineStyle(2,UiKit.TEAL);
         var left:Number = x + 44;
         var span:Number = w - 52;
         for(var i:int = 0; i < points.length; i++)
         {
            var px:Number = left + span * i / (points.length - 1);
            var py:Number = y + h - 8 - (h - 16) * (Number(points[i]) - lo) / (hi - lo);
            if(i == 0)
            {
               g.graphics.moveTo(px,py);
            }
            else
            {
               g.graphics.lineTo(px,py);
            }
         }
         page.addChild(g);
         UiKit.text(page,String(int(hi)),x + 4,y + 2,11,UiKit.GREY,UiKit.BOLD);
         UiKit.text(page,String(int(lo)),x + 4,y + h - 16,11,UiKit.GREY,UiKit.BOLD);
      }

      private function statsTab(page:Sprite, p:Object) : void
      {
         var t:Object = p.totals || {};
         var y:Number = TOP;
         var nums:Array = [["KOS",int(t.kos)],["FALLS",int(t.falls)],["SELF-KOS",int(t.self_kos)],
            ["DAMAGE DEALT",int(t.damage_dealt)],["DAMAGE TAKEN",int(t.damage_taken)]];
         var x:Number = 24;
         for each(var n:Array in nums)
         {
            UiKit.text(page,n[0],x,y,11,UiKit.GREY,UiKit.XBOLD);
            UiKit.text(page,String(n[1]),x,y + 14,22,UiKit.WHITE,UiKit.XBOLD);
            x += 170;
         }
         y += 64;
         var colW:Number = (area.width - 72) / 2;
         UiKit.text(page,"TOP LEGENDS",24,y,15,UiKit.TEAL,UiKit.XBOLD);
         UiKit.text(page,"GAMES",24 + 220,y + 2,11,UiKit.GREY,UiKit.XBOLD);
         UiKit.text(page,"W-L",24 + 290,y + 2,11,UiKit.GREY,UiKit.XBOLD);
         UiKit.text(page,"WIN %",24 + 360,y + 2,11,UiKit.GREY,UiKit.XBOLD);
         UiKit.text(page,"KOS",24 + 430,y + 2,11,UiKit.GREY,UiKit.XBOLD);
         var legends:Array = p.legends as Array || [];
         var ly:Number = y + 24;
         for(var i:int = 0; i < legends.length && i < 8; i++)
         {
            var l:Object = legends[i];
            try
            {
               var icon:Bitmap = LeaderboardWindow.legendIcon(int(l.legend),28);
               if(icon != null)
               {
                  icon.x = 24;
                  icon.y = ly;
                  page.addChild(icon);
               }
            }
            catch(e:Error)
            {
            }
            UiKit.fit(UiKit.text(page,LeaderboardWindow.legendName(int(l.legend),String(l.legend_name)),60,ly + 4,14,
               UiKit.WHITE,UiKit.BOLD),150);
            UiKit.text(page,String(int(l.matches)),24 + 220,ly + 5,13,UiKit.LIGHT,UiKit.MEDIUM);
            UiKit.text(page,int(l.wins) + "-" + int(l.losses),24 + 290,ly + 5,13,UiKit.LIGHT,UiKit.MEDIUM);
            UiKit.text(page,pct(l.win_rate),24 + 360,ly + 5,13,UiKit.LIGHT,UiKit.MEDIUM);
            UiKit.text(page,String(int(l.kos)),24 + 430,ly + 5,13,UiKit.LIGHT,UiKit.MEDIUM);
            ly += 32;
         }
         var wx:Number = 48 + colW;
         UiKit.text(page,"TOP WEAPONS",wx,y,15,UiKit.TEAL,UiKit.XBOLD);
         UiKit.text(page,"KOS",wx + 160,y + 2,11,UiKit.GREY,UiKit.XBOLD);
         UiKit.text(page,"DAMAGE",wx + 230,y + 2,11,UiKit.GREY,UiKit.XBOLD);
         UiKit.text(page,"TIME HELD",wx + 320,y + 2,11,UiKit.GREY,UiKit.XBOLD);
         var weapons:Array = p.weapons as Array || [];
         var wy:Number = y + 24;
         if(weapons.length == 0)
         {
            UiKit.text(page,"No weapon numbers yet.",wx,wy,14,UiKit.GREY,UiKit.MEDIUM);
         }
         for(var k:int = 0; k < weapons.length && k < 6; k++)
         {
            var w:Object = weapons[k];
            UiKit.icon(page,weaponIcon(String(w.weapon)),wx,wy,28);
            UiKit.fit(UiKit.text(page,weaponName(String(w.weapon)),wx + 34,wy + 4,14,UiKit.WHITE,UiKit.BOLD),122);
            UiKit.text(page,String(int(w.kos)),wx + 160,wy + 5,13,UiKit.LIGHT,UiKit.MEDIUM);
            UiKit.text(page,String(int(w.damage)),wx + 230,wy + 5,13,UiKit.LIGHT,UiKit.MEDIUM);
            UiKit.text(page,clock(Number(w.held)),wx + 320,wy + 5,13,UiKit.LIGHT,UiKit.MEDIUM);
            wy += 32;
         }
      }

      private static const WEAPON_NAMES:Object = {"Pistol":"BLASTERS","Fists":"GAUNTLETS","Boots":"BATTLE BOOTS"};

      private static function weaponName(weapon:String) : String
      {
         return WEAPON_NAMES[weapon] != null ? String(WEAPON_NAMES[weapon]) : spaced(weapon).toUpperCase();
      }

      private static function weaponIcon(weapon:String) : MovieClip
      {
         try
         {
            var clip:MovieClip = weapon ? class_687.method_1714("a_WeaponIcon_" + weapon,"UI_Icons") : null;
            if(clip != null)
            {
               clip.stopAllMovieClips();
            }
            return clip;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private function matchesTab(page:Sprite, p:Object) : void
      {
         var recent:Array = p.recent as Array || [];
         var me:int = int(p.id);
         var y:Number = TOP;
         UiKit.text(page,"LAST MATCHES",24,y,15,UiKit.TEAL,UiKit.XBOLD);
         if(recent.length == 0)
         {
            UiKit.text(page,"No matches yet.",24,y + 26,14,UiKit.GREY,UiKit.MEDIUM);
            return;
         }
         y += 28;
         var rowW:Number = area.width - 32;
         for(var i:int = 0; i < recent.length && y < area.height - 30; i++)
         {
            var m:Object = recent[i];
            var row:Sprite = new Sprite();
            row.y = y;
            row.graphics.beginFill(0,0);
            row.graphics.drawRect(16,-2,rowW,28);
            row.graphics.endFill();
            page.addChild(row);
            var item:Object = {"w":"match " + m.id,"sprite":row,"parent":page,"width":rowW,"height":28,
               "focusBox":[16,-2,rowW,28],"use":watcher(m)};
            items.push(item);
            item.players = [];
            for each(var mp:Object in m.players as Array || [])
            {
               if(int(mp.account) != me)
               {
                  item.players.push({"account":int(mp.account),"name":String(mp.name || "")});
               }
            }
            item.menu = replayEntry(item.use);
            row.addEventListener(MouseEvent.CLICK,rowClick(item,false));
            var mine:Object = null;
            var others:Array = [];
            for each(var pl:Object in m.players as Array || [])
            {
               if(int(pl.account) == me && mine == null)
               {
                  mine = pl;
               }
               else
               {
                  others.push(pl);
               }
            }
            var outcome:String = mine != null ? String(mine.outcome || "").toUpperCase() : "";
            UiKit.text(row,outcome || "-",24,4,14,outcome == "WIN" ? UiKit.TEAL : (outcome == "LOSS" ? UiKit.RED :
               UiKit.LIGHT),UiKit.XBOLD);
            if(mine != null)
            {
               try
               {
                  var icon:Bitmap = LeaderboardWindow.legendIcon(int(mine.legend),24);
                  if(icon != null)
                  {
                     icon.x = 90;
                     row.addChild(icon);
                  }
               }
               catch(e:Error)
               {
               }
               if(mine.kos != null)
               {
                  UiKit.text(row,int(mine.kos) + "-" + int(mine.falls),120,5,13,UiKit.LIGHT,UiKit.MEDIUM);
               }
            }
            var vs:Array = [];
            var with_:Array = [];
            for each(var o:Object in others)
            {
               (mine != null && o.team != null && int(o.team) > 0 && int(o.team) == int(mine.team) ? with_ : vs).push(o);
            }
            var px:Number = 180;
            var pEnd:Number = 180 + area.width * 0.42;
            if(with_.length > 0)
            {
               px = playersAt(row,"WITH",with_,px,pEnd) + 14;
            }
            playersAt(row,"VS",vs,px,pEnd);
            UiKit.fit(UiKit.text(row,LeaderboardWindow.mapName(m),area.width * 0.42 + 200,5,13,UiKit.LIGHT,
               UiKit.MEDIUM),area.width * 0.22);
            UiKit.text(row,clock(Number(m.duration)) + (m.rated ? "   RANKED" : ""),area.width * 0.66 + 200,5,12,
               UiKit.GREY,UiKit.BOLD);
            if(m.replay)
            {
               var watch:Sprite = new Sprite();
               watch.x = rowW - 80;
               watch.buttonMode = true;
               row.addChild(watch);
               UiKit.rect(watch,0,1,86,24,UiKit.PANEL,5);
               watch.graphics.lineStyle(1,UiKit.TEAL);
               watch.graphics.drawRoundRect(0,1,86,24,10);
               UiKit.text(watch,"REPLAY",43,5,12,UiKit.TEAL,UiKit.XBOLD,0,true);
               watch.addEventListener(MouseEvent.CLICK,rowClick(item,true));
            }
            else
            {
               UiKit.text(row,"NO REPLAY",rowW - 70,5,12,UiKit.GREY,UiKit.XBOLD);
            }
            y += 30;
         }
      }

      private static function playersAt(row:Sprite, label:String, players:Array, x:Number, end:Number) : Number
      {
         var t:TextField = UiKit.text(row,label,x,5,13,UiKit.GREY,UiKit.XBOLD);
         x += t.textWidth + 10;
         var room:Number = players.length > 0 ? (end - x) / players.length : 0;
         for(var i:int = 0; i < players.length; i++)
         {
            var o:Object = players[i];
            var start:Number = x;
            if(int(o.avatar) > 0)
            {
               try
               {
                  var av:Bitmap = LeaderboardWindow.avatar(int(o.avatar),22);
                  if(av != null)
                  {
                     av.x = x;
                     av.y = 1;
                     row.addChild(av);
                     x += 26;
                  }
               }
               catch(ae:Error)
               {
               }
            }
            if(int(o.legend) > 0)
            {
               try
               {
                  var icon:Bitmap = LeaderboardWindow.legendIcon(int(o.legend),22);
                  if(icon != null)
                  {
                     icon.x = x;
                     icon.y = 1;
                     row.addChild(icon);
                  }
               }
               catch(e:Error)
               {
               }
               x += 26;
            }
            var name:TextField = UiKit.fit(UiKit.text(row,String(o.name) + (i < players.length - 1 ? "," : ""),x,5,13,
               UiKit.WHITE,UiKit.BOLD),Math.max(40,room - (x - start) - 8));
            x += name.width + 10;
         }
         return x;
      }

      private function rowClick(item:Object, pick:Boolean = true) : Function
      {
         var self:ProfileWindow = this;
         return function(e:MouseEvent):void
         {
            e.stopPropagation();
            var at:int = self.items.indexOf(item);
            if(at >= 0 && at != self.focus)
            {
               self.focus = at;
               self.paintFocus();
            }
            if(pick)
            {
               self.useItem(item,0);
            }
         };
      }

      private function watcher(m:Object) : Function
      {
         var self:ProfileWindow = this;
         return function():void
         {
            if(!m.replay)
            {
               DummyDrift.show("No replay: the server keeps none of that match.",2500);
               return;
            }
            BackTrail.leaving("replay");
            ReplayShare.fetch(uint(m.room),uint(m.seed),true);
         };
      }

      private static function pct(rate:Object) : String
      {
         return rate == null ? "-" : Math.round(Number(rate) * 100) + "%";
      }

      private static function clock(ms:Number) : String
      {
         var s:int = int(ms / 1000);
         var h:int = s / 3600;
         var mm:int = (s % 3600) / 60;
         var ss:int = s % 60;
         return (h > 0 ? h + ":" + (mm < 10 ? "0" : "") : "") + mm + ":" + (ss < 10 ? "0" : "") + ss;
      }
   }
}
