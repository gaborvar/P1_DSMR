# Reads DSMR P1 telegrams from the serial log file. Relevant fields of the telegrams are written to a CSV (separator is semicolon) file as a table of records. 
# Prevents invalid data by checking for errors in the telegrams and either fixing them or dropping if a fix would be too complex.
# Calculates checksum from each telegram and writes TRUE for a match or FALSE for incorrect checksum to a CSV file.
# Takes several minutes to process a daily worth of (24x360) telegrams. File operations could be optimised.
# CSV output is intended to be processed by Excel. See charts separately. 
# Can be extended with further parsing of the telegrams. Currently it :
    # checks for voltage above regulated leves and marks the record. 
    # checks for current over a certain level and marks the record if above.
    # calculates power (kW) from the increment in the energy meter (kWh) and stores in a separate field. This is useful to valadate if the power field is characteristic of the full 10 sec interval.

# It detects communication errors and fixes certain frequently occurring error types. Additional correctable errors could be added to the error correction capabilities. 
        # E.g. timestamp may be occasionally incorrect, blurring stats if the noise hit the line holding the timestamp in the telegram. 
        # Timestamp could be calculated from the previous and the next telegram's timestamp. (not implemented)
# This is acceptable if error rate is low. For error rates > 10% per telegram (which corresponds less than 0.005% per byte) or larger you probably need more sophisticated error handling.

# $global:PerPlusMatches =""
# $global:FullChksumhistory =""


$inpLog = "P1 meter putty - 20230605.log"   # This is the input file that holds the log of the full serial communication from the meter.
# $loc = Get-Location
# echo $loc.Path
# echo $PSScriptRoot

# if ($psISE -ne $null) {
#    $defaultDirectory = $psISE.CurrentPowerShellTab.Path
#    Set-Location -Path $defaultDirectory
# }

$nFixedCks = 0
$ValidityStats =""  # will store a list of telegrams that failed the checksum test, and the number of characters that are not expected (i.e. ASCII CRLF or xFF)
$telegram =""


$earlierfirstline = "/AUX59902759988"   # initialization value for a valid first line. Used for error correction. 
    # This is a valid first line but may not be useful in the specific application, depending on the meter's choice of header. 
    # You may want to (but not necessary for error correction to work) replace this with the first line that your meter emits. 
    # It will be superseded with a correct first line taken from the feed so other meters with different first line can also benefit from error correction.


$telegramPrevkWhIn = $null
$TelegramPrevkWhInTime = $null

$nTelegrams = 0
$nFalseTelegram = 0

$timePat = "0-0:1\.0\.0\((\d{12}[SW])\).*"
$FirstLinesPattern = "\r\n\r\n0-0:1\.0\.0\([\s\S]*$" # This is the regex that matches the segment starting from the end of the first line to the first byte that changes from telegram to telegram
    # This will be used to test if a checkum-failed telegram actually has healthy beginning except for the first byte. 
    # The first byte is the most prone to transmission errors. It fortunately is easy to guess (/)

$VoltPat = '1-0:[357]2.7.0\((\d+\.\d+)\*V\)' # regular expression pattern to match the number
$AmpPat = '1-0:[357]1.7.0\((\d+)\*A\)' # regular expression pattern to match the number

$Volt3Pat = '1-0:32.7.0\((\d+\.\d+)\*V\)' # regular expression pattern to match voltage for phase 3
$Volt5Pat = '1-0:52.7.0\((\d+\.\d+)\*V\)' # regular expression pattern to match voltage for phase 5
$Volt7Pat = '1-0:72.7.0\((\d+\.\d+)\*V\)' # regular expression pattern to match the number

$Amp3Pat = '1-0:31.7.0\((\d+)\*A\)' # regular expression pattern to match the number
$Amp5Pat = '1-0:51.7.0\((\d+)\*A\)' # regular expression pattern to match the number
$Amp7Pat = '1-0:71.7.0\((\d+)\*A\)' # regular expression pattern to match the number

