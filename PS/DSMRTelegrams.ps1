﻿# Reads DSMR P1 telegrams from the serial log file. Relevant fields of the telegrams are written to a CSV (separator is semicolon) file as a table of records. 
# Prevents invalid data by checking for errors in the telegrams and either fixing them or dropping if a fix would be too complex.
# Calculates checksum from each telegram and writes TRUE for a match or FALSE for incorrect checksum to a CSV file. (currently inactive for performance - $ValidityStats)
# CSV output is intended to be processed by Excel. See charts separately. 
# Can be extended with further parsing of the telegrams. Currently it :
    # checks for voltage above regulated levels and marks the record. 
    # checks for current over a certain level and marks the record if above.
    # calculates power (kW) from the increment in the energy meter (kWh) and stores in a separate field. 
        # This is useful to validate whether the power reading is characteristic of the full 10 sec interval or just a transient spike.
    # improves precision of current (A) readings based on the power (kW) fields (the current reading is truncated to integer which can be somewhat rectified)

# It detects communication errors and fixes certain frequently occurring error types. 
        # Additional correctable errors could be added to the error correction capabilities. 
        # E.g. timestamp may be occasionally incorrect, blurring stats if the noise hit the line holding the timestamp in the telegram. 
        # Timestamp could be calculated from the previous and the next telegram's timestamp. (not implemented)
# This is sufficient if error rate is fairly low. For error rates > 10% per telegram (which corresponds less than 0.005% per byte) or larger you probably need more sophisticated error handling.

# Takes a minute to process a daily worth of (24x360) telegrams. Typical performance is 5 msec per record (roughly half an hour per month, on i7-7700 CPU). File operations could be optimised.



$inpLog = "P1 meter w solar - 20250524.log"   # This is the input file that holds the log of the full serial communication from the meter. Can use * wildcard.


$nFixedCks = 0       # Count of corrected checksum errors
# $ValidityStats = ""  # will store a list of every telegram timestamp and a boolean to state if the telegram is valid. If False, the number of invalid chars is given (i.e. ASCII CRLF or xFF). If True, the added integer provides the number of fixed records since the beginning.
$telegram = ""
$timestamp = "-No timestamp-"
$prevProviderMessage = ""

$EarlierFirstLine = "/AUX59902759988"   # initialization value for a valid first line. Used for error correction. 
    # This is a valid first line but may not be useful in the specific application, depending on the meter's choice of header. 
    # You may want to (but do not have to - the error correction would still work) replace this with the first line that your meter emits. 
    # It will be superseded with a correct first line taken from the feed so other meters with different first line can also benefit from error correction.
    # This variable will be updated with the first line of the telegram when any syntactically correct telegram is read


$telegramPrevkWhIn = $null
$TelegramPrevkWhInTime = $null

$nTelegrams = 0
$nFalseTelegram = 0

$timePat = "0-0:1\.0\.0\((\d{12}[SW])\).*"
$SkipFirstLine_Pattern = "\r\n\r\n0-0:1\.0\.0\([\s\S]*$" # This is the regex that matches the segment of the telegram 
    # starting from the end of the first line ending at the end of the telegram.
    # This will be used to test if a checksum-failed telegram actually has healthy beginning except for the first byte. 
    # The first byte is the most prone to transmission errors. It fortunately is easy to guess (it is always a slash /)

# $VoltPat = '1-0:[357]2.7.0\((\d+\.\d+)\*V\)' # regular expression pattern to match any of the 3 voltages
# $AmpPat = '1-0:[357]1.7.0\((\d+)\*A\)' # regular expression pattern to match any amps

$Volt3Pat = '1-0:32.7.0\((\d+\.\d+)\*V\)' # regular expression pattern to match voltage for phase 3
$Volt5Pat = '1-0:52.7.0\((\d+\.\d+)\*V\)' # regular expression pattern to match voltage for phase 5
$Volt7Pat = '1-0:72.7.0\((\d+\.\d+)\*V\)' # regular expression pattern to match voltage for phase 7

$Amp3Pat = '1-0:31.7.0\((\d+)\*A\)' # regular expression pattern to match amps
$Amp5Pat = '1-0:51.7.0\((\d+)\*A\)' # regular expression pattern to match amps
$Amp7Pat = '1-0:71.7.0\((\d+)\*A\)' # regular expression pattern to match amps

$kWInPat  = '1-0:1.7.0\((\d+\.\d+)\*kW\)' # regular expression pattern to match the power consumption
$kWOutPat = '1-0:2.7.0\((\d+\.\d+)\*kW\)' # regular expression pattern to match the power to the grid

$kWhInPat  = '1-0:1.8.0\((\d+\.\d+)\*kWh\)'   # regular exp to match total energy incoming from grid
$kWhOutPat = '1-0:2.8.0\((\d+\.\d+)\*kWh\)'         # ... energy export to grid

