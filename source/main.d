// Main file for DodgePong

import std.stdio;
import std.math;

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

immutable double[4] PONGER_BOUNDARY = [-12, -10, 12, 10];
immutable PONGER_HITBOX = Box(-10, -12, 20, 25);

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

class DodgePong : Drawable {
	// Need this to draw stuff
	RenderWindow window;
	bool isRunning = false;
	int[int] keyDirectionalMap;
	
	// A.K.A. the player
	Ponger ponger;
	
	// Playable area of the game
	Box playBoundaries;
	
	this() {
		// Setup window
		auto videoMode = VideoMode(GAME_WIDTH, GAME_HEIGHT);
		window = new RenderWindow(videoMode, GAME_TITLE);
		
		// Setup key map
		keyDirectionalMap[GO_NORTH_KEY] = NORTH;
		keyDirectionalMap[GO_EAST_KEY] = EAST;
		keyDirectionalMap[GO_SOUTH_KEY] = SOUTH;
		keyDirectionalMap[GO_WEST_KEY] = WEST;
		keyDirectionalMap.rehash();
		
		playBoundaries = Box(0, 0, GAME_WIDTH, GAME_HEIGHT);
		
		// Start up player
		ponger = new Ponger();
		ponger.x = GAME_WIDTH / 2;
		ponger.y = GAME_HEIGHT / 2;
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
		foreach(int key, int direction; keyDirectionalMap) {
			if(playerInput.pressedKey.get(key, false)) {
				ponger.going[direction] = true;
			}
			
			if(playerInput.releasedKey.get(key, false)) {
				ponger.going[direction] = false;
			}
		}
		
		ponger.computeGoing(ponger.going, ponger.going_x, ponger.going_y);
	}
	
	// Updates game variables based on time
	void update(in double delta) {
		ponger.updateSpeed(delta);
		
		ponger.x += ponger.vel_x * delta;
		ponger.y += ponger.vel_y * delta;
		
		// Keep ponger inside boundaries
		auto hitbox = ponger.getHitbox();
		auto containedBox = hitbox.moveInside(playBoundaries);
		
		// Update based on offset
		ponger.x += containedBox.left - hitbox.left;
		ponger.y += containedBox.top - hitbox.top;
	}
	
	// Render game
	override void draw(RenderTarget renderTarget, RenderStates states) {
		renderTarget.clear(BACKGROUND_COLOR);
		
		// Rendering the player
		enum PLAYER_HEIGHT = 25;
		enum PLAYER_WIDTH = 20;
		
		Transform t = Transform.Identity;
		t.translate(ponger.x, ponger.y);
		t.translate(-PLAYER_WIDTH / 2, -PLAYER_HEIGHT / 2);
		
		auto pongerSprite = new RectangleShape(Vector2f(0, 0));
		pongerSprite.size = Vector2f(PLAYER_WIDTH, PLAYER_HEIGHT);
		pongerSprite.fillColor = Color(255, 255, 255);
		
		states.transform = t;
		renderTarget.draw(pongerSprite, states);
	}
}

// Used to store game input
struct PlayerInput {
	bool closedWindow = false;
	bool lostFocus = false;
	bool[int] pressedKey, releasedKey;
	bool[int] pressedButton, releasedButton;
}

class Ponger {
	// Position in the game
	double x, y;
	
	// Movement rate
	double vel_x = 0, vel_y = 0;
	
	// Where the ponger is going, relative coordinates -1..1
	int going_x, going_y;
	int[4] going = [false, false, false, false];
	
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

// Utility to cap a value
void cap(ref double value, in double  bottom, in double top) pure nothrow {
	value = value > bottom ? (value < top ? value : top) : bottom ;
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
	
	bool[4] partsOutside(in Box container) pure const {
		bool[4] result;
		result[NORTH] = top < container.top;
		result[SOUTH] = bottom >= container.bottom;
		result[WEST] = left < container.left;
		result[EAST] = right >= container.right;
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
