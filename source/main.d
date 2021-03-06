// Main file for DodgePong
import std.stdio;
import std.math;
import std.array;
import std.algorithm;
import std.conv;
import random = std.random;

import dsfml.system;
import dsfml.graphics;
import dsfml.audio;

import utility;

enum GAME_WIDTH    = 600;
enum GAME_HEIGHT   = 600;
enum STATUS_HEIGHT = 40;

enum WINDOW_WIDTH  = GAME_WIDTH;
enum WINDOW_HEIGHT = GAME_HEIGHT + STATUS_HEIGHT;
enum WINDOW_TITLE = "Dodge Pong";

// Key bindings
enum GO_NORTH_KEY = Keyboard.Key.Up;
enum GO_EAST_KEY  =  Keyboard.Key.Right;
enum GO_SOUTH_KEY = Keyboard.Key.Down;
enum GO_WEST_KEY  = Keyboard.Key.Left;
enum SWING_KEY = Keyboard.Key.D;
enum NEW_GAME_KEY = Keyboard.Key.N;
enum PAUSE_KEY = Keyboard.Key.Escape;

// Player maxiumum velocity in units per second
enum PONGER_VELOCITY_CAP = 400;
// Stops the player in .2 seconds
enum PONGER_FRICTION = PONGER_VELOCITY_CAP / .2;
// Goes full speed in .2 seconds
enum PONGER_ACCEL = PONGER_VELOCITY_CAP / .2 + PONGER_FRICTION;

enum BALL_MAX_SPEED           = 600 / .3;
enum BALL_START_SPEED         = BALL_MAX_SPEED / 4;
enum BALL_SPEED_TIME_CAP      = BALL_MAX_SPEED / 4;
enum BALL_SPEED_STRIKE_CAP    = BALL_MAX_SPEED / 2;

enum BALL_SPEED_TIME_SCALAR   = BALL_SPEED_TIME_CAP / 120; // 2 minutes
enum BALL_SPEED_STRIKE_SCALAR = BALL_SPEED_STRIKE_CAP / 30; // 30 strikes

enum BALL_ACCELERATION_RATE = .2;

enum BALL_ANGULAR_FRICTION = PI; // Pretty sure this isn't a thing.
enum SWING_ANGULAR_POWER = 3;

immutable PONGER_HITBOX = Box(-20, -17, 34, 40);
immutable BALL_HITBOX = Box(-4, -4, 8, 8);
immutable BALL_BOUNDARY =
	Box(10, 20 + STATUS_HEIGHT, GAME_WIDTH - 20, GAME_HEIGHT - 20);
immutable PONGER_BOUNDARY =
	Box(20, 20 + STATUS_HEIGHT, GAME_WIDTH - 40, GAME_HEIGHT - 20);


enum BALL_STEP_SIZE = 10.0;
enum BALL_STEP_THRESHOLD = .2;
enum BALL_STRIKE_SHIELD_DURATION = .1;

enum TRACE_LIFE = .4;
enum TRACE_INTERVAL = 2;

enum FLICKER_LIFE = .4;
enum FLICKER_SPAWN_RATE = FLICKER_LIFE / 10;
enum SPAWN_FLICKER_SPEED_FACTOR = -.2;

enum MIN_HIT_PARTICLES = 3;
enum MAX_HIT_PARTICLES = 6;
enum HIT_FLICKER_SPEED_FACTOR = .1;

enum MIN_STRIKE_PARTICLES = 10;
enum MAX_STRIKE_PARTICLES = 20;
enum STRIKE_FLICKER_SPEED_FACTOR = .2;

// Time between the start of a swing and the time it stops being effective
enum SWING_DURATION = 0.15;

// Minimum time between a swing and another
enum SWING_RECHARGE_TIME = .2;

// Speed added to the ball when it's hit
enum STRIKE_BOOST = BALL_START_SPEED * .5;

