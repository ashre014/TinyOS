#include <stdio.h>

#include "Sensor.h"

module SensorC {

    uses interface Boot;

    // Timer interface with millisecond resolution
    uses {
        interface Timer<TMilli> as Timer1;
        interface Timer<TMilli> as Timer2;
    }

    // Radio interface
    uses {
        // interface for starting and stopping the radio
        interface SplitControl as AMControl;

        // interface for packet
        // provides accessors for the message_t
        interface Packet;

        // interface for sending radio messages
        // provides the AM sending interface
        interface AMSend;

        // interface for receiving radio messages
        // provides an event for receiving messages
        interface Receive;
    }

    // Serial interface
    uses {
        // interface for serial interface control
        interface SplitControl as SerialAMControl;
        // interface for serial packet
        interface Packet as SerialPacket;
        // interface for sending serial messages
        interface AMSend as SerialAMSend;
    }

    // interfaces for reading from the sensor hardware
    uses interface Read<uint16_t> as Photo;
    uses interface Read<uint16_t> as Temp;
}

implementation {

    // reference voltage of ADC
    float REFERENCE_VOLTAGE = 1.5;
    // Highest level for 12 bit ADC
    float ADC_LEVEL = 4096.0;
    // resistance
    float RESISTANCE = 100000.0;

    // radio status indicator
    bool radioBusy = FALSE;
    bool uartBusy = FALSE;

    // message buffers
    message_t buffer;
    message_t serialBuffer;

    // variables to store outgoing messages
    radio_message_t *radioMessage;
    serial_message_t *serialMessage;

    // variables to store incoming messages
    radio_message_t *incomming_payload;

    // variable to store intermediate values
    float voltage = 0.0;
    float current = 0.0;

    // variables to store temperature and luminance
    float temperature;
    float luminance;

    // task declarations
    task void readTemperature();
    task void readLuminance();

    task void transmitSensorPayload();
    task void transmitSerialPayload();

    // on successful boot
    event void Boot.booted() {

        // enable the radio
        call AMControl.start();

        if (TOS_NODE_ID != 2) { return; }

        // enable the serial interface for node 2
        call SerialAMControl.start();
    }

    // event for radio status
    event void AMControl.startDone(error_t err) {

        if (err == SUCCESS) {
            // timers not needed for node 2
            if (TOS_NODE_ID == 2) { return; }

            // start the timers
            call Timer1.startPeriodic(SENSOR1_TIMER_PERIOD_MILLI);
            call Timer2.startPeriodic(SENSOR2_TIMER_PERIOD_MILLI);
        } else {
            // try enabling the radio on failure
            call AMControl.start();
        }
    }

    // event for serial interface status
    event void SerialAMControl.startDone(error_t err) {

        if (err == SUCCESS) { return; }

        // try initializing the interface on failure
        call SerialAMControl.start();
    }

    // events for handling radio and serial hardware shutdown
    event void AMControl.stopDone(error_t err) { }
    event void SerialAMControl.stopDone(error_t err) { }

    // event for handling sent radio message
    event void AMSend.sendDone(message_t *message, error_t err) {

        if (message == &buffer) {
            // set the radio state flag to idle
            radioBusy = FALSE;
        }
    }

    // task to start sending sensor data payload
    task void transmitSensorPayload() {

        // try sending the payload
        if (call AMSend.send(AM_BROADCAST_ADDR, &buffer, sizeof(radio_message_t)) != SUCCESS) {
            // try again on failure
            post transmitSensorPayload();
        } else {
            // set the radio state flag to busy on success
            radioBusy = TRUE;
        }
    }

    // event for handling temperature read
    event void Temp.readDone(error_t err, uint16_t value) {

        // try reading again on failure
        if (err != SUCCESS) {
            post readTemperature();
            return;
        }
        /*
            Conversion formula obtained from
            https://sensirion.com/media/documents/BD45ECB5/61642783/Sensirion_Humidity_Sensors_SHT1x_Datasheet.pdf, page 8 and 9
            Assuming the sensor is running off of 3V and the ADC has 14 bits resolution
        */
        // calculate the temperature
        temperature = -39.60 + (0.01 * value);

        // get the payload field of the radio packet
        radioMessage = (radio_message_t *)(call Packet.getPayload(&buffer, sizeof(radio_message_t)));

        // return if radioMessage pointer is NULL
        if (radioMessage == NULL) { return; }
        // return if payload length is less than sizeof(radio_message_t)
        if (call Packet.maxPayloadLength() < sizeof(radio_message_t)) { return; }

        // set type to 1 to indicate temperature data
        radioMessage->type = (nx_uint8_t)1;
        // set the temperature reading
        radioMessage->reading = (nx_uint16_t)temperature;

        // schedule task to transmit the packet
        post transmitSensorPayload();
    }

    // event for handling luminance read
    event void Photo.readDone(error_t err, uint16_t value) {

        // try reading again on failure
        if (err != SUCCESS) {
            post readLuminance();
            return;
        }
        /*
            Conversion formula obtained from
            http://tinyos.stanford.edu/tinyos-wiki/index.php/Boomerang_ADC_Example#PAR.2FTSR_Light_Photodiodes
        */
        // calculate the voltage
        voltage = (value / ADC_LEVEL) * REFERENCE_VOLTAGE;
        // calculate the current
        current = voltage / RESISTANCE;
        // calculate luminance
        luminance = 0.625 * 1e6 * current * 1000;

        // get the payload field of the radio packet
        radioMessage = (radio_message_t *)(call Packet.getPayload(&buffer, sizeof(radio_message_t)));

        // return if radioMessage pointer is NULL
        if (radioMessage == NULL) { return; }
        // return if payload length is less than sizeof(radio_message_t)
        if (call Packet.maxPayloadLength() < sizeof(radio_message_t)) { return; }

        // set type to 2 to indicate luminance data
        radioMessage->type = (nx_uint8_t)2;
        // set the luminance reading
        radioMessage->reading = (nx_uint16_t)luminance;

        // schedule task to transmit the packet
        post transmitSensorPayload();
    }

    // task to read temperature
    task void readTemperature() {
        // schedule to read the temperature on failure
        if (call Temp.read() != SUCCESS){ post readTemperature(); }
    }

    // task to read luminance
    task void readLuminance() {
        // schedule to read the luminance on failure
        if (call Photo.read() != SUCCESS){ post readLuminance(); }
    }

    // Handle Timer1 event
    event void Timer1.fired() {
        // if radio is not busy, schedule task to read luminance
        if (!radioBusy) { post readLuminance(); }
    }

    // Handle Timer1 event
    event void Timer2.fired() {
         // if radio is not busy, schedule task to read temperature
        if (!radioBusy) { post readTemperature(); }
    }

    // task to transmit serial payload
    task void transmitSerialPayload() {

        // try sending the serial packet
        if (call SerialAMSend.send(AM_BROADCAST_ADDR, &serialBuffer, sizeof(serial_message_t)) != SUCCESS) { 
            // schedule the task again on failure
            post transmitSerialPayload();
        } else {
            // set the status to busy
            uartBusy = TRUE;
        }
    }

    // event for handling sent serial message
    event void SerialAMSend.sendDone(message_t *message, error_t err) {
        // set the status to idle
        if (&serialBuffer == message) {
            uartBusy = FALSE;
        }
    }

    // event for handling received messages over radio
    event message_t *Receive.receive(message_t *message, void *payload, uint8_t length) {
        // only node 2 forwards data through serial interface
        if (TOS_NODE_ID != 2) { return message; }
        // check the size of received messages
        if (length != sizeof(radio_message_t)) { return message; }

        // cast the payload to radio_message_t type
        incomming_payload = (radio_message_t *)payload;

        // get the payload field of the serial packet
        serialMessage = (serial_message_t *)(call SerialPacket.getPayload(&serialBuffer, sizeof(serial_message_t)));

        // return if serialMessage pointer is NULL
        if (serialMessage == NULL) { return message; }
        // return if payload length is less than sizeof(serial_message_t)
        if (call SerialPacket.maxPayloadLength() < sizeof(serial_message_t)) { return message; }

        // fill serialMessage->data with 0's
        memset(serialMessage->data, 0, sizeof(serial_message_t));

        // if the payload type is 1, it is temperature data
        if (incomming_payload->type == 1) {
            // format the serial message with space padded temperature reading
            sprintf((char *)serialMessage->data, "Temperature : %4d\r\n", incomming_payload->reading);
        // if the payload type is 2, it is luminance data
        } else if (incomming_payload->type == 2) {
            // format the serial message with space padded luminance reading
            sprintf((char *)serialMessage->data, "Luminance   : %4d\r\n", incomming_payload->reading);
        }

        // schedule task to transmit the serial packet
        if (!uartBusy) { post transmitSerialPayload(); }
        
        return message;
    }
}
