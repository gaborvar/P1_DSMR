# P1_DSMR

Providing energy metering data to home energy management automation and integration.
PowerShell script code and hardware implementation sample included. 


**Intro**

This experimental project is useful in homes with electricity meters that are equipped with a P1 port, using DSMR data specs. This is a fairly common interface offered by a growing number of electricity providers to home owners to access data generated within the meter installed in their homes by the electricity service provider.

While several commercial P1 interface implementations are available, the goal of this small project was to avoid dependency on:
* Wireless (WiFi or other)
* External links outside your home
* Data integration limitations from an external party controlling data availability and associated service fees 

You are in the intended audience if:
* you want more control than commercially available building blocks allow
* you know how you want to use your meter data. This project does not attempt to replicate either Home Assistant or visulisations but it provides useful input to either. 
* you are considering a hardware interface (simple electronics) between the meter and your usage point. However you can substitute this step with commercial ready-to-order equipment or with flashing firmware.
* you use platforms where PowerShell runs, Windows or others. Code tested only on Windows 10 and should be fairly easy to port to non-Windows platforms.

Have fun building - and please keep feedback flowing !


**Input:**
Currently log files that mirror the P1 port, created by Putty terminal. 

**Output:**
CSV files with data fields for filtered and preprocessed data for use in energy management in HA or other platforms, without the cryptic stuff in the DSMR interface. In my case grid phase voltage is critical because overvoltage disables the production of power from the PV plant on my roof. To avoid overvoltage situations I plan to manage consumption in Home Assistant so I added voltage fields to the output. Change the PowerShell code as your needs dictate. Peak current may be also useful if you want to switch on or off equipment in your home automatically for your optimisation objectives.


**Implementation**

Due to specifics of the output interface on the smart meter (open collector port) a slim but important electronics layer is needed.
I was not fortunate to accomplish the necessary signal inversion by reconfiguring the chip in my USB converter cable as others did with their FTDI chips. The PL-2303 GC chip within my DTECH USB/serial converter cable is either not able to invert the signal or it is not documented. I created the simple circuit suggested and documented by others. Sufficient literature is available on other sites (e.g. https://github.com/sza2/esp01p1dsmr, thanks for sharing) so I only share two photos of my temporary board.

The cabling and the electronics are not immune to errors from noise currently. I hope the final implementation will be more resistant. I detect checksum error on 0.3 pct of telegrams on average, measured before error correction. Error rate fluctuates for specific periods of the day so I suspect a noise source somewhere in the neighborhood which is switched on for specific times of the day. Noise rate improved when I tweaked the capacitance smoothing the power supply from the USB side. I hope there is still room for improvement by more tweaks. 

I use roughly 10 meter Cat5e cable between the power meter and the electronics which is connected to the USB port of the PC with a short USB cable. Out of the four twisted pairs in the Cat5e, I chose to use one of the pairs for the Data and the Data GND pins rather than assigning them to wires in two different pairs - which would have been more straightforward given the pinout of the RJ12 interface on the meter. I am hoping to be more resistant to noise this way but I did not test the alternative. If you have an opinion on how wire assignment influences noise you are welcome.

Sharing photos of the preliminary electronics.

I do some error handling in the code to improve reliability of the readings and preserve more data rather than discarding full telegrams due to checksum falure. I still experience noise between the meter and the USB interface. Based on the typical errors (failure modes) that affect my system, the logic checks for the most frequent errors and corrects the telegram. I can catch and correct 50-90% of the errors with this mechanism. The checksum method employed in DSMR v5 is 16 bit which limits our ability to catch all faulty telegrams: If the meter emits a telegram every 10 seconds it means roughy 9k data transfers daily. The likelyhood of at least one faulty telegram which produces the same checksum as the transmitted original adds up fairly quickly.


**Usage**

DSMRTelegrams.ps1 script is the main module.
First run PrepareChecksumLookup.ps1 which precalculates an array for checksum computing. It creates ChksumLookup.bin that DSMRTelegrams.ps1 relies on. 


**Useful links (many thanks to the authors!):** 

https://github.com/matthijskooijman/arduino-dsmr

https://github.com/matthijskooijman/arduino-dsmr/tree/master/src/dsmr

https://www.ztatz.nl/

https://github.com/sza2/esp01p1dsmr

(in Hungarian:) 

https://www.eon.hu/content/dam/eon/eon-hungary/documents/Lakossagi/aram/muszaki-ugyek/p1_port%20felhaszn_interfesz_taj_%2020230210.pdf

https://hup.hu/node/173041


**Future plans**

I intend to test USB virtualization software in Windows 10 which allows me to pass the data from this project to a Hyper-V VM that runs Home Assistant.

I plan to replace file based input created as terminal logs with directly reading the USB port from code.

I will probably stop the maintenance of this project after a few more iterations. Once HA integration works I will develop control logic there and I will conclude this P1/DSMR learning exercise as accomplished.