$global:errorlog ="Timestamp, ChecksumCalc, Errordescription (Position: NoisyChar...)`r`n" 


# Add-type @"     # removed dependency on .net type definition and replaced with class 
class DSMRTelegramRecordType {
    [string]$timeString
    [double]$kWhIn
    [double]$kWhOut
    [float]$Voltage3
    [float]$Voltage5
    [float]$Voltage7
    [int]$Amp3                  # EON P1 truncates the reading to integer.
    [int]$Amp5                  # EON P1 truncates the reading to integer.
    [int]$Amp7                  # EON P1 truncates the reading to integer.
    [float]$kWIn
    [float]$kWOut
    [float]$kWInfromConsumption   # this is a calculated field: power calculated from the cumulative energy reading
    [float]$TotalAmp            # calculated field: total current based on power in/out and voltage on all 3 phases
    [string]$VoltStress
    [string]$AmpStress
    [string]$kWStress
}
#"@ 

Function WriteErrorRatePrediction() {
        $prediction = "Rounded error rate would be "
        if ( $rateFalse -gt 0 ) {
            $prediction +=
            "$($rateFalse - 0.01) % " + 
            "if no error occured in the next " + 
            "$( [math]::Round(( ($nFalseTelegram / ($rateFalse - 0.005) * 100 ) - $nTelegrams) / 360, 1) ) " + 
            "hours " +
            "or "
            }
        $prediction += "$( [math]::Round( ($nFalseTelegram + 1 ) / ($nTelegrams + 1 ) * 100, 2 )) % " +
        "if another error occured immediately." 
        Write-Output $prediction 
    }

Function CheckSumFromTG  {
    param (
        [string]$tlgr
    )
        [uint16]$chksum=0

        for ($TB = 0; $TB -lt $tlgr.length; $TB++) {

            if ([int]$tlgr[$TB] -le 255  ) {
            
                $chksum = $ChksumLookup[$chksum -bxor ( [byte]$tlgr[$TB] )]   # lookup instead of calculation. 

            } else {
                $start = [Math]::Max($TB - 20, 0)
                $length = [Math]::Min(30, $tlgr.Length - $start)
                write-host ("Double byte code found while calculating checksum in $timestamp. Position: $TB, character: $([int]$tlgr[$TB]), $($tlgr.Substring($start, $length))" )
                if ([int]$tlgr[$TB] -eq 729) {  #  PWSH 7.x get-content -Encoding ansi translates xFF to 729 - in case we cannot control encoding. 
                    Write-Host ("Code 729 is found while calculating checksum. It may indicate that code page 1250 was assumed by get-content while ingesting. Should be 1252 or no translation.")
                }
                throw "Not_a_Byte_ERROR:$TB"
            }


#            $endTime = Get-Date
#            $endArithmTime = get-date
        }

        return $chksum
    }

Function RecordAbortiveError {      # Updates many global vars so specifying 'global:' for vars that are CHANGED is important.
    param (
        [string]$ErrorMessage,
        [int]$ErrorPos = 0, # default value: 0 means "not provided"
        [int]$ValidityError = -1  
    )

    $global:nFalseTelegram ++
    if ($nTelegrams -ne 0 ) {
        $global:rateFalse = [math]::Round($nFalseTelegram / $nTelegrams *100 , 2)
        }
    else {
        $global:rateFalse = 0
        }

    $global:errorlog += $timestamp + ", "+ $ErrorMessage 
    if ($ErrorPos -ne 0) {
        $start = [Math]::Max($ErrorPos - 10, 0)
        $length = [Math]::Min(20, $telegram.Length - $start)

        $global:errorlog += " Char $([int]$telegram[$ErrorPos]) at position $ErrorPos, around '" + $telegram.substring($start, $length) + "'" + ", rate of error: " + $rateFalse + " % or " + $nFalseTelegram
        }
    $global:errorlog +=  "`r`n"
    $global:ValidityStats += "False," + $ValidityError + "`r`n"

    Write-Output "$timestamp $ErrorMessage position $ErrorPos, around '$($telegram.substring($start, $length))' rate of error: $rateFalse %  or $nFalseTelegram"
    WriteErrorRatePrediction

    $global:timestamp = "-No timestamp-(prev:" + $timestamp + ")"   # invalidate the timestamp until a new one is found


    return
}

Function RecordCorrectedError {
    param (
        [string]$ErrorMessage,
        [int]$ErrorPos = 0 # default value: 0 means "not provided"
    )
    $global:nFixedCks++
    $global:ErrorCorrected = $nFixedCks
    $global:errorlog += $timestamp
    $global:errorlog += ", " + $ErrorMessage + " $nFixedCks telegrams fixed.`r`n"
    Write-Host $ErrorMessage, " Corrected $nFixedCks"

    }

