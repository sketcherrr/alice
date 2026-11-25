// Alice Cardputer-Adv SSH prototype. No API key, shell or pet save on the device.
#include <Arduino.h>
#include <ArduinoJson.h>
#include <M5Cardputer.h>
#include <Preferences.h>
#include <WiFi.h>
#include <libssh_esp32.h>
#include <libssh/libssh.h>
#include <cmath>

struct Config {
  String ssid, wifiPassword, host, user, password, fingerprint;
  uint16_t port = 2222;
} config;
struct Command { char op[12]; char action[16]; int choice; };
struct Event { bool connected; bool response; char body[1024]; };
QueueHandle_t commands = nullptr, events = nullptr;
Preferences preferences;
M5Canvas canvas(&M5Cardputer.Display);
bool setupMode = false, connected = false, busy = false, choosePersona = true;
bool sleeping = false, playing = false, hasState = false, selectingPersona = false;
int energy = 0, comfort = 0, satiety = 0, cleanliness = 0;
String notice = "Connecting...";
uint32_t lastDraw = 0, effectUntil = 0, lastSnapshot = 0;
char effect = 0;
String serialLine;
bool serialOverflow = false;

bool parseConfig(const String &text) {
  JsonDocument doc;
  if (deserializeJson(doc, text) || !doc.is<JsonObject>()) return false;
  const char *keys[] = {"wifi_ssid", "wifi_password", "ssh_host", "ssh_user", "ssh_password", "host_fingerprint"};
  for (const char *key : keys) {
    if (!doc[key].is<const char *>()) return false;
    String value = doc[key].as<String>();
    if (value.length() > 128 || value.indexOf('\n') >= 0 || value.indexOf('\r') >= 0) return false;
  }
  String ssid = doc["wifi_ssid"].as<String>();
  String host = doc["ssh_host"].as<String>();
  String user = doc["ssh_user"].as<String>();
  String password = doc["ssh_password"].as<String>();
  String fingerprint = doc["host_fingerprint"].as<String>();
  int port = doc["ssh_port"] | 2222;
  if (!ssid.length() || ssid.length() > 32 || !host.length() || !user.length() || !password.length() ||
      port < 1 || port > 65535 || fingerprint.length() != 50 || !fingerprint.startsWith("SHA256:")) return false;
  for (size_t i = 7; i < fingerprint.length(); ++i) {
    char c = fingerprint[i];
    if (!isalnum(static_cast<unsigned char>(c)) && c != '+' && c != '/') return false;
  }
  config.ssid = ssid;
  config.wifiPassword = doc["wifi_password"].as<String>();
  config.host = host;
  config.user = user;
  config.password = password;
  config.fingerprint = fingerprint;
  config.port = port;
  return true;
}

void post(bool up, bool response, const char *body) {
  Event event{};
  event.connected = up;
  event.response = response;
  strlcpy(event.body, body, sizeof(event.body));
  xQueueSend(events, &event, portMAX_DELAY);
}

bool checkHost(ssh_session session) {
  ssh_key key = nullptr;
  unsigned char *hash = nullptr;
  size_t length = 0;
  bool trusted = false;
  if (ssh_get_server_publickey(session, &key) == SSH_OK &&
      ssh_get_publickey_hash(key, SSH_PUBLICKEY_HASH_SHA256, &hash, &length) == SSH_OK) {
    char *fingerprint = ssh_get_fingerprint_hash(SSH_PUBLICKEY_HASH_SHA256, hash, length);
    trusted = fingerprint && config.fingerprint == fingerprint;
    if (fingerprint) ssh_string_free_char(fingerprint);
  }
  if (hash) ssh_clean_pubkey_hash(&hash);
  if (key) ssh_key_free(key);
  return trusted;
}

