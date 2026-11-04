package port.runtime;

#if flash
typedef XML = flash.xml.XML;
typedef XMLList = flash.xml.XMLList;
#else
class XML {
   public static var ignoreComments:Bool = true;
   public static var ignoreProcessingInstructions:Bool = true;
   public static var ignoreWhitespace:Bool = true;
   public static var prettyPrinting:Bool = true;
   public static var prettyIndent:Int = 2;

   public var kind(default, null):String;
   var localName_:String;
   var value:String;
   var attrNames:Array<String>;
   var attrValues:Array<String>;
   var kids:Array<XML>;
   var parent_:XML;

   public function new(?value:Dynamic = null) {
      kind = "text";
      this.value = "";
      kids = [];
      attrNames = [];
      attrValues = [];
      if (value == null) {
         return;
      }
      if (Std.isOfType(value, XML)) {
         (cast value:XML).copyInto(this);
         return;
      }
      if (Std.isOfType(value, XMLListData)) {
         var list:XMLListData = cast value;
         if (list.items.length == 1) {
            list.items[0].copyInto(this);
            return;
         }
         if (list.items.length != 0) {
            E4XParser.typeError("Error #1088: The markup in the document following the root element must be well-formed.");
         }
         return;
      }
      var text = Std.string(value);
      var nodes = E4XParser.parse(text);
      var top = [for (n in nodes) if (n.kind != "text" || StringTools.trim(n.value) != "") n];
      if (top.length == 0) {
         return;
      }
      if (top.length > 1) {
         E4XParser.typeError("Error #1088: The markup in the document following the root element must be well-formed.");
      }
      top[0].copyInto(this);
   }

   static function make(kind:String, name:String, value:String):XML {
      var x = new XML();
      x.kind = kind;
      x.localName_ = name;
      x.value = value;
      return x;
   }

   @:allow(port.runtime.E4XParser)
   static inline function element(name:String):XML {
      return make("element", name, "");
   }

   @:allow(port.runtime.E4XParser)
   static inline function textNode(text:String, kind:String = "text"):XML {
      return make(kind, null, text);
   }

   @:allow(port.runtime.E4XParser)
   static inline function instruction(name:String, body:String):XML {
      return make("processing-instruction", name, body);
   }

   @:allow(port.runtime.E4XParser)
   function addParsed(child:XML):Void {
      child.parent_ = this;
      kids.push(child);
   }

   @:allow(port.runtime.E4XParser)
   function addParsedAttribute(name:String, v:String):Void {
      attrNames.push(name);
      attrValues.push(v);
   }

   function copyInto(target:XML):Void {
      target.kind = kind;
      target.localName_ = localName_;
      target.value = value;
      target.attrNames = attrNames.copy();
      target.attrValues = attrValues.copy();
      target.kids = [];
      for (k in kids) {
         var c = k.copy();
         c.parent_ = target;
         target.kids.push(c);
      }
   }

   public function copy():XML {
      var x = new XML();
      copyInto(x);
      return x;
   }

   public static function settings():Dynamic {
      return {
         ignoreComments: ignoreComments,
         ignoreProcessingInstructions: ignoreProcessingInstructions,
         ignoreWhitespace: ignoreWhitespace,
         prettyPrinting: prettyPrinting,
         prettyIndent: prettyIndent
      };
   }

   public static function defaultSettings():Dynamic {
      return {
         ignoreComments: true,
         ignoreProcessingInstructions: true,
         ignoreWhitespace: true,
         prettyPrinting: true,
         prettyIndent: 2
      };
   }

   public static function setSettings(?value:Dynamic = null):Void {
      if (value == null) {
         value = defaultSettings();
      }
      if (Reflect.hasField(value, "ignoreComments")) {
         ignoreComments = Reflect.field(value, "ignoreComments");
      }
      if (Reflect.hasField(value, "ignoreProcessingInstructions")) {
         ignoreProcessingInstructions = Reflect.field(value, "ignoreProcessingInstructions");
      }
      if (Reflect.hasField(value, "ignoreWhitespace")) {
         ignoreWhitespace = Reflect.field(value, "ignoreWhitespace");
      }
      if (Reflect.hasField(value, "prettyPrinting")) {
         prettyPrinting = Reflect.field(value, "prettyPrinting");
      }
      if (Reflect.hasField(value, "prettyIndent")) {
         prettyIndent = Reflect.field(value, "prettyIndent");
      }
   }


