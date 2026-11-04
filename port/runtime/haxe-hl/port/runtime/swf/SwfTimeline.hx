package port.runtime.swf;

import openfl.display.DisplayObject;
import openfl.display.FrameLabel;
import openfl.display.MovieClip;
import openfl.display.Scene;
import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.display.Timeline;
import openfl.text.AntiAliasType;
import openfl.text.GridFitType;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFieldType;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import port.runtime.swf.SwfLibrary.PlaceState;
import port.runtime.swf.SwfLibrary.SpriteDef;

@:access(openfl.display.Timeline)
class SwfTimeline extends Timeline {
    static var instanceCount = 0;

    var library:SwfLibrary;
    var def:SpriteDef;
    var target:Sprite;
    var objects:FastIntMap<{state:PlaceState, object:DisplayObject}> = new FastIntMap();

    public function new(library:SwfLibrary, def:SpriteDef) {
        super();
        this.library = library;
        this.def = def;
        frameRate = null;
        var labels = [for (label in def.labels) new FrameLabel(label.name, label.frame)];
        scenes = [new Scene("", labels, def.frames.length > 0 ? def.frames.length : 1)];
    }

    override public function attachMovieClip(movieClip:MovieClip):Void {
        target = movieClip;
        enterFrame(1);
    }

    override public function initializeSprite(sprite:Sprite):Void {
        target = sprite;
        enterFrame(1);
    }

    override public function enterFrame(frame:Int):Void {
        if (target == null || def.frames.length == 0) return;
        if (frame < 1) frame = 1;
        if (frame > def.frames.length) frame = def.frames.length;
        var states = def.frames[frame - 1];
        var keep = new FastIntMap<Bool>();
        for (state in states) keep.set(state.depth, true);
        for (depth in [for (k in objects.keys()) k]) {
            if (!keep.exists(depth)) {
                var old = objects.get(depth);
                if (old.object.parent == target) target.removeChild(old.object);
                forget(old.object);
                objects.remove(depth);
            }
        }
        var previous:DisplayObject = null;
        for (state in states) {
            var entry = objects.get(state.depth);
            if (entry != null && entry.state.serial != state.serial) {
                if (entry.object.parent == target) target.removeChild(entry.object);
                forget(entry.object);
                objects.remove(state.depth);
                entry = null;
            }
            if (entry == null) {
                var object = create(state.charId);
                entry = {state: null, object: object};
                objects.set(state.depth, entry);
                var index = previous != null && previous.parent == target ? target.getChildIndex(previous) + 1 : 0;
                target.addChildAt(object, index);
            }
            if (entry.state != state) {
                if (entry.state != null) unset(entry.object, entry.state, state);
                apply(entry.object, state);
                entry.state = state;
            }
            previous = entry.object;
        }
        applyMasks(states);
    }

    var masked:Map<DisplayObject, DisplayObject> = new Map();

    function applyMasks(states:Array<PlaceState>) {
        var wanted = new Map<DisplayObject, DisplayObject>();
        for (state in states) {
            if (state.clipDepth <= 0) continue;
            var mask = objects.get(state.depth);
            if (mask == null) continue;
            for (other in states) {
                if (other.depth > state.depth && other.depth <= state.clipDepth) {
                    var entry = objects.get(other.depth);
                    if (entry != null) wanted.set(entry.object, mask.object);
                }
            }
        }
        for (object => mask in masked) {
            if (!wanted.exists(object) && object.mask == mask) object.mask = null;
        }
        for (object => mask in wanted) {
            if (object.mask != mask) object.mask = mask;
        }
        masked = wanted;
    }

    function apply(object:DisplayObject, state:PlaceState) {
        if (state.matrix != null) {
            if (Std.isOfType(object, EditTextField)) {
                var field:EditTextField = cast object;
                var m = state.matrix.clone();
                m.tx += m.a * field.originX + m.c * field.originY;
                m.ty += m.b * field.originX + m.d * field.originY;
                object.transform.matrix = m;
            } else {
                object.transform.matrix = state.matrix;
            }
        }
        if (state.colorTransform != null) object.transform.colorTransform = state.colorTransform;
        if (state.filters != null) object.filters = [for (f in state.filters) f.clone()];
        if (state.blendMode >= 2) object.blendMode = blendModeOf(state.blendMode);
        if (state.name != null) {
            object.name = state.name;
            var names:Dynamic = @:privateAccess target.__portTimelineNames;
            if (names == null) {
                names = {};
                @:privateAccess target.__portTimelineNames = names;
            }
            Reflect.setField(names, state.name, object);
        }
        if (state.visible >= 0) object.visible = state.visible == 1;
        if (Std.isOfType(object, MorphShape)) {
            var morph:MorphShape = cast object;
            if (morph.ratio != state.ratio && library.drawMorph(morph.charId, state.ratio, morph.graphics)) {
                morph.ratio = state.ratio;
            }
        }
    }

