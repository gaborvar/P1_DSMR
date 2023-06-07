
$inpLog = "Sample P1 meter putty - 20230428.log"
# Specify the serial port settings
$port = new-Object System.IO.Ports.SerialPort COM3,115200,None,8,one


 [byte] $serdata = 0 
# Open the serial port
write-host $port.Open()

# Read data from the serial port

while ($port.isopen) {
$serdata = $port.Readbyte()


Write-Host ($serdata, [char]$serdata )

}
# Close the serial port
$port.Close()