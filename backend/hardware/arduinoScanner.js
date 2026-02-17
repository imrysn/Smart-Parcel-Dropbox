/**
 * Arduino UNO R3 Scanner Controller
 * Communicates with MH-ET Live Scanner v3 via Serial
 */

const { SerialPort } = require('serialport');
const { ReadlineParser } = require('@serialport/parser-readline');

class ArduinoScanner {
  constructor() {
    this.port = null;
    this.parser = null;
    this.isConnected = false;
    this.onBarcodeCallback = null;
  }

  /**
   * Initialize serial connection to Arduino
   */
  async connect() {
    try {
      const portName = process.env.SCANNER_PORT || 'COM3';
      const baudRate = parseInt(process.env.SCANNER_BAUD_RATE) || 9600;

      this.port = new SerialPort({
        path: portName,
        baudRate: baudRate
      });

      this.parser = this.port.pipe(new ReadlineParser({ delimiter: '\n' }));

      this.port.on('open', () => {
        console.log(`✅ Arduino Scanner connected on ${portName}`);
        this.isConnected = true;
      });

      this.port.on('error', (err) => {
        console.error('❌ Arduino Scanner Error:', err.message);
        this.isConnected = false;
      });

      // Listen for barcode scans
      this.parser.on('data', (data) => {
        const barcode = data.trim();
        if (barcode && this.onBarcodeCallback) {
          console.log(`📦 Barcode scanned: ${barcode}`);
          this.onBarcodeCallback(barcode);
        }
      });

      return true;
    } catch (error) {
      console.error('❌ Failed to connect to Arduino:', error.message);
      return false;
    }
  }

  /**
   * Set callback for barcode scans
   */
  onBarcodeScan(callback) {
    this.onBarcodeCallback = callback;
  }

  /**
   * Send command to Arduino
   */
  sendCommand(command) {
    if (this.isConnected && this.port) {
      this.port.write(`${command}\n`);
      console.log(`📤 Sent to Arduino: ${command}`);
    }
  }

  /**
   * Disconnect from Arduino
   */
  disconnect() {
    if (this.port && this.port.isOpen) {
      this.port.close();
      this.isConnected = false;
      console.log('🔌 Arduino Scanner disconnected');
    }
  }
}

module.exports = new ArduinoScanner();