$kWPat = '1-0:1.7.0\((\d+\.\d+)\*kW\)' # regular expression pattern to match the number

$kWhInPat = '1-0:1.8.0\((\d+\.\d+)\*kWh\)'

$global:errorlog ="Timestamp,Position,NoisyChar,`r`n" 


# custom type to log athe relevant fields of the telegram

# [System.Management.Automation.PSTypeName]::

Add-type @" 
public class DSMRTelegramRecordType {
    public string timeString ;
    public double kWhIn ;
    public float Voltage3 ;
    public float Voltage5 ;
    public float Voltage7 ;
    public int Amp3 ;
    public int Amp5 ;
    public int Amp7 ;
    public float kW ;
    public float kWfromConsumption ;
    public string VoltStress ;
    public string AmpStress ;
    public string kWStress ;
}
"@ 

Function CheckSumFromTG($tlgr)  {
        [uint16]$chksum=0

        for ($TB = 0; $TB -lt $tlgr.length; $TB++) {
       # write-host ($Telegram[$TB], [System.Text.Encoding]::ASCII.GetBytes($telegram[$TB])[0])


            try {

                $chksum = $chksum -bxor ( [byte]$tlgr[$TB] )
                # whote-host "Conversion to byte, or XOR failed" 


            }
            catch {
                $errormessage = "cannot convert to byte or XOR char " + [int]$tlgr[$TB] + " in telegram $timestamp at character position $TB, after "
                $errormessage +=  $tlgr[[Math]::Max( $TB-7,0) .. [Math]::Max($TB-1, 0)]
                $global:errorlog += $timestamp +", "+ $errormessage +"`r`n"
                $chksum = 0
                break    # if error happens in the first char of the telegram then returns zero to avoid uninitialized local variable
            }



            
            $chksum = $ChksumLookup[$chksum]   # alternative with lookup. Lookup takes 15 ms vs 100 ms for each incoming byte on a specific i7-7700 CPU @ 3.60GHz system.
            #$global:FullChksumhistory += $chksum.ToString() + ", " # debug

#            $endTime = Get-Date
#            $endArithmTime = get-date
        }

                    # write-host $tlgr $chksum  $PerPlusMatches   ($tlgr -ceq $PerPlusMatches)
                    # if ( $chksum -eq 15090 ){
                    #    $global:PerPlusMatches = $tlgr
                    #    }
                    # write-host "It is "  ($tlgr -ceq $global:PerPlusMatches) "that " $chksum " should be 15090"

                    # $global:FullChksumhistory = ""
        return $chksum
    }

# create an array of records
$telegramRecords = New-Object System.Collections.Generic.List[DSMRTelegramRecordType]

#$telegramRecords = @( [DSMRTelegramRecordType]$null
#)
   [float] $maxV = 0 
   [int] $maxA = 0
   $MaxATime = ""
   $MaxVTime = ""

# [uint16]$chksum = 0
# [uint16]$c = 0
# [byte]$i = 0


############################################################################################################################################


# This routine creates a table which will be used to determine the updated checksum value given a new byte in the stream. It creates a lookup table (vector). 

# input: each of the possible checksum values i.e. from 0 to xFFFF 
# assumption: the new byte in the stream that should update the checksum is zero. At run time we will adjust the index into this vector to accommodate all 255 other data points. 
# output: a vector (one dimensional array) of uint16 numbers, each is the updated checksum assuming the old checksum is the index and the incoming data point is zero.
# 65536 uint16 data points as checksum values are 16 bit 


# note: We can cover all 65536 x 256 combinations of checksum and incoming data with just one vector. At run time the checksum needs to be XOR-ed with the incoming byte to calculate the correct index for the incoming byte.




    # Create an array with 65536 elements

$ChksumLookup = New-Object uint16[](65536)

