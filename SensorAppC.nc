configuration SensorAppC { }

implementation {

    components SensorC as App;
    components MainC;

    // Timer components
    components new TimerMilliC() as Timer1;
    components new TimerMilliC() as Timer2;


    // Component for sending and receiving radio message
    components ActiveMessageC;
    // Component for sending radio messages
    components new AMSenderC(RADIO_AM_ID);
    // Component for receiving radio messages
    components new AMReceiverC(RADIO_AM_ID);


    // Component for the total solar radiation sensor
    components new HamamatsuS10871TsrC() as Photo;
    // Component for the temperature sensor
    components new SensirionSht11C() as Temp;

    // Component for serial interface
    components SerialActiveMessageC;
    components new SerialAMSenderC(SERIAL_AM_ID);


    // Wiring to external interfaces
    // MainC is the provider for the Boot interface
    App.Boot -> MainC;

    // Wiring for timer interfaces
    App.Timer1 -> Timer1;
    App.Timer2 -> Timer2;

    // Wiring for radio interfaces
    App.AMControl -> ActiveMessageC;
    App.Packet -> AMSenderC;
    App.AMSend -> AMSenderC;
    App.Receive -> AMReceiverC;

    // Wiring fot serial interface
    App.SerialAMControl -> SerialActiveMessageC;
    App.SerialPacket -> SerialAMSenderC;
    App.SerialAMSend -> SerialAMSenderC;

    // Wiring for sensor interfaces
    App.Photo -> Photo;
    App.Temp -> Temp.Temperature;
}