   public function name():String {
      return kind == "element" || kind == "attribute" || kind == "processing-instruction" ? localName_ : null;
   }

   public function localName():String {
      return name();
   }

   public function setName(name:Dynamic):Void {
      if (kind == "element" || kind == "attribute") {
         localName_ = Std.string(name);
      }
   }

   public function nodeKind():String {
      return kind;
   }

   public function parent():XML {
      return parent_;
   }

   public function childIndex():Int {
      return parent_ == null || kind == "attribute" ? -1 : parent_.kids.indexOf(this);
   }

   public function length():Int {
      return 1;
   }

   public function hasSimpleContent():Bool {
      if (kind != "element") {
         return kind != "comment" && kind != "processing-instruction";
      }
      for (k in kids) {
         if (k.kind == "element") {
            return false;
         }
      }
      return true;
   }

   public function hasComplexContent():Bool {
      return kind == "element" && !hasSimpleContent();
   }


   public function attribute(name:Dynamic):XMLList {
      var key = Std.string(name);
      var out = new XMLListData();
      if (kind != "element") {
         return out;
      }
      for (i in 0...attrNames.length) {
         if (key == "*" || attrNames[i] == key) {
            out.items.push(attributeNode(i));
         }
      }
      return out;
   }

   public function attributes():XMLList {
      return attribute("*");
   }

   function attributeNode(i:Int):XML {
      var a = make("attribute", attrNames[i], attrValues[i]);
      a.parent_ = this;
      return a;
   }

   public function attributeValue(name:String):String {
      var i = attrNames.indexOf(name);
      return i < 0 ? null : attrValues[i];
   }

   public function setAttributeValue(name:String, v:Dynamic):Void {
      if (kind != "element") {
         return;
      }
      var text = Std.isOfType(v, String) ? (v : String) : As3.coerceString(v);
      var i = attrNames.indexOf(name);
      if (i < 0) {
         attrNames.push(name);
         attrValues.push(text);
      } else {
         attrValues[i] = text;
      }
   }

   public function deleteAttribute(name:String):Bool {
      var i = attrNames.indexOf(name);
      if (i >= 0) {
         attrNames.splice(i, 1);
         attrValues.splice(i, 1);
      }
      return true;
   }


   public function children():XMLList {
      return XMLListData.of(kids.copy());
   }

   public function child(name:Dynamic):XMLList {
      if (Std.isOfType(name, Int) || (Std.isOfType(name, Float) && Math.ffloor(name) == name)) {
         var i:Int = Std.int(name);
         return XMLListData.of(i >= 0 && i < kids.length ? [kids[i]] : []);
      }
      var key = Std.string(name);
      return XMLListData.of([for (k in kids) if (k.kind == "element" && (key == "*" || k.localName_ == key)) k]);
   }

   public function elements(?name:Dynamic = "*"):XMLList {
      return child(name == null ? "*" : Std.string(name));
   }

   public function descendants(?name:Dynamic = "*"):XMLList {
      var key = name == null ? "*" : Std.string(name);
      var out:Array<XML> = [];
      collectDescendants(key, out);
      return XMLListData.of(out);
   }

   function collectDescendants(key:String, out:Array<XML>):Void {
      for (k in kids) {
         if (key == "*" ? k.kind == "element" || k.kind == "text" : k.kind == "element" && k.localName_ == key) {
            out.push(k);
         }
         k.collectDescendants(key, out);
      }
   }

   public function text():XMLList {
      return XMLListData.of([for (k in kids) if (k.kind == "text") k]);
   }

   public function comments():XMLList {
      return XMLListData.of([for (k in kids) if (k.kind == "comment") k]);
   }

   static function toNodes(node:Dynamic):Array<XML> {
      if (Std.isOfType(node, XML)) {
         return [cast node];
      }
      if (Std.isOfType(node, XMLListData)) {
         return (cast node:XMLListData).items.copy();
      }
      return [textNode(As3.coerceString(node))];
   }

