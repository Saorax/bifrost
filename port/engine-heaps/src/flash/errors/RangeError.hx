package flash.errors;

class RangeError extends flash.errors.Error {
	public function new(message:String = "") {
		super(message, 0);
		name = "RangeError";
	}
}
