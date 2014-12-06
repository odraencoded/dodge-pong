// Main file for DodgePong

import std.stdio;
import std.math;
import std.array;
import random = std.random;

import dsfml.graphics;
import dsfml.system;

enum GAME_WIDTH = 600;
enum GAME_HEIGHT = 600;
enum GAME_TITLE = "Dodge Pong";

enum BACKGROUND_COLOR = Color(32, 32, 32, 255);

// Key bindings
enum GO_NORTH_KEY = Keyboard.Key.Up;
enum GO_EAST_KEY  =  Keyboard.Key.Right;
enum GO_SOUTH_KEY = Keyboard.Key.Down;
enum GO_WEST_KEY  = Keyboard.Key.Left;
enum SWING_CW_KEY = Keyboard.Key.D;
enum SWING_CCW_KEY = Keyboard.Key.A;

// Ponger directional input map
enum NORTH = 0;
enum EAST  = 1;
enum SOUTH = 2;
enum WEST  = 3;

// Player maxiumum velocity in units per second
enum PONGER_VELOCITY_CAP = 400;
// Stops the player in .2 seconds
enum PONGER_FRICTION = PONGER_VELOCITY_CAP / .2;
// Goes full speed in .2 seconds
enum PONGER_ACCEL = PONGER_VELOCITY_CAP / .2 + PONGER_FRICTION;

enum BALL_START_SPEED = 600 / .5;

immutable PONGER_HITBOX = Box(-10, -12, 20, 25);
immutable BALL_HITBOX = Box(-4, -4, 8, 8);

enum BALL_STEP_SIZE = 10.0;
enum BALL_STEP_THRESHOLD = .2;
enum TRACE_LIFE = 0.4;
enum TRACE_INTERVAL = 6;


void main(string[] args) {
	// Setup game
	auto game = new DodgePong();
	game.isRunning = true;
	
	// Start main loop
	auto frameClock = new dsfml.system.Clock();
	while(true) {
		// Get this frame delta time
		immutable double frameDelta = frameClock.restart().asSeconds();
		
		PlayerInput* playerInput;
		game.gatherInput(playerInput);
		game.processInput(playerInput);
		
		// Exit when the game stops running
		if(game.isRunning == false) {
			game.window.close();
			break;
		}
		
		// Logic part of the logic/draw cycle
		game.update(frameDelta);
		
		// Render game
		game.window.draw(game);
		game.window.display();
		
		// Clean up after each frame
		import core.memory : GC;
		GC.collect();
	}
}

// The game class
class DodgePong : Drawable {
	// Need this to draw stuff
	RenderWindow window;
	bool isRunning = false;
	Direction[int] keyDirectionalMap;
	
	// A.K.A. the player
	Ponger ponger;
	Ball ball;
	
	// Playable area of the game
	Box playBoundaries;
	