bool exchange(ssh_session session, ssh_channel channel, const Command &command, uint32_t id, String &reply) {
  JsonDocument request;
  request["v"] = 1;
  request["id"] = id;
  request["op"] = command.op;
  if (command.action[0]) request["action"] = command.action;
  if (!strcmp(command.op, "persona")) request["choice"] = command.choice;
  if (!strcmp(command.action, "guess")) request["guess"] = command.choice;
  String wire;
  serializeJson(request, wire);
  wire += '\n';
  size_t sent = 0;
  uint32_t start = millis();
  while (sent < wire.length() && millis() - start < 12000) {
    int count = ssh_channel_write(channel, wire.c_str() + sent, wire.length() - sent);
    if (count == SSH_ERROR || count == 0) return false;
    if (count > 0) sent += count;
    vTaskDelay(pdMS_TO_TICKS(10));
  }
  if (sent != wire.length()) return false;
  reply = "";
  while (millis() - start < 12000 && WiFi.status() == WL_CONNECTED && ssh_is_connected(session)) {
    char buffer[128];
    int count = ssh_channel_read_timeout(channel, buffer, sizeof(buffer), 0, 100);
    if (count == SSH_ERROR || ssh_channel_is_eof(channel)) return false;
    if (count > 0) {
      for (int i = 0; i < count; ++i) {
        if (buffer[i] == '\n') {
          if (i != count - 1) return false;
          JsonDocument response;
          if (deserializeJson(response, reply) || response["v"].as<int>() != 1 ||
              !response["id"].is<uint32_t>() || response["id"].as<uint32_t>() != id ||
              !response["ok"].is<bool>()) return false;
          return true;
        }
        if (reply.length() >= 1023) return false;
        reply += buffer[i];
      }
    }
    vTaskDelay(pdMS_TO_TICKS(10));
  }
  return false;
}

void networkTask(void *) {
  // libssh stays on this task; drawing and keyboard polling stay responsive.
  libssh_begin();
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(config.ssid.c_str(), config.wifiPassword.c_str());
  uint32_t id = 0;
  for (;;) {
    if (WiFi.status() != WL_CONNECTED) {
      post(false, false, "WiFi: waiting for 2.4 GHz network.");
      vTaskDelay(pdMS_TO_TICKS(5000));
      continue;
    }
    post(false, false, "Opening SSH...");
    ssh_session session = ssh_new();
    ssh_channel channel = nullptr;
    bool ready = false, authenticationFailed = false;
    const char *error = "SSH unavailable. Check host and port.";
    if (session) {
      unsigned int port = config.port;
      long timeout = 8;
      if (ssh_options_set(session, SSH_OPTIONS_HOST, config.host.c_str()) == SSH_OK &&
          ssh_options_set(session, SSH_OPTIONS_USER, config.user.c_str()) == SSH_OK &&
          ssh_options_set(session, SSH_OPTIONS_PORT, &port) == SSH_OK &&
          ssh_options_set(session, SSH_OPTIONS_TIMEOUT, &timeout) == SSH_OK &&
          ssh_options_set(session, SSH_OPTIONS_HOSTKEYS, "ssh-ed25519") == SSH_OK &&
          ssh_connect(session) == SSH_OK) {
        if (!checkHost(session)) {
          error = "Host key mismatch! Hold G0 to fix.";
          authenticationFailed = true;
        } else if (ssh_userauth_password(session, nullptr, config.password.c_str()) != SSH_AUTH_SUCCESS) {
          error = "SSH login failed. Hold G0 to fix.";
          authenticationFailed = true;
        } else {
          channel = ssh_channel_new(session);
          ready = channel && ssh_channel_open_session(channel) == SSH_OK &&
                  ssh_channel_request_exec(channel, "alice-card-v1") == SSH_OK;
          error = "Host bridge unavailable. Check service.";
        }
      }
    }
    if (ready) {
      Command command{};
      strlcpy(command.op, "snapshot", sizeof(command.op));
      String reply;
      if (exchange(session, channel, command, ++id, reply)) {
        post(true, true, reply.c_str());
        while (ready) {
          if (xQueueReceive(commands, &command, pdMS_TO_TICKS(200)) == pdTRUE) {
            if (!exchange(session, channel, command, ++id, reply)) {
              ready = false;
              error = "Link lost. Refreshing save; no replay.";
            } else post(true, true, reply.c_str());
          }
          if (WiFi.status() != WL_CONNECTED || !ssh_is_connected(session) || ssh_channel_is_eof(channel)) {
            ready = false;
            error = "Disconnected. Reconnecting...";
          }
        }
      } else error = "No valid reply. Check host bridge.";
    }
    xQueueReset(commands); // Never replay an action with an uncertain outcome.
    post(false, false, error);
    if (channel) ssh_channel_free(channel);
    if (session) { ssh_disconnect(session); ssh_free(session); }
    // Do not hammer passwords or retry a changed host key. Reconfigure or reboot.
    while (authenticationFailed) vTaskDelay(pdMS_TO_TICKS(1000));
    vTaskDelay(pdMS_TO_TICKS(5000));
    xQueueReset(commands);
  }
}

