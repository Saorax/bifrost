package bh.mods.examplescreen
{
   import bh.platform.BigWindow;
   import bh.platform.BmodImport;
   import bh.platform.Prompts;
   import bh.platform.ColorEditor;
   import bh.platform.ContentMods;
   import bh.platform.MapArt;
   import bh.platform.ModSettings;
   import bh.platform.MusicPacks;
   import bh.platform.Modal;
   import bh.platform.ModServerWindow;
   import bh.platform.Platform;
   import bh.platform.net.ModCheck;
   import bh.platform.net.ModShare;
   import flash.display.Bitmap;
   import flash.display.BitmapData;
   import flash.display.DisplayObject;
   import flash.display.Loader;
   import flash.display.MovieClip;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.events.MouseEvent;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.geom.Point;
   import flash.geom.Rectangle;
   import flash.system.ApplicationDomain;
   import flash.text.Font;
   import flash.text.TextField;
   import flash.text.TextFieldAutoSize;
   import flash.text.TextFormat;
   import flash.events.SecurityErrorEvent;
   import flash.net.URLLoader;
   import flash.net.URLLoaderDataFormat;
   import flash.net.URLRequest;
   import flash.utils.ByteArray;
   import flash.utils.getTimer;

   public class ModsScreen extends ScreenBase
   {
      private static const PANEL:uint = 0x0B2336;
      private static const BODY:uint = 0x061521;
      private static const TEAL:uint = 0x4FE3D0;
      private static const WHITE:uint = 0xFFFFFF;
      private static const GREY:uint = 0x7F8C99;
      private static const LIGHT:uint = 0xC8D2DC;
      private static const ROW_SELECTED:uint = 0x123A5A;
      private static const LINE:uint = 0x1D3A52;
      private static const NAVY_TEXT:uint = 0x0B2336;

      private static const BOLD:String = "BMG Bespoke Sans Bold";
      private static const XBOLD:String = "BMG Bespoke Sans Extrabold";
      private static const MEDIUM:String = "BMG Author Medium";

      private static const TABS:Array = ["INSTALLED","MAP ART","AUDIO","ADDED ITEMS","COMMUNITY"];

      private var HALF:Number = 540;
      private var LEFT:Number = -530;
      private var LIST_W:Number = 440;
      private var DX:Number = -76;
      private var DW:Number = 606;
      private var TOP:Number = -50;
      private var HEIGHT:Number = 372;

      private static const SCREEN:Rectangle = new Rectangle(-683,-287,1366,768);

      private static var keys:Object = {};
      private static var nextKey:int = 0;
      private static var bitmaps:Object = {};
      private static var waiting:Object = {};
      private static var fontsChecked:Boolean = false;
      private static var gameFonts:Boolean = false;

      private var body:Sprite;
      private var tabBody:Sprite;
      private var tabClips:Array = [];
      private var tab:int = 0;
      private var status:TextField;

      private var entries:Array = [];
      private var rows:Array = [];
      private var rowHeight:Number = 50;
      private var listView:Sprite;
      private var listContent:Sprite;
      private var listHeight:Number = 0;
      private var scrollBar:Sprite;
      private var barGrab:Number = -1;
      private var selected:int = 0;
      private var remembered:Array = [0,0,0,0,0];
      private var details:Sprite;
      private var dolls:Array = [];

      private var chipNames:Array = [];
      private var chipIndex:Array = [0,0,0,0,0];
      private var chipBar:Sprite;

      private var focus:String = "list";
      private var tiles:Array = [];
      private var tileFocus:int = 0;
      private var allMaps:TextField;
      private var allMapsLine:Shape;

      private var signatures:Array = [];
      private var signatureAt:int = 0;
      private var signatureDoll:PaperDoll;
      private var signatureLabel:TextField;
      private var signatureWidth:Number = 0;
      private var signatureCostume:CostumeType;
      private var soundsOn:Boolean = false;

      public function ModsScreen(game:GameCore)
      {
         super(game,"a_ScreenNews","am_PanelInternal","UI_NewsPage");
         var_3798 = "FadeIn";
         var_14711 = "FadeOut";
         var_5327 = true;
      }

      private static function key(text:String) : String
      {
         if(keys[text] == null)
         {
            keys[text] = "BH_Mods_T" + nextKey++;
            if(Localization.var_14676 != null)
            {
               Localization.var_14676.var_15061.method_65(keys[text],text);
            }
         }
         return keys[text];
      }

      private static function fontsReady() : Boolean
      {
         if(!fontsChecked)
         {
            fontsChecked = true;
            for each(var f:Font in Font.enumerateFonts(false))
            {
               if(f.fontName == BOLD)
               {
                  gameFonts = true;
               }
            }
         }
         return gameFonts;
      }

      private static function text(parent:Sprite, s:String, x:Number, y:Number, size:Number, color:uint, font:String,
                                   width:Number = 0, center:Boolean = false) : TextField
      {
         var t:TextField = new TextField();
         t.selectable = false;
         t.mouseEnabled = false;
         t.embedFonts = fontsReady();
         t.defaultTextFormat = new TextFormat(t.embedFonts ? font : "_sans",size,color,!t.embedFonts && font != MEDIUM);
         t.autoSize = TextFieldAutoSize.LEFT;
         if(width > 0)
         {
            t.multiline = true;
            t.wordWrap = true;
            t.width = width;
         }
         t.text = s;
         t.x = center ? x - t.width / 2 : x;
         t.y = y;
         parent.addChild(t);
         return t;
      }

      private static function fit(t:TextField, width:Number) : TextField
      {
         var s:String = t.text;
         while(t.width > width && s.length > 1)
         {
            s = s.substr(0,s.length - 1);
            t.text = s + "...";
         }
         return t;
      }

      private static function rect(parent:Sprite, x:Number, y:Number, w:Number, h:Number, color:uint,
                                   radius:Number = 0) : Shape
      {
         var s:Shape = new Shape();
         s.graphics.beginFill(color);
         if(radius > 0)
         {
            s.graphics.drawRoundRect(x,y,w,h,radius,radius);
         }
         else
         {
            s.graphics.drawRect(x,y,w,h);
         }
         s.graphics.endFill();
         parent.addChild(s);
         return s;
      }

      private static function picture(parent:Sprite, file:File, w:Number, h:Number, cover:Boolean) : void
      {
         if(file == null || !file.exists)
         {
            return;
         }
         var place:Function = function(bd:BitmapData):void
         {
            var b:Bitmap = new Bitmap(bd,"auto",true);
            var scale:Number = cover ? Math.max(w / bd.width,h / bd.height) : Math.min(w / bd.width,h / bd.height);
            b.scaleX = b.scaleY = scale;
            b.x = (w - b.width) / 2;
            b.y = (h - b.height) / 2;
            parent.addChild(b);
            if(cover)
            {
               b.mask = rect(parent,0,0,w,h,0);
            }
         };
         var path:String = file.nativePath;
         if(bitmaps[path] is BitmapData)
         {
            place(bitmaps[path]);
            return;
         }
         if(waiting[path] != null)
         {
            waiting[path].push(place);
            return;
         }
         waiting[path] = [place];
         try
         {
            var bytes:ByteArray = new ByteArray();
            var stream:FileStream = new FileStream();
            stream.open(file,FileMode.READ);
            stream.readBytes(bytes);
            stream.close();
            var loader:Loader = new Loader();
            loader.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void
            {
               var bd:BitmapData = (loader.content as Bitmap).bitmapData;
               bitmaps[path] = bd;
               for each(var f:Function in waiting[path])
               {
                  f(bd);
               }
               delete waiting[path];
            });
            loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR,function(e:Event):void
            {
               Platform.log("mods window: picture " + path + " didn't load");
               delete waiting[path];
            });
            loader.loadBytes(bytes);
         }
         catch(e:Error)
         {
            Platform.log("mods window: picture " + path + ": " + e.message);
            delete waiting[path];
         }
      }

      private static function icon(parent:Sprite, clip:DisplayObject, x:Number, y:Number, size:Number) : void
      {
         if(clip == null)
         {
            return;
         }
         var holder:Sprite = new Sprite();
         holder.mouseEnabled = false;
         holder.mouseChildren = false;
         holder.addChild(clip);
         var b:Rectangle = clip.getBounds(holder);
         if(b.width > 0 && b.height > 0)
         {
            var scale:Number = Math.min(size / b.width,size / b.height);
            clip.scaleX = clip.scaleY = scale;
            b = clip.getBounds(holder);
            clip.x -= b.x + b.width / 2 - size / 2;
            clip.y -= b.y + b.height / 2 - size / 2;
         }
         holder.x = x;
         holder.y = y;
         parent.addChild(holder);
      }

      private static function badge(parent:Sprite, letter:String, x:Number, y:Number, size:Number) : void
      {
         rect(parent,x,y,size,size,LINE,size);
         text(parent,letter,x + size / 2,y + size / 2 - size * 0.32,size * 0.45,TEAL,XBOLD,0,true);
      }

      private static function modsFolder() : File
      {
         return File.applicationDirectory.resolvePath(ContentMods.FOLDER);
      }

      override public function OnCreateScreen() : void
      {
         current = this;
         for(var i:int = 0; i < panelClip.numChildren; i++)
         {
            panelClip.getChildAt(i).visible = false;
         }
         var r:Rectangle = pageScreen();
         HALF = (r.width - 40) / 2;
         LEFT = r.x + 30;
         TOP = r.y + 122 + 36;
         HEIGHT = r.height - 222 - 36;
         LIST_W = Math.round((r.width - 60) * 0.4);
         DX = LEFT + LIST_W + 14;
         DW = r.right - 30 - DX;
         body = new Sprite();
         panelClip.addChild(body);
         rect(body,r.x,r.y,r.width,r.height,BODY);
         rect(body,r.x,r.y,r.width,104,PANEL);
         rect(body,r.x,r.y + 104,r.width,3,TEAL);
         rect(body,r.x,r.bottom - 64,r.width,64,PANEL);
         text(body,"MODS",r.x + 36,r.y + 14,30,WHITE,XBOLD);
         var gap:Number = Math.min(200,(r.width - 72) / TABS.length);
         for(i = 0; i < TABS.length; i++)
         {
            var clip:MovieClip = class_687.method_1497("a_TabButton","UI_EventCenter");
            clip.x = r.x + 36 + i * gap;
            clip.y = r.y + 60;
            clip.scaleX = clip.scaleY = 0.85 * gap / 200;
            if(clip.getChildByName("am_Text") != null)
            {
               clip.getChildByName("am_Text").visible = false;
            }
            var holder:Sprite = new Sprite();
            clip.addChild(holder);
            text(holder,TABS[i],79,6,17,NAVY_TEXT,BOLD,0,true);
            clip.buttonMode = true;
            clip.mouseChildren = false;
            clip.addEventListener(MouseEvent.CLICK,tabClick(i));
            clip.addEventListener(MouseEvent.ROLL_OVER,tabHover(i,true));
            clip.addEventListener(MouseEvent.ROLL_OUT,tabHover(i,false));
            body.addChild(clip);
            tabClips.push(clip);
         }
         bottomButton("BACK",r.right - 210,function():void
         {
            onClose();
         },r.y + 18,0.85);
         bottomButton("OPEN MODS FOLDER",r.x + 36,openFolder,r.bottom - 50);
         bottomButton("IMPORT .BMOD",r.x + 246,importBmod,r.bottom - 50);
         bottomButton("COLOUR EDITOR",r.x + 456,openColorEditor,r.bottom - 50);
         status = text(body,"",r.x + 680,r.bottom - 42,15,TEAL,MEDIUM);
         hint = new Sprite();
         hint.y = r.bottom - 92;
         hintWidth = r.right - 36;
         body.addChild(hint);
         buildTab();
      }

      private var hint:Sprite;

      private var hintWidth:Number = 0;

      private function paintHint() : void
      {
         if(hint == null)
         {
            return;
         }
         hint.removeChildren();
         var n:Object = Prompts.KEYS;
         var option:String = tab == 0 ? "REMOVE" : (tab == 4 ? "LIKE" : "COLOUR EDITOR");
         Prompts.fill(this,hint,n.tabs + " TABS     " + n.page + " PAGE     " + n.select + " SELECT     " + n.option + " " +
            option + "     {Alt} MODS ON THE SERVER     " + n.back + " BACK",20,12,GREY,hintWidth);
      }

      private function pageScreen() : Rectangle
      {
         try
         {
            if(panelClip != null && panelClip.stage != null)
            {
               var tl:Point = panelClip.globalToLocal(new Point(0,0));
               var br:Point = panelClip.globalToLocal(new Point(panelClip.stage.stageWidth,panelClip.stage.stageHeight));
               if(br.x - tl.x > 600 && br.y - tl.y > 300)
               {
                  return new Rectangle(tl.x,tl.y,br.x - tl.x,br.y - tl.y);
               }
            }
         }
         catch(e:Error)
         {
         }
         return SCREEN.clone();
      }

      private function bottomButton(label:String, x:Number, act:Function, y:Number, scale:Number = 0.95) : void
      {
         var b:MovieClip = class_687.method_1497("a_TabButton","UI_EventCenter");
         b.x = x;
         b.y = y;
         b.scaleX = scale;
         b.scaleY = 0.85;
         if(b.getChildByName("am_Text") != null)
         {
            b.getChildByName("am_Text").visible = false;
         }
         var holder:Sprite = new Sprite();
         b.addChild(holder);
         text(holder,label,83,6,17,NAVY_TEXT,BOLD,0,true);
         b.buttonMode = true;
         b.mouseChildren = false;
         b.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            act();
         });
         b.addEventListener(MouseEvent.ROLL_OVER,function(e:MouseEvent):void
         {
            b.gotoAndStop("Over");
         });
         b.addEventListener(MouseEvent.ROLL_OUT,function(e:MouseEvent):void
         {
            b.gotoAndStop("Ready");
         });
         body.addChild(b);
      }

      private function openServerWindow(at:int) : void
      {
         onClose();
         ModServerWindow.open(at,function():void
         {
            ExampleScreenMod.open();
         });
      }

      private function openColorEditor() : void
      {
         onClose();
         ColorEditor.open(function():void
         {
            ExampleScreenMod.open();
         });
      }

      private function tabClick(i:int) : Function
      {
         return function(e:MouseEvent):void
         {
            showTab(i);
         };
      }

      private function tabHover(i:int, over:Boolean) : Function
      {
         return function(e:MouseEvent):void
         {
            (tabClips[i] as MovieClip).gotoAndStop(i == tab ? (over ? "OverSelected" : "Selected") : (over ? "Over" : "Ready"));
         };
      }

      private function showTab(i:int) : void
      {
         if(i == tab || i < 0 || i >= TABS.length)
         {
            return;
         }
         remembered[tab] = selected;
         tab = i;
         buildTab();
      }

      private function onClose(e:MouseEvent = null, id:uint = 0) : void
      {
         clearRowDolls();
         clearDolls();
         unloadBanks();
         Hide();
      }

      private var openedFrom:ScreenBase;

      override public function Display() : void
      {
         if(!isActive && ScreenBase.focusedScreen !== this)
         {
            openedFrom = ScreenBase.focusedScreen;
         }
         super.Display();
      }

      override public function Hide() : void
      {
         super.Hide();
         BigWindow.handFocusBack(this,openedFrom);
         openedFrom = null;
      }

      private function openFolder() : void
      {
         try
         {
            var folder:File = modsFolder();
            if(!folder.exists)
            {
               folder.createDirectory();
            }
            folder.openWithDefaultApplication();
         }
         catch(e:Error)
         {
            Modal.show("Mods","The mods folder couldn't be opened: " + e.message);
         }
      }

      private function importBmod() : void
      {
         BmodImport.browse(imported);
      }

      public function imported(r:Object) : void
      {
         if(r != null && r.ok && current == this && body != null)
         {
            buildTab();
         }
      }

      private function buildTab() : void
      {
         for(var i:int = 0; i < tabClips.length; i++)
         {
            (tabClips[i] as MovieClip).gotoAndStop(i == tab ? "Selected" : "Ready");
         }
         clearDolls();
         clearRowDolls();
         if(tabBody != null)
         {
            body.removeChild(tabBody);
         }
         tabBody = new Sprite();
         body.addChild(tabBody);
         entries = [];
         rows = [];
         tiles = [];
         focus = "list";
         listView = null;
         details = null;
         allMaps = null;
         chipBar = null;
         ModShare.libraryChanged = communityArrived;
         ModShare.shareDone = shareEnded;
         if(ModShare.library == null && !ModShare.browsing())
         {
            ModShare.browse();
         }
         if(ModShare.mine == null && !ModShare.askingMine())
         {
            ModShare.askMine();
         }
         paintHint();
         switch(tab)
         {
            case 0:
               buildInstalled();
               break;
            case 1:
               buildMapArt();
               break;
            case 2:
               buildMusic();
               break;
            case 3:
               buildItems();
               break;
            default:
               buildCommunity();
         }
         updateStatus();
      }

      private function updateStatus() : void
      {
         if(status == null)
         {
            return;
         }
         var s:String = "";
         if(tab == 0 || tab == 3)
         {
            var changes:int = 0;
            for each(var mod:Object in ContentMods.all)
            {
               if(!ContentMods.isLive(mod) && ModSettings.isDisabled(mod.id) == ContentMods.isLoaded(mod.id))
               {
                  changes++;
               }
            }
            s = changes > 0 ? changes + (changes == 1 ? " change applies" : " changes apply") + " when the game restarts" :
               ContentMods.all.length + " mods installed";
         }
         else if(tab == 4)
         {
            s = ModShare.library != null && ModShare.libraryError == null ? ModShare.library.length + (ModShare.library.length == 1 ? " public mod" : " public mods") + " on the server" : "";
            if(ModShare.libraryMessage != null)
            {
               s = ModShare.libraryMessage;
            }
            else if(ModShare.updated.length > 0)
            {
               s = "Updated: " + ModShare.updated.join(", ") + " (loads when the game restarts)";
            }
         }
         else if(tab == 1)
         {
            var on:int = MapArt.on().length;
            s = MapArt.maps().length + " maps have art from " + on + (on == 1 ? " mod" : " mods");
         }
         else if(tab == 2)
         {
            var audioMods:int = MusicPacks.on().length;
            s = audioMods + (audioMods == 1 ? " mod changes" : " mods change") + " music or sounds";
         }
         status.text = s;
      }

      private function chips(names:Array) : void
      {
         chipNames = ["All"].concat(names);
         if(chipIndex[tab] >= chipNames.length)
         {
            chipIndex[tab] = 0;
         }
         chipBar = new Sprite();
         chipBar.x = LEFT;
         chipBar.y = TOP - 36;
         tabBody.addChild(chipBar);
         paintChips();
      }

      private function paintChips() : void
      {
         if(chipBar == null)
         {
            return;
         }
         chipBar.removeChildren();
         var x:Number = 0;
         for(var i:int = 0; i < chipNames.length; i++)
         {
            var chip:Sprite = new Sprite();
            chip.x = x;
            chip.buttonMode = true;
            chipBar.addChild(chip);
            var on:Boolean = i == chipIndex[tab];
            var label:TextField = text(chip,String(chipNames[i]).toUpperCase(),12,3,13,on ? NAVY_TEXT : LIGHT,XBOLD);
            var back:Shape = rect(chip,0,0,label.width + 24,24,on ? TEAL : LINE,24);
            chip.setChildIndex(back,0);
            if(on && focus == "chips")
            {
               rect(chip,6,27,label.width + 12,3,WHITE);
            }
            chip.addEventListener(MouseEvent.CLICK,chipClick(i));
            x += label.width + 30;
         }
      }

      private function chipClick(i:int) : Function
      {
         return function(e:MouseEvent):void
         {
            pickChip(i);
         };
      }

      private function pickChip(i:int) : void
      {
         if(i == chipIndex[tab])
         {
            return;
         }
         chipIndex[tab] = i;
         remembered[tab] = 0;
         var keep:String = focus;
         buildTab();
         if(keep == "chips")
         {
            setFocus("chips");
         }
      }

      private function chipFilter() : String
      {
         return chipIndex[tab] > 0 && chipIndex[tab] < chipNames.length ? chipNames[chipIndex[tab]] : null;
      }

      private function makeList(rowH:Number, count:int, draw:Function) : void
      {
         rowHeight = rowH;
         listHeight = HEIGHT;
         listView = new Sprite();
         listView.x = LEFT;
         listView.y = TOP;
         tabBody.addChild(listView);
         var hit:Shape = new Shape();
         hit.graphics.beginFill(0,0);
         hit.graphics.drawRect(0,0,LIST_W + 12,HEIGHT);
         hit.graphics.endFill();
         listView.addChild(hit);
         listContent = new Sprite();
         listView.addChild(listContent);
         listContent.mask = rect(listView,0,0,LIST_W + 12,HEIGHT,0);
         scrollBar = new Sprite();
         listView.addChild(scrollBar);
         scrollBar.addEventListener(MouseEvent.MOUSE_DOWN,barPressed);
         scrollBar.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            e.stopPropagation();
         });
         listView.addEventListener(MouseEvent.MOUSE_WHEEL,function(e:MouseEvent):void
         {
            scrollTo(-listContent.y - e.delta * 20);
         });
         for(var i:int = 0; i < count; i++)
         {
            var row:MovieClip = new MovieClip();
            row.y = i * rowH;
            row.buttonMode = true;
            listContent.addChild(row);
            rows.push(row);
            var bg:Shape = new Shape();
            row.addChild(bg);
            row.bg = bg;
            draw(row,i);
            row.addEventListener(MouseEvent.CLICK,rowClick(i));
         }
         details = new Sprite();
         details.x = DX;
         details.y = TOP;
         tabBody.addChild(details);
         selected = Math.max(0,Math.min(remembered[tab],count - 1));
         for(i = 0; i < count; i++)
         {
            paintRow(i);
         }
         scrollTo(selected * rowH - HEIGHT / 2 + rowH / 2);
         showDetails();
      }

      private function rowClick(i:int) : Function
      {
         return function(e:MouseEvent):void
         {
            setFocus("list");
            select(i);
         };
      }

      private function paintRow(i:int) : void
      {
         if(i < 0 || i >= rows.length)
         {
            return;
         }
         var bg:Shape = rows[i].bg;
         bg.graphics.clear();
         bg.graphics.beginFill(i == selected ? ROW_SELECTED : PANEL);
         bg.graphics.drawRect(0,0,LIST_W,rowHeight - 4);
         bg.graphics.endFill();
         if(i == selected)
         {
            bg.graphics.beginFill(focus == "list" ? TEAL : GREY);
            bg.graphics.drawRect(0,0,5,rowHeight - 4);
            bg.graphics.endFill();
         }
      }

      private function select(i:int) : void
      {
         if(rows.length == 0)
         {
            return;
         }
         i = Math.max(0,Math.min(i,rows.length - 1));
         var old:int = selected;
         selected = i;
         paintRow(old);
         paintRow(i);
         var y:Number = i * rowHeight;
         if(y < -listContent.y)
         {
            scrollTo(y);
         }
         else if(y + rowHeight > -listContent.y + listHeight)
         {
            scrollTo(y + rowHeight - listHeight);
         }
         if(old != i)
         {
            showDetails();
         }
      }

      private function scrollTo(y:Number) : void
      {
         var total:Number = rows.length * rowHeight;
         var max:Number = Math.max(0,total - listHeight);
         y = Math.max(0,Math.min(y,max));
         listContent.y = -y;
         scrollBar.graphics.clear();
         if(max > 0)
         {
            scrollBar.graphics.beginFill(0,0);
            scrollBar.graphics.drawRect(LIST_W + 2,0,12,listHeight);
            scrollBar.graphics.beginFill(LINE);
            scrollBar.graphics.drawRect(LIST_W + 6,0,4,listHeight);
            scrollBar.graphics.beginFill(GREY);
            var thumb:Number = Math.max(30,listHeight * listHeight / total);
            scrollBar.graphics.drawRect(LIST_W + 6,(listHeight - thumb) * y / max,4,thumb);
            scrollBar.graphics.endFill();
         }
      }

      private function barThumb() : Number
      {
         return Math.max(30,listHeight * listHeight / (rows.length * rowHeight));
      }

      private function barPressed(e:MouseEvent) : void
      {
         var max:Number = Math.max(0,rows.length * rowHeight - listHeight);
         if(max <= 0 || scrollBar.stage == null)
         {
            return;
         }
         e.stopPropagation();
         var thumb:Number = barThumb();
         var top:Number = (listHeight - thumb) * -listContent.y / max;
         barGrab = scrollBar.mouseY >= top && scrollBar.mouseY <= top + thumb ? scrollBar.mouseY - top : thumb / 2;
         barMoved(null);
         scrollBar.stage.addEventListener(MouseEvent.MOUSE_MOVE,barMoved);
         scrollBar.stage.addEventListener(MouseEvent.MOUSE_UP,barReleased);
      }

      private function barMoved(e:MouseEvent) : void
      {
         var max:Number = Math.max(0,rows.length * rowHeight - listHeight);
         var room:Number = listHeight - barThumb();
         if(barGrab >= 0 && max > 0 && room > 0)
         {
            scrollTo((scrollBar.mouseY - barGrab) / room * max);
         }
      }

      private function barReleased(e:MouseEvent) : void
      {
         barGrab = -1;
         if(scrollBar != null && scrollBar.stage != null)
         {
            scrollBar.stage.removeEventListener(MouseEvent.MOUSE_MOVE,barMoved);
            scrollBar.stage.removeEventListener(MouseEvent.MOUSE_UP,barReleased);
         }
      }

      private function showDetails() : void
      {
         if(details == null)
         {
            return;
         }
         clearDolls();
         details.removeChildren();
         if(entries.length == 0)
         {
            return;
         }
         switch(tab)
         {
            case 0:
               modDetails(entries[selected]);
               break;
            case 1:
               mapDetails(entries[selected]);
               break;
            case 2:
               musicDetails(entries[selected]);
               break;
            case 3:
               itemDetails(entries[selected]);
               break;
            case 4:
               communityDetails(entries[selected]);
         }
      }

      private function emptyNote(s:String) : void
      {
         var box:Sprite = new Sprite();
         box.x = LEFT;
         box.y = TOP;
         tabBody.addChild(box);
         rect(box,0,0,HALF * 2 - 20,HEIGHT,PANEL);
         text(box,s,HALF - 10,160,18,GREY,BOLD,0,true);
      }

      private static const ITEM_TABLES:Object = {"costumeTypes":"Skin","weaponSkinTypes":"Weapon skin","avatarTypes":"Avatar",
         "TauntTypes":"Emote","EmojiTypes":"Emoji","ColorSchemeTypes":"Colour","HeroTypes":"Legend","LevelTypes":"Map",
         "PodiumTypes":"Podium","CompanionTypes":"Sidekick","TrailEffectTypes":"Trail"};

      private static const KIND_ORDER:Array = ["Legend","Skin","Weapon skin","Avatar","Emote","Emoji","Colour","Map",
         "Podium","Sidekick","Trail"];

      private static const QUOTE:String = String.fromCharCode(34);

      private static const KEY_COLUMNS:Object = {"costumeTypes":"CostumeName","weaponSkinTypes":"WeaponSkinName",
         "avatarTypes":"AvatarName","TauntTypes":"@TauntName","EmojiTypes":"@EmojiName","ColorSchemeTypes":"@ColorSchemeName",
         "HeroTypes":"@HeroName","LevelTypes":"@LevelName","PodiumTypes":"@PodiumName","CompanionTypes":"@CompanionName",
         "TrailEffectTypes":"@TrailEffectName"};

      private static function between(s:String, start:String, end:String) : String
      {
         var a:int = s.indexOf(start);
         if(a < 0)
         {
            return null;
         }
         a += start.length;
         var b:int = s.indexOf(end,a);
         return b < 0 ? null : s.substring(a,b);
      }

      private static function itemsOf(mod:Object) : Array
      {
         var out:Array = [];
         var english:Object = mod.strings != null && mod.strings["English"] != null ? mod.strings["English"] : {};
         for each(var kind:String in KIND_ORDER)
         {
            for(var table:String in ITEM_TABLES)
            {
               if(ITEM_TABLES[table] != kind)
               {
                  continue;
               }
               for each(var row:* in mod.tables != null ? mod.tables[table] as Array : null)
               {
                  var id:String = null;
                  var nameKey:String = null;
                  var shown:String = null;
                  var copy:String = null;
                  if(row is String)
                  {
                     id = between(String(row),"=" + QUOTE,QUOTE);
                     nameKey = between(String(row),"<DisplayNameKey>","<");
                     shown = between(String(row),"<DisplayName>","<");
                  }
                  else if(row != null && row.set != null)
                  {
                     copy = row.copy;
                     id = row.set[KEY_COLUMNS[table]] != null ? String(row.set[KEY_COLUMNS[table]]) : copy;
                     nameKey = row.set.DisplayNameKey != null ? String(row.set.DisplayNameKey) : null;
                  }
                  else
                  {
                     continue;
                  }
                  var name:String = nameKey != null && english[nameKey] != null ? english[nameKey] : (shown || id || copy);
                  if(name != null)
                  {
                     out.push({"name":name,"kind":kind,"mod":mod,"copy":copy,"id":id});
                  }
               }
            }
         }
         return out;
      }

      private static function categories(mod:Object) : Array
      {
         var out:Array = [];
         var names:Object = {"Skin":"Skins","Weapon skin":"Weapons","Avatar":"Avatars","Emote":"Emotes","Emoji":"Emotes",
            "Legend":"Legends","Map":"Maps"};
         for each(var item:Object in itemsOf(mod))
         {
            var c:String = names[item.kind] != null ? names[item.kind] : "Other";
            if(out.indexOf(c) < 0)
            {
               out.push(c);
            }
         }
         if(modes(mod) > 0)
         {
            out.unshift("Modes");
            var other:int = out.indexOf("Other");
            if(other >= 0 && !hasOtherTables(mod))
            {
               out.splice(other,1);
            }
         }
         if(mod.mapArt != null)
         {
            out.push("Map art");
         }
         if(mod.music != null || mod.sounds != null)
         {
            out.push("Music");
         }
         if(out.length == 0)
         {
            out.push("Other");
         }
         return out;
      }

      private static const CATEGORY_ORDER:Array = ["Modes","Legends","Skins","Weapons","Avatars","Emotes","Maps","Map art",
         "Music","Other"];

      private static function modes(mod:Object) : int
      {
         var n:int = 0;
         var rows:int = 0;
         for(var table:String in mod.tables)
         {
            var t:String = table.toLowerCase();
            if((t == "scoringtypes" || t == "gamemodetypes") && mod.tables[table] is Array)
            {
               if(t == "scoringtypes")
               {
                  n += mod.tables[table].length;
               }
               rows += mod.tables[table].length;
            }
         }
         return n > 0 ? n : rows;
      }

      private static function hasOtherTables(mod:Object) : Boolean
      {
         for(var table:String in mod.tables)
         {
            var t:String = table.toLowerCase();
            if(t != "scoringtypes" && t != "gamemodetypes" && ITEM_TABLES[table] == null && mod.tables[table] is Array &&
               mod.tables[table].length > 0)
            {
               return true;
            }
         }
         return false;
      }

      private static function summary(mod:Object) : String
      {
         var counts:Object = {};
         for each(var item:Object in itemsOf(mod))
         {
            counts[item.kind] = (counts[item.kind] || 0) + 1;
         }
         var parts:Array = [];
         for each(var kind:String in KIND_ORDER)
         {
            if(counts[kind])
            {
               var n:int = counts[kind];
               parts.push(n + " " + kind.toLowerCase() + (n == 1 ? "" : "s"));
            }
         }
         var gameModes:int = modes(mod);
         if(gameModes > 0)
         {
            parts.unshift(gameModes + (gameModes == 1 ? " game mode" : " game modes"));
         }
         if(mod.tables != null && mod.tables.PowerSwapTypes is Array && mod.tables.PowerSwapTypes.length > 0)
         {
            parts.push("signature effects");
         }
         if(mod.mapArt != null)
         {
            var maps:int = 0;
            for(var level:String in mod.mapArt.maps)
            {
               maps++;
            }
            parts.push("art for " + maps + (maps == 1 ? " map" : " maps"));
         }
         if(mod.soundBanks is Array && mod.soundBanks.length > 0)
         {
            parts.push("sounds");
         }
         if(mod.music != null)
         {
            var tracks:int = 0;
            for(var track:String in mod.music.tracks)
            {
               tracks++;
            }
            parts.push(tracks + (tracks == 1 ? " music track" : " music tracks"));
         }
         if(mod.sounds != null)
         {
            var sounds:int = 0;
            for(var ev:String in mod.sounds)
            {
               sounds++;
            }
            parts.push(sounds + (sounds == 1 ? " sound" : " sounds"));
         }
         var tableWords:Object = {"powertypes":[" move"," moves"],"runetypes":[" stance"," stances"],
            "stattypes":[" stat-point row"," stat-point rows"]};
         for(var table:String in mod.tables)
         {
            var words:Array = tableWords[table.toLowerCase()];
            if(words != null && mod.tables[table] is Array && mod.tables[table].length > 0)
            {
               var changed:int = mod.tables[table].length;
               parts.push(changed + (changed == 1 ? words[0] : words[1]) + " changed");
            }
         }
         return parts.length > 0 ? parts.join(" · ") : "data changes";
      }

      private static function itemIcon(item:Object) : DisplayObject
      {
         try
         {
            if(item.kind == "Skin")
            {
               var costume:CostumeType = CostumeType.method_5476(item.id);
               return costume != null && costume.var_12178 ? class_687.method_1714(costume.var_12178,costume.var_4697) : null;
            }
            if(item.kind == "Avatar")
            {
               var avatar:class_16 = class_16.method_4153(item.id);
               return avatar != null ? avatar.method_7036() : null;
            }
            if(item.kind == "Weapon skin")
            {
               var weapon:class_725 = class_725.method_7621(item.id);
               if(weapon == null)
               {
                  return null;
               }
               var own:String = weapon.var_2697 && ApplicationDomain.currentDomain.hasDefinition(weapon.var_2697) ?
                  weapon.var_2697 : "a_WeaponIcon_" + weapon.var_12803;
               return class_687.method_1714(own,"UI_Icons");
            }
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private function rowPicture(row:MovieClip, item:Object) : void
      {
         if(item.kind == "Skin" && ContentMods.isLoaded(item.mod.id))
         {
            var costume:CostumeType = CostumeType.method_5476(item.id);
            if(costume != null)
            {
               var box:Sprite = new Sprite();
               box.x = 8;
               box.y = 3;
               row.addChild(box);
               rect(box,0,0,40,46,BODY,8);
               var holder:MovieClip = new MovieClip();
               holder.mouseEnabled = false;
               holder.mouseChildren = false;
               box.addChild(holder);
               holder.mask = rect(box,0,0,40,46,0);
               try
               {
                  var d:PaperDoll = new PaperDoll(owner,holder,null,20,43,null,0.11);
                  rowDolls.push(d);
                  var anim:String = PaperDoll.method_637(costume.var_7289,costume);
                  PaperDoll.method_5580(costume,null,costume.var_7289,costume.var_15258,d,anim,null,null);
                  d.method_39(anim,true,true);
                  d.method_4082();
               }
               catch(e:Error)
               {
                  Platform.log("mods window: row doll failed: " + e.message);
               }
               return;
            }
         }
         itemBadge(row,item,8,5,40);
      }

      private var rowDolls:Array = [];

      private function clearRowDolls() : void
      {
         for each(var d:PaperDoll in rowDolls)
         {
            try
            {
               d.method_5548();
            }
            catch(e:Error)
            {
            }
         }
         rowDolls = [];
      }

      private static function itemBadge(parent:Sprite, item:Object, x:Number, y:Number, size:Number) : void
      {
         var clip:DisplayObject = ContentMods.isLoaded(item.mod.id) ? itemIcon(item) : null;
         if(clip != null)
         {
            rect(parent,x,y,size,size,BODY,8);
            icon(parent,clip,x + 2,y + 2,size - 4);
         }
         else
         {
            badge(parent,String(item.kind).charAt(0),x,y,size);
         }
      }

      private function clearDolls() : void
      {
         for each(var doll:PaperDoll in dolls)
         {
            try
            {
               doll.method_5548();
            }
            catch(e:Error)
            {
            }
         }
         dolls = [];
         signatureDoll = null;
      }

      private function previewBox(parent:Sprite, x:Number, y:Number, w:Number, h:Number, caption:String) : MovieClip
      {
         var box:Sprite = new Sprite();
         box.x = x;
         box.y = y;
         parent.addChild(box);
         rect(box,0,0,w,h,BODY);
         var holder:MovieClip = new MovieClip();
         holder.mouseEnabled = false;
         holder.mouseChildren = false;
         box.addChild(holder);
         holder.mask = rect(box,0,0,w,h,0);
         fit(text(box,caption,8,h - 22,12,GREY,XBOLD),w - 16);
         return holder;
      }

      private function newDoll(holder:MovieClip, x:Number, y:Number, scale:Number) : PaperDoll
      {
         var d:PaperDoll = new PaperDoll(owner,holder,null,x,y,null,scale);
         dolls.push(d);
         return d;
      }

      private function skinPreview(costume:CostumeType, holder:MovieClip, x:Number, y:Number, scale:Number) : void
      {
         try
         {
            var d:PaperDoll = newDoll(holder,x,y,scale);
            var anim:String = PaperDoll.method_637(costume.var_7289,costume);
            PaperDoll.method_5580(costume,null,costume.var_7289,costume.var_15258,d,anim,null,null);
            d.method_39(anim,true,true);
            d.method_4082();
         }
         catch(e:Error)
         {
            Platform.log("mods window: skin preview failed: " + e.getStackTrace());
         }
      }

      private function weaponPreview(weapon:class_725, holder:MovieClip, x:Number, y:Number, scale:Number) : void
      {
         if(weapon == null)
         {
            return;
         }
         try
         {
            var d:PaperDoll = newDoll(holder,x,y,scale);
            PaperDoll.method_387(d,weapon,null);
            d.method_4082();
            if(weapon.var_12803)
            {
               var box:Sprite = holder.parent as Sprite;
               icon(box,class_687.method_1714("a_WeaponIcon_" + weapon.var_12803,"UI_Icons"),6,6,24);
            }
         }
         catch(e:Error)
         {
            Platform.log("mods window: weapon preview failed: " + e.getStackTrace());
         }
      }

      private static function signaturesOf(costume:CostumeType) : Array
      {
         var out:Array = [];
         var hero:HeroType = costume.var_7289;
         if(hero == null)
         {
            return out;
         }
         var names:Array = [[hero.mSpecialPower1,"Neutral"],[hero.mSpecialPower1_Forward,"Side"],[hero.mSpecialPower1_Down,"Down"],
            [hero.mSpecialPower2,"Neutral"],[hero.mSpecialPower2_Forward,"Side"],[hero.mSpecialPower2_Down,"Down"]];
         for each(var pair:Array in names)
         {
            var power:String = pair[0];
            if(power == null || power == "--")
            {
               continue;
            }
            var pt:PowerType = PowerType.method_6087(power);
            if(pt == null)
            {
               continue;
            }
            var at:int = power.indexOf("Smash");
            out.push({"power":pt,"name":power,"label":(at > 0 ? power.substr(0,at) : power) + " · " + pair[1]});
         }
         return out;
      }

      private function signaturePreview(costume:CostumeType, holder:MovieClip, box:Sprite, w:Number, h:Number,
                                        sounds:Array) : void
      {
         signatures = signaturesOf(costume);
         for each(var sig:Object in signatures)
         {
            for each(var sound:Object in sounds)
            {
               if(sound.cast && sound.power == sig.name && sig.sound == null)
               {
                  sig.sound = sound.event;
               }
            }
         }
         signatureCostume = costume;
         signatureWidth = w;
         signatureAt = Math.min(signatureAt,Math.max(0,signatures.length - 1));
         if(signatures.length == 0)
         {
            return;
         }
         signatureDoll = newDoll(holder,w / 2,h - 34,0.42);
         signatureLabel = text(box,"",w / 2,30,12,WHITE,BOLD,0,true);
         arrow(box,6,4,-1,function():void
         {
            cycleSignature(-1);
         });
         arrow(box,w - 28,4,1,function():void
         {
            cycleSignature(1);
         });
         playSignature();
      }

      private function cycleSignature(dir:int) : void
      {
         if(signatures.length == 0 || signatureDoll == null)
         {
            return;
         }
         signatureAt = (signatureAt + dir + signatures.length) % signatures.length;
         soundsOn = true;
         playSignature();
      }

      private function playSignature() : void
      {
         if(signatureDoll == null || signatures.length == 0)
         {
            return;
         }
         var sig:Object = signatures[signatureAt];
         signatureLabel.text = sig.label + "  " + (signatureAt + 1) + "/" + signatures.length;
         fit(signatureLabel,signatureWidth - 8);
         signatureLabel.x = signatureWidth / 2 - signatureLabel.width / 2;
         try
         {
            var pt:PowerType = sig.power;
            PaperDoll.method_6642(signatureDoll,pt,signatureCostume,null,null);
            signatureAnim = pt.method_3298(signatureCostume,null).var_10352;
            var entity:Object = Object(signatureDoll).var_11807;
            if(entity != null && entity.var_142 != null)
            {
               entity.var_142.var_1410 = true;
            }
            signatureDoll.method_5389();
            signatureDoll.method_4082();
            signatureStart = getTimer();
            if(body != null && !body.hasEventListener(Event.ENTER_FRAME))
            {
               body.addEventListener(Event.ENTER_FRAME,sigTick);
            }
            if(sig.sound != null && soundsOn)
            {
               playSound(sig.sound,signatureCostume);
            }
         }
         catch(e:Error)
         {
            Platform.log("mods window: signature preview failed: " + e.getStackTrace());
         }
      }

      private static function soundsOf(mod:Object, token:String) : Array
      {
         var out:Array = [];
         if(token == null)
         {
            return out;
         }
         for each(var row:* in mod.tables != null ? mod.tables.costumeTypes as Array : null)
         {
            if(row != null && row.set != null && row.set.CostumeName == token)
            {
               if(row.set.NameSoundEvent)
               {
                  out.push({"event":String(row.set.NameSoundEvent),"label":"Announcer"});
               }
               if(row.set.OnSelectedSoundEvent)
               {
                  out.push({"event":String(row.set.OnSelectedSoundEvent),"label":"Lock-in"});
               }
            }
         }
         var seen:Object = {};
         for each(row in mod.tables != null ? mod.tables.PowerSwapTypes as Array : null)
         {
            var xml:String = row is String ? String(row) : (row != null && row.add != null ? String(row.add) : "");
            for each(var tag:String in ["CastSoundEvent","HitSoundEvent"])
            {
               var event:String = between(xml,"<" + tag + ">","<");
               if(event == null || event.indexOf(token) < 0 || seen[event])
               {
                  continue;
               }
               seen[event] = true;
               var parts:Array = plainEvent(event).replace("_Play","").replace("_" + token,"").split("_");
               out.push({"event":event,"label":parts.slice(2).join(" "),"power":between(xml,"<TargetPower>","<"),
                  "cast":tag == "CastSoundEvent"});
            }
         }
         return out;
      }

      private static function plainEvent(event:String) : String
      {
         return event.length > 2 && event.charAt(1) == ":" ? event.substr(2) : event;
      }

      private var banksFor:CostumeType;

      private function loadBanks(costume:CostumeType) : void
      {
         if(banksFor == costume)
         {
            return;
         }
         unloadBanks();
         try
         {
            if(costume.var_7289 != null)
            {
               costume.var_7289.method_4649(false);
            }
            if(costume.mWeaponSkin1 != null)
            {
               costume.mWeaponSkin1.method_4649(false);
            }
            if(costume.mWeaponSkin2 != null)
            {
               costume.mWeaponSkin2.method_4649(false);
            }
            costume.method_4649(false);
            banksFor = costume;
         }
         catch(e:Error)
         {
            Platform.log("mods window: sound banks of a skin didn't load: " + e.message);
         }
      }

      private function unloadBanks() : void
      {
         if(banksFor == null)
         {
            return;
         }
         try
         {
            banksFor.method_4649(true);
            if(banksFor.mWeaponSkin1 != null)
            {
               banksFor.mWeaponSkin1.method_4649(true);
            }
            if(banksFor.mWeaponSkin2 != null)
            {
               banksFor.mWeaponSkin2.method_4649(true);
            }
            if(banksFor.var_7289 != null)
            {
               banksFor.var_7289.method_4649(true);
            }
         }
         catch(e:Error)
         {
         }
         banksFor = null;
      }

      private function playSound(event:String, costume:CostumeType) : void
      {
         if(costume != null)
         {
            loadBanks(costume);
         }
         try
         {
            class_727.PostEvent(plainEvent(event));
         }
         catch(e:Error)
         {
            Platform.log("mods window: sound " + event + ": " + e.message);
         }
      }

      private function soundBox(parent:Sprite, sounds:Array, costume:CostumeType, x:Number, y:Number, w:Number, h:Number) : void
      {
         var box:Sprite = new Sprite();
         box.x = x;
         box.y = y;
         parent.addChild(box);
         rect(box,0,0,w,h,BODY);
         fit(text(box,"SOUNDS",8,h - 22,12,GREY,XBOLD),w - 70);
         var list:Sprite = new Sprite();
         box.addChild(list);
         var per:int = Math.max(1,int((h - 34) / 24));
         var page:int = 0;
         var paint:Function = function():void
         {
            list.removeChildren();
            for(var i:int = page * per; i < sounds.length && i < (page + 1) * per; i++)
            {
               var line:Sprite = new Sprite();
               line.y = 6 + (i - page * per) * 24;
               line.buttonMode = true;
               list.addChild(line);
               rect(line,4,0,w - 8,21,PANEL,6);
               var play:Shape = new Shape();
               play.graphics.beginFill(TEAL);
               play.graphics.moveTo(10,5);
               play.graphics.lineTo(18,10.5);
               play.graphics.lineTo(10,16);
               play.graphics.endFill();
               line.addChild(play);
               fit(text(line,sounds[i].label,22,2,11,LIGHT,BOLD),w - 30);
               line.addEventListener(MouseEvent.CLICK,soundClick(sounds[i].event,costume));
            }
         };
         paint();
         if(sounds.length > per)
         {
            arrow(box,w - 52,h - 26,-1,function():void
            {
               page = Math.max(0,page - 1);
               paint();
            });
            arrow(box,w - 28,h - 26,1,function():void
            {
               page = Math.min(int((sounds.length - 1) / per),page + 1);
               paint();
            });
         }
      }

      private function soundClick(event:String, costume:CostumeType) : Function
      {
         return function(e:MouseEvent):void
         {
            e.stopPropagation();
            playSound(event,costume);
         };
      }

      private var signatureAnim:String;
      private var signatureStart:int = 0;

      private function sigTick(e:Event) : void
      {
         if(signatureDoll == null)
         {
            return;
         }
         try
         {
            var en:Object = Object(signatureDoll).var_11807;
            var anim:Object = en != null ? en.var_142.var_7804 : null;
            if(anim == null || int(anim.var_14424) <= 0)
            {
               return;
            }
            var last:int = int(anim.var_14424);
            var frame:int = int((getTimer() - signatureStart) * 60 / 1000) % (last + 24);
            en.method_2961(Math.min(frame,last));
         }
         catch(err:Error)
         {
         }
      }

      private function noteBox(parent:Sprite, s:String, x:Number, y:Number, w:Number, h:Number) : void
      {
         var note:Sprite = new Sprite();
         note.x = x;
         note.y = y;
         parent.addChild(note);
         rect(note,0,0,w,h,BODY);
         text(note,s,w / 2,h / 2 - 10,14,GREY,BOLD,0,true);
      }

      private function previews(parent:Sprite, mod:Object, only:Object, x:Number, y:Number, w:Number, h:Number) : void
      {
         var items:Array = only != null ? [only] : itemsOf(mod);
         if((mod.music != null || mod.sounds != null) && mod.mapArt == null && items.length == 0)
         {
            var titles:Array = [];
            for each(var musicPack:Object in MusicPacks.packs)
            {
               for each(var t:Object in (musicPack.id == mod.id ? musicPack.tracks : []))
               {
                  titles.push(t.title);
               }
            }
            noteBox(parent,(titles.length > 0 ? "Tracks: " + titles.join(", ") + ". " : "") + "They play while this mod is on (AUDIO lists what it changes).",
               x,y,w,h);
            return;
         }
         if(!ContentMods.isLoaded(mod.id) && mod.mapArt == null)
         {
            noteBox(parent,items.length > 0 ? "Previews show once the mod is loaded (switch it on and restart the game)." :
               "Nothing to preview.",x,y,w,h);
            return;
         }
         var gap:Number = 8;
         var costume:CostumeType = null;
         var skinName:String = null;
         var weapons:Array = [];
         var avatars:Array = [];
         for each(var item:Object in items)
         {
            if(item.kind == "Skin" && costume == null)
            {
               costume = CostumeType.method_5476(item.id);
               skinName = item.id;
            }
            else if(item.kind == "Weapon skin")
            {
               var ws:class_725 = class_725.method_7621(item.id);
               if(ws != null)
               {
                  weapons.push(ws);
               }
            }
            else if(item.kind == "Avatar")
            {
               avatars.push(item);
            }
         }
         var bw:Number = (w - gap * 3) / 4;
         if(costume != null)
         {
            var sounds:Array = soundsOf(mod,skinName);
            var boxes:int = sounds.length > 0 ? 5 : 4;
            bw = (w - gap * (boxes - 1)) / boxes;
            soundsOn = false;
            skinPreview(costume,previewBox(parent,x,y,bw,h,"SKIN"),bw / 2,h - 34,0.42);
            weaponPreview(costume.mWeaponSkin1,previewBox(parent,x + (bw + gap),y,bw,h,"WEAPON 1"),bw / 2,h / 2 - 8,0.55);
            weaponPreview(costume.mWeaponSkin2,previewBox(parent,x + (bw + gap) * 2,y,bw,h,"WEAPON 2"),bw / 2,h / 2 - 8,0.55);
            var sigHolder:MovieClip = previewBox(parent,x + (bw + gap) * 3,y,bw,h,"SIGNATURES");
            signaturePreview(costume,sigHolder,sigHolder.parent as Sprite,bw,h,sounds);
            if(sounds.length > 0)
            {
               soundBox(parent,sounds,costume,x + (bw + gap) * 4,y,bw,h);
            }
            return;
         }
         if(weapons.length > 0)
         {
            for(var i:int = 0; i < Math.min(4,weapons.length); i++)
            {
               var weapon:class_725 = weapons[i];
               var caption:String = "WEAPON";
               try
               {
                  caption = String(class_256.method_1351(weapon.mDisplayNameKey)).toUpperCase();
               }
               catch(e:Error)
               {
               }
               weaponPreview(weapon,previewBox(parent,x + (bw + gap) * i,y,bw,h,caption),bw / 2,h / 2 - 8,0.6);
            }
            return;
         }
         if(avatars.length > 0)
         {
            var strip:Sprite = new Sprite();
            strip.x = x;
            strip.y = y;
            parent.addChild(strip);
            rect(strip,0,0,w,h,BODY);
            var size:Number = only != null ? Math.min(h - 20,160) : 62;
            var per:int = Math.max(1,int((w - 12) / (size + 10)));
            var fitRows:int = Math.max(1,int((h - 12) / (size + 10)));
            for(i = 0; i < avatars.length && i < per * fitRows; i++)
            {
               itemBadge(strip,avatars[i],12 + (i % per) * (size + 10),10 + int(i / per) * (size + 10),size);
            }
            return;
         }
         if(mod.mapArt != null)
         {
            var shown:int = 0;
            for each(var map:Object in MapArt.maps())
            {
               var ours:Boolean = false;
               for each(var pack:Object in map.packs)
               {
                  ours = ours || pack.id == mod.id;
               }
               if(!ours || shown >= 4)
               {
                  continue;
               }
               var cell:Sprite = new Sprite();
               cell.x = x + (bw + gap) * shown;
               cell.y = y;
               parent.addChild(cell);
               rect(cell,0,0,bw,h,BODY);
               var pic:Sprite = new Sprite();
               pic.x = 6;
               pic.y = 6;
               cell.addChild(pic);
               picture(pic,MapArt.choiceThumbnail(map.level,mod.id),bw - 12,(bw - 12) * 9 / 16,true);
               fit(text(cell,String(map.name),8,(bw - 12) * 9 / 16 + 12,13,WHITE,BOLD),bw - 16);
               shown++;
            }
            if(shown == 0)
            {
               noteBox(parent,"Switched off: its maps use their other art.",x,y,w,h);
            }
            return;
         }
         noteBox(parent,"Nothing to preview.",x,y,w,h);
      }

      private function buildInstalled() : void
      {
         var cats:Array = [];
         for each(var mod:Object in ContentMods.all)
         {
            for each(var c:String in categories(mod))
            {
               if(cats.indexOf(c) < 0)
               {
                  cats.push(c);
               }
            }
         }
         cats.sort(function(a:String, b:String):int
         {
            return CATEGORY_ORDER.indexOf(a) - CATEGORY_ORDER.indexOf(b);
         });
         chips(cats);
         var only:String = chipFilter();
         for each(mod in ContentMods.all)
         {
            if(ModShare.isRemoved(mod))
            {
               continue;
            }
            if(only == null || categories(mod).indexOf(only) >= 0)
            {
               entries.push(mod);
            }
         }
         if(entries.length == 0)
         {
            emptyNote(ContentMods.all.length == 0 ? "No mods installed. Put mod folders in the mods folder." : "No mods of this kind.");
            return;
         }
         makeList(54,entries.length,function(row:MovieClip, i:int):void
         {
            var mod:Object = entries[i];
            var items:Array = itemsOf(mod);
            if(items.length > 0)
            {
               rowPicture(row,items[0]);
            }
            else
            {
               badge(row,mod.mapArt != null ? "M" : (mod.music != null || mod.sounds != null ? "S" : "?"),8,5,40);
            }
            fit(text(row,String(mod.name),58,4,17,WHITE,BOLD),LIST_W - 150);
            fit(text(row,kindLine(mod),58,26,13,TEAL,MEDIUM),LIST_W - 150);
            var toggle:Sprite = new Sprite();
            toggle.x = LIST_W - 76;
            toggle.y = 12;
            row.addChild(toggle);
            row.toggle = toggle;
            paintToggle(toggle,!ModSettings.isDisabled(mod.id));
            toggle.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
            {
               e.stopPropagation();
               setFocus("list");
               select(i);
               switchMod(i);
            });
         });
      }

      private static function kindLine(mod:Object) : String
      {
         var s:String = summary(mod);
         return s.charAt(0).toUpperCase() + s.substr(1);
      }

      private static function paintToggle(t:Sprite, on:Boolean) : void
      {
         t.removeChildren();
         t.buttonMode = true;
         rect(t,0,0,64,26,on ? TEAL : 0x2A3A4A,26);
         rect(t,on ? 40 : 2,2,22,22,WHITE,22);
         text(t,on ? "ON" : "OFF",on ? 10 : 29,3,14,on ? BODY : GREY,XBOLD);
      }

      private function switchMod(i:int) : void
      {
         var mod:Object = entries[i];
         ModSettings.setDisabled(mod.id,!ModSettings.isDisabled(mod.id));
         if((mod.music != null || mod.sounds != null) && ContentMods.isLive(mod))
         {
            audioChanged();
         }
         paintToggle(rows[i].toggle,!ModSettings.isDisabled(mod.id));
         showDetails();
         updateStatus();
      }

      private static function stateOf(mod:Object) : String
      {
         var on:Boolean = !ModSettings.isDisabled(mod.id);
         if(ContentMods.isLive(mod))
         {
            return on ? "On" : "Off";
         }
         var loaded:Boolean = ContentMods.isLoaded(mod.id);
         return on == loaded ? (loaded ? "Loaded" : "Off") : (on ? "On when the game restarts" : "Off when the game restarts");
      }

      private function modDetails(mod:Object) : void
      {
         rect(details,0,0,DW,HEIGHT,PANEL);
         var textX:Number = 8;
         if(mod.preview != null)
         {
            var frame:Sprite = new Sprite();
            frame.x = 8;
            frame.y = 8;
            details.addChild(frame);
            rect(frame,0,0,300,169,BODY);
            picture(frame,(mod.dir as File).resolvePath(mod.preview),300,169,false);
            textX = 320;
         }
         var tw:Number = DW - textX - 10;
         var y:Number = 8;
         fit(text(details,String(mod.name),textX,y,24,WHITE,XBOLD),tw);
         y += 32;
         fit(text(details,"v" + mod.version + (mod.author ? " · by " + mod.author : ""),textX,y,14,TEAL,MEDIUM),tw);
         y += 22;
         var about:String = String(mod.description || "").replace(/\s+/g," ");
         var limit:int = mod.preview != null ? 170 : 260;
         if(about.length > limit)
         {
            about = about.substr(0,limit - 3) + "...";
         }
         if(about.length > 0)
         {
            var desc:TextField = text(details,about,textX,y,13,LIGHT,MEDIUM,tw);
            y += desc.height + 4;
         }
         y = Math.max(y,120);
         fit(text(details,"ADDS: " + summary(mod),textX,y,13,WHITE,MEDIUM),tw);
         var state:String = stateOf(mod);
         text(details,state,textX,y + 20,14,state == "Loaded" || state == "On" ? TEAL : GREY,BOLD);
         var right:Number = shareButton(mod,DW - 10,y + 12);
         removeButton(mod,right - 10,y + 12);
         previews(details,mod,null,8,186,DW - 16,HEIGHT - 194);
      }

      private function removeButton(mod:Object, x:Number, y:Number) : void
      {
         if(!(mod.dir is File))
         {
            return;
         }
         var button:Sprite = new Sprite();
         button.buttonMode = true;
         details.addChild(button);
         var label:TextField = text(button,"REMOVE",14,6,14,WHITE,XBOLD);
         var back:Shape = rect(button,0,0,label.width + 28,30,LINE,30);
         button.setChildIndex(back,0);
         button.x = x - back.width;
         button.y = y;
         button.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            askRemove(mod);
         });
      }

      private function askRemove(mod:Object) : void
      {
         if(mod == null || ModShare.isRemoved(mod))
         {
            return;
         }
         Modal.show("Remove " + mod.name + "?","Its folder moves to mods-removed, beside the mods folder " +
            "(nothing is deleted). " + (ContentMods.isLoaded(mod.id) ? "It stays in the game until you restart it." : ""),[{
            "label":"Remove",
            "action":function():void
            {
               var why:String = ModShare.remove(mod);
               if(why != null)
               {
                  Modal.show("Not removed",mod.name + ": " + why + ".");
                  return;
               }
               status.text = "Removed " + mod.name + (ContentMods.isLoaded(mod.id) ? " (gone after a restart)" : "");
               if(tab == 0)
               {
                  buildTab();
               }
            }
         },{"label":"Keep"}]);
      }

      private function shareButton(mod:Object, x:Number, y:Number) : Number
      {
         var st:String = ModShare.shareState(mod);
         if(st == null)
         {
            return x;
         }
         if(st != "share")
         {
            var copy:Object = ModShare.mineOf(ModCheck.entryOf(mod));
            var words:Object = {"sending":"Sending to the server...","private":"On the server, private","review":
               "On the server, waiting for review","public":"On the server's Community tab","rejected":"Rejected by the server"};
            var note:TextField = text(details,(words[st] || st) + (copy != null && st != "rejected" ? " · key " + copy.key : ""),0,
               y + 8,13,st == "public" ? TEAL : (st == "rejected" ? 0xFF5F5F : LIGHT),MEDIUM);
            note.x = x - note.width;
            return note.x;
         }
         var button:Sprite = new Sprite();
         button.buttonMode = true;
         details.addChild(button);
         var label:TextField = text(button,"SEND TO SERVER",14,6,14,NAVY_TEXT,XBOLD);
         var back:Shape = rect(button,0,0,label.width + 28,30,TEAL,30);
         button.setChildIndex(back,0);
         button.x = x - back.width;
         button.y = y;
         button.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            shareMod(mod);
         });
         return button.x;
      }

      private function shareMod(mod:Object) : void
      {
         if(ModShare.shareState(mod) != "share")
         {
            return;
         }
         openServerWindow(1);
         if(ModServerWindow.shown != null)
         {
            ModServerWindow.shown.askSend(mod);
         }
      }

      private function buildMapArt() : void
      {
         var all:Array = MapArt.maps();
         var kinds:Array = [];
         for each(var kind:String in ["1v1","2v2","FFA","Big","Game modes","Other"])
         {
            for each(var m:Object in all)
            {
               if(m.types.indexOf(kind) >= 0 && kinds.indexOf(kind) < 0)
               {
                  kinds.push(kind);
               }
            }
         }
         chips(kinds);
         var only:String = chipFilter();
         for each(m in all)
         {
            if(only == null || m.types.indexOf(only) >= 0)
            {
               entries.push(m);
            }
         }
         if(all.length == 0)
         {
            emptyNote("No map art installed or switched on. Map mods (imported map .bmods) show up here.");
            return;
         }
         if(entries.length == 0)
         {
            emptyNote("No maps of this kind have mod art.");
            return;
         }
         makeList(60,entries.length,function(row:MovieClip, i:int):void
         {
            var map:Object = entries[i];
            var thumb:Sprite = new Sprite();
            thumb.x = 10;
            thumb.y = 4;
            row.addChild(thumb);
            row.thumb = thumb;
            fit(text(row,String(map.name),108,6,17,WHITE,BOLD),LIST_W - 120);
            row.choice = text(row,"",108,29,14,TEAL,MEDIUM);
            paintMapRow(i);
         });
      }

      private function arrow(parent:Sprite, x:Number, y:Number, dir:int, act:Function) : void
      {
         var b:Sprite = new Sprite();
         b.x = x;
         b.y = y;
         b.buttonMode = true;
         rect(b,0,0,22,22,WHITE,6);
         var s:Shape = new Shape();
         s.graphics.beginFill(NAVY_TEXT);
         if(dir < 0)
         {
            s.graphics.moveTo(14,5);
            s.graphics.lineTo(7,11);
            s.graphics.lineTo(14,17);
         }
         else
         {
            s.graphics.moveTo(8,5);
            s.graphics.lineTo(15,11);
            s.graphics.lineTo(8,17);
         }
         s.graphics.endFill();
         b.addChild(s);
         b.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            e.stopPropagation();
            act();
         });
         parent.addChild(b);
      }

      private function paintMapRow(i:int) : void
      {
         if(i < 0 || i >= rows.length)
         {
            return;
         }
         var map:Object = entries[i];
         var row:MovieClip = rows[i];
         var value:String = MapArt.choice(map.level);
         (row.choice as TextField).text = MapArt.choiceName(value);
         fit(row.choice,LIST_W - 120);
         var thumb:Sprite = row.thumb;
         thumb.removeChildren();
         rect(thumb,0,0,88,50,BODY);
         picture(thumb,MapArt.choiceThumbnail(map.level,value),88,50,true);
      }

      private function allChoices() : Array
      {
         var list:Array = ["default"];
         for each(var pack:Object in MapArt.on())
         {
            list.push(pack.id);
         }
         list.push("shuffle");
         list.push("mass");
         return list;
      }

      private function currentAll() : String
      {
         var seen:String = null;
         for each(var m:Object in MapArt.maps())
         {
            var c:String = MapArt.choice(m.level);
            if(seen != null && c != seen)
            {
               return null;
            }
            seen = c;
         }
         return seen;
      }

      private function refreshAllMaps() : void
      {
         if(allMaps == null)
         {
            return;
         }
         var value:String = currentAll();
         allMaps.text = value == null ? "Mixed" : MapArt.choiceName(value);
         fit(allMaps,170);
         allMaps.x = 201 - allMaps.width / 2;
         allMapsLine.graphics.clear();
         if(focus == "all")
         {
            allMapsLine.graphics.beginFill(TEAL);
            allMapsLine.graphics.drawRect(120,24,162,3);
            allMapsLine.graphics.endFill();
         }
      }

      private function changeAllMaps(dir:int) : void
      {
         var options:Array = allChoices();
         var at:int = options.indexOf(currentAll());
         var value:String = options[(at < 0 ? 0 : at + dir + options.length) % options.length];
         var apply:Function = function():void
         {
            for each(var m:Object in MapArt.maps())
            {
               if(MapArt.choices(m.level).indexOf(value) >= 0)
               {
                  ModSettings.setMapArt(m.level,value);
               }
            }
            for(var i:int = 0; i < rows.length; i++)
            {
               paintMapRow(i);
            }
            refreshAllMaps();
            showDetails();
         };
         if(value == "mass")
         {
            confirmMass("every map",apply);
         }
         else
         {
            apply();
         }
      }

      private function confirmMass(what:String, apply:Function) : void
      {
         Modal.show("Mass random","Mass random builds " + what + " from random pieces: each platform and the background " +
            "is picked from the game's art and every map-art mod's, again on every load. The map can look mixed and may " +
            "not match at all. Use it?",[{"label":"Use it","action":apply},{"label":"Cancel"}]);
      }

      private function mapDetails(map:Object) : void
      {
         rect(details,0,0,DW,HEIGHT,PANEL);
         fit(text(details,String(map.name),14,6,24,WHITE,XBOLD),DW - 28);
         fit(text(details,"Art used when this map loads · " + map.types.join(", "),14,38,14,TEAL,MEDIUM),DW - 28);
         tiles = [];
         var choices:Array = MapArt.choices(map.level);
         var value:String = MapArt.choice(map.level);
         var cols:int = 4;
         for(var i:int = 0; i < choices.length; i++)
         {
            var tile:MovieClip = new MovieClip();
            tile.x = 14 + (i % cols) * 146;
            tile.y = 70 + int(i / cols) * 112;
            tile.buttonMode = true;
            details.addChild(tile);
            tiles.push(tile);
            tile.value = choices[i];
            paintTile(tile,map,choices[i] == value,focus == "tiles" && i == tileFocus);
            tile.addEventListener(MouseEvent.CLICK,tileClick(i));
         }
      }

      private function paintTile(tile:MovieClip, map:Object, chosen:Boolean, focused:Boolean) : void
      {
         tile.removeChildren();
         var value:String = tile.value;
         rect(tile,-3,-3,140,80,focused ? WHITE : (chosen ? TEAL : LINE));
         var pic:Sprite = new Sprite();
         tile.addChild(pic);
         rect(pic,0,0,134,74,BODY);
         if(value == "shuffle")
         {
            text(pic,"?",67,10,44,TEAL,XBOLD,0,true);
         }
         else if(value == "mass")
         {
            text(pic,"MIX",67,20,28,TEAL,XBOLD,0,true);
         }
         else
         {
            picture(pic,MapArt.choiceThumbnail(map.level,value),134,74,true);
         }
         fit(text(tile,MapArt.choiceName(value),0,80,13,chosen ? WHITE : LIGHT,BOLD),134);
      }

      private function tileClick(i:int) : Function
      {
         return function(e:MouseEvent):void
         {
            focus = "tiles";
            tileFocus = i;
            pickTile(i);
         };
      }

      private function pickTile(i:int) : void
      {
         var map:Object = entries[selected];
         var value:String = tiles[i].value;
         var apply:Function = function():void
         {
            ModSettings.setMapArt(map.level,value);
            paintMapRow(selected);
            refreshAllMaps();
            paintTiles();
         };
         if(value == "mass" && MapArt.choice(map.level) != "mass")
         {
            confirmMass(map.name,apply);
         }
         else
         {
            apply();
         }
      }

      private function paintTiles() : void
      {
         if(entries.length == 0 || tab != 1)
         {
            return;
         }
         var map:Object = entries[selected];
         var value:String = MapArt.choice(map.level);
         for(var i:int = 0; i < tiles.length; i++)
         {
            paintTile(tiles[i],map,tiles[i].value == value,focus == "tiles" && i == tileFocus);
         }
      }

      private function buildMusic() : void
      {
         if(MusicPacks.packs.length == 0)
         {
            emptyNote("No mods with music or sounds installed. Mods with \"music\" or \"sounds\" (MP3 files) show up here.");
            return;
         }
         entries = MusicPacks.changes();
         makeList(56,entries.length,function(row:MovieClip, i:int):void
         {
            fit(text(row,String(entries[i].label).toUpperCase(),16,5,17,WHITE,BOLD),LIST_W - 100);
            row.choice = text(row,"",16,28,14,TEAL,MEDIUM);
            var toggle:Sprite = new Sprite();
            toggle.x = LIST_W - 76;
            toggle.y = 14;
            row.addChild(toggle);
            row.toggle = toggle;
            toggle.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
            {
               e.stopPropagation();
               setFocus("list");
               select(i);
               switchAudioMod(i);
            });
            paintMusicRow(i);
         });
      }

      private function audioLine(entry:Object) : String
      {
         if(!entry.on)
         {
            return entry.kind == "music" ? "The game's music (" + entry.line + " is off)" : entry.line + " (off)";
         }
         if(!entry.wins)
         {
            return entry.line + " - a later mod's is heard";
         }
         if(entry.kind == "sounds" && entry.lost > 0)
         {
            return entry.line + " (" + entry.lost + " from a later mod)";
         }
         return entry.line;
      }

      private function paintMusicRow(i:int) : void
      {
         if(i < 0 || i >= rows.length || tab != 2)
         {
            return;
         }
         var label:TextField = rows[i].choice;
         label.text = audioLine(entries[i]);
         label.textColor = entries[i].wins ? TEAL : GREY;
         fit(label,LIST_W - 100);
         paintToggle(rows[i].toggle,entries[i].on);
      }

      private function switchAudioMod(i:int) : void
      {
         if(i < 0 || i >= entries.length)
         {
            return;
         }
         var id:String = entries[i].pack.id;
         ModSettings.setDisabled(id,!ModSettings.isDisabled(id));
         audioChanged();
         var keep:int = selected;
         entries = MusicPacks.changes();
         for(var r:int = 0; r < rows.length && r < entries.length; r++)
         {
            paintMusicRow(r);
         }
         select(keep);
         showDetails();
         updateStatus();
      }

      private static function audioChanged() : void
      {
         MusicPacks.rebuildSounds();
         MusicPacks.restartIfPlaying();
      }

      private function musicDetails(entry:Object) : void
      {
         rect(details,0,0,DW,HEIGHT,PANEL);
         fit(text(details,String(entry.label),14,6,24,WHITE,XBOLD),DW - 28);
         var about:String;
         var lines:Array = [];
         if(entry.kind == "sounds")
         {
            for each(var ev:String in entry.events)
            {
               lines.push(ev.replace(/^VO_Announcer_InGame_/,"Announcer ").replace(/_Play$/,"").split("_").join(" "));
            }
            about = "While " + entry.pack.name + " is on, these sounds come from it instead of the game:";
         }
         else if(entry.kind == "tracks")
         {
            lines = entry.titles;
            about = "Tracks a mod map can play (its BGMusic); they replace none of the game's music:";
         }
         else if(entry.slot == MusicPacks.BATTLE)
         {
            about = "Every map's music, unless a mod changes that map's own music.";
         }
         else if(entry.slot == "DefaultUI")
         {
            about = "The music of the main menu and the other menu screens.";
         }
         else if(entry.slot == "DefaultCharacterSelect")
         {
            about = "The music on character select.";
         }
         else if(entry.slot == "DefaultWinTheme")
         {
            about = "The music on the results screen after a match.";
         }
         else
         {
            about = "Wherever the game plays this music (" + entry.slot + ").";
         }
         fit(text(details,about,14,38,14,TEAL,MEDIUM),DW - 28);
         var top:Number = 70;
         if(entry.kind == "music")
         {
            fit(text(details,"Now: " + MusicPacks.choiceName(MusicPacks.replacement(entry.slot)),22,top,14,WHITE,BOLD),DW - 44);
            top += 28;
         }
         for(var k:int = 0; k < lines.length && top + k * 20 < HEIGHT - 90; k++)
         {
            fit(text(details,lines[k],22,top + k * 20,13,LIGHT,MEDIUM),DW - 44);
         }
         if(k < lines.length)
         {
            text(details,"and " + (lines.length - k) + " more",22,top + k * 20,13,GREY,MEDIUM);
         }
         fit(text(details,entry.pack.name + " is " + (entry.on ? "on" : "off") + ": " + Prompts.plain(Prompts.KEYS.select) +
            " switches it (the same switch as INSTALLED). When two mods change the same, the later one is heard.",14,
            HEIGHT - 56,13,GREY,MEDIUM),DW - 28);
         var now:String = MusicPacks.nowPlaying();
         fit(text(details,"Playing now: " + (now.indexOf("game:") == 0 ? "the game's music" : (now == "none" ? "nothing" :
            MusicPacks.choiceName(now.split(" ")[0]))) + ".",14,HEIGHT - 30,13,GREY,MEDIUM),DW - 28);
      }

      private function buildItems() : void
      {
         var all:Array = [];
         for each(var mod:Object in ContentMods.all)
         {
            all = all.concat(itemsOf(mod));
         }
         var kinds:Array = [];
         for each(var kind:String in KIND_ORDER)
         {
            for each(var it:Object in all)
            {
               if(it.kind == kind && kinds.indexOf(kind + "s") < 0)
               {
                  kinds.push(kind + "s");
               }
            }
         }
         chips(kinds);
         var only:String = chipFilter();
         for each(it in all)
         {
            if(only == null || it.kind + "s" == only)
            {
               entries.push(it);
            }
         }
         if(entries.length == 0)
         {
            emptyNote(all.length == 0 ? "The mods installed add no items." : "No items of this kind.");
            return;
         }
         makeList(54,entries.length,function(row:MovieClip, i:int):void
         {
            var item:Object = entries[i];
            rowPicture(row,item);
            fit(text(row,String(item.name),58,4,17,WHITE,BOLD),LIST_W - 70);
            fit(text(row,item.kind + " · " + item.mod.name,58,26,13,TEAL,MEDIUM),LIST_W - 70);
         });
      }

      private function itemDetails(item:Object) : void
      {
         rect(details,0,0,DW,HEIGHT,PANEL);
         itemBadge(details,item,8,8,64);
         fit(text(details,String(item.name),84,8,24,WHITE,XBOLD),DW - 96);
         fit(text(details,item.kind + (item.copy ? ", next to " + item.copy : "") + " · from " + item.mod.name +
            (ContentMods.isLoaded(item.mod.id) ? "" : " (off)"),84,40,14,TEAL,MEDIUM),DW - 96);
         if(item.id != null)
         {
            fit(text(details,item.id,84,60,13,GREY,MEDIUM),DW - 96);
         }
         previews(details,item.mod,item.kind == "Weapon skin" || item.kind == "Avatar" || item.kind == "Skin" ? item : null,
            8,90,DW - 16,HEIGHT - 98);
      }

      private function buildCommunity() : void
      {
         ModShare.libraryChanged = communityArrived;
         if(ModShare.library != null && ModShare.libraryError == null && ModShare.libraryOlder(20000) && !ModShare.browsing())
         {
            ModShare.browse();
         }
         if(ModShare.library == null || ModShare.libraryError != null)
         {
            if(!ModShare.browsing() && !ModShare.browse())
            {
               communityNote("Not connected to a server","Community mods come from the project's server you play on " +
                  "(Options > Servers). Without one, put mods in the mods folder (Open mods folder, below) and restart the game.");
               return;
            }
            if(ModShare.library == null || ModShare.browsing())
            {
               communityNote("Asking the server...","");
               return;
            }
         }
         if(ModShare.libraryError != null)
         {
            communityNote("No community mods",ModShare.libraryError);
            return;
         }
         var kinds:Array = [];
         for each(var k:Object in ModShare.library)
         {
            for each(var kind:String in k.kinds is Array ? k.kinds : ["Other"])
            {
               if(kinds.indexOf(kind) < 0 && CATEGORY_ORDER.indexOf(kind) >= 0)
               {
                  kinds.push(kind);
               }
            }
         }
         kinds.sort(function(a:String, b:String):int
         {
            return CATEGORY_ORDER.indexOf(a) - CATEGORY_ORDER.indexOf(b);
         });
         chips(kinds.concat(["Not installed","Updates"]));
         var only:String = chipFilter();
         for each(var m:Object in ModShare.library)
         {
            var state:String = ModShare.stateOf(String(m.entry));
            var hasKind:Boolean = m.kinds is Array ? m.kinds.indexOf(only) >= 0 : only == "Other";
            if(only == null || only == "Not installed" && state == "new" || only == "Updates" && state == "other" ||
               CATEGORY_ORDER.indexOf(only) >= 0 && hasKind)
            {
               entries.push(m);
            }
         }
         if(entries.length == 0)
         {
            emptyNote(ModShare.library.length == 0 ? "The server has no public mods yet. Got a key from someone? " +
               "Mods on the server (" + Prompts.plain("{Alt}") + ") > BY KEY." : "No mods of this kind.");
            return;
         }
         makeList(54,entries.length,function(row:MovieClip, i:int):void
         {
            var mod:Object = entries[i];
            badge(row,String(mod.name || "?").charAt(0).toUpperCase(),8,5,40);
            fit(text(row,String(mod.name),58,4,17,WHITE,BOLD),LIST_W - 170);
            fit(text(row,versionText(mod.version) + " · " + counts(mod) + (mod.author ? " · by " + mod.author : ""),58,26,
               13,TEAL,MEDIUM),LIST_W - 170);
            var st:String = ModShare.stateOf(String(mod.entry));
            var hot:Boolean = st == "new" || st == "other";
            var label:TextField = text(row,communityLabel(st),0,15,13,hot ? NAVY_TEXT : LIGHT,XBOLD);
            label.x = LIST_W - 14 - label.width;
            var back:Shape = rect(row,label.x - 10,12,label.width + 20,24,hot ? TEAL : LINE,24);
            row.setChildIndex(back,row.getChildIndex(label));
         });
      }

      private function communityNote(title:String, about:String) : void
      {
         var box:Sprite = new Sprite();
         box.x = LEFT;
         box.y = TOP;
         tabBody.addChild(box);
         var w:Number = HALF * 2 - 20;
         rect(box,0,0,w,HEIGHT,PANEL);
         text(box,title,w / 2,120,22,WHITE,XBOLD,0,true);
         if(about)
         {
            var t:TextField = text(box,about,w / 2 - 280,160,15,LIGHT,MEDIUM,560);
            var centred:TextFormat = t.getTextFormat();
            centred.align = "center";
            t.setTextFormat(centred);
         }
      }

      private static function counts(mod:Object) : String
      {
         if(mod.likes == null)
         {
            return sizeText(mod.size);
         }
         var likes:int = int(mod.likes);
         var got:int = int(mod.downloads);
         return (mod.liked ? "LIKED · " : "") + likes + (likes == 1 ? " like" : " likes") + " · " + got +
            (got == 1 ? " download" : " downloads");
      }

      private function toggleLike(mod:Object) : void
      {
         if(mod == null || mod.likes == null)
         {
            return;
         }
         if(!ModShare.like(String(mod.id),!mod.liked))
         {
            status.text = "Not connected to a server";
            return;
         }
         status.text = (mod.liked ? "Taking back your like of " : "Liking ") + mod.name + "...";
      }

      private static function communityLabel(state:String) : String
      {
         switch(state)
         {
            case "loaded":
               return "INSTALLED";
            case "on":
               return "ON AT RESTART";
            case "off":
               return "INSTALLED, OFF";
            case "other":
               return "OTHER VERSION";
         }
         return "GET";
      }

      private static function remotePicture(parent:Sprite, url:String, w:Number, h:Number) : void
      {
         var key:String = url.split("?")[0] + "?" + url.split("&entry=")[1];
         var place:Function = function(bd:BitmapData):void
         {
            var b:Bitmap = new Bitmap(bd,"auto",true);
            b.scaleX = b.scaleY = Math.min(w / bd.width,h / bd.height);
            b.x = (w - b.width) / 2;
            b.y = (h - b.height) / 2;
            parent.addChild(b);
         };
         if(bitmaps[key] is BitmapData)
         {
            place(bitmaps[key]);
            return;
         }
         if(waiting[key] != null)
         {
            waiting[key].push(place);
            return;
         }
         waiting[key] = [place];
         var fail:Function = function(why:String):void
         {
            Platform.log("mods window: preview " + key + ": " + why);
            delete waiting[key];
         };
         var http:URLLoader = new URLLoader();
         http.dataFormat = URLLoaderDataFormat.BINARY;
         http.addEventListener(Event.COMPLETE,function(e:Event):void
         {
            var bytes:ByteArray = http.data as ByteArray;
            var png:Boolean = bytes != null && bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
            var jpg:Boolean = bytes != null && bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
            if(!png && !jpg)
            {
               fail("not a PNG or JPEG");
               return;
            }
            var loader:Loader = new Loader();
            loader.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e2:Event):void
            {
               var bd:BitmapData = (loader.content as Bitmap).bitmapData;
               bitmaps[key] = bd;
               for each(var f:Function in waiting[key])
               {
                  f(bd);
               }
               delete waiting[key];
            });
            loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR,function(e2:Event):void
            {
               fail("didn't decode");
            });
            loader.loadBytes(bytes);
         });
         http.addEventListener(IOErrorEvent.IO_ERROR,function(e:Event):void
         {
            fail("didn't load");
         });
         http.addEventListener(SecurityErrorEvent.SECURITY_ERROR,function(e:Event):void
         {
            fail("refused");
         });
         try
         {
            http.load(new URLRequest(url));
         }
         catch(err:Error)
         {
            fail(err.message);
         }
      }

      private static function versionText(version:Object) : String
      {
         var v:String = String(version);
         return v.charAt(0) == "v" || v.charAt(0) == "V" ? v : "v" + v;
      }

      private static function sizeText(bytes:Number) : String
      {
         if(bytes >= 1048576)
         {
            return Math.round(bytes / 104857.6) / 10 + " MB";
         }
         return Math.max(1,Math.round(bytes / 1024)) + " KB";
      }

      private function communityArrived() : void
      {
         if(tab == 0 && isActive)
         {
            showDetails();
            updateStatus();
            return;
         }
         if(tab == 4 && isActive)
         {
            remembered[4] = selected;
            var keep:String = focus;
            var keepId:String = selected >= 0 && selected < entries.length ? String(entries[selected].id) : null;
            buildTab();
            if(keep == "chips" && chipBar != null)
            {
               setFocus("chips");
            }
            else if(keepId != null)
            {
               for(var i:int = 0; i < entries.length; i++)
               {
                  if(entries[i].id == keepId && i != selected)
                  {
                     select(i);
                     break;
                  }
               }
            }
         }
      }

      private static function communityState(st:String) : String
      {
         switch(st)
         {
            case "loaded":
               return "Installed and loaded.";
            case "on":
               return "Installed: it loads when the game restarts.";
            case "off":
               return "Installed but switched off.";
            case "other":
               return "Another version of it is installed here; getting this one moves that one to mods-replaced (beside the mods folder).";
         }
         return "Not installed.";
      }

      private function communityDetails(mod:Object) : void
      {
         rect(details,0,0,DW,HEIGHT,PANEL);
         var textX:Number = 8;
         var url:String = mod.preview ? ModShare.previewUrl(String(mod.entry)) : null;
         if(url != null)
         {
            var frame:Sprite = new Sprite();
            frame.x = 8;
            frame.y = 8;
            details.addChild(frame);
            rect(frame,0,0,300,169,BODY);
            remotePicture(frame,url,300,169);
            textX = 320;
         }
         var tw:Number = DW - 18;
         var y:Number = 8;
         fit(text(details,String(mod.name),textX,y,24,WHITE,XBOLD),DW - textX - 10);
         y += 32;
         fit(text(details,versionText(mod.version) + (mod.author ? " · by " + mod.author : ""),textX,y,14,TEAL,MEDIUM),
            DW - textX - 10);
         y += 22;
         var about:String = String(mod.description || "").split("\n").join(" ").split("\r").join(" ");
         if(url != null && about.length > 170)
         {
            about = about.substr(0,167) + "...";
         }
         if(about.length > 0)
         {
            var desc:TextField = text(details,about,textX,y,13,LIGHT,MEDIUM,DW - textX - 10);
            y += desc.height + 6;
         }
         y = Math.max(y,url != null ? 186 : 130);
         fit(text(details,sizeText(mod.size) + " · " + mod.files + (mod.files == 1 ? " file" : " files") + " · shared " + String(mod.at).substr(0,10) + " · id " +
            mod.id,8,y,13,GREY,MEDIUM),tw);
         y += 22;
         if(mod.likes != null)
         {
            var kindsLine:String = (mod.kinds is Array ? mod.kinds.join(", ") : "Other").toUpperCase();
            var line:TextField = text(details,kindsLine + " · " + counts(mod),8,y + 6,13,TEAL,BOLD);
            fit(line,tw - 170);
            var likeButton:Sprite = new Sprite();
            likeButton.buttonMode = true;
            details.addChild(likeButton);
            var likeLabel:TextField = text(likeButton,mod.liked ? "LIKED" : "LIKE",14,6,14,mod.liked ? NAVY_TEXT : WHITE,XBOLD);
            var likeBack:Shape = rect(likeButton,0,0,likeLabel.width + 28,30,mod.liked ? TEAL : LINE,30);
            likeButton.setChildIndex(likeBack,0);
            likeButton.x = DW - 10 - likeBack.width;
            likeButton.y = y;
            likeButton.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
            {
               toggleLike(mod);
            });
            y += 36;
         }
         else
         {
            y += 4;
         }
         var st:String = ModShare.stateOf(String(mod.entry));
         var stateText:TextField = text(details,communityState(st) + (ModShare.isSubscribed(String(mod.id)) ? " Kept up to " +
            "date: a newer upload installs by itself (REMOVE on INSTALLED stops it)." : ""),8,y,14,st == "loaded" || st == "on" ?
            TEAL : WHITE,BOLD,tw);
         y += stateText.height + 10;
         var action:String = st == "new" ? "GET" : (st == "other" ? "GET THIS VERSION" : (st == "off" ? "SWITCH ON" : null));
         if(action != null)
         {
            var button:Sprite = new Sprite();
            button.x = 8;
            button.y = y;
            button.buttonMode = true;
            details.addChild(button);
            var label:TextField = text(button,action,18,7,16,NAVY_TEXT,XBOLD);
            var back:Shape = rect(button,0,0,label.width + 36,34,TEAL,34);
            button.setChildIndex(back,0);
            button.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
            {
               getCommunity(mod);
            });
            text(details,"(or press select)",label.width + 54,y + 8,13,GREY,MEDIUM);
            y += 46;
         }
         text(details,"Public mods come from other players through this server, each one checked by the server's owner " +
            "first, and the server lets through only mod files with no code. Mods load when the game starts.",8,
            Math.max(y,HEIGHT - 60),12,GREY,MEDIUM,tw);
      }

      private function getCommunity(mod:Object) : void
      {
         var entry:String = String(mod.entry);
         var st:String = ModShare.stateOf(entry);
         if(st == "loaded" || st == "on")
         {
            return;
         }
         status.text = st == "off" ? "Switching on " + mod.name : "Downloading " + mod.name + " (" + sizeText(mod.size) + ")...";
         ModShare.getFromLibrary(entry,function(why:String):void
         {
            if(why == null)
            {
               Modal.show(String(mod.name),(st == "off" ? "Switched on." : "Installed in the mods folder.") +
                  " Restart the game to load it.");
            }
            else
            {
               Modal.show("Not installed",mod.name + ": " + why + ".");
            }
            communityArrived();
         });
      }

      private function shareEnded(entry:String, why:String) : void
      {
         var name:String = entry.split("#")[0];
         Modal.show(why == null ? "Sent" : "Not sent",why == null ? name + " is on the server now (Mods on the server shows its key)." : name + ": " + why + ".");
         communityArrived();
      }

      override public function OnInitDisplay() : void
      {
         updateStatus();
      }

      override public function OnRefreshScreen() : void
      {
         updateStatus();
      }

      override public function HandleInput(input:int) : Boolean
      {
         if(!method_5588())
         {
            return false;
         }
         switch(input)
         {
            case 18:
            case 19:
               onClose();
               return true;
            case 21:
               if(tab == 0 && entries.length > 0 && selected >= 0 && selected < entries.length)
               {
                  askRemove(entries[selected]);
               }
               else if(tab == 4 && entries.length > 0 && selected >= 0 && selected < entries.length)
               {
                  toggleLike(entries[selected]);
               }
               else
               {
                  openColorEditor();
               }
               return true;
            case 20:
               openServerWindow(0);
               return true;
            case 26:
               showTab((tab + TABS.length - 1) % TABS.length);
               return true;
            case 27:
               showTab((tab + 1) % TABS.length);
               return true;
            case 24:
            case 25:
               if(rows.length > 0)
               {
                  var page:int = Math.max(1,int(listHeight / rowHeight) - 1);
                  if(focus != "list")
                  {
                     setFocus("list");
                  }
                  select(selected + (input == 24 ? -page : page));
               }
               return true;
         }
         if(focus == "chips")
         {
            switch(input)
            {
               case 1:
                  if(chipIndex[tab] > 0)
                  {
                     pickChip(chipIndex[tab] - 1);
                  }
                  break;
               case 2:
                  if(chipIndex[tab] < chipNames.length - 1)
                  {
                     pickChip(chipIndex[tab] + 1);
                  }
                  else if(allMaps != null)
                  {
                     setFocus("all");
                  }
                  break;
               case 5:
                  if(rows.length > 0)
                  {
                     setFocus("list");
                  }
            }
            return true;
         }
         if(focus == "all")
         {
            switch(input)
            {
               case 1:
                  changeAllMaps(-1);
                  break;
               case 2:
               case 23:
               case 17:
               case 11:
                  changeAllMaps(1);
                  break;
               case 4:
                  setFocus("chips");
                  break;
               case 5:
                  if(rows.length > 0)
                  {
                     setFocus("list");
                  }
            }
            return true;
         }
         if(focus == "tiles")
         {
            var cols:int = 4;
            switch(input)
            {
               case 1:
                  if(tileFocus % cols == 0)
                  {
                     setFocus("list");
                     return true;
                  }
                  tileFocus--;
                  break;
               case 2:
                  tileFocus = Math.min(tiles.length - 1,tileFocus + 1);
                  break;
               case 4:
                  tileFocus = Math.max(0,tileFocus - cols);
                  break;
               case 5:
                  tileFocus = Math.min(tiles.length - 1,tileFocus + cols);
                  break;
               case 23:
               case 17:
               case 11:
                  pickTile(tileFocus);
            }
            paintTiles();
            return true;
         }
         switch(input)
         {
            case 4:
               if(selected == 0 && chipBar != null)
               {
                  setFocus("chips");
               }
               else
               {
                  select(selected - 1);
               }
               break;
            case 5:
               select(selected + 1);
               break;
            case 1:
               if(tab != 2)
               {
                  cycleSignature(-1);
               }
               break;
            case 2:
               if(tab == 1 && tiles.length > 0)
               {
                  var value:String = MapArt.choice(entries[selected].level);
                  tileFocus = 0;
                  for(var i:int = 0; i < tiles.length; i++)
                  {
                     if(tiles[i].value == value)
                     {
                        tileFocus = i;
                     }
                  }
                  setFocus("tiles");
               }
               else if(tab != 2)
               {
                  cycleSignature(1);
               }
               break;
            case 23:
            case 17:
            case 11:
               if(tab == 0 && entries.length > 0)
               {
                  switchMod(selected);
               }
               else if(tab == 4 && entries.length > 0)
               {
                  getCommunity(entries[selected]);
               }
               else if(tab == 2 && entries.length > 0)
               {
                  switchAudioMod(selected);
               }
         }
         return true;
      }

      private function setFocus(where:String) : void
      {
         focus = where;
         paintRow(selected);
         paintChips();
         refreshAllMaps();
         paintTiles();
      }

      public static var current:ModsScreen;

      override public function OnDestroyScreen() : void
      {
         clearRowDolls();
         clearDolls();
         unloadBanks();
         tabClips = [];
         rows = [];
         tiles = [];
         entries = [];
      }
   }
}