	this() {
		// Setup window
		auto videoMode = VideoMode(GAME_WIDTH, GAME_HEIGHT);
		window = new RenderWindow(videoMode, GAME_TITLE);
		
		// Setup key map
		keyDirectionalMap[GO_NORTH_KEY] = Direction.North;
		keyDirectionalMap[GO_EAST_KEY]  = Direction.East ;
		keyDirectionalMap[GO_SOUTH_KEY] = Direction.South;
		keyDirectionalMap[GO_WEST_KEY]  = Direction.West ;
		keyDirectionalMap.rehash();
		
		playBoundaries = Box(0, 0, GAME_WIDTH, GAME_HEIGHT);
		
		// Start up player
		ponger = new Ponger();
		ponger.x = GAME_WIDTH / 2;
		ponger.y = GAME_HEIGHT / 5 * 4;
		
		// Start up ball
		ball = new Ball();
		ball.x = GAME_WIDTH / 2;
		ball.y = GAME_HEIGHT / 5 * 1;
		
		auto startAngle = random.uniform(20.0, 70.0) * random.uniform(0, 3);
		ball.vel_x = cos(startAngle / 180 * PI) * BALL_START_SPEED;
		ball.vel_y = sin(startAngle / 180 * PI) * BALL_START_SPEED;
		
	}
	
	
	// Gets input done by the player and stores it in a PlayerInput structure
	void gatherInput(out PlayerInput* playerInput) {
		import dsfml.window: Event, Keyboard, Mouse;
		Event event;
		
		playerInput = new PlayerInput;
		
		while(window.pollEvent(event)) {
			switch(event.type) {
				// Close window
				case(Event.EventType.Closed):
					playerInput.closedWindow = true;
					break;
				
				// Resize view
				case(Event.EventType.Resized):
					break;
				
				// Register input
				case(Event.EventType.KeyPressed):
					immutable auto keyCode = event.key.code;
					playerInput.pressedKey[keyCode] = true;
					break;
				
				case(Event.EventType.KeyReleased):
					immutable auto keyCode = event.key.code;
					playerInput.releasedKey[keyCode] = true;
					break;
				
				case(Event.EventType.MouseButtonPressed):
					immutable auto buttonCode = event.mouseButton.button;
					playerInput.pressedButton[buttonCode] = true;
					break;
				
				case(Event.EventType.MouseButtonReleased):
					immutable auto buttonCode = event.mouseButton.button;
					playerInput.releasedButton[buttonCode] = true;
					break;
				
				case(Event.EventType.LostFocus):
					playerInput.lostFocus = true;
					break;
				
				default:
			}
		}
	}
	
	
	// Processes player input
	void processInput(in PlayerInput* playerInput) {
		if(playerInput.closedWindow) {
			isRunning = false;
		}
		
		// Figure out where the player is going
		foreach(int key, Direction direction; keyDirectionalMap) {
			if(playerInput.pressedKey.get(key, false)) {
				ponger.going[direction] = true;
				ponger.facing = direction;
			}
			
			if(playerInput.releasedKey.get(key, false)) {
				ponger.going[direction] = false;
			}
		}
		
		ponger.computeGoing(ponger.going, ponger.going_x, ponger.going_y);
	}
	
	
	// Updates game variables based on time
	void update(in double delta) {
		updatePonger(delta);
		updateBall(delta);
	}
	
	void updatePonger(in double delta) {
		// Update ponger
		ponger.updateSpeed(delta);
		
		ponger.x += ponger.vel_x * delta;
		ponger.y += ponger.vel_y * delta;
		
		// Boundary collision
		Box hitbox = ponger.getHitbox();
		Box containedBox = hitbox.moveInside(playBoundaries);
		
		// Update based on offset
		ponger.x += containedBox.left - hitbox.left;
		ponger.y += containedBox.top - hitbox.top;
	}
	
	void updateBall(in double delta) {
		double distanceLeft = vectorLength(ball.vel_x * delta, ball.vel_y * delta);
		
		do {
			double nvx, nvy, vel;
			normalize(ball.vel_x * delta, ball.vel_y * delta, nvx, nvy, vel);
			
			double step = distanceLeft;
			step.cap(0, BALL_STEP_SIZE);
			
			// Remember position
			auto px = ball.x;
			auto py = ball.y;
			
			// Spin ball
			auto angle = atan2(ball.vel_y, ball.vel_x);
			angle += ball.vel_angle * delta * (step / distanceLeft);
			nvx = cos(angle);
			nvy = sin(angle);
			ball.vel_x = nvx * vel / delta;
			ball.vel_y = nvy * vel / delta;
			
			// Move the ball
			ball.x += nvx * step;
			ball.y += nvy * step;
			
			// Check collision
			Box hitbox = ball.getHitbox();
			Box containedBox = hitbox.moveInside(playBoundaries);
			
			if(hitbox != containedBox) {
				ball.x += containedBox.left - hitbox.left;
				ball.y += containedBox.top - hitbox.top;
				
				double rotate = 0;
				
				bool[4] partsOutside = hitbox.getPartsOutside(playBoundaries);
				if(partsOutside[NORTH] || partsOutside[SOUTH]) {
					ball.vel_y *= -1;
					if(partsOutside[NORTH]) {
						rotate -= ball.vel_x;
					} else {
						rotate += ball.vel_x;
					}
				}
				if(partsOutside[WEST] || partsOutside[EAST]) {
					ball.vel_x *= -1;
					if(partsOutside[WEST]) {
						rotate -= ball.vel_y;
					} else {
						rotate += ball.vel_y;
					}
				}
				
				rotate /= vel / delta;
				ball.vel_angle += rotate * PI / 4;
				ball.vel_angle.cap(-PI/4, PI/4);

				// Spin ball
				angle = atan2(ball.vel_y, ball.vel_x);
				auto angle_change = PI / (16 - abs(rotate) * 6);
				angle += random.uniform(-angle_change, angle_change);
				
				nvx = cos(angle);
				nvy = sin(angle);
				
				ball.vel_x = nvx * vel / delta;
				ball.vel_y = nvy * vel / delta;
			}
			
			// Calculate displacement
			auto dx = ball.x - px;
			auto dy = ball.y - py;
			auto dl = vectorLength(dx, dy);
			
			distanceLeft -= dl;
			ball.addTraceFrom(px, py);
			
		} while(distanceLeft > BALL_STEP_THRESHOLD);
		
		// Age particles
		int cut = -1;
		auto particles = ball.traceParticles;
		for(int i = particles.length - 1; i >= 0; i--) {
			auto p = &particles[i];
			p.life -= delta;
			if(p.life <= 0) {
				cut = i;
				break;
			}
		}
		
		if(cut != -1) {
			ball.traceParticles = array(ball.traceParticles[cut + 1..$]);
		}
	}
	