// Animation stuff
enum PONGER_WALKING_RATE = 1.0 / 10; // 20 times per second
enum PONGER_SWINGING_RATE = .05;

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
	
	// Resources
	Font statusFont;
	
	// Graphics
	Text scoreText, skillText, timeText, pauseText, gameOverText;
	Texture pongerTexture, bgTexture, particlesTexture;
	Sprite pongerSprite, bgSprite;
	
	// Audio
	Sound swingSound, strikeSound, wallHitSound, pongerHitSound, newGameSound,
	      pauseSound;
	
	// Whether the game has started
	bool gameStarted, gameOver, gamePaused;
	
	// Score data
	int score;
	double timePlaying = 0;
	int swings, strikes, streak;
	
	
	this() {
		// Setup window
		auto videoMode = VideoMode(WINDOW_WIDTH, WINDOW_HEIGHT);
		window = new RenderWindow(videoMode, WINDOW_TITLE);
		
		// Disable key repeat
		window.setKeyRepeatEnabled(false);
		
		// Setup key map
		keyDirectionalMap[GO_NORTH_KEY] = Direction.North;
		keyDirectionalMap[GO_EAST_KEY]  = Direction.East ;
		keyDirectionalMap[GO_SOUTH_KEY] = Direction.South;
		keyDirectionalMap[GO_WEST_KEY]  = Direction.West ;
		keyDirectionalMap.rehash();
		
		// Load assets
		statusFont = new Font;
		statusFont.loadFromFile("assets/Inconsolata.otf");
		
		pongerTexture = new Texture;
		pongerTexture.loadFromFile("assets/ponger.png");
		
		bgTexture = new Texture;
		bgTexture.loadFromFile("assets/background.png");
		
		particlesTexture = new Texture;
		particlesTexture.loadFromFile("assets/particles.png");
		
		// Setup graphics
		// Ponger
		pongerSprite = new Sprite;
		pongerSprite.setTexture(pongerTexture);
		
		// Background
		bgSprite = new Sprite;
		bgSprite.setTexture(bgTexture);
		
		// Status
		scoreText = new Text;
		scoreText.setFont(statusFont);
		scoreText.setCharacterSize(30);
		scoreText.setColor(Color(255, 255, 255));
		
		timeText = new Text;
		timeText.setFont(statusFont);
		timeText.setCharacterSize(30);
		timeText.setColor(Color(255, 255, 255));
		
		skillText = new Text;
		skillText.setFont(statusFont);
		skillText.setCharacterSize(30);
		skillText.setColor(Color(255, 255, 255));
		
		pauseText = new Text;
		pauseText.setFont(statusFont);
		pauseText.setCharacterSize(30);
		pauseText.setColor(Color(255, 255, 255));
		pauseText.setString("Paused (Press ESC)");
		
		gameOverText = new Text;
		gameOverText.setFont(statusFont);
		gameOverText.setCharacterSize(30);
		gameOverText.setColor(Color(255, 255, 255));
		gameOverText.setString("Game Over (Press N)");
		
		// Audio
		auto swingBuffer = new SoundBuffer;
		swingBuffer.loadFromFile("assets/swing.wav");
		swingSound = new Sound();
		swingSound.setBuffer(swingBuffer);
		
		swingSound.volume = 70;
		
		auto wallHitBuffer = new SoundBuffer;
		wallHitBuffer.loadFromFile("assets/wall-hit.wav");
		wallHitSound = new Sound();
		wallHitSound.setBuffer(wallHitBuffer);
	
		wallHitSound.volume = 80;
		
		auto strikeBuffer = new SoundBuffer;
		strikeBuffer.loadFromFile("assets/strike.wav");
		strikeSound = new Sound();
		strikeSound.setBuffer(strikeBuffer);
		strikeSound.volume = 100;
		
		auto pongerHitBuffer = new SoundBuffer;
		pongerHitBuffer.loadFromFile("assets/ponger-hit.wav");
		pongerHitSound = new Sound();
		pongerHitSound.setBuffer(pongerHitBuffer);
		pongerHitSound.volume = 80;
		
		auto newGameBuffer = new SoundBuffer;
		newGameBuffer.loadFromFile("assets/new-game.wav");
		newGameSound = new Sound();
		newGameSound.setBuffer(newGameBuffer);
		newGameSound.volume = 100;
		
		auto pauseBuffer = new SoundBuffer;
		pauseBuffer.loadFromFile("assets/pause.wav");
		pauseSound = new Sound();
		pauseSound.setBuffer(pauseBuffer);
		pauseSound.volume = 100;
		
		newGame();
		updateStatus();
	}
	
	void newGame() {
		gameStarted = false;
		gameOver = false;
		
		// Start up player
		ponger = new Ponger();
		ponger.x = GAME_WIDTH / 2;
		ponger.y = GAME_HEIGHT / 5 * 4;
		
		// Start up ball
		ball = new Ball();
		ball.x = GAME_WIDTH / 2;
		ball.y = GAME_HEIGHT / 2;
		
		// Reset score
		timePlaying = 0;
		score = 0;
		swings = 0;
		strikes = 0;
		streak = 0;
		ball.naturalSpeed = BALL_START_SPEED;
		
		// Play sound
		newGameSound.play();
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
		} else {
			// If you close the window I won't bother processing the rest
			if(gameOver == false) {
				if(playerInput.pressedKey.get(PAUSE_KEY, false)) {
					gamePaused = !gamePaused;
					pauseSound.play();
					ponger.going = [false, false, false, false];
				} 
				
				if(!gamePaused) {
					// Game isn't over so we can still play.
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
					
					// There are two buttons two swing, one for each side.
					// idk why I made it like this.
					if(playerInput.pressedKey.get(SWING_KEY, false)) {
						if(ponger.swingRecharge <= 0) {
							ponger.swing = new PongerSwing();
							ponger.swingRecharge = SWING_RECHARGE_TIME + SWING_DURATION;
							swingSound.play();
							
							// Reset animation
							ponger.animationTime = 0;
							
							if(gameStarted) swings++;
						}
					}
				}
			} else if(playerInput.pressedKey.get(PAUSE_KEY, false)) {
				newGame();
			}
			
			// If you lose you can still start a new game.
			// If you haven't lost you can start a new game too but why would you?
			if(playerInput.pressedKey.get(NEW_GAME_KEY, false)) {
				newGame();
			}
		}
	}
	
	
	// Updates game variables based on time
	void update(in double delta) {
		if(!gamePaused) {
			updateScore(delta);
			updatePonger(delta);
			updateBall(delta);
		}
	}
	
	
	void updateScore(in double delta) {
		if(!gameOver) {
			if(gameStarted) {
				timePlaying += delta;
			}
			
			// Calculate the ball natural speed
			auto baseSpeed = BALL_START_SPEED;
			auto timeSpeed = timePlaying * BALL_SPEED_TIME_SCALAR;
			timeSpeed.cap(0, BALL_SPEED_TIME_CAP);
			
			auto strikeSpeed = strikes * BALL_SPEED_STRIKE_SCALAR;
			strikeSpeed.cap(0, BALL_SPEED_STRIKE_CAP);
			
			ball.naturalSpeed = baseSpeed + timeSpeed + strikeSpeed;
			
			updateStatus();
		}
	}
	
	
	void updateStatus() {
		// Score text
		scoreText.position = Vector2f(10, 0);
		scoreText.setString(score.to!dstring);
		
		// Streak text
		int accuracy;
		if(swings > 0) {
			accuracy = strikes * 100 / swings;
		} else {
			accuracy = 100;
		}
		skillText.setString("%" ~ accuracy.to!dstring ~ " x" ~ streak.to!dstring);
		auto bounds = skillText.getLocalBounds();
		skillText.position = Vector2f((WINDOW_WIDTH - bounds.width) / 2, 0);
		
		
		// Time text
		auto seconds = timePlaying.to!int;
		if(seconds < 10) {
			timeText.setString("0:0" ~ seconds.to!dstring);
		} else if(seconds < 60) {
			timeText.setString("0:" ~ seconds.to!dstring);
		} else {
			auto minutes = seconds / 60;
			seconds = seconds % 60;
			timeText.setString(minutes.to!dstring ~ ":" ~ seconds.to!dstring);
		}
		bounds = timeText.getLocalBounds();
		timeText.position = Vector2f(WINDOW_WIDTH - 10 - bounds.width, 0);
	}
	
	
	void updatePonger(in double delta) {
		if(!gameOver) {
			// Increase velocity based on input
			ponger.vel_x += ponger.going_x * delta * PONGER_ACCEL;
			ponger.vel_y += ponger.going_y * delta * PONGER_ACCEL;
		}
		
		// Update animation
		ponger.animationTime += delta;
		
		// Recharge swing
		if(ponger.swingRecharge > 0) {
			ponger.swingRecharge -= delta;
		}
		
		
		// Update speed
		ponger.updateSpeed(delta);
		
		// Move
		ponger.x += ponger.vel_x * delta;
		ponger.y += ponger.vel_y * delta;
		
		// Boundary collision
		Box hitbox = ponger.getHitbox();
		Box containedBox = hitbox.moveInside(PONGER_BOUNDARY);
		
		// Update based on offset
		ponger.x += containedBox.left - hitbox.left;
		ponger.y += containedBox.top - hitbox.top;
		
		auto swing = ponger.swing;
		if(swing) {
			swing.duration += delta;
			if(swing.duration > SWING_DURATION) {
				if(swing.struck == false) {
					// Lose streak
					streak = 0;
				}
				
				// Remove swing
				ponger.swing = null;
				
				// Update animation
				ponger.animationTime = 0;
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
			double subDelta;
			if(distance == 0) {
				subDelta = delta;
			} else {
				subDelta = delta * (step / distance);
			}
			
			// Remember current position
			auto px = ball.x;
			auto py = ball.y;
			
			// Remove strike shield
			if(ball.strikeShield > 0)
				ball.strikeShield -= subDelta;
		
			ball.applyAngularFriction(subDelta);
			
			// Spin ball
			if(step > 0) {
				ball.spin(subDelta);
				
				// Accelerate ball
				double nvx, nvy, vel;
				normalize(ball.vel_x, ball.vel_y, nvx, nvy, vel);
				
				double dvel = ball.naturalSpeed - vel;
				vel = vel + dvel * subDelta * BALL_ACCELERATION_RATE;
				
				ball.vel_x = nvx * vel;
				ball.vel_y = nvy * vel;
				
				// Move the ball
				ball.x += ball.vel_x * subDelta;
				ball.y += ball.vel_y * subDelta;
			}
			
			tryToStrikeBall();
			tryToHitPonger();
			if(!gameOver)
				keepBallInsideGame();
			
			// Calculate displacement
			auto dx = ball.x - px;
			auto dy = ball.y - py;
			auto dl = vectorLength(dx, dy);
			
			distanceLeft -= dl;
			
			// Add trace particles to ball
			ball.addTraceFrom(px, py);
			ball.flicker(subDelta);
			
		} while(distanceLeft > BALL_STEP_THRESHOLD);
		
		updateBallParticles(delta);
	}
	
	
	void tryToStrikeBall() {
		// Check collision
		Box hitbox = ball.getHitbox();
		
		// Striking the ball
		auto swing = ponger.swing;
		if(swing == null)
			return; // No way to strike.
		
		auto swingHitbox = swing.getHitbox(ponger);
		if(hitbox.intersectsWith(swingHitbox)) {
			// STRIKE!!!
			if(ball.strikeShield <= 0) {
				double nvx, nvy, vel;
				normalize(ball.vel_x, ball.vel_y, nvx, nvy, vel);
				
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
				double fr = (ponger.facing - 1)* -PI / 2;
				double rdx = dx * cos(fr) - dy * sin(fr);
				double rdy = dx * sin(fr) + dy * cos(fr);
				
				double angle = atan2(rdy, rdx);
				ball.vel_angle += angle * SWING_ANGULAR_POWER;
				
				// Setting velocities
				if(gameStarted) {
					// Increase score
					strikes++;
					streak++;
					swing.struck = true;
					
					auto pointsScored = vel.to!int;
					pointsScored *= 1 + streak / 2;
					score += pointsScored;
					
					// Strike the ball normally
					ball.vel_x = nvx * (vel + STRIKE_BOOST);
					ball.vel_y = nvy * (vel + STRIKE_BOOST);
				} else {
					// Set the start speed for the ball
					ball.vel_x = nvx * (ball.naturalSpeed + STRIKE_BOOST);
					ball.vel_y = nvy * (ball.naturalSpeed + STRIKE_BOOST);
					
					gameStarted = true;
				}
				
				// Play sound
				strikeSound.play();
				ball.addStrikeParticles();
			}
			
			// Reset shield
			ball.strikeShield = BALL_STRIKE_SHIELD_DURATION;
		}
	}
	
	
	void tryToHitPonger() {
		// Checking ball collision against player
		auto hitbox = ball.getHitbox();
		auto pongerBox = ponger.getHitbox();
		if(hitbox.intersectsWith(pongerBox)) {
			if(ball.strikeShield <= 0 && gameStarted) {
				// Play got hit = game over
				gameOver = true;
				pongerHitSound.play();
				ball.addStrikeParticles();
				
				// Push player
				ponger.vel_x = ball.vel_x;
				ponger.vel_y = ball.vel_y;
			}
			
			// Reset strike shield
			ball.strikeShield = BALL_STRIKE_SHIELD_DURATION;
		}
	}
	
	
	void keepBallInsideGame() {
			// Keeping the ball inside the game
			Box hitbox = ball.getHitbox();
			Box containedBox = hitbox.moveInside(BALL_BOUNDARY);
			
			if(hitbox != containedBox) {
				ball.x += containedBox.left - hitbox.left;
				ball.y += containedBox.top - hitbox.top;
				
				// Mirror velocity
				bool[4] partsOutside = hitbox.getPartsOutside(BALL_BOUNDARY);
				if(partsOutside[Direction.North] || partsOutside[Direction.South]) {
					ball.vel_y *= -1;
				}
				if(partsOutside[Direction.West] || partsOutside[Direction.East]) {
					ball.vel_x *= -1;
				}
				
				// Play sound
				wallHitSound.play();
				ball.addHitParticles();
			}
	}
	
	
	void updateBallParticles(in double delta) pure {
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
		
		auto flickeringParticles = ball.flickeringParticles;
		for(int i = 0; i < flickeringParticles.length; i++) {
			FlickerParticle* p = &flickeringParticles[i];
			p.x += p.vx * delta;
			p.y += p.vy * delta;
			p.life -= delta;
			if(p.life <= 0) {
				flickeringParticles = flickeringParticles.remove(i);
				i--;
			}
		}
		ball.flickeringParticles = flickeringParticles;
	}
	
	
	// Render game
	override void draw(RenderTarget renderTarget, RenderStates states) {
		renderTarget.draw(bgSprite);
		renderStatus(renderTarget, states);
		renderPlayer(renderTarget, states);
		renderBall(renderTarget, states);
		renderCover(renderTarget, states);
	}
	
	
	void renderStatus(RenderTarget renderTarget, RenderStates states) {
		enum STATUS_SIZE = Vector2f(WINDOW_WIDTH, STATUS_HEIGHT);
		auto statusBackground = new RectangleShape(STATUS_SIZE);
		statusBackground.fillColor = Color(0, 0, 0);
		
		renderTarget.draw(statusBackground, states);
		
		renderTarget.draw(scoreText);
		renderTarget.draw(skillText);
		renderTarget.draw(timeText);
	}
	
	
	void renderPlayer(RenderTarget renderTarget, RenderStates states) {
		// Rendering the player sprite
		enum PLAYER_WIDTH = PONGER_HITBOX.width;
		enum PLAYER_HEIGHT = PONGER_HITBOX.height;
		enum PLAYER_SIZE = Vector2f(PLAYER_WIDTH, PLAYER_HEIGHT);
		
		// Getting frame information
		immutable(SpriteFrame)* currentFrame;
		auto directionFrames = PongerFrames[ponger.facing];
		
		if(ponger.swing) {
			auto swingingFrames = directionFrames[PongerAnimation.Swinging];
			if(ponger.animationTime < PONGER_SWINGING_RATE) {
				// Focusing
				currentFrame = &swingingFrames[0];
			} else {
				// Swinging
				currentFrame = &swingingFrames[1];
			}
			
		} else if(!gameOver && (ponger.going_x || ponger.going_y)) {
			auto walkingFrames = directionFrames[PongerAnimation.Walking];
			int i = (ponger.animationTime / PONGER_WALKING_RATE).to!int;
			// +1 because the frame 0 is the standing still frame.
			i = (i + 1) % walkingFrames.length;
			currentFrame = &walkingFrames[i];
		} else {
			auto walkingFrames = directionFrames[PongerAnimation.Walking];
			currentFrame = &walkingFrames[0];
		}
		
		
		auto frameBox = currentFrame.box;
		
		// Setting frame settings
		pongerSprite.textureRect = frameBox.toIntRect;
		pongerSprite.origin = currentFrame.origin;
		
		// Translating to player position
		Transform t = Transform.Identity;
		t.translate(ponger.x, ponger.y);
		t.translate(PONGER_HITBOX.left, PONGER_HITBOX.top);
		
		// Drawing sprite
		states.transform = t;
		renderTarget.draw(pongerSprite, states);
	}
	
	
	void renderBall(RenderTarget renderTarget, RenderStates states) {
		// Rendering of the ball
		enum BALL_RADIUS = 5;
		
		// Rendering particles
		Vertex[] vertices;
		states.texture = particlesTexture;
		
		// Rendering trace
		vertices = getTraceVertices();
		
		states.blendMode = BlendMode.Alpha;
		renderTarget.draw(vertices, PrimitiveType.Quads, states);
		
		states.blendMode = BlendMode.Add;
		renderTarget.draw(vertices, PrimitiveType.Quads, states);
		
		//Rendering flickering
		vertices = getFlickerVertices();
		states.blendMode = BlendMode.Alpha;
		renderTarget.draw(vertices, PrimitiveType.Quads, states);
		
		states.blendMode = BlendMode.Add;
		renderTarget.draw(vertices, PrimitiveType.Quads, states);
		
		// Rendering of the ball
		vertices = [
			Vertex(Vector2f(-8, -8), Color(160, 255, 160, 255), Vector2f(16,  0)),
			Vertex(Vector2f( 8, -8), Color(160, 255, 160, 255), Vector2f(32,  0)),
			Vertex(Vector2f( 8,  8), Color(160, 255, 160, 255), Vector2f(32, 16)),
			Vertex(Vector2f(-8,  8), Color(160, 255, 160, 255), Vector2f(16, 16)),
		];
		
		if(gameStarted) {
			foreach(ref Vertex v; vertices) {
				v.texCoords.x -= 16;
			}
		}
		
		Transform t = Transform.Identity;
		t.translate(ball.x, ball.y);
		states.transform = t;
		
		if(!gameStarted) {
			states.blendMode = BlendMode.Alpha;
			renderTarget.draw(vertices, PrimitiveType.Quads, states);
		}
		
		states.blendMode = BlendMode.Add;
		renderTarget.draw(vertices, PrimitiveType.Quads, states);
	}
	
	
	Vertex[] getTraceVertices() {
		Vertex[] result;
		
		enum TRACE_RADIUS = 8;
		
		foreach(const TracePartcile p; ball.traceParticles) {
			Vertex tl, tr, br, bl;
			
			tl.position = Vector2f(p.x - TRACE_RADIUS, p.y - TRACE_RADIUS);
			tr.position = Vector2f(p.x + TRACE_RADIUS, p.y - TRACE_RADIUS);
			br.position = Vector2f(p.x + TRACE_RADIUS, p.y + TRACE_RADIUS);
			bl.position = Vector2f(p.x - TRACE_RADIUS, p.y + TRACE_RADIUS);
			
			tl.texCoords = Vector2f( 0,  0);
			tr.texCoords = Vector2f(16,  0);
			br.texCoords = Vector2f(16, 16);
			bl.texCoords = Vector2f( 0, 16);
			
			auto transition = p.life / TRACE_LIFE;
			auto alpha = (64 + 64 * transition).to!ubyte;
			auto mainColor = (127 + 128 * transition).to!ubyte;
			auto otherColor = (64 + 64 * transition).to!ubyte;
			
			bl.color = Color(otherColor, mainColor, otherColor, alpha);
			tl.color = tr.color = br.color = bl.color;
			
			result ~= [tl, tr, br, bl];
		}
		
		return result;
	}
	
	Vertex[] getFlickerVertices() {
		Vertex[] result;
		enum FLICKER_RADIUS = 4;
		foreach(const FlickerParticle p; ball.flickeringParticles) {
			Vertex tl, tr, br, bl;
			
			tl.position = Vector2f(p.x - FLICKER_RADIUS, p.y - FLICKER_RADIUS);
			tr.position = Vector2f(p.x + FLICKER_RADIUS, p.y - FLICKER_RADIUS);
			br.position = Vector2f(p.x + FLICKER_RADIUS, p.y + FLICKER_RADIUS);
			bl.position = Vector2f(p.x - FLICKER_RADIUS, p.y + FLICKER_RADIUS);
			
			tl.texCoords = Vector2f(20,  4);
			tr.texCoords = Vector2f(28,  4);
			br.texCoords = Vector2f(28, 12);
			bl.texCoords = Vector2f(20, 12);
			
			auto transition = p.life / FLICKER_LIFE;
			auto alpha = (55 + 200 * transition).to!ubyte;
			auto mainColor = (55 + 200 * transition).to!ubyte;
			auto otherColor = (55 + 55 * transition).to!ubyte;
			
			bl.color = Color(otherColor, mainColor, otherColor, alpha);
			tl.color = tr.color = br.color = bl.color;
			
			result ~= [tl, tr, br, bl];
		}
		
		return result;
	}
	
	
	void renderCover(RenderTarget renderTarget, RenderStates states) {
		enum BG_PADDING = 20;
		enum BG_COLOR = Color(0, 0, 0);
		
		Text coverText;
		
		if(gameOver) {
			coverText = gameOverText;
		} else if(gamePaused) {
			coverText = pauseText;
		}
		
		if(coverText) {
			auto textBox = coverText.getLocalBounds();
			coverText.position = Vector2f(
				(GAME_WIDTH - textBox.width) / 2,
				STATUS_HEIGHT + (GAME_HEIGHT - textBox.height) / 2);
			
			textBox = coverText.getGlobalBounds();
			auto bgSize = Vector2f(
				textBox.width + BG_PADDING * 2,
				textBox.height + BG_PADDING * 2);
			
			auto textBackground = new RectangleShape(bgSize);
			textBackground.position = Vector2f(
				textBox.left - BG_PADDING,
				textBox.top - BG_PADDING);
			
			textBackground.fillColor = BG_COLOR;
			renderTarget.draw(textBackground);
			renderTarget.draw(coverText);
		}
	}
}