    function unset(object:DisplayObject, was:PlaceState, now:PlaceState):Void {
        if (now.colorTransform == null && was.colorTransform != null) object.transform.colorTransform = new openfl.geom.ColorTransform();
        if (now.filters == null && was.filters != null) object.filters = [];
        if (now.blendMode < 2 && was.blendMode >= 2) object.blendMode = NORMAL;
        if (now.visible < 0 && was.visible == 0) object.visible = true;
    }

    function forget(object:DisplayObject):Void {
        var names:Dynamic = @:privateAccess target.__portTimelineNames;
        if (names != null && object.name != null && Reflect.field(names, object.name) == object)
            Reflect.deleteField(names, object.name);
    }

    static function blendModeOf(mode:Int):openfl.display.BlendMode {
        return switch (mode) {
            case 2: LAYER;
            case 3: MULTIPLY;
            case 4: SCREEN;
            case 5: LIGHTEN;
            case 6: DARKEN;
            case 7: DIFFERENCE;
            case 8: ADD;
            case 9: SUBTRACT;
            case 10: INVERT;
            case 11: ALPHA;
            case 12: ERASE;
            case 13: OVERLAY;
            case 14: HARDLIGHT;
            default: NORMAL;
        }
    }

    function create(charId:Int):DisplayObject {
        switch (library.kindOf(charId)) {
            case Sprite:
                var sprite = library.sprite(charId);
                var clip = MovieClip.fromTimeline(new SwfTimeline(library, sprite));
                clip.name = "instance" + (++instanceCount);
                return clip;
            case EditText:
                return editText(library.editText(charId));
            case Shape:
                if (library.isMorph(charId)) {
                    var morph = new MorphShape(charId);
                    morph.name = "instance" + (++instanceCount);
                    return morph;
                }
                var shape = library.shape(charId);
                if (shape != null) {
                    shape.name = "instance" + (++instanceCount);
                    return shape;
                }
                return placeholder(library.shapeBounds(charId));
            default:
                var shape = new Shape();
                shape.name = "instance" + (++instanceCount);
                return shape;
        }
    }

    static function placeholder(b:SwfLibrary.Bounds):DisplayObject {
        var shape = new Shape();
        shape.name = "instance" + (++instanceCount);
        if (b != null && b.xMax > b.xMin && b.yMax > b.yMin) {
            shape.graphics.beginFill(0, 0);
            shape.graphics.drawRect(b.xMin, b.yMin, b.xMax - b.xMin, b.yMax - b.yMin);
            shape.graphics.endFill();
        }
        return shape;
    }

    public static function editText(def:SwfLibrary.EditTextDef):TextField {
        var tf = new EditTextField(def.bounds.xMin, def.bounds.yMin);
        tf.name = "instance" + (++instanceCount);
        var format = new TextFormat(def.font, Math.round(def.size), def.color, def.bold, def.italic);
        format.align = switch (def.align) {
            case 1: TextFormatAlign.RIGHT;
            case 2: TextFormatAlign.CENTER;
            case 3: TextFormatAlign.JUSTIFY;
            default: TextFormatAlign.LEFT;
        }
        format.leftMargin = Math.round(def.leftMargin);
        format.rightMargin = Math.round(def.rightMargin);
        format.indent = Math.round(def.indent);
        format.leading = Math.round(def.leading);
        tf.defaultTextFormat = format;
        tf.multiline = def.multiline;
        tf.wordWrap = def.wordWrap;
        tf.displayAsPassword = def.password;
        tf.selectable = !def.noSelect;
        tf.border = def.border;
        tf.type = def.readOnly ? TextFieldType.DYNAMIC : TextFieldType.INPUT;
        if (def.maxChars > 0) tf.maxChars = def.maxChars;
        if (def.settings != null) {
            tf.antiAliasType = def.settings.advanced ? AntiAliasType.ADVANCED : AntiAliasType.NORMAL;
            tf.gridFitType = switch (def.settings.gridFit) {
                case 1: GridFitType.PIXEL;
                case 2: GridFitType.SUBPIXEL;
                default: GridFitType.NONE;
            }
            tf.sharpness = def.settings.sharpness;
        }
        tf.width = def.bounds.xMax - def.bounds.xMin;
        tf.height = def.bounds.yMax - def.bounds.yMin;
        if (def.text != null) {
            if (def.html) tf.htmlText = def.text else tf.text = def.text;
        }
        if (def.autoSize) tf.autoSize = def.align == 1 ? TextFieldAutoSize.RIGHT : def.align == 2 ? TextFieldAutoSize.CENTER
            : TextFieldAutoSize.LEFT;
        return tf;
    }
}

class EditTextField extends TextField {
    public var originX:Float;
    public var originY:Float;

    public function new(originX:Float, originY:Float) {
        super();
        this.originX = originX;
        this.originY = originY;
    }
}

class MorphShape extends Shape {
    public var charId:Int;
    public var ratio:Int = -1;

    public function new(charId:Int) {
        super();
        this.charId = charId;
    }
}
