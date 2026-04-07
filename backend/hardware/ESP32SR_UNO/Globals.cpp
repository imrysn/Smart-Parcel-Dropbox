#include "StateMetrics.h"

// Definition of all externs
SystemState currentState = IDLE;
bool isReceivingMode     = true;
bool isRiderMode         = false;  
bool isMultiMode         = false;  
int  scannedCount        = 0;      
int  consecutiveScanFails= 0;      
bool stateInitialized    = false;
bool doorWasOpened       = false;
unsigned long stateStartTime     = 0;
unsigned long stabilityStartTime = 0;
unsigned long lastDebugTime      = 0;

unsigned long actionDelayStart  = 0;
bool          actionDelayActive = false;
SystemState   pendingNextState  = IDLE;
bool          isScannerTestActive = false;
unsigned long lastStateChangeTime = 0;
unsigned long scannerTestStartTime = 0;

bool   riderVerifyReceived = false;
bool   riderVerifyValid    = false;
char serial2Buffer[128]       = ""; 
char ownerSessionToken[32]   = "";   
bool   ownerApprovalReceived = false;
bool   ownerApprovalValid    = false;
bool   ownerQrDrawn          = false; 
bool   ownerVerifyTimedOut   = false; 

Preferences nvsPrefs;
// Network State (NVS)
char nvsWifiSSID[33]      = "";
char nvsWifiPassword[64]  = "";
char primaryUserId[32]    = ""; // Phase 6: Sync from backend
bool   deviceRegistered = false;  
unsigned long previousMillisWiFi = 0;
unsigned long intervalWiFi = 10000;  

char registrationToken[32] = ""; 
char hmacKey[65]           = ""; 
bool   regTokenReceived  = false;
bool   regQrDrawn        = false;
bool   deviceJustRegistered = false; 

char registeredDropOff[64]  = "";  
char registeredPickup[64]   = "";  
char currentTrackingId[64]  = "";  

bool scanResultReceived = false;
bool scanResultValid    = false;

bool lockTopOpen      = false;  
bool lockPickupOpen   = false;  
bool lockReceivedOpen = false;  

bool lastWifiState = false;
bool lastSocketState = false;
bool lastDoorState = false;
unsigned long lastIndicatorUpdate = 0;

char offlineQueue[MAX_OFFLINE_QUEUE][64];
int offlineQueueCount = 0;

unsigned long lastLockscreenUpdate = 0;
int eyeX = 160; 
int eyeY = 120;
int pupilX = 160;
int pupilY = 120;
int targetPupilX = 160;
int targetPupilY = 120;
bool isBlinking = false;
unsigned long nextBlinkTime = 0;
unsigned long nextTextTime = 0;
bool showingText = false;
int textX = 320;
int currentOffsetX = 0;
int targetOffsetX = 0;
unsigned long lastMoveTime = 0;
RobotEmotion  currentEmotion = NEUTRAL;
unsigned long lastEmotionTime = 0;

unsigned long dropOffRegisterTime = 0;
unsigned long pickupRegisterTime  = 0;
const unsigned long TIMEOUT_MS    = 300000;

// Non-blocking hardware state init
int           currentServoPos     = 180; // Safe default
int           targetServoPos      = 180;
unsigned long lastServoMoveTime   = 0;
float         lastUsPlatformDist  = 999.0;
float         lastUsPickupDist    = 999.0;
float         lastUsDropoffDist   = 999.0;
unsigned long lastUsPlatformTime  = 0;
unsigned long lastUsPickupTime    = 0;
unsigned long lastUsDropoffTime   = 0;

Servo            platformServo;
Adafruit_ILI9341 tft(TFT_CS, TFT_DC, TFT_RST);
SocketIOclient   socketIO;

const int US_PLATFORM[2] = {15,  4};
const int US_PICKUP[2]   = { 7, 16};
const int US_DROPOFF[2]  = {18,  8};