// Used to store game input
struct PlayerInput {
	bool closedWindow = false;
	bool lostFocus = false;
	bool[int] pressedKey, releasedKey;
}


// Represents the player
class Ponger {
	// Position in the game
	double x, y;
	
	// Swing!!!
	PongerSwing* swing;
	
	// Time between a swing and another
	double swingRecharge = 0;
	
	// Movement rate
	double vel_x = 0, vel_y = 0;
	
	// Where the ponger is going, relative coordinates -1..1
	int going_x, going_y;
	int[4] going = [false, false, false, false];
	Direction facing = Direction.North;
	
	// Animation stuff
	double animationTime = 0;
	
	
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
		
		// Cap velocity
		cap(vel_x, -PONGER_VELOCITY_CAP, PONGER_VELOCITY_CAP);
		cap(vel_y, -PONGER_VELOCITY_CAP, PONGER_VELOCITY_CAP);
	}
}


// Representing a swing from the ponger
struct PongerSwing {
	double duration = 0;
	bool struck = false;
	
	Box getHitbox(in Ponger swinger) pure const {
		auto result = swinger.getHitbox();
		
		enum PADDING = 24;
		enum WIDTH = 30;
		
		final switch(swinger.facing) {
			case(Direction.North):
				result.left -= PADDING;
				result.width += PADDING * 2;
				result.top -= WIDTH;
				result.height = WIDTH + PADDING;
				break;
			
			case(Direction.East):
				result.top -= PADDING;
				result.height += PADDING * 2;
				result.left += result.width - PADDING;
				result.width = WIDTH + PADDING;
				break;
			
			case(Direction.South):
				result.left -= PADDING;
				result.width += PADDING * 2;
				result.top += result.height - PADDING;
				result.height = WIDTH + PADDING;
				break;
			
			case(Direction.West):
				result.top -= PADDING;
				result.height += PADDING * 2;
				result.left -= WIDTH;
				result.width = WIDTH + PADDING;
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
				px = box.left;
				break;
			
			case(Direction.East):
				px = box.right - MARGIN;
				py = box.top;
				break;
			
			case(Direction.South):
				py = box.bottom - MARGIN;
				px = box.right;
				break;
			
			case(Direction.West):
				px = box.left + MARGIN;
				py = box.top;
				break;
		}
	}
}


