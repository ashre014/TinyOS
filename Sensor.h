#ifndef SENSOR_H
#define SENSOR_H

enum {
    // IDs for radio and serial active message
    RADIO_AM_ID = 0xC0,
    SERIAL_AM_ID = 0x89,

    // Time in milliseconds for the timers
    SENSOR1_TIMER_PERIOD_MILLI = 1024,
    SENSOR2_TIMER_PERIOD_MILLI = 2048,
};

// struct to store sensor data
typedef nx_struct RadioMsg {
    // type to distinguish either temperature or luminance
    nx_uint8_t type;

    // temperature / luminance reading from the sensor
    nx_uint16_t reading;
}
radio_message_t;

// Message length for the serial transfer
#ifndef MSG_LENGTH
#define MSG_LENGTH	28
#endif

// struct to store serial data
typedef nx_struct SerialMsg {
    // message to send to the PC
    nx_uint8_t data[MSG_LENGTH];
}
serial_message_t;

#endif
