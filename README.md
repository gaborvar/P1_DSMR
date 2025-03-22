# P1_DSMR

The objective of this project is to provide energy meter data to home energy management automation and integration.
The project includes PowerShell script code and hardware implementation sample.


# Intro

This experimental project is useful in homes with electricity meters that are equipped with a P1 port, implementing DSMR data specs. This is a fairly common interface offered by a growing number of electricity providers to home owners to access data generated within the meter installed in their homes by the electricity service provider.

While several commercial P1 interface implementations are available, the goal of this small project was to avoid dependency on:
* Wireless (WiFi or other)
* External links outside your home
* Data integration limitations imposed by external parties that control data availability and may charge service fees or seek other compensation
* Noise causing transmission errors from the meter. 

You are in the intended audience if:
* you want more control than commercially available building blocks allow
* you know how you want to use your meter data. This project does not attempt to replicate either Home Assistant or visualisations but it provides useful input to them. 
* you are considering a hardware interface (simple electronics) between the meter and your usage point. You can substitute this step with commercial ready-to-order equipment or by flashing firmware of your interface.
* you use platforms where PowerShell runs, Windows or others. Code tested only on Windows 10 and should be fairly easy to port to non-Windows platforms.

Have fun building - and please keep feedback flowing !


# Input:
In the current implementation the input is log files that mirror the P1 port data flow (telegrams). These log files can be created by e.g. Putty terminal. Code can be changed to take serial port as input directly.

# Output:

CSV files. Data fields include filtered and preprocessed data for use in energy management in HA or other platforms, without the cryptic stuff in the DSMR interface. 
In my case grid phase voltage seemed critical because overvoltage disables the production of power from the PV plant on my roof so I added voltage fields to the CSV output. These fields allowed me to analyse voltage and conclude that overvoltage can be fully addressed by simply assigning the largest consuming devices to the right phase. In your case more sophisticated management may be necessary but the voltage fields are there for use in your optimization logic.
I also added calculated fields to alleviate the limitation in many meter models that current (A) is truncated to integer and direction of energy flow is not directly tracked per phase. Change the PowerShell code as your needs dictate. Peak current may be also useful if you want to switch on or off equipment in your home automatically for your optimisation objectives.
Two additional files are also created: A validity CSV that includes a line for each input telegram with a boolean specifying if the record is valid (without or after CRC based error correction) or not. The third output is a log of noise induced errors and the conclusion of attempts to correct them, with some details to understand line noise. 

# Implementation

Due to specifics of the output interface on the smart meter (open collector port) a slim but important electronics layer is needed.
I was not fortunate enough to accomplish the necessary signal inversion by reconfiguring or flashing the chip in my USB converter cable as others did with their FTDI chips. The PL-2303 GC chip within my DTECH USB/serial converter cable is either not able to invert the signal or it is not documented. I created the simple circuit suggested and documented by others. Sufficient literature is available on other sites (e.g. https://github.com/sza2/esp01p1dsmr, thanks for sharing) so I only share two photos of my temporary board.

The cabling and the electronics are not immune to errors from noise. I detect checksum error in 10 telegrams daily on average, with high variability. In my case the pattern of errors suggest both residential and atmospheric noise i. e. error rate is significantly higher in stormy weather. Noise rate improved when I tweaked the capacitance smoothing the power supply from the USB side. Errors are corrected with logic implemented in code. I could further improve error rate by correcting more error types but I postpone work as long as the current reliability of transmission (three to four nines) is acceptable.

I use roughly 10 meter Cat5e cable between the power meter and the electronics which is connected to the USB port of the PC with a short USB cable. Out of the four twisted pairs in the Cat5e, I chose to use one of the pairs for the Data and the Data GND pins rather than assigning them to wires in two different pairs - which would have been more straightforward given the pinout of the RJ12 interface on the meter. I am hoping to be more resistant to noise this way but I did not test the alternative. If you have an opinion on how wire assignment influences noise you are welcome.

Sharing photos of the preliminary electronics.

I do error handling in the code to improve reliability of the readings and preserve more data rather than discarding full telegrams due to checksum failure in certain bytes within them.  Based on the typical errors (failure modes) that affect my system, the logic checks for the most frequent errors and corrects the telegram. I can catch and correct 80-95% of the errors with this mechanism. The checksum method employed in DSMR v5 is 16 bit which limits our ability to catch all faulty telegrams: If the meter emits a telegram every 10 seconds it means roughy 9k data transfers daily. The likelihood of at least one faulty telegram which produces the same checksum as the transmitted original adds up fairly quickly.


# Usage

DSMRTelegrams.ps1 script is the main module. 
Change the name of the input file in line ' $inpLog = "P1 meter putty - 20230605.log" '  
Run it in the same directory where the serial log file is located. 



# Useful links (many thanks to the authors!):

https://github.com/matthijskooijman/arduino-dsmr

https://github.com/matthijskooijman/arduino-dsmr/tree/master/src/dsmr

https://www.promotic.eu/en/pmdoc/Subsystems/Comm/PmDrivers/IEC62056_OBIS.htm  (OBIS codes from IEC standard)

https://www.ztatz.nl/

https://github.com/sza2/esp01p1dsmr

(in Hungarian:) 

https://www.eon.hu/content/dam/eon/eon-hungary/documents/Lakossagi/aram/muszaki-ugyek/p1_port%20felhaszn_interfesz_taj_%2020230210.pdf

https://hup.hu/node/173041



# Future plans

I intend to test data protection technologies like confidential computing to address concerns with cloud based processing. See https://learn.microsoft.com/en-us/azure/confidential-computing/confidential-containers

I experimented with integration with Open AI large language models to see how they can be used to understand and infer from data provided by this project. The platform for LLM integration was Home Assistant. Open AI models can be prompted to access external data sources through APIs provided by external party. Home Assistant offers an API that is a good fit for the LLM to call when it decices that it needs preloaded P1 data and other related data stored in Home Assistant. (this code is not yet included in this public Github project)

I planned to test USB virtualization software in Windows 10 which allows me to pass data from this project to a Docker container that runs Home Assistant in WSL (Windows Subsystem for Linux). I plan to replace file based input created as terminal logs with directly reading the USB port from code. Other approaches than USB virtualization might be a better fit for this goal.

I will look into leveraging other DSMR parsers available on github, however there are implementation differences apparently even within the same jurisdiction (in my case Hungary) which may prevent me from using generic DSMR libraries not honed for my electricity provider. 

I will probably stop the maintenance of this project after a few more iterations. Once HA integration and cloud integration works I will develop control logic there and I will conclude this P1/DSMR learning exercise as accomplished.