$execTime = Get-Date

    for ( $c=0; $c -le 65535; $c++) {

            # checksum algorithm begins

        $chksum = $c   ##   Should be:   $c -bxor 0   but it equals $c

            for ($i = 0; $i -lt 8; $i++) {
                if ($chksum -band 1) {
                    $chksum = ($chksum -shr 1) -bxor 0xA001
                } else {
                    $chksum = $chksum -shr 1
                }
            }

    #        echo $c
       $ChksumLookup[$c] = $chksum
        
    }


# Alternatively, we can import the array from file. Not needed any more.

# $stream = New-Object System.IO.FileStream("C:\Users\gabor\OneDrive\Dokumentumok\KocsagU\NapelemVillany\P1\ChksumLookup.bin", [System.IO.FileMode]::Open)
# $reader = New-Object System.IO.BinaryReader($stream)

# $ChksumLookup = New-Object uint16[](65536)


# for ($i = 0; $i -lt 65536; $i++) {
#    $ChksumLookup[$i] = $reader.ReadUInt16()
# }

# $reader.Close()
# $stream.Close()

$execTime = $(get-date) - $execTime
Write-host "Checksum table prepared in $execTime"

##############################################################################################################################################



Get-Content $inpLog | ForEach-Object {

switch -regex   ($_) {

    "(/.*$)" {   # start of telegram indicated by /

        $telegram = $Matches[1] + "`r`n"   # anything in the line before a "/" is dropped. Anything before this line is also dropped (a telegram fragment). Normally this drops nothing except when the closing "!" of the previous telegram was not found

        break
        }


    "\!([0-9A-Fa-f]{4})$" {   # sender checksum indicated by "!" and four hex numbers (upper or lower case accepted), followed by end of line. ( a series of 9 characters including the beginning and ending CRLF characters)
            # to make it more robust we should test if this 7-character string occurs inside a data object (in a legitimate line of the telegram that can include arbitraty data)
            # e.g. Can the utility service provider message 0-0:96.13.0(<message>) may include "!" ?  
            # I did not find reference doc with sufficient details.  Best so far is https://www.netbeheernederland.nl/_upload/Files/Slimme_meter_15_a727fce1f1.pdf

        $telegram = $telegram + "!" 

        $SenderChks = $Matches[1]
        
        #if ($timestamp -eq "230427025540S"){
        #write-host $telegram
        #    }

#            $startTime = get-date 

             [uint16] $CalcChecksum =  CheckSumFromTG($telegram)

        try {
            $senderChksInt = [UInt16]::Parse($SenderChks, [System.Globalization.NumberStyles]::HexNumber)
       
        } catch {
            write-error "Unreadable CRC in telegram $timestamp."
            $senderChksInt = 0
         }




        $ValidityStats += $timestamp + "," 
        $ErrorCorrected = 0
        $nTelegrams ++
        [uint16]$ChksumTGCorrected = 0
        
        if ($senderChksInt -ne $CalcChecksum ) { # if checksums do not match handle the error here by trying to substitute suspect bytes. Otherwise skip forward to process telegram into a record.

 #               if ($telegram.Length -ne 2342) {
 #                   $tempMatch= ($telegram -cmatch $EarlierFirstLine.Substring(1) + $FirstLinesPattern)
 #                   $ChksumTGCorrected = CheckSumFromTG( "/" + $Matches[0])
 #           write-host "Telegram $timestamp length:   $($telegram.length) firstline match: $tempMatch  Calculated/Sent checksum: $ChksumTGCorrected / $senderChksInt"
 #           }     
 
            
            # test if the beginning of the telegram (disregarding the very first byte) is the same as expected, from earlier telegram(s). If so, it is likely that the error only affects the first byte. 
            # If a valid first line is found in a corrupted telegram then we assume this is the beginning of the telegram and ascertain it with an extra checksum calculation. 

            if  ( ($telegram -cmatch $EarlierFirstLine.Substring(1) + $FirstLinesPattern) -and ( ( CheckSumFromTG( "/" + $Matches[0])) -eq $senderChksInt )  )  {  # it should ensure that if the comparison throws an error execution continues in the right script block.

            # happiness, proceed to data extraction to TelegramRec after fixing the first byte of $telegram
                $nFixedCks++
                $Errorcorrected = $nFixedCks
                $errorlog += $timestamp

                $errorlog += ", fixed by resetting first char in $($telegram.substring(0,10)) to /. $nFixedCks telegrams fixed.`r`n"
                # write-host $telegram
                # write-host $Matches
        
                write-host "Telegram fixed. Chksum calculated from input: $CalcChecksum.  Corrected $nFixedCks  old length: $($telegram.Length)"
                $telegram = "/" + $Matches[0]
 
                }

                # future error correction hint: replace in the custom service provider message with xFF and add extra xFF if shorter due to error that created UTF8 prefix character

     #           if ($telegram -match $ServProviderMessagePat) {
     #               $TGwithoutcustomMessage = $telegram -replace "0-0:96\.13\.0\(.*?\)\r\n", ""

     #               $Noisychars = $TGwithoutcustomMessage | Select-String -pattern "(\x100-\xFFFF)" -AllMatches | ForEach-Object { $_.Matches }
            
            else {

 
        
            # Give up. This telegram is unhealable. We just record the error parameters and exit telegram processing without recording the values in TelegramRec

            $nFalseTelegram ++
            $rateFalse = [math]::Round($nFalseTelegram / $nTelegrams *100 , 2)
            $errorlog += $timestamp

            echo "Chksum error at $timestamp, rate of error: $rateFalse %  or $nFalseTelegram"            


            $pattern = '[\x00-\x09\x0B-\x0C\x0E-\x1F\x80-\xFE]'   # matches non-ASCII characters except xFF, CR and LF. These are not expected in a DSMR telegram. (except perhaps the service provider message) 
            $NoisyChars = $telegram | Select-String -Pattern $pattern -AllMatches | ForEach-Object { $_.Matches }   # select-string operates on all $telegram at once, not per line.
            
            foreach ($NChar in $NoisyChars) {
                Write-Host " Non-ASCII character '$($NChar.Value)' at position $($NChar.Index)" 
                $errorlog += "," + $NChar.Index + "," +  [int]($NChar.Value[0])
                }

            if ($noisychars -and ($NChar.index -lt ($telegram.Length-6) ) ) { 
                $errorlog += "," + $telegram.substring($NChar.index+1, 5)  }
                else {
                $errorlog+= ", no invalid char but telegram failed for other reason"
                }
            $errorlog += "`r`n"

            $ValidityStats +=  "False,"  +   $NoisyChars.Length + "`r`n"  # +  $senderChksInt.ToChar(

            #  Remove leftovers from this telegram that would contaminate the next. We discard fragments, although it could might be possible to fix the error by examining remaining lines. For future improvement.

            $telegram  = ""
            $timestamp = ""

            break    #exit the Switch case for terminating line in the telegram (!<checksum>). Continue with starting fresh looking for the next start of telegram in the same Switch in the next iteration.

            }
            # issue: if an error is generated in the if statement ($telegram -cmatch $EarlierFirstLine.Substring(1) + $FirstLinesPattern) then neither of the branches execute but execution continues here.
            # Pattern is tested to exclude any non-printable ASCII but there might be other reasons why a statement may generate an error.
        }




     # the current telegram should be syntactically correct from this point on, e.g. $timestamp should exist and be meaningful. If it weren't it would have failed the checksum test

            $ValidityStats +=  "True,"  +   $ErrorCorrected + "`r`n"

            $FirstLine = $telegram -split '\r?\n' | Select-Object -First 1    # store the first line of the telegram to see if transmission errors in the first line of later telegrams can be corrected. 

            if ( $EarlierFirstLine -ne $EarlierFirstLine ) {
            if ( ! ( $FirstLine | Select-String -Pattern '[\x00-\x09\x0B-\x0C\x0E-\x1F\x80-\xFE\(\)\\\.]')) {    # Only employ the first line if it does not inclde characters that are likely errors, e.g. non-ASCII chars with exceptions
                $EarlierFirstline = $FirstLine
                $errorlog += "First line of telegram " + $timestamp + " is different from earlier:" + $FirstLine +". Will be used to correct errors."
                }
                }

            # create a single record 
            $telegramRec = [DSMRTelegramRecordType] @{
                kWhIn = [double]::NaN
                Voltage3 = [float]::NaN
                Voltage5 = [float]::NaN
                Voltage7 = [float]::NaN
                Amp3 = [int]::MinValue
                Amp5 = [int]::MinValue
                Amp7 = [int]::MinValue
                kW = [float]::MinValue
                kWfromConsumption = [float]::NaN
                VoltStress = ""
                AmpStress = ""
            }



            switch -regex ($telegram) {

                $timePat  {  $Telegramrec.TimeString = $Matches[1]  # Time field
                    }

                $kWhInPat {  $TelegramRec.kWhIn = [double]$Matches[1] # convert the matched string to a double
                    }

                $volt3pat {  
                    $TelegramRec.Voltage3 = [float]$Matches[1] # convert the matched string to a float
                    if ($TelegramRec.Voltage3 -gt 240) { $telegramrec.VoltStress += "3" }
                    }

                $Volt5Pat {  $TelegramRec.Voltage5 = [float]$Matches[1] # convert the matched string to a float
                    if ($TelegramRec.Voltage5 -gt 240) { $telegramrec.VoltStress += "5" }
                    }

                $Volt7Pat {  $TelegramRec.Voltage7 = [float]$Matches[1] # convert the matched string to a float
                    if ($TelegramRec.Voltage7 -gt 240) { $telegramrec.VoltStress += "7" }
                    }

                $Amp3Pat {   $TelegramRec.Amp3 = [int]$Matches[1] # convert the matched string to an integer
                    if ($TelegramRec.Amp3 -gt 16) { $telegramrec.AmpStress += "3" }
                    }

                $Amp5Pat {   $TelegramRec.Amp5 = [int]$Matches[1] # convert the matched string to an integer
                    if ($TelegramRec.Amp5 -gt 16) { $telegramrec.AmpStress += "5" }
                    }

                $Amp7Pat {   $TelegramRec.Amp7 = [int]$Matches[1] # convert the matched string to an integer
                    if ($TelegramRec.Amp7 -gt 16) { $telegramrec.AmpStress += "7" }
                    }

                $kWPat { $TelegramRec.kW = [float]$Matches[1] # convert the matched string to a float
                    if ($TelegramRec.kW -gt 4400) { $telegramrec.kWStress = $true }
                    }

                } 




            # Convert the timedate field string of the telegram into time. This will be used only for internal stuff. Output will use the original OBIS/COSEM format.

         

            $TelegramTime = get-date -year ("20"+$timestamp.substring(0,2)) -month $timestamp.substring(2,2) -day $timestamp.substring(4,2) -hour $timestamp.Substring(6,2) -minute $timestamp.Substring(8,2)  -second $timestamp.Substring(10,2)  

               if ($timestamp[-1] -eq "S" ) {    # Standard (winter) hour is 1 lower in summer than the timestamp
              
                $TelegramTime += new-timespan -Hours 1
                
                  }

       

            if ($TelegramPrevkWhInTime) {


                                  # we assume that time between the last two records were 10 seconds if the dates are less than 15 seconds apart.
                                  # for longer time periods we do not calculate power consumption from the two energy readings

                if ( ($TelegramTime.subtract($TelegramPrevkWhInTime)).totalseconds -lt 15 )   {   # when switching from and to daylight saving time a record may be lost.

                    $TelegramRec.kWfromConsumption = ( $TelegramRec.kWhIn - $TelegramPrevkWhIn ) * 360  # Assuming that each telegram is 10 seconds apart, calculating power from energy by deviding energy with time (1/360 hours)
                    }
                        else {
                        $TelegramRec.kWfromConsumption = [float]::NaN
                        }

                }  
                else {
                    $TelegramRec.kWfromConsumption = [float]::NaN
                    }


            $TelegramPrevkWhInTime = $TelegramTime
            $TelegramPrevkWhIn = $TelegramRec.kWhIn

            if ( $TelegramRec.Voltage3 -ge $maxV ) {

                $maxv = $telegramRec.Voltage3
                $MaxVTime = $Timestamp
                $TelegramRec.VoltStress += "3"
                }


            if ( $TelegramRec.Voltage5 -ge $maxV ) {

                $maxv = $telegramRec.Voltage5
                $MaxVTime = $Timestamp
                $TelegramRec.VoltStress += "5"
                }

            if ( $TelegramRec.Voltage7 -ge $maxV ) {

                $maxv = $telegramRec.Voltage7
                $MaxVTime = $Timestamp
                $TelegramRec.VoltStress += "7"
                }



            if ( $TelegramRec.Amp3 -ge $maxA ) {

                $maxA = $telegramRec.Amp3
                $MaxATime = $Timestamp
                $TelegramRec.AmpStress += "3"
                }


            if ( $TelegramRec.Amp5 -ge $maxA ) {

                $maxA = $telegramRec.Amp5
                $MaxATime = $Timestamp
                $TelegramRec.AmpStress += "5"
                }

            if ( $TelegramRec.Amp7 -ge $maxA ) {

                $maxA = $telegramRec.Amp7
                $MaxATime = $Timestamp
                $TelegramRec.AmpStress += "7"
                }



            $telegramrecords += $telegramRec   #.psobject.Copy()


            

            $telegram  = ""
            $timestamp = ""

        }

    $timePat {
        $Timestamp = $matches[1]
        $telegram = $telegram + $_ + "`r`n" 
        }



#    "(/.*$)" {   # This is in prep for simple error handling/correction. 
                    # The most frequent error in a transmission affects the first few bytes of the telegram. 
                    # Out of these errors the most frequent error replaces the "/" with ascii 14.   
                    # This is an error that is easy to correct (replace three characters before the assumed start of telegram with "CRLF/" and re-test the checksum start of telegram indicated by /

        # $telegram = $Matches[1] + "`r`n"   # anything in the line before a "/" is dropped. Anything before this line is also dropped (a telegram fragment). Normally this drops nothing except when the closing "!" of the previous telegram was not found

        # break
        # }

    
    default {$telegram = $telegram + $_ + "`r`n" }
}


}
$outCSV = $inpLog + "-validity.csv"
Out-File -FilePath $outCSV  -InputObject $ValidityStats   # this output file holds a record for each telegram whether correct or not. 
    # For erroneous (not corrected) telegrams it provides the number of unexpected chars (minimum number as it does not attempt to find all incorrect chars.)
    # for corrected records it includes how many errors were corrected from the beginning of the file. 
    # for untouched records it is zero.

$rateFalse = [math]::Round($nFalseTelegram / $nTelegrams *100 , 2)
echo "$nFalseTelegram checksums are still false. Rate of error: $rateFalse %. $nFixedCks of $nTelegrams telegrams are fixed in $inpLog"

Out-File -FilePath ($inpLog + ".Noise.csv")  -InputObject $errorlog   # this is an error log file. Only reports when an incoming telegram whad errors

# out-file -FilePath ($inpLog+".txt") -inputobject $telegramRecords
$telegramRecords | Export-Csv -Path ($inpLog+"_Records.csv") -NoTypeInformation -UseCulture  # this is the main output file with "_Records.csv" appended to the input file name

if ( $maxVtime -and $maxATime )
    {
            #  $SummaryMax = 
    write-output ("Maximum voltage: " + $maxV +  " on date " + $maxVtime.Substring(2,4) + " at " + $maxVtime.substring(6,4) + ".  Max current: " + $maxA + " A at " + $maxAtime.Substring(6,4) + " in log '"+ $inpLog +"'")
    }