	// Render game
	override void draw(RenderTarget renderTarget, RenderStates states) {
		renderTarget.clear(BACKGROUND_COLOR);
		renderPlayer(renderTarget, states);
		renderBall(renderTarget, states);
	}
	
	
	void renderPlayer(RenderTarget renderTarget, RenderStates states) {
		// Rendering the player
		enum PLAYER_HEIGHT = 40;
		enum PLAYER_WIDTH = 35;
		enum PLAYER_SIZE = Vector2f(PLAYER_WIDTH, PLAYER_HEIGHT);
		
		Transform t = Transform.Identity;
		t.translate(ponger.x, ponger.y);
		t.translate(-PLAYER_WIDTH / 2, -PLAYER_HEIGHT / 2);
		
		auto pongerSprite = new RectangleShape(PLAYER_SIZE);
		pongerSprite.fillColor = Color(255, 255, 255);
		
		states.transform = t;
		renderTarget.draw(pongerSprite, states);
		
		// Draw facing(change this later)
		enum FACING_WIDTH = 8;
		auto facingSprite = new RectangleShape(PLAYER_SIZE);
		
		if(ponger.facing == Direction.North) {
			facingSprite.size = Vector2f(PLAYER_WIDTH, FACING_WIDTH);
		} else if(ponger.facing == Direction.East) {
			facingSprite.size = Vector2f(FACING_WIDTH, PLAYER_HEIGHT);
			t.translate(PLAYER_WIDTH - FACING_WIDTH, 0);
		} else if(ponger.facing == Direction.South) {
			facingSprite.size = Vector2f(PLAYER_WIDTH, FACING_WIDTH);
			t.translate(0, PLAYER_HEIGHT - FACING_WIDTH);
		} else if(ponger.facing == Direction.West) {
			facingSprite.size = Vector2f(FACING_WIDTH, PLAYER_HEIGHT);
		}
		
		facingSprite.fillColor = Color(255, 0, 0);
		
		states.transform = t;
		renderTarget.draw(facingSprite, states);
	}
	
	
	void renderBall(RenderTarget renderTarget, RenderStates states) {
		Transform t;
		
		// Rendering of the ball
		enum BALL_RADIUS = 5;
		
		// Rendering particles
		auto particleSprite = new CircleShape(BALL_RADIUS);
		foreach(const TracePartcile p; ball.traceParticles) {
			t = Transform.Identity;
			t.translate(p.x, p.y);
			t.translate(-BALL_RADIUS, -BALL_RADIUS);
			
			auto scale = p.life / TRACE_LIFE;
			t.scale(.6 + .4 * scale, .6 + .4 * scale);
			particleSprite.fillColor = Color(
				cast(ubyte)(255 * scale),
				255,
				cast(ubyte)(255* scale),
				cast(ubyte)(255 * scale)
			);
			
			states.transform = t;
			renderTarget.draw(particleSprite, states);
		}
		
		// Rendering of the ball
		t = Transform.Identity;
		t.translate(ball.x, ball.y);
		t.translate(-BALL_RADIUS, -BALL_RADIUS);
		
		auto ballSprite = new CircleShape(BALL_RADIUS);
		ballSprite.fillColor = Color(255, 255, 255);
		
		states.transform = t;
		renderTarget.draw(ballSprite, states);
	}
}