enum PongerAnimation {
	Walking = 0,
	Swinging = 1,
}


immutable PongerFrames = [
	[ // North
		[ // Walking
			SpriteFrame(Box(16,  16, 64, 80), 16, 16),
			SpriteFrame(Box(16,  96, 64, 80), 16, 16),
			SpriteFrame(Box(16, 176, 64, 80), 16, 16),
			SpriteFrame(Box(16, 256, 64, 80), 16, 16),
		],
		[ // Swinging
			SpriteFrame(Box(496, 32, 64, 64), 16, 16),
			SpriteFrame(Box(496, 96, 96, 96), 16, 48),
		]
	], 
	[ // East
		[ // Walking
			SpriteFrame(Box(80,  16, 64, 80), 16, 16),
			SpriteFrame(Box(80,  96, 64, 80), 16, 16),
			SpriteFrame(Box(80, 176, 64, 80), 16, 16),
			SpriteFrame(Box(80, 256, 64, 80), 16, 16),
		],
		[ // Swinging
			SpriteFrame(Box(384,  32, 64, 64), 16, 16),
			SpriteFrame(Box(384, 128, 96, 96), 16, 16),
		]
	], 
	[ // South
		[ // Walking
			SpriteFrame(Box(144,  16, 64, 80), 16, 16),
			SpriteFrame(Box(144,  96, 64, 80), 16, 16),
			SpriteFrame(Box(144, 176, 64, 80), 16, 16),
			SpriteFrame(Box(144, 256, 64, 80), 16, 16),
		],
		[ // Swinging
			SpriteFrame(Box(304,  32, 64, 64), 16, 16),
			SpriteFrame(Box(288, 128, 96, 96), 32, 16),
		]
	], 
	[ // West
		[ // Walking
			SpriteFrame(Box(208,  16, 64, 80), 16, 16),
			SpriteFrame(Box(208,  96, 64, 80), 16, 16),
			SpriteFrame(Box(208, 176, 64, 80), 16, 16),
			SpriteFrame(Box(208, 256, 64, 80), 16, 16),
		],
		[ // Swinging
			SpriteFrame(Box(384, 240, 64, 64), 16, 16),
			SpriteFrame(Box(368, 336, 96, 96), 48, 16),
		]
	]
];