   function adopt(node:XML):XML {
      if (node.parent_ != null && node.parent_ != this) {
         node.parent_.kids.remove(node);
      } else if (node.parent_ == this) {
         kids.remove(node);
      }
      node.parent_ = this;
      return node;
   }

   public function appendChild(node:Dynamic):XML {
      for (n in toNodes(node)) {
         kids.push(adopt(n));
      }
      return this;
   }

   public function prependChild(node:Dynamic):XML {
      var nodes = toNodes(node);
      nodes.reverse();
      for (n in nodes) {
         kids.unshift(adopt(n));
      }
      return this;
   }

   function insertAt(anchor:Dynamic, node:Dynamic, after:Bool):Dynamic {
      var a:XML = Std.isOfType(anchor, XMLListData) ? (cast anchor:XMLListData).items[0] : cast anchor;
      var nodes = toNodes(node);
      for (n in nodes) {
         adopt(n);
      }
      var at = a == null ? (after ? 0 : kids.length) : kids.indexOf(a);
      if (a != null && at < 0) {
         return null;
      }
      if (a != null && after) {
         at++;
      }
      for (n in nodes) {
         kids.insert(at++, n);
      }
      return this;
   }

   public function insertChildAfter(anchor:Dynamic, node:Dynamic):Dynamic {
      return insertAt(anchor, node, true);
   }

   public function insertChildBefore(anchor:Dynamic, node:Dynamic):Dynamic {
      return insertAt(anchor, node, false);
   }

   public function removeChild(node:Dynamic):Dynamic {
      for (n in toNodes(node)) {
         if (kids.remove(n)) {
            n.parent_ = null;
         }
      }
      return node;
   }

   public function setChildren(value:Dynamic):XML {
      for (k in kids) {
         k.parent_ = null;
      }
      kids = [];
      return appendChild(value);
   }


   public function toXMLString():String {
      var b = new StringBuf();
      print(b, 0);
      return b.toString();
   }

   public function toString():String {
      if (kind == "attribute" || kind == "text") {
         return value;
      }
      if (kind == "element" && hasSimpleContent()) {
         var b = new StringBuf();
         for (k in kids) {
            if (k.kind == "text") {
               b.add(k.value);
            }
         }
         return b.toString();
      }
      return toXMLString();
   }

   public function valueOf():XML {
      return this;
   }

   static function escapeText(s:String):String {
      return s.split("&").join("&amp;").split("<").join("&lt;").split(">").join("&gt;");
   }

   static function escapeAttribute(s:String):String {
      return s.split("&").join("&amp;").split("<").join("&lt;").split("\"").join("&quot;");
   }

   function print(b:StringBuf, depth:Int):Void {
      var pad = prettyPrinting ? StringTools.lpad("", " ", depth * prettyIndent) : "";
      switch (kind) {
         case "text":
            b.add(pad);
            b.add(escapeText(prettyPrinting ? StringTools.trim(value) : value));
         case "attribute":
            b.add(escapeAttribute(value));
         case "comment":
            b.add(pad);
            b.add("<!--" + value + "-->");
         case "processing-instruction":
            b.add(pad);
            b.add("<?" + localName_ + (value == "" ? "" : " " + value) + "?>");
         default:
            b.add(pad);
            b.add("<" + localName_);
            for (i in 0...attrNames.length) {
               b.add(" " + attrNames[i] + "=\"" + escapeAttribute(attrValues[i]) + "\"");
            }
            if (kids.length == 0) {
               b.add("/>");
               return;
            }
            b.add(">");
            var oneLine = !prettyPrinting || (kids.length == 1 && kids[0].kind == "text");
            if (oneLine) {
               for (k in kids) {
                  k.print(b, prettyPrinting ? 0 : depth);
               }
            } else {
               for (k in kids) {
                  b.add("\n");
                  k.print(b, depth + 1);
               }
               b.add("\n" + pad);
            }
            b.add("</" + localName_ + ">");
      }
   }
}

class XMLListData {
   public var items:Array<XML>;

