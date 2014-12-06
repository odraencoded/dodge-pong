// Main file for DodgePong
import std.stdio;
import std.math;
import std.array;
import random = std.random;

import dsfml.graphics;
import dsfml.system;

import utility;

enum GAME_WIDTH = 600;
enum GAME_HEIGHT = 600;
enum GAME_TITLE = "Dodge Pong";

enum BACKGROUND_COLOR = Color(32, 32, 32, 255);

// Key bindings
enum GO_NORTH_KEY = Keyboard.Key.Up;
enum GO_EAST_KEY  =  Keyboard.Key.Right;
enum GO_SOUTH_KEY = Keyboard.Key.Down;
enum GO_WEST_KEY  = Keyboard.Key.Left;
enum SWING_CCW_KEY = Keyboard.Key.D;
enum SWING_CW_KEY = Keyboard.Key.A;
enum NEW_GAME_KEY = Keyboard.Key.N;

// Player maxiumum velocity in units per second
enum PONGER_VELOCITY_CAP = 400;
// Stops the player in .2 seconds
enum PONGER_FRICTION = PONGER_VELOCITY_CAP / .2;
// Goes full speed in .2 seconds
enum PONGER_ACCEL = PONGER_VELOCITY_CAP / .2 + PONGER_FRICTION;

enum BALL_START_SPEED = 600 / .5;
enum BALL_ANGULAR_FRICTION = PI; // Pretty sure this isn't a thing.
enum SWING_ANGULAR_POWER = 1;

immutable PONGER_HITBOX = Box(-20, -17, 34, 40);
immutable BALL_HITBOX = Box(-4, -4, 8, 8);

enum BALL_STEP_SIZE = 10.0;
enum BALL_STEP_THRESHOLD = .2;
enum BALL_STRIKE_SHIELD_DURATION = .1;

enum TRACE_LIFE = 0.4;
enum TRACE_INTERVAL = 6;