# create an array of records
$telegramRecords = New-Object System.Collections.Generic.List[DSMRTelegramRecordType]

   [float] $maxV = 0 
   [int]   $maxA = 0
   $MaxAtime = ""
   $MaxVtime = ""


############################################################################################################################################


# This routine creates a table which will be used to determine the updated checksum value given a new byte in the stream. It creates a lookup table (vector). 

# input: each of the possible checksum values i.e. from 0 to xFFFF 
# assumption: the new byte in the stream that should update the checksum is zero. At run time we will adjust the index into this vector to accommodate all 255 other data points. 
# output: a vector (one dimensional array) of uint16 numbers, each is the updated checksum assuming the old checksum is the index and the incoming data point is zero.
# 65536 uint16 data points as checksum values are 16 bit 

# note: We can cover all 65536 x 256 combinations of checksum and incoming data with just one vector. At run time the checksum needs to be XOR-ed with the incoming byte to calculate the correct index for the incoming byte.




    # Create an array with 65536 elements

$ChksumLookup = New-Object uint16[](65536)

# $execTime = Get-Date

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

       $ChksumLookup[$c] = $chksum
        
    }


##############################################################################################################################################
##############################################################################################################################################

#     Main loop starts here reading the port log file line by line
#     On char encoding: 
# https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-content?view=powershell-5.1
# https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-content?view=powershell-7.5
# in 5.1: "Default Uses the encoding that corresponds to the system's active code page (usually ANSI)."

$StartTime = [datetime]::Now

if ($PSversiontable.PSVersion.Major -ge 6) {
        $PSenc = "windows-1252"
    }
    else {
        $PSenc = "Default"
    }

