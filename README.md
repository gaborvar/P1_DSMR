# P1_DSMR
Energy meter data processing to provide input data to energy management automation
PowerShell script code provided. 

Due to specifics of the output interface on the smart meter (open collector port) a slim but important elecronics layer is needed.
I was not fortunate to do the job by reconfiguring chip in my USB converter cable as others did with FTDI chips. The PL-2303 GC chip within my DTECH USB/serial converter cable is either not able to invert the signal or not documented how to do it. I created the simple circuit suggested and documented by others. Sufficint literature is available on other sites so I only share two photos of my temporary board. 

The cabling and the electronics are not immune to errors from noise. I hope the final implemenation will be more resistant. Currently I detect checksum error on 0.3 pct of telegrams on average. Error rate fluctuates for specific periods of the day so I suspect a noise source somewhere in the neighborhood. Noise rate improved when I tweaked the capacitance smoothing the power supply from the USB side. I hope there is still room for improvement by more tweaks. 
I use a roughly 10 meter Cat5e cable between the power meter and the electronics which is connected to the USB port of the PC with a short USB cable.
 
A shared photos of the electronics.


Useful links (thanks to the authors): 

https://github.com/matthijskooijman/arduino-dsmr
https://github.com/matthijskooijman/arduino-dsmr/tree/master/src/dsmr

https://www.ztatz.nl/

https://github.com/sza2/esp01p1dsmr

(in Hungarian) https://www.eon.hu/content/dam/eon/eon-hungary/documents/Lakossagi/aram/muszaki-ugyek/p1_port%20felhaszn_interfesz_taj_%2020230210.pdf