   public function new(?items:Array<XML> = null) {
      this.items = items == null ? [] : items;
   }

   public static inline function of(items:Array<XML>):XMLListData {
      return new XMLListData(items);
   }

   public function length():Int {
      return items.length;
   }

   public function iterator():Iterator<XML> {
      return items.copy().iterator();
   }

   public function child(name:Dynamic):XMLList {
      var out:Array<XML> = [];
      for (x in items) {
         out = out.concat((x.child(name) : XMLListData).items);
      }
      return of(out);
   }

   public function children():XMLList {
      var out:Array<XML> = [];
      for (x in items) {
         out = out.concat((x.children() : XMLListData).items);
      }
      return of(out);
   }

   public function elements(?name:Dynamic = "*"):XMLList {
      return child(name == null ? "*" : name);
   }

   public function attribute(name:Dynamic):XMLList {
      var out:Array<XML> = [];
      for (x in items) {
         out = out.concat((x.attribute(name) : XMLListData).items);
      }
      return of(out);
   }

   public function descendants(?name:Dynamic = "*"):XMLList {
      var out:Array<XML> = [];
      for (x in items) {
         out = out.concat((x.descendants(name) : XMLListData).items);
      }
      return of(out);
   }

   public function text():XMLList {
      var out:Array<XML> = [];
      for (x in items) {
         out = out.concat((x.text() : XMLListData).items);
      }
      return of(out);
   }

   public function name():String {
      return items.length == 1 ? items[0].name() : null;
   }

   public function hasSimpleContent():Bool {
      return items.length == 0 || (items.length == 1 && items[0].hasSimpleContent());
   }

   public function copy():XMLList {
      return of([for (x in items) x.copy()]);
   }

   public function toXMLString():String {
      return [for (x in items) x.toXMLString()].join("\n");
   }

   public function toString():String {
      if (items.length == 1 || (items.length > 0 && Lambda.foreach(items, x -> x.kind == "attribute" || x.kind == "text"))) {
         return [for (x in items) x.toString()].join("");
      }
      return toXMLString();
   }
}

@:forward(items, length, iterator, child, children, elements, attribute, descendants, text, name, hasSimpleContent,
   copy, toXMLString, toString)
abstract XMLList(XMLListData) from XMLListData to XMLListData {
   public inline function new(?items:Array<XML> = null) {
      this = new XMLListData(items);
   }

   @:from static inline function fromArray(items:Array<XML>):XMLList {
      return new XMLListData(items);
   }

   @:arrayAccess public inline function get(index:Int):XML {
      return this.items[index];
   }

   @:arrayAccess public inline function set(index:Int, value:XML):XML {
      return this.items[index] = value;
   }

   @:op(A + B) static function concat(a:XMLList, b:XMLList):XMLList {
      return new XMLListData((a : XMLListData).items.concat((b : XMLListData).items));
   }
}

class E4XParser {
   var s:String;
   var p:Int;

   function new(s:String) {
      this.s = s;
      p = 0;
   }

   public static function typeError(message:String):Dynamic {
      #if (openfl || heaps || flash)
      throw new flash.errors.TypeError(message);
      #else
      throw message;
      #end
   }

   public static function parse(text:String):Array<XML> {
      var parser = new E4XParser(text);
      var root = XML.element("#root");
      parser.content(root, null);
      return [for (k in @:privateAccess root.kids) k];
   }

   function fail(what:String):Dynamic {
      return typeError("Error #1090: XML parser failure: " + what + " at " + p);
   }

   inline function at(text:String):Bool {
      return s.substr(p, text.length) == text;
   }