enum SWING_MAX_DURATION = 0.15;

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
	
	// Whether the game has started
	bool gameStarted;
	
	
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
		
		newGame();
	}
	
	void newGame() {
		gameStarted = false;
		
		// Start up player
		ponger = new Ponger();
		ponger.x = GAME_WIDTH / 2;
		ponger.y = GAME_HEIGHT / 5 * 4;
		
		// Start up ball
		ball = new Ball();
		ball.x = GAME_WIDTH / 2;
		ball.y = GAME_HEIGHT / 2;
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
		
		if(playerInput.pressedKey.get(SWING_CW_KEY, false)) {
			ponger.swing = new PongerSwing();
			ponger.swing.direction = Turning.Clockwise;
		}
		
		if(playerInput.pressedKey.get(SWING_CCW_KEY, false)) {
			ponger.swing = new PongerSwing();
			ponger.swing.direction = Turning.CounterClockwise;
		}
		
		if(playerInput.pressedKey.get(NEW_GAME_KEY, false)) {
			newGame();
		}
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
		
		auto swing = ponger.swing;
		if(swing) {
			swing.duration += delta;
			if(swing.duration > SWING_MAX_DURATION) {
				ponger.swing = null;
			}
		}
	}
	
	
	void updateBall(in double delta) {
		double distance = vectorLength(ball.vel_x * delta, ball.vel_y * delta);
		double distanceLeft = distance;
		
		do {
			// How much will be done this iteration
			double step = distanceLeft;
			step.cap(0, BALL_STEP_SIZE);
			double subDelta = delta * (step / distance);
			
			// Normalize velocity vector
			double nvx, nvy, vel;
			normalize(ball.vel_x, ball.vel_y, nvx, nvy, vel);
			
			// Remember current position
			auto px = ball.x;
			auto py = ball.y;
			
			// Remove strike shield
			if(ball.strikeShield > 0) {
				ball.strikeShield -= subDelta;
			}
			
			// Remove angular velocity
			if(ball.vel_angle > 0) {
				ball.vel_angle -= BALL_ANGULAR_FRICTION * subDelta;
				ball.vel_angle.cap(0, ball.vel_angle);
			} else if(ball.vel_angle < 0) {
				ball.vel_angle += BALL_ANGULAR_FRICTION * subDelta;
				ball.vel_angle.cap(ball.vel_angle, 0);
			}
			
			// Spin ball
			if(step > 0) {
				auto angle = atan2(ball.vel_y, ball.vel_x);
				angle += ball.vel_angle * subDelta;
				nvx = cos(angle);
				nvy = sin(angle);
				ball.vel_x = nvx * vel;
				ball.vel_y = nvy * vel;
				
				// Move the ball
				ball.x += nvx * step;
				ball.y += nvy * step;
			}
			
			// Check collision
			Box hitbox = ball.getHitbox();
			
			// Striking the ball
			auto swing = ponger.swing;
			if(swing) {
				auto swingHitbox = swing.getHitbox(ponger);
				if(hitbox.intersectsWith(swingHitbox)) {
					// STRIKE!!!
					if(ball.strikeShield <= 0) {
						// Calculate angle between the ball and the swing's "pivot"
						double sx, sy;
						swing.getPivot(ponger, sx, sy);
						
						double dx = ball.x - sx;
						double dy = ball.y - sy;
						
						double ndx, ndy, dl;
						normalize(dx, dy, ndx, ndy, dl);
						
						// Mixing vectors
						nvx = nvx + ndx * 3;
						nvy = nvy + ndy * 3;
						
						normalize(nvx, nvy, nvx, nvy, dl);
						
						// Adding angular velocity
						double angle = atan2(dy, dx);
						ball.vel_angle += angle * SWING_ANGULAR_POWER;
						
						// Setting velocities
						if(gameStarted) {
							// Strike the ball normally
							ball.vel_x = nvx * vel;
							ball.vel_y = nvy * vel;
						} else {
							// Set the start speed for the ball
							ball.vel_x = nvx * BALL_START_SPEED;
							ball.vel_y = nvy * BALL_START_SPEED;
						}
					}
					
					ball.strikeShield = BALL_STRIKE_SHIELD_DURATION;
				}
			}
			
			// Keeping the ball inside the game
			Box containedBox = hitbox.moveInside(playBoundaries);
			
			if(hitbox != containedBox) {
				ball.x += containedBox.left - hitbox.left;
				ball.y += containedBox.top - hitbox.top;
				
				double rotate = 0;
				
				bool[4] partsOutside = hitbox.getPartsOutside(playBoundaries);
				if(partsOutside[Direction.North] || partsOutside[Direction.South]) {
					ball.vel_y *= -1;
					if(partsOutside[Direction.North]) {
						rotate -= ball.vel_x;
					} else {
						rotate += ball.vel_x;
					}
				}
				if(partsOutside[Direction.West] || partsOutside[Direction.East]) {
					ball.vel_x *= -1;
					if(partsOutside[Direction.West]) {
						rotate -= ball.vel_y;
					} else {
						rotate += ball.vel_y;
					}
				}
			}
			
			// Calculate displacement
			auto dx = ball.x - px;
			auto dy = ball.y - py;
			auto dl = vectorLength(dx, dy);
			
			distanceLeft -= dl;
			ball.addTraceFrom(px, py);
			
		} while(distanceLeft > BALL_STEP_THRESHOLD);
		
		updateBallParticles(delta);
		
	}
	
	void updateBallParticles(in double delta) {
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
		enum PLAYER_WIDTH = PONGER_HITBOX.width;
		enum PLAYER_HEIGHT = PONGER_HITBOX.height;
		enum PLAYER_SIZE = Vector2f(PLAYER_WIDTH, PLAYER_HEIGHT);
		
		Transform t = Transform.Identity;
		t.translate(ponger.x, ponger.y);
		t.translate(PONGER_HITBOX.left, PONGER_HITBOX.top);
		
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
		
		// Rendering swing
		auto swing = ponger.swing;
		if(swing) {
			auto hitbox = swing.getHitbox(ponger);
			auto hitboxSize = Vector2f(hitbox.width, hitbox.height);
			auto swingingSprite = new RectangleShape(hitboxSize);
			
			swingingSprite.fillColor = Color(255, 255, 0);
			
			t = Transform.Identity;
			//t.translate(ponger.x, ponger.y);
			//t.translate(-PLAYER_WIDTH / 2, -PLAYER_HEIGHT / 2);
			t.translate(hitbox.left, hitbox.top);
			states.transform = t;
			renderTarget.draw(swingingSprite, states);
		}
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
		if(going[Direction.North]) y -= 1;
		if(going[Direction.East ]) x += 1;
		if(going[Direction.South]) y += 1;
		if(going[Direction.West ]) x -= 1;
	}
	
	
	void updateSpeed(in double delta) pure {
		// Apply friction
		double nx, ny, vel;
		normalize(vel_x, vel_y, nx, ny, vel);
		if(vel != 0) {
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
	Turning direction;
	double duration = 0;
	
	Box getHitbox(in Ponger swinger) pure const {
		auto result = swinger.getHitbox();
		
		enum PADDING = 12;
		enum TURNING_OFFSET = 12;
		enum WIDTH = 30;
		
		final switch(swinger.facing) {
			case(Direction.North):
				result.left -= PADDING;
				result.width += PADDING * 2;
				result.top -= WIDTH;
				result.height = WIDTH;
				if(direction == Turning.Clockwise) result.left -= TURNING_OFFSET;
				else result.left += TURNING_OFFSET;
				break;
			
			case(Direction.East):
				result.top -= PADDING;
				result.height += PADDING * 2;
				result.left += result.width;
				result.width = WIDTH;
				if(direction == Turning.Clockwise) result.top -= TURNING_OFFSET;
				else result.top += TURNING_OFFSET;
				break;
			
			case(Direction.South):
				result.left -= PADDING;
				result.width += PADDING * 2;
				result.top += result.height;
				result.height = WIDTH;
				
				if(direction == Turning.Clockwise) result.left += TURNING_OFFSET;
				else result.left -= TURNING_OFFSET;
				break;
			
			case(Direction.West):
				result.top -= PADDING;
				result.height += PADDING * 2;
				result.left -= WIDTH;
				result.width = WIDTH;
				if(direction == Turning.Clockwise) result.top += TURNING_OFFSET;
				else result.top -= TURNING_OFFSET;
				break;
		}
		
		return result;
	}
	
	void getPivot(in Ponger swinger, out double px, out double py) pure const {
		auto box = swinger.getHitbox();
		
		enum MARGIN = 12;
		
		final switch(swinger.facing) {
			case(Direction.North):
				py = box.top + MARGIN;
				if(direction == Turning.Clockwise) px = box.left;
				else px = box.right;
				break;
			
			case(Direction.East):
				px = box.right - MARGIN;
				if(direction == Turning.Clockwise) py = box.top;
				else py = box.bottom;
				break;
			
			case(Direction.South):
				py = box.bottom - MARGIN;
				if(direction == Turning.Clockwise) px = box.right;
				else px = box.left;
				break;
			
			case(Direction.West):
				px = box.left + MARGIN;
				if(direction == Turning.Clockwise) py = box.bottom;
				else py = box.top;
				break;
		}
	}
}

// Represents the ball
class Ball {
	// Position in the game
	double x, y;
	
	// Movement rate
	double vel_x = 0, vel_y = 0;
	double vel_angle = 0;
	
	// Fixes striking the same ball twice over multiple frames
	double strikeShield = 0;
	
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