void send(const char *op, const char *action = "", int choice = 0) {
  if (!connected || busy) return;
  Command command{};
  strlcpy(command.op, op, sizeof(command.op));
  strlcpy(command.action, action, sizeof(command.action));
  command.choice = choice;
  if (xQueueSend(commands, &command, 0) == pdTRUE) {
    busy = true;
    selectingPersona = !strcmp(op, "persona");
    lastSnapshot = millis();
  }
}

void meter(const char *label, int value, int y, uint16_t color) {
  canvas.setTextColor(0x3AEE);
  canvas.setCursor(112, y);
  canvas.printf("%s %3d", label, value);
  canvas.fillRoundRect(112, y + 10, 116, 4, 2, 0xD71D);
  canvas.fillRoundRect(112, y + 10, constrain(value, 0, 100) * 116 / 100, 4, 2, color);
}

void draw() {
  const uint16_t blue = 0x759F, dark = 0x296D, pink = 0xFBB8;
  canvas.fillScreen(0xF7FF);
  canvas.setTextColor(dark);
  canvas.setTextSize(1);
  canvas.setCursor(8, 3);
  canvas.print("ALICE / tiny island");
  canvas.setCursor(192, 3);
  canvas.print(connected ? (busy ? "..." : "SSH OK") : "OFFLINE");
  if (setupMode) {
    canvas.setCursor(8, 28);
    canvas.print("USB setup\n\n  Run configure-cardputer.py\n  with your alice.local.json.\n\n  No microSD needed.\n  Passwords stay off screen.");
  } else if (choosePersona) {
    canvas.setCursor(8, 28);
    canvas.print("Choose our little vibe:\n\n  1  Gentle, with her own ideas\n  2  Clever and a little playful\n  3  Quiet, thoughtful, warms slowly");
  } else {
    int y = 47 + static_cast<int>(2 * sin(millis() / 500.0));
    // Small original whale-hood avatar, drawn locally without large textures.
    canvas.fillEllipse(50, y + 6, 31, 27, blue);
    canvas.fillTriangle(23, y - 7, 8, y - 16, 18, y + 8, blue);
    canvas.fillTriangle(78, y - 7, 94, y - 16, 83, y + 8, blue);
    canvas.fillEllipse(50, y + 8, 24, 20, 0xFFDE);
    canvas.fillTriangle(27, y - 9, 46, y - 17, 36, y + 3, blue);
    canvas.fillTriangle(45, y - 14, 71, y - 9, 61, y + 4, blue);
    bool blink = sleeping || millis() % 4200 < 150;
    if (blink) {
      canvas.drawLine(37, y + 9, 43, y + 9, dark);
      canvas.drawLine(58, y + 9, 64, y + 9, dark);
    } else {
      canvas.fillEllipse(40, y + 8, 2, 4, dark);
      canvas.fillEllipse(61, y + 8, 2, 4, dark);
    }
    canvas.fillEllipse(32, y + 15, 4, 2, pink);
    canvas.fillEllipse(70, y + 15, 4, 2, pink);
    canvas.drawLine(48, y + 17, 53, y + 17, dark);
    if (sleeping) { canvas.setCursor(79, 26); canvas.print("zZ"); }
    if (effectUntil && static_cast<int32_t>(effectUntil - millis()) > 0) {
      if (effect == 'b') {
        for (int i = 0; i < 4; ++i) canvas.drawCircle(15 + i * 23, 70 - (millis() / 80 + i * 9) % 36, 4, blue);
      } else if (effect == 'f') {
        canvas.fillCircle(63, y + 24, 7, 0xFDCA);
        canvas.fillCircle(62, y + 22, 1, dark);
        canvas.fillCircle(66, y + 26, 1, dark);
      } else { canvas.setCursor(40, 19); canvas.setTextColor(pink); canvas.print("<3"); }
    }
    meter("Energy", energy, 17, blue);
    meter("Mood  ", comfort, 34, pink);
    meter("Food  ", satiety, 51, 0xFDCA);
    meter("Clean ", cleanliness, 68, 0x6DF7);
  }
  if (!setupMode) {
    canvas.setTextColor(dark);
    canvas.setCursor(8, 88);
    canvas.print(notice.substring(0, 37));
    canvas.setCursor(8, 98);
    canvas.print(notice.substring(37, 74));
    canvas.setCursor(8, 114);
    canvas.print(playing ? "Pearl hunt! Choose shell: 1 2 3" : "F food B bath S sleep W wake H pat");
    canvas.setCursor(8, 124);
    canvas.print("G game T tea P persona R refresh");
  }
  canvas.pushSprite(0, 0);
}

