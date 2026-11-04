package flash.desktop;

@:forward
abstract ClipboardFormats(openfl.desktop.ClipboardFormats) from openfl.desktop.ClipboardFormats
      to openfl.desktop.ClipboardFormats {
   public static var HTML_FORMAT(get, never):ClipboardFormats;
   public static var RICH_TEXT_FORMAT(get, never):ClipboardFormats;
   public static var TEXT_FORMAT(get, never):ClipboardFormats;
   public static var BITMAP_FORMAT(get, never):ClipboardFormats;

   static inline function get_HTML_FORMAT():ClipboardFormats return openfl.desktop.ClipboardFormats.HTML_FORMAT;
   static inline function get_RICH_TEXT_FORMAT():ClipboardFormats return openfl.desktop.ClipboardFormats.RICH_TEXT_FORMAT;
   static inline function get_TEXT_FORMAT():ClipboardFormats return openfl.desktop.ClipboardFormats.TEXT_FORMAT;
   static inline function get_BITMAP_FORMAT():ClipboardFormats return cast -1;
}