Get-Content -Path $inpLog -Encoding $PSenc | ForEach-Object {

switch -regex   ($_) {

    "(/.*$)" {      # start of telegram indicated by / 
                    # Not necessarily starts with "/" in case of pre-telegram noise. We handle such noise later. 
                    # May include more than one "/" if CRLF's were dropped and two "/" signs fall into the same line

        $telegram = $Matches[1] + "`r`n"   # anything in the line before a "/" is dropped. Anything before this line is also dropped (a telegram fragment). Normally this drops nothing except when the previous telegram was aborted.
                 # In case a telegram fragment was collected before this new telegram, its timestamp is not reset here. If the "/" is an error, by removing the timestamp we lose track of the record, cannot report the error correctly.
                 # If the leading "/" is corrupted, we may still identify correct telegram start later when the closing "!" is detected and the telegram can be analysed."

        break
        }


    "\!([0-9A-Fa-f]{4})$" {   # sender checksum indicated by "!" and four hex numbers (upper or lower case accepted), followed by end of line. ( a series of 9 characters including the beginning and ending CRLF characters)
            # to make it more robust we should test if this 9-character string occurs inside a data object (in a line of the telegram that allows arbitrary data)
            # e.g. Can the utility service provider message 0-0:96.13.0(<message>) include CR, LF or "!" ?  
            # I did not find reference doc with sufficient details.  Best so far is https://www.netbeheernederland.nl/_upload/Files/Slimme_meter_15_a727fce1f1.pdf


        $SenderChks = $Matches[1]


        $nTelegrams ++
        # $ValidityStats += $timestamp + "," 

        if ($false) {

        # Check if error would cause checksum calculation to fail, e.g. unnecessary mapping by Powershell ingest to >255 unicode
        # Step 1: Convert string to char array
        $charArray = $telegram.ToCharArray()

        # Step 2: Replace and validate
        for ($i = 0; $i -lt $charArray.Length; $i++) {
            $code = [int]$charArray[$i]

            if ($code -eq 729) {        # PWSH 7.x get-content -Encoding ansi replaces xFF with 729
                # Replace bad Unicode (˙) with 255
                $charArray[$i] = [char]255
                Write-Output "729 spotted and replaced in $timestamp"
            }
            elseif ($code -eq 402) {    # Powershell 5.1 replaces x83 with 402. Probably it assumes ansi 1252
                $charArray[$i] = [char]131
            }
            elseif ( $code -gt 255 ) {
                write-output "i: $i,  code: $code"
                RecordAbortiveError "Invalid character code ingested, not trying to fix." -ErrorPos $i
                break
            }
        }
        if ($code -gt 255) {
            break
        }

        # Step 3: Rebuild the cleaned string
        $sb = [System.Text.StringBuilder]::new($charArray.Length)
        $null = $sb.Append($charArray)


        $telegram = $sb.ToString() + "!" 
    } else {
        $telegram += "!"
    }


        try {
            [uint16]$CalcChecksum =  CheckSumFromTG $telegram
        }
        catch {
            if ( -not ($_ -match '^Not_a_Byte_ERROR:(\d+)$') ) {
                throw
                }
            $TB = [int]$Matches[1]
            # Write-Host "Double-byte code found, cannot cast to byte during checksum, at position $TB in telegram $timestamp."

            if  ( 
                ($TB -ge $telegram.length - 1) -or 
                -not ($telegram.Substring($TB + 1) -cmatch $EarlierFirstLine.Substring(1) + $SkipFirstLine_Pattern)  
                ) {

                RecordAbortiveError "Cannot convert an ingested code back to byte. No valid telegram is found after the error position." -ErrorPos $TB

                break       #   This exits the switch block, not only the Catch.
                            #   $telegram fragment accumulated up to this point will be deleted when the next telegram starts (with "/")
                }

            RecordCorrectedError "Byte conversion error found pre-telegram:  $($telegram.substring( 0, [Math]::Min(20, $telegram.Length ))) Removing leading garbage. "
            $telegram = "/" + $Matches[0]

            # write-host "Byte conversion error pre-telegram. Removed. Proceeding. Telegram boundaries are fixed at $timestamp. Corrected $nFixedCks"

            try {
            [uint16]$CalcChecksum =  CheckSumFromTG $telegram      # In case a second character also throws an error 
            }
            catch {
                if ( -not ($_ -match '^Not_a_Byte_ERROR:(\d+)$') ) {
                    throw
                    }
                $TB = [int]$Matches[1]
    
                RecordAbortiveError "After removing pre-telegram noise including a double-byte character, another double-byte char is found in checksum calculation. Aborting telegram." -ErrorPos $TB
                break
            }
        }
        

        try {
            $senderChksInt = [UInt16]::Parse($SenderChks, [System.Globalization.NumberStyles]::HexNumber)
        } 
        catch {
            $errorlog += $timestamp + ", Unreadable CRC in telegram.`r`n"
            # $ValidityStats += "False,`r`n"

            $nFalseTelegram ++
            $rateFalse = [math]::Round($nFalseTelegram / $nTelegrams *100 , 2)

            Write-Output "Unreadable CRC error at $timestamp, rate of error: $rateFalse %  or $nFalseTelegram"            

            $timestamp = "-No timestamp-"   # invalidate the timestamp until a new one is found

            break   #   We exit the SWITCH block with a BREAK which skips further error detection and correction, 
                    #   and completes the processing the last line of the telegram.
                    #   $telegram fragment accumulated up to this point will be deleted when the next telegram starts (with "/")
                    #   todo: if we exit the telegram processing here and do not delete the $telegram, and the next telegram starts with a 
                    #   correctable error in the first line (first "/" lost in transit), then error correction may not work. 
                    #   It may rely on the missing "/" being in the first line. (?)
        }




        $ErrorCorrected = 0

        # [uint16]$ChksumTGCorrected = 0
        
        if ($senderChksInt -ne $CalcChecksum ) {    # if checksums do not match handle the error here by trying to substitute suspect bytes. Otherwise skip forward to process telegram into a record.

 #               if ($telegram.Length -ne 2342) {
 #                   $tempMatch= ($telegram -cmatch $EarlierFirstLine.Substring(1) + $SkipFirstLine_Pattern)
 #                   $ChksumTGCorrected = CheckSumFromTG( "/" + $Matches[0])
 #           write-host "Telegram $timestamp length:   $($telegram.length) firstline match: $tempMatch  Calculated/Sent checksum: $ChksumTGCorrected / $senderChksInt"
 #           }     
 

            #      look for the service provider message, then remove all chars before the OBIS code after the previous ')'&CRLF. These characters are often read erroneously due to line noise. 

            $oldtelegram = $telegram
            $telegram = $telegram -replace "\)\r\n(.*?)0-0:96\.13\.0\(", ")`r`n0-0:96.13.0("        # (.*?) represents the chars that must not be there unless line noise occurred

            if ($telegram.Length -ne $oldtelegram.Length) {     # better to check the length than the content of strings. Two different strings may test as equal if the difference is only some nonprinting chars
                Write-Output ("Removed characters before the service provider message. Len telegram: $($oldtelegram.Length); after fix: $($telegram.Length).  " +
                            "Before fix:  $($oldtelegram.substring(1280,70))")
                $errorlog += $timestamp + ", Removed characters before the service provider message:   " + $oldtelegram.substring(1280,80) + 
                        "   1302nd char code: " + ([int][char]$oldtelegram.Substring(1302,1)) + "  Len telegram: " + ($oldtelegram.Length) + "`r`n"
            }

            # Test if the first line of the noisy telegram includes a valid first line if the leading garbled bytes are disregarded. If so, it is likely that the line error only affects the first byte of the dispatched telegram and the leading zero bytes. 
            # If a valid first line is found in a corrupted telegram then we assume it marks the beginning of the correct telegram, chop off everything before it, and ascertain validity with an extra checksum calculation. 

            try {
            if  ( ($telegram -cmatch $EarlierFirstLine.Substring(1) + $SkipFirstLine_Pattern) -and ( ( CheckSumFromTG( "/" + $Matches[0])) -eq $senderChksInt )  )  {  # it should ensure that if the comparison throws an error execution continues in the right script block.
                                                    #               Function call on the left of -eq must in parenthesis if type is uint16. Otherwise precedence or type casting is messed up
                                    
                                                    
            # Success, proceed to data extraction to TelegramRec after fixing the first byte of $telegram
                $nFixedCks++
                $Errorcorrected = $nFixedCks
                $errorlog += $timestamp
                $errorlog += ", Tested for garbled characters in the first line $($telegram.substring(0,12)) and removed them if found. Telegram is now valid.  $nFixedCks telegrams fixed."
                # $errorlog +=       # compare to [convert]::ToString(([int][char]"/"),2)
                if (-not $telegram.contains(([char]14 + "AU"))) { 
                    $errorlog += (" Unusual error pattern: Leading '/' was not modified to char(14) in transit.  " +  
                        (" First three chars: " + [int][char]($telegram.substring(0,1)) + " (" + [convert]::ToString(([int][char]($telegram.substring(0,1)) ),2) + ")   " + 
                        [int][char]($telegram.substring(1,1)) + " (" + [convert]::ToString(([int][char]($telegram.substring(1,1)) ),2) + ")  " + 
                        [int][char]($telegram.substring(2,1))  +"`r`n" )        )        # + $telegram.Substring(0, [math]::Min( $telegram.Length , 30)  ) +"`r`n" 
                    Write-Host "Unusual pattern preceding the telegram; fixed. First char: ", ([convert]::ToString(([int][char]($telegram.substring(0,1)) ),2))
                    }
                else {
                    $errorlog += "`r`n"
                }

                write-host "Telegram fixed at $timestamp. Corrected $nFixedCks"
                $telegram = "/" + $Matches[0]

                }

            elseif (        # Test if the telegram is fixed by replacing the service provider message with the message in the previous correct telegram (all 255's currently).
                    $prevProviderMessage -ne "" -and 
                    $telegram -match "([\s\S]*?\r?\n0-0:96\.13\.0\()(.*?)(\)\r?\n[\s\S]*|\)$)" -and         # This handles line breaks. Code should start at the beginning of the line.
                    $matches[2]  -ne  $prevProviderMessage -and
                    ((CheckSumFromTG($matches[1] +  $prevProviderMessage + $matches[3])) -eq $senderChksInt)     # Function call on the left of -eq must be in parenthesis.  # Error in CheckSumFromTG is unlikely as all 3 parts have gone through it earlier
                    ) {
                # Write-Host "Checksums comparison result (must be True, not a number): " ((CheckSumFromTG($matches[1] +  $prevProviderMessage + $matches[3])) -eq $senderChksInt)
                
                $telegram = $matches[1] +  $prevProviderMessage + $matches[3]       #   replace provider message with the old

                if ($prevProviderMessage -match "^[\xFF]*$") {  # for display, shorten the long service provider message  
                    $prevProviderMessage = "string of xFFs"     # prevProviderMessage will be taken from $telegram so we do not need to preserve it here
                }
                                                
                $nFixedCks++
                $Errorcorrected = $nFixedCks

                Write-Output ($timestamp + " Replaced the provider message with:   " + $prevProviderMessage + "    Corrected $nFixedCks" )
                $errorlog += $timestamp + ", Replaced the service provider message with the previous telegram's:   " + $prevProviderMessage + "  $nFixedCks telegrams fixed.`r`n"

                }


                # Future error correction hints: 
                #   (done) Replace in the custom service provider message after '0-0:96.13.0(' all chars with xFF and add extra xFF if shorter due to error that created UTF8 prefix character
                #   (done) Check if chars exist before the service provider message after the previous ')' and if so remove them by matching obis code pattern '0-0:96.13.0' 
                #   (done) apply correction of first line to telegrams that suffer byte conversion error in the pre-telegram garbage
                # then validate checksum again

             
            else {

 
        
            # Give up. This telegram is unhealable. We just record the error parameters and exit telegram processing without recording the values in TelegramRec

            # Change this to call RecordAbortiveError -ErrorMessage "..." -ErrorPos 
            $nFalseTelegram ++
            if ($nTelegrams -ne 0 ) {
                $rateFalse = [math]::Round($nFalseTelegram / $nTelegrams *100 , 2)
                }
            else {
                $rateFalse = 0
                }
            $errorlog += $timestamp + ", " + $CalcChecksum

            Write-Output "Checksum error at $timestamp, rate of error: $rateFalse %  or $nFalseTelegram"            

            $pattern = '[\x00-\x09\x0B-\x0C\x0E-\x1F\x80-\xFE]'   # matches non-ASCII characters except xFF, CR and LF. These are not expected in a DSMR telegram. (except perhaps the service provider message) 
            $NoisyChars = $telegram | Select-String -Pattern $pattern -AllMatches | ForEach-Object { $_.Matches }   # select-string operates on all $telegram at once, not per line.

            foreach ($NChar in $NoisyChars) {
                Write-Host " Non-ASCII character '$($NChar.Value)' at position $($NChar.Index)" 
                $errorlog += ", " + $NChar.Index + ": " +  [int]($NChar.Value[0])
                }

                WriteErrorRatePrediction

            if ( $NoisyChars ) {
                if ($NChar.index -lt ($telegram.Length-6) ) {
                    $errorlog += " before '" + $telegram.substring($NChar.index+1, 5)  +"'  " 
                    }
                }
                else {
                $errorlog+= ", no invalid char but telegram failed for another reason.  "
                }

            $errorlog += " " + $rateFalse + " % error rate or " + $nFalseTelegram + " telegrams.`r`n"

            # $ValidityStats +=  "False,"  +   $NoisyChars.Length + "`r`n"  # add the number of chars found invalid. Lower estimate for errors.


            #  Remove leftovers from this telegram that would contaminate the next. We discard fragments, although it might be possible to fix the error by examining remaining lines. For future improvement.

            $telegram  = ""
            $timestamp = "-No timestamp-"

            break    # exit the Switch case for the terminating line (the line with "!<checksum>") in the telegram. Continue with starting fresh: looking for the next start of telegram in the same Switch in the next iterations.

            }

        }
        catch { 
            # second byte/xor error or unknown error. Exit with error log.
            if (-not ($_ -match '^Not_a_Byte_ERROR:(\d+)$') ) {
                throw
                }
            $TB = [int]$Matches[1]
            Write-Host "Error in broad TRY around error correction code. Caught byte conversion or XOR error at $TB"

            RecordAbortiveError "Cannot convert to byte or cannot XOR char while trying to make corrections in broad TRY-CATCH. " -ErrorPos $TB

            break       #   This exits the switch block, not only the Catch.
                        #   $telegram fragment accumulated up to this point will be deleted when the next telegram starts (with "/")

        }
            # issue fixed with try-catch: if an error is generated in the if statement ($telegram -cmatch $EarlierFirstLine.Substring(1) + $SkipFirstLine_Pattern) then neither of the branches execute but execution continues here.
            # Pattern is tested to exclude any non-printable ASCII but there might be other reasons why a statement may generate an error.
        }




     # the current telegram should be syntactically correct from this point on, e.g. $timestamp should exist and be meaningful. If it weren't it would have failed the checksum test

            # $ValidityStats +=  "True,"  +   $ErrorCorrected + "`r`n"      
            # If the record is valid then the additional field informs whether it had valid CRC (last field is 0) or it was corrected (last field is the number of telegrams fixed)
            # todo: check if $Errorcorrected variable is needed. $nFixedCks seems reusable here


    # In preparation for error detection of later telegrams we process the first line of this telegram 
            $FirstLine = $telegram -split '\r?\n' | Select-Object -First 1    # Separate the first line of the current telegram ...  
                         #      so we can compare it to corresponding parts of later telegrams. The goal is to detect transmission errors in the first line of later telegrams. 

            if ( $FirstLine -ne $EarlierFirstLine ) {   # never executed. For future improvement.
                $errorlog += $timestamp + " First line of telegram is different from earlier. " 

                if ( ! ( $FirstLine | Select-String -Pattern '[\x00-\x09\x0B-\x0C\x0E-\x1F\x80-\xFE\(\)\\\.]')) {    # Employ the first line only if it does not include characters that are likely errors, e.g. non-ASCII chars with exceptions
                    $EarlierFirstline = $FirstLine         #  Persist the first line of the current telegram for later use in upcoming  telegrams
                    $errorlog += "'"+ $FirstLine +"' will be used to detect errors.`r`n"
                    }
                else {
                    $errorlog += "EarlierFirstLine is not updated. `r`n"
                    }
                }

    # create a single record, then fill it with copied and calculated data from the telegram

            $telegramRec = [DSMRTelegramRecordType]::new()     # @{
                $telegramRec.kWhIn  = [double]::NaN
                $telegramRec.kWhOut = [double]::NaN
                $telegramRec.Voltage3 = [float]::NaN
                $telegramRec.Voltage5 = [float]::NaN
                $telegramRec.Voltage7 = [float]::NaN
                $telegramRec.Amp3 = [int]::MinValue
                $telegramRec.Amp5 = [int]::MinValue
                $telegramRec.Amp7 = [int]::MinValue
                $telegramRec.kWIn = [float]::MinValue
                $telegramRec.kWOut = [float]::MinValue
                $telegramRec.kWInfromConsumption = [float]::NaN
                $telegramRec.TotalAmp = [float]::NaN
                $telegramRec.VoltStress = ""
                $telegramRec.AmpStress = ""
            #  }



            switch -regex ($telegram) {

                $timePat  {  $Telegramrec.TimeString = $Matches[1]  # Time field
                    }

                $kWhInPat {  $TelegramRec.kWhIn = [double]$Matches[1] # convert the matched string to a double
                    }
                $kWhOutPat {  $TelegramRec.kWhOut = [double]$Matches[1] # convert the matched string to a double
                    }

                $Volt3Pat {  $TelegramRec.Voltage3 = [float]$Matches[1] # convert the matched string to a float
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

         
                $kWInPat { $TelegramRec.kWIn = [float]$Matches[1] # convert the matched string to a float
                    if ($TelegramRec.kWIn -gt 4400) { $telegramrec.kWStress = $true }
                    }
                $kWOutPat { $TelegramRec.kWOut = [float]$Matches[1] # convert the matched string to a float
                    if ($TelegramRec.kWOut -gt 4400) { $telegramrec.kWStress = $true }
                    }
    
                } 




            # Convert the timedate field string of the telegram into time. This will be used only for internal stuff. Output will use the original OBIS/COSEM format.
            # Purpose: when switching from and to daylight saving time prevent losing a record.
         

            $TelegramTime = get-date -year ("20"+$timestamp.substring(0,2)) -month $timestamp.substring(2,2) -day $timestamp.substring(4,2) -hour $timestamp.Substring(6,2) -minute $timestamp.Substring(8,2)  -second $timestamp.Substring(10,2)  

               if ($timestamp[-1] -eq "S" ) {    # Standard (winter) hour is 1 lower in summer than the timestamp
              
                $TelegramTime -= new-timespan -Hours 1
                
                  }

       

            if ($TelegramPrevkWhInTime) {


                    # we assume that time between the last two records were 10 seconds if the dates are less than 15 seconds apart.
                    # for longer time periods we do not calculate power consumption from the two energy readings

                if ( ($TelegramTime.subtract($TelegramPrevkWhInTime)).totalseconds -lt 15 )   {   # normal timespan is 10 seconds but may be noisy hence comparison with 15 seconds.

                    $TelegramRec.kWInfromConsumption = ( $TelegramRec.kWhIn - $TelegramPrevkWhIn ) * 360    # Assuming that each telegram is 10 seconds apart, calculating power from energy by deviding energy with time (1/360 hours)
                    }
                        else {
                        $TelegramRec.kWInfromConsumption = [float]::NaN
                        }

                }  
                else {
                    $TelegramRec.kWInfromConsumption = [float]::NaN
                    }


            $TelegramPrevkWhInTime = $TelegramTime
            $TelegramPrevkWhIn = $TelegramRec.kWhIn


    # Alleviate the low precision of current readings by looking at the power and voltage. 
    # P1 port Amper readings are truncated to integer and do not show the direction of the energy flow per phase. 

            if ( $telegramRec.kWOut -eq 0)  {       # unfortunately we can calculate useful statistics only if each phase transfers energy in the same direction as the other two. 
                $telegramRec.TotalAmp =  - $Telegramrec.kWIn / ($telegramRec.Voltage3 + $TelegramRec.Voltage5 + $TelegramRec.Voltage7) * 3 * 1000  # calculate P/U, using the average of U per phase.  Reactive power not accounted for.
                }               #   negative TotalAmp means consuming from grid.

            elseif ( $telegramRec.kWIn -eq 0) {     # No consumption from grid
                $telegramRec.TotalAmp = $Telegramrec.kWOut / ($telegramRec.Voltage3 + $TelegramRec.Voltage5 + $TelegramRec.Voltage7) * 3 * 1000  # calculate P/U, using the average of U per phase. Reactive power not accounted for.
                }                #  Positive TotalAmp means feeding to grid.

                #        precision could be increased by factoring in the reactive power. Subject to future work.


            if ( $TelegramRec.Voltage3 -ge $maxV ) {

                $maxV = $telegramRec.Voltage3
                $MaxVtime = $timestamp      # triggers a false positive warning in Visual Studio as it is declared in a script block
                $TelegramRec.VoltStress += "3"
                }


            if ( $TelegramRec.Voltage5 -ge $maxV ) {

                $maxV = $telegramRec.Voltage5
                $MaxVtime = $timestamp
                $TelegramRec.VoltStress += "5"
                }

            if ( $TelegramRec.Voltage7 -ge $maxV ) {

                $maxV = $telegramRec.Voltage7
                $MaxVtime = $timestamp
                $TelegramRec.VoltStress += "7"
                }



            if ( $TelegramRec.Amp3 -ge $maxA ) {

                $maxA = $telegramRec.Amp3
                $MaxAtime = $timestamp      # triggers a false positive warning in Visual Studio as it is declared in a script block
                $TelegramRec.AmpStress += "3"
                }


            if ( $TelegramRec.Amp5 -ge $maxA ) {

                $maxA = $telegramRec.Amp5
                $MaxAtime = $timestamp
                $TelegramRec.AmpStress += "5"
                }

            if ( $TelegramRec.Amp7 -ge $maxA ) {

                $maxA = $telegramRec.Amp7
                $MaxAtime = $timestamp
                $TelegramRec.AmpStress += "7"
                }



            $telegramRecords.Add($telegramRec)   #.psobject.Copy()


            
            if ($telegram -match "\n0-0:96\.13\.0\(([ -\u00FF\r\n]*)\)\r?\n") {     # save the provider message (currently set to all xFFs) in case it is noisy in the next telegram  
                $prevProviderMessage = $Matches[1]
                # write-host "New provider message recorded: $prevProviderMessage"
                }

            $telegram  = ""             #   Remove the telegram. Not strictly necessary as it will be removed when the next telegram starts.
            $timestamp = "-No timestamp-(prev:" + $timestamp + ")"

        }       #   End of processing the last line of the telegram (the line with "!" and the checksum)

    $timePat {
        $timestamp = $matches[1]
        $telegram = $telegram + $_ + "`r`n" 
        }

    
    default {$telegram = $telegram + $_ + "`r`n" }
}


}

if ($PSversiontable.PSVersion.Major -ge 6) {    # Trying to limit size of output files. To be tested with both 5.1 and pwsh 7.x
    $PSenc = "utf8NoBOM"
}
else {
    $PSenc = "UTF8"
}

$outPath = ( $inpLog -replace '\*', '' ) + ".Test.NoPreSweep.PS"+ $PSVersionTable.PSVersion.Major + $PSVersionTable.PSVersion.Minor
# Out-File -FilePath ($outPath + "Validity.csv")  -InputObject $ValidityStats -Encoding $PSenc    # this output file holds a record for each telegram whether correct or not. 
    # In Windows Powershell 5.1, Out-File creates UTF-16LE. PowerShell defaults to utf8NoBOM for all output.
    # For erroneous (not corrected) telegrams it provides the number of unexpected chars. 
        # (minimum number as it does not attempt to find all incorrect chars.)
        # (for severe errors e.g. damaged checksum field the number of affected bytes is omitted)
    # for corrected records it includes how many errors were corrected from the beginning of the file. 
    # for untouched records it is zero.

if ($nTelegrams -ne 0 ) {
    $rateFalse = [math]::Round($nFalseTelegram / $nTelegrams *100 , 2)
    $rateFixedChks = [math]::Round($nFixedCks  / $nTelegrams *100 , 2)
    if (( $nFixedCks + $nFalseTelegram )  -ne 0) {
        $rateErrorfix = [math]::Round( $nFixedCks / ( $nFixedCks + $nFalseTelegram ) *100 , 1)
        }
    else { $rateErrorfix = "No"}

    Write-Output "$nFalseTelegram checksums are still false. Rate of error: $rateFalse % of total. $nFixedCks of $nTelegrams telegrams ($rateFixedChks %) are fixed in '$inpLog'"
    WriteErrorRatePrediction
    
    $errorlog += "Total, fixed, remaining:  " + $nTelegrams + "  "  + $nFixedCks + "  " + $nFalseTelegram + " (" + $rateFalse + "% of total).  " + $rateErrorfix + " % of errors are fixed.`r`n"
    $duration = ([datetime]::Now - $StartTime).totalseconds * 1000
    $errorlog +=  "Exec time: $([math]::Round($duration/$nTelegrams,2))  msec/telegram"
    Out-File -FilePath ($outPath + "Noise.csv")  -InputObject $errorlog   # this is an error log file. Only reports when an incoming telegram had errors
    }


$telegramRecords | Export-Csv -Path ($outPath+"Records.csv") -NoTypeInformation -UseCulture -Encoding $PSenc     # this is the main output file with "_Records.csv" appended to the input file name

if ( $MaxVtime -and $MaxAtime ) {
    write-output ("Maximum voltage: " + $maxV +  " on date " + $MaxVtime.Substring(2,4) + " at " + $MaxVtime.substring(6,4) + ".  Max current: " + $maxA + " A on date " + $MaxAtime.Substring(2,4) + " at " + $MaxAtime.Substring(6,4))
    }