void provision() {
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\r') continue;
    if (c == '\n') {
      if (!serialOverflow && serialLine == "ALICE_SETUP") Serial.println("ALICE_READY");
      else if (!serialOverflow && parseConfig(serialLine)) {
        if (preferences.putString("config", serialLine) == serialLine.length()) {
          preferences.putBool("setup", false);
          Serial.println("ALICE_SAVED");
          Serial.flush();
          delay(300);
          ESP.restart();
        } else Serial.println("ALICE_SAVE_FAILED");
      } else Serial.println("ALICE_INVALID");
      serialLine = "";
      serialOverflow = false;
    } else if (serialLine.length() < 1536) serialLine += c;
    else serialOverflow = true;
  }
}

void setup() {
  auto cfg = M5.config();
  M5Cardputer.begin(cfg, true); // 1.1.1 detects ADV's TCA8418 keyboard.
  Serial.begin(115200);
  M5Cardputer.Display.setRotation(1);
  M5Cardputer.Display.setBrightness(110);
  canvas.setColorDepth(8);
  if (!canvas.createSprite(240, 135)) {
    M5Cardputer.Display.println("Display allocation failed.");
    while (true) delay(1000);
  }
  preferences.begin("alice-card", false);
  setupMode = preferences.getBool("setup", false) || !parseConfig(preferences.getString("config", ""));
  if (setupMode) { Serial.println("ALICE_READY"); return; }
  commands = xQueueCreate(1, sizeof(Command));
  events = xQueueCreate(3, sizeof(Event));
  if (!commands || !events || xTaskCreate(networkTask, "alice-ssh", 32768, nullptr, 1, nullptr) != pdPASS)
    notice = "Not enough memory. Restart device.";
}

void loop() {
  M5Cardputer.update();
  if (M5Cardputer.BtnA.pressedFor(1500)) { preferences.putBool("setup", true); ESP.restart(); }
  if (setupMode) provision();
  else {
    Event event{};
    while (events && xQueueReceive(events, &event, 0) == pdTRUE) {
      connected = event.connected;
      busy = false;
      if (event.response) {
        JsonDocument response;
        if (!deserializeJson(response, event.body)) {
          if (response["state"].is<JsonObject>()) {
            JsonObjectConst state = response["state"].as<JsonObjectConst>();
            sleeping = state["sleeping"] | false;
            playing = !strcmp(state["game"] | "idle", "playing");
            energy = state["energy"] | 0;
            comfort = state["comfort"] | 0;
            satiety = state["satiety"] | 0;
            cleanliness = state["cleanliness"] | 0;
            if (!hasState || state["persona"].isNull() || (response["ok"].as<bool>() && selectingPersona))
              choosePersona = state["persona"].isNull();
            hasState = true;
          }
          notice = response["message"].as<String>();
          if (response["ok"].as<bool>() && effect) effectUntil = millis() + 2500;
          else effectUntil = 0;
        }
      } else notice = event.body;
      if (!connected) { effect = 0; effectUntil = 0; }
      lastSnapshot = millis();
    }
    if (M5Cardputer.Keyboard.isChange() && M5Cardputer.Keyboard.isPressed()) {
      for (char key : M5Cardputer.Keyboard.keysState().word) {
        key = tolower(static_cast<unsigned char>(key));
        if (key == 'p' && !busy) { choosePersona = true; notice = "Choose personality 1, 2 or 3."; }
        else if (key >= '1' && key <= '3' && !busy) {
          effect = 0;
          if (choosePersona) send("persona", "", key - '0');
          else if (playing) send("action", "guess", key - '1');
        } else if (key == 'r' && !busy) { effect = 0; send("snapshot"); }
        else if (!choosePersona && !busy && connected) {
          const char *action = nullptr;
          switch (key) {
            case 'f': action = "feed"; break; case 'b': action = "bath"; break;
            case 's': action = "rest"; break; case 'w': action = "wake"; break;
            case 'h': action = "pet"; break; case 'g': action = "start_game"; break;
            case 't': action = "tea"; break;
          }
          if (action) { effect = key; send("action", action); }
        }
      }
    }
    if (connected && !busy && millis() - lastSnapshot > 15000) {
      effect = 0;
      send("snapshot");
    }
  }
  if (millis() - lastDraw > 80) { draw(); lastDraw = millis(); }
  delay(10);
}
