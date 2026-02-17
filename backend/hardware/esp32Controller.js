/**
 * ESP32-S3 Hardware Controller
 * Communicates with ESP32-S3 via HTTP to control two doors
 */

const axios = require('axios');

class ESP32Controller {
  constructor() {
    this.esp32Ip = process.env.ESP32_IP || '192.168.1.100';
    this.esp32Port = process.env.ESP32_PORT || 80;
    this.baseUrl = `http://${this.esp32Ip}:${this.esp32Port}`;
  }

  /**
   * Control a specific door
   * @param {string} doorType - 'parcel' or 'user'
   * @param {string} command - 'open' or 'close'
   */
  async controlDoor(doorType, command) {
    try {
      console.log(`📡 Sending to ESP32: ${doorType} door ${command}`);
      
      const response = await axios.post(`${this.baseUrl}/door`, {
        type: doorType,
        action: command
      }, {
        timeout: 5000
      });

      console.log(`✅ ESP32 Response:`, response.data);
      return {
        success: true,
        data: response.data
      };
    } catch (error) {
      console.error(`❌ ESP32 Error:`, error.message);
      return {
        success: false,
        error: error.message
      };
    }
  }

  /**
   * Get current door states from ESP32
   */
  async getDoorStates() {
    try {
      const response = await axios.get(`${this.baseUrl}/status`, {
        timeout: 5000
      });

      return {
        success: true,
        parcelDoorOpen: response.data.parcelDoorOpen || false,
        userDoorOpen: response.data.userDoorOpen || false,
        parcelDetected: response.data.parcelDetected || false
      };
    } catch (error) {
      console.error(`❌ ESP32 Status Error:`, error.message);
      return {
        success: false,
        parcelDoorOpen: false,
        userDoorOpen: false,
        parcelDetected: false
      };
    }
  }

  /**
   * Check if ESP32 is online
   */
  async ping() {
    try {
      await axios.get(`${this.baseUrl}/ping`, { timeout: 2000 });
      return true;
    } catch (error) {
      return false;
    }
  }
}

module.exports = new ESP32Controller();