struct SpriteFrame {
	Box box;
	int ox, oy;
	
	Vector2f origin() pure const @property {
		return Vector2f(ox, oy);
	}
}


// Represents the ball
class Ball {
	// Position in the game
	double x, y;
	
	// Movement rate
	double vel_x = 0, vel_y = 0;
	double vel_angle = 0;
	double naturalSpeed = 0;
	
	// Fixes striking the same ball twice over multiple frames
	double strikeShield = 0;
	
	// The trace left by the ball
	TracePartcile[] traceParticles;
	double traceRemainder = 0;
	
	FlickerParticle[] flickeringParticles;
	double flickerRemainder = 0;
	
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
	
	
	void flicker(in double delta) {
		FlickerParticle newParticles[];
		
		flickerRemainder += delta;
		while(flickerRemainder >= FLICKER_SPAWN_RATE) {
			flickerRemainder -= FLICKER_SPAWN_RATE;
			
			auto angle = atan2(vel_y, vel_x);
			auto vel = vectorLength(vel_x, vel_y) * SPAWN_FLICKER_SPEED_FACTOR;
		
			FlickerParticle newParticle;
			
			auto particleAngle = angle + random.uniform(- PI / 16, PI / 16);
			
			newParticle.x = x + random.uniform(-10.0, 10.0);
			newParticle.y = y + random.uniform(-10.0, 10.0);
			newParticle.vx = cos(particleAngle) * vel;
			newParticle.vy = sin(particleAngle) * vel;
			newParticle.life = FLICKER_LIFE;
			
			newParticles ~= newParticle;
		}
		
		flickeringParticles ~= newParticles;
	}
	
	
	void addHitParticles() {
		auto nParticles = random.uniform(MIN_HIT_PARTICLES, MAX_HIT_PARTICLES);
		
		FlickerParticle newParticles[];
		auto angle = atan2(vel_y, vel_x);
		auto vel = vectorLength(vel_x, vel_y) * HIT_FLICKER_SPEED_FACTOR;
		
		for(int i = 0; i < nParticles; i++) {
			FlickerParticle newParticle;
			
			auto particleAngle = angle + random.uniform(- PI / 2, PI / 2);
			
			newParticle.x = x + random.uniform(-8.0, 8.0);
			newParticle.y = y + random.uniform(-8.0, 8.0);
			newParticle.vx = cos(particleAngle) * vel;
			newParticle.vy = sin(particleAngle) * vel;
			newParticle.life = FLICKER_LIFE;
			
			newParticles ~= newParticle;
		}
		
		flickeringParticles ~= newParticles;
	}
	
	
	void addStrikeParticles() {
		auto nParticles = random.uniform(
			MIN_STRIKE_PARTICLES, MAX_STRIKE_PARTICLES);
		
		FlickerParticle newParticles[];
		auto angle = atan2(vel_y, vel_x);
		angle += vel_angle * .2;
		auto vel = vectorLength(vel_x, vel_y) * STRIKE_FLICKER_SPEED_FACTOR;
		
		for(int i = 0; i < nParticles; i++) {
			FlickerParticle newParticle;
			
			auto particleAngle = angle + random.uniform(- PI / 3, PI / 3);
			
			newParticle.x = x + random.uniform(-16.0, 16.0);
			newParticle.y = y + random.uniform(-16.0, 16.0);
			newParticle.vx = cos(particleAngle) * vel;
			newParticle.vy = sin(particleAngle) * vel;
			newParticle.life = FLICKER_LIFE;
			
			newParticles ~= newParticle;
		}
		
		flickeringParticles ~= newParticles;
	}
	
	
	void spin(in double delta) pure {
		// Rotates the ball velocity based on its angular velocity
		auto angle = atan2(vel_y, vel_x);
		angle += vel_angle * delta;
		
		auto vel = vectorLength(vel_x, vel_y);
		vel_x = cos(angle) * vel;
		vel_y = sin(angle) * vel;
	}
	
	
	void applyAngularFriction(in double delta) pure {
		// Decrease the angular velocity of the ball
		if(vel_angle > 0) {
			vel_angle -= BALL_ANGULAR_FRICTION * delta;
			vel_angle.cap(0, vel_angle);
		} else if(vel_angle < 0) {
			vel_angle += BALL_ANGULAR_FRICTION * delta;
			vel_angle.cap(vel_angle, 0);
		}
	}
}


struct TracePartcile {
	double x, y, life;
}

struct FlickerParticle {
	double x, y, vx, vy, life;
}