   function content(parent:XML, closing:String):Void {
      var text = new StringBuf();
      var hasText = false;
      inline function flushText() {
         if (hasText) {
            var t = text.toString();
            if (!XML.ignoreWhitespace || StringTools.trim(t) != "") {
               @:privateAccess parent.addParsed(XML.textNode(XML.ignoreWhitespace ? StringTools.trim(t) : t));
            }
            text = new StringBuf();
            hasText = false;
         }
      }
      while (p < s.length) {
         var c = s.charCodeAt(p);
         if (c != "<".code) {
            if (c == "&".code) {
               text.add(entity());
            } else {
               text.addChar(c);
               p++;
            }
            hasText = true;
            continue;
         }
         if (at("<![CDATA[")) {
            var end = s.indexOf("]]>", p + 9);
            if (end < 0) fail("unterminated CDATA");
            text.add(s.substring(p + 9, end));
            hasText = true;
            p = end + 3;
            continue;
         }
         flushText();
         if (at("</")) {
            var end = s.indexOf(">", p);
            if (end < 0) fail("unterminated end tag");
            var name = StringTools.trim(s.substring(p + 2, end));
            if (name != closing) fail("</" + name + "> where </" + closing + "> was expected");
            p = end + 1;
            return;
         }
         if (at("<!--")) {
            var end = s.indexOf("-->", p + 4);
            if (end < 0) fail("unterminated comment");
            if (!XML.ignoreComments) {
               @:privateAccess parent.addParsed(XML.textNode(s.substring(p + 4, end), "comment"));
            }
            p = end + 3;
            continue;
         }
         if (at("<?")) {
            var end = s.indexOf("?>", p + 2);
            if (end < 0) fail("unterminated processing instruction");
            var body = s.substring(p + 2, end);
            var space = body.indexOf(" ");
            var target = space < 0 ? body : body.substr(0, space);
            if (!XML.ignoreProcessingInstructions && target.toLowerCase() != "xml") {
               @:privateAccess parent.addParsed(XML.instruction(target, space < 0 ? "" : StringTools.trim(body.substr(space + 1))));
            }
            p = end + 2;
            continue;
         }
         if (at("<!")) {
            var depth = 0;
            while (p < s.length) {
               var d = s.charCodeAt(p++);
               if (d == "[".code) depth++;
               else if (d == "]".code) depth--;
               else if (d == ">".code && depth <= 0) break;
            }
            continue;
         }
         p++;
         var name = readName();
         var el = XML.element(name);
         while (true) {
            skipSpace();
            if (p >= s.length) fail("unterminated tag <" + name);
            if (at("/>")) {
               p += 2;
               @:privateAccess parent.addParsed(el);
               break;
            }
            if (s.charCodeAt(p) == ">".code) {
               p++;
               @:privateAccess parent.addParsed(el);
               content(el, name);
               break;
            }
            var attr = readName();
            skipSpace();
            if (s.charCodeAt(p) != "=".code) fail("attribute " + attr + " without a value");
            p++;
            skipSpace();
            var quote = s.charCodeAt(p);
            if (quote != '"'.code && quote != "'".code) fail("unquoted attribute " + attr);
            p++;
            var v = new StringBuf();
            while (p < s.length && s.charCodeAt(p) != quote) {
               if (s.charCodeAt(p) == "&".code) {
                  v.add(entity());
               } else {
                  v.addChar(s.charCodeAt(p++));
               }
            }
            p++;
            @:privateAccess el.addParsedAttribute(attr, v.toString());
         }
      }
      flushText();
      if (closing != null) fail("unterminated element <" + closing + ">");
   }

   function skipSpace():Void {
      while (p < s.length && StringTools.isSpace(s, p)) {
         p++;
      }
   }

   function readName():String {
      var start = p;
      while (p < s.length) {
         var c = s.charCodeAt(p);
         if (StringTools.isSpace(s, p) || c == ">".code || c == "/".code || c == "=".code) break;
         p++;
      }
      if (p == start) fail("a name was expected");
      return s.substring(start, p);
   }

   function entity():String {
      var end = s.indexOf(";", p);
      if (end < 0 || end - p > 10) {
         p++;
         return "&";
      }
      var name = s.substring(p + 1, end);
      p = end + 1;
      return switch (name) {
         case "lt": "<";
         case "gt": ">";
         case "amp": "&";
         case "quot": '"';
         case "apos": "'";
         default:
            if (StringTools.startsWith(name, "#x")) String.fromCharCode(Std.parseInt("0x" + name.substr(2)));
            else if (StringTools.startsWith(name, "#")) String.fromCharCode(Std.parseInt(name.substr(1)));
            else "&" + name + ";";
      }
   }
}
#end