// Used to store game input
struct PlayerInput {
	bool closedWindow = false;
	bool lostFocus = false;
	bool[int] pressedKey, releasedKey;
	bool[int] pressedButton, releasedButton;
}


// Represents the player
class Ponger {
	// Position in the game
	double x, y;
	
	// Swing!!!
	PongerSwing* swing;
	
	// Movement rate
	double vel_x = 0, vel_y = 0;
	
	// Where the ponger is going, relative coordinates -1..1
	int going_x, going_y;
	int[4] going = [false, false, false, false];
	Direction facing = Direction.North;
	
	// Gets the ponger's hitbox
	Box getHitbox() pure const @property {
		return PONGER_HITBOX.shift(x, y);
	}
	
	void computeGoing(in int[4] going, out int x, out int y) pure const {
		if(going[NORTH]) y -= 1;
		if(going[EAST]) x += 1;
		if(going[SOUTH]) y += 1;
		if(going[WEST]) x -= 1;
	}
	
	
	void updateSpeed(in double delta) pure {
		// Apply friction
		auto vel = sqrt(vel_x * vel_x + vel_y * vel_y);
		if(vel != 0) {
			// Normalize
			auto nx = vel_x / vel;
			auto ny = vel_y / vel;
			// Slow down
			vel -= PONGER_FRICTION * delta;
			cap(vel, 0, vel);
			// De-normalize
			vel_x = nx * vel;
			vel_y = ny * vel;
		}
		
		// Increase velocity based on input
		vel_x += going_x * delta * PONGER_ACCEL;
		vel_y += going_y * delta * PONGER_ACCEL;
		
		// Cap velocity
		cap(vel_x, -PONGER_VELOCITY_CAP, PONGER_VELOCITY_CAP);
		cap(vel_y, -PONGER_VELOCITY_CAP, PONGER_VELOCITY_CAP);
	}
}

// Representing a swing from the ponger
struct PongerSwing {
	Direction direction;
	double duration;
}


// Swing direction
enum Direction {
	North  = 0,
	East   = 1,
	South  = 2,
	West   = 3,
	
	Clockwise,
	CounterClockwise
}


// Represents the ball
class Ball {
	// Position in the game
	double x, y;
	
	// Movement rate
	double vel_x = 0, vel_y = 0;
	double vel_angle = 0;
	
	// The trace left by the ball
	TracePartcile[] traceParticles;
	double traceRemainder = 0;
	
	Box getHitbox() pure const {
		return BALL_HITBOX.shift(x, y);
	}
	
	void addTraceFrom(in double fx, in double fy) pure {
		// Calculate displacement
		auto dx = x - fx;
		auto dy = y - fy;
		
		// Normalize difference
		double nx, ny, distance;
		normalize(dx, dy, nx, ny, distance);
		
		auto traceLength = traceRemainder + distance;
		auto particleCount = traceLength / TRACE_INTERVAL;
		for(int i = 1; i <= particleCount; i++) {
			auto progress = TRACE_INTERVAL * i - traceRemainder;
			TracePartcile newParticle;
			newParticle.x = fx + nx * progress;
			newParticle.y = fy + ny * progress;
			newParticle.life = TRACE_LIFE;
			traceParticles ~= newParticle;
		}
		
		// Update remainder
		traceRemainder = (traceRemainder + distance) % TRACE_INTERVAL;
	}
}


struct TracePartcile {
	double x, y, life;
}

// Utility to cap a value
void cap(ref double value, in double  bottom, in double top) pure nothrow {
	value = value > bottom ? (value < top ? value : top) : bottom ;
}

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

double vectorLength(in double x, in double y) pure nothrow {
	return sqrt(x * x + y * y);
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
	
	bool[4] getPartsOutside(in Box container) pure const {
		bool[4] result;
		result[NORTH] = top     < container.top;
		result[EAST]  = right  >= container.right;
		result[SOUTH] = bottom >= container.bottom;
		result[WEST]  = left    < container.left;
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


