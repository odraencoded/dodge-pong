// Utility functions/classes/etc
import std.math;

// Directions, for directional stuff
enum Direction {
	North  = 0,
	East   = 1,
	South  = 2,
	West   = 3,
}

// Turning values for the PongerSwing
enum Turning {
	Clockwise,
	CounterClockwise
}

// Utility to do the collisions
struct Box {
	double left, top, width, height;
	this(in double left, in double top, in double width, in double height) pure {
		this.left = left; this.top = top;
		this.width = width; this.height = height;
	}
	
	@property {
		double right() pure const { return left + width; }
		void right(in double value) pure { left = value - width; }
		
		double bottom() pure const { return top + height; }
		void bottom(in double value) pure { top = value - height; }
	}
	
	Box dup() pure const { return Box(left, top, width, height); }
	
	Box shift(in double x, in double y) pure const {
		return Box(left + x, top + y, width, height);
	}
	
	bool intersectsWith(in Box b) pure const {
		return !(
			left           > b.left + b.width  ||
			left + width  <= b.left            ||
			top            > b.top  + b.height ||
			top  + height <= b.top
		);
	}
	
	bool[4] getPartsOutside(in Box container) pure const {
		bool[4] result;
		result[Direction.North] = top     < container.top   ;
		result[Direction.East ] = right  >= container.right ;
		result[Direction.South] = bottom >= container.bottom;
		result[Direction.West ] = left    < container.left  ;
		return result;
	}
	
	// Tries to place this box inside another box
	Box moveInside(in Box container) pure const {
		Box result = dup();
		if(left    < container.left  ) result.left   = container.left;
		if(right  >= container.right ) result.right  = container.right;
		if(bottom >= container.bottom) result.bottom = container.bottom;
		if(top     < container.top   ) result.top    = container.top;
		return result;
	}
}

// Caps a value between a min and a max
void cap(ref double value, in double  bottom, in double top) pure nothrow {
	value = value > bottom ? (value < top ? value : top) : bottom ;
}


// Normalizes a vector
void normalize(in double x, in double y,
               out double nx, out double ny, out double l) pure nothrow {
		l = vectorLength(x, y);
		if(l == 0) {
			nx = 0;
			ny = 0;
		} else {
			nx = x / l;
			ny = y / l;
		}
}


// Returns the length of a vector
double vectorLength(in double x, in double y) pure nothrow {
	return sqrt(x * x + y * y);
}