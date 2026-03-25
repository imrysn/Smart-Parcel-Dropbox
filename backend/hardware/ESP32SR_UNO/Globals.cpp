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

bool   riderVerifyReceived = false;
bool   riderVerifyValid    = false;
String serial2Buffer       = ""; 

String ownerSessionToken     = "";   
bool   ownerApprovalReceived = false;
bool   ownerApprovalValid    = false;
bool   ownerQrDrawn          = false; 
bool   ownerVerifyTimedOut   = false; 

Preferences nvsPrefs;
// Network State (NVS)
String nvsWifiSSID      = "";
String nvsWifiPassword  = "";
bool   deviceRegistered = false;  
unsigned long previousMillisWiFi = 0;
unsigned long intervalWiFi = 10000;  

String registrationToken = ""; 
bool   regTokenReceived  = false;
bool   regQrDrawn        = false;
bool   deviceJustRegistered = false; 

String registeredDropOff  = "";  
String registeredPickup   = "";  
String currentTrackingId  = "";  

bool scanResultReceived = false;
bool scanResultValid    = false;

bool lockTopOpen      = false;  
bool lockPickupOpen   = false;  
bool lockReceivedOpen = false;  

bool lastWifiState = false;
bool lastSocketState = false;
bool lastDoorState = false;
unsigned long lastIndicatorUpdate = 0;

String offlineQueue[MAX_OFFLINE_QUEUE];
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

Servo            platformServo;
Adafruit_ILI9341 tft(TFT_CS, TFT_DC, TFT_RST);
SocketIOclient   socketIO;

const int US_PLATFORM[2] = {15,  4};
const int US_PICKUP[2]   = { 7, 16};
const int US_DROPOFF[2]  = {18,  8};
