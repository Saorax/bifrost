package flash.errors;

class TypeError extends flash.errors.Error {
	public function new(message:String = "") {
		super(message, 0);
		name = "TypeError";
	}
}
