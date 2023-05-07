
# DSMR P1 telegram from log file. No parsing within telegram except timestamp extraction.
# Calculates checksum from each etlegram and writes to a CSV file.
# Takes several minutes or an hour to process a daily worth of (24x360) telegrams. File operations could be optimised.
# CSV putput is intended to be processed by Excel. See charts separately. 
# Can be extended with further parsing of the telegrams.
# Does not yet handle errors within telegrams with failed checksums, e.g. timestamp may be occasionally incorrect, blurring stats.


$inpLog = "C:\Users\gabor\Documents\GitHub\P1_DSMR\PS\sample P1 meter putty - 20230502.log"

$FinalStat=""
$telegram=""
$nTelegrams = 0
$nFalseTelegram = 0

$VoltPat = '1-0:[357]2.7.0\((\d+\.\d+)\*V\)' # regular expression pattern to match the number
$AmpPat = '1-0:[357]1.7.0\((\d+)\*A\)' # regular expression pattern to match the number


Get-Content $inpLog | ForEach-Object {

switch -regex   ($_) {

    "(/.*$)" {   # start of telegram indicated by /

        $telegram = $Matches[1] + "`r`n"   # anything in the line before a "/" is dropped. Anything before this line is also dropped (a telegram fragment). Normally this drops nothing except when the closing "!" of the previous telegram was not found

        }

    "\!([0-9A-Fa-f]{4}).*$" {   # sender checksum indicated by ! and four hex numbers
     
        $telegram = $telegram + "!" 
        $SenderChks = $Matches[1]
        
        # $TelegramByteArray = [byte[]]$telegram

        [uint16] $chksum = 0
        [byte] $byteValue = $null


        for ($TB = 0; $TB -lt $Telegram.length; $TB++) {
       # write-host ($Telegram[$TB], [System.Text.Encoding]::ASCII.GetBytes($telegram[$TB])[0])


            try {

                $chksum = $chksum -bxor ( [byte]$telegram[$TB] )
                # whote-host "Conversion to byte, or XOR failed" 
            }
            catch {
                $errormessage = "cannot convert to byte or XOR char " + [int]$telegram[$TB] + " in telegram $timestamp at character position $TB, after "
                $errormessage +=  $telegram[[Math]::Max( $TB-7,0) .. [Math]::Max($TB-1, 0)]
                Write-Error $errormessage
                continue
            }

            for ($i = 0; $i -lt 8; $i++) {
                if ($chksum -band 1) {
                    $chksum = ($chksum -shr 1) -bxor 0xA001
                } else {
                    $chksum = $chksum -shr 1
                }
            }

        }



        try {
            $senderChksInt = [UInt16]::Parse($SenderChks, [System.Globalization.NumberStyles]::HexNumber)
       
        } catch {
            write-error "Unreadable CRC at telegram $timestamp."
            $senderChksInt = 0
         }



  ### This finds the Volt/Amper value for only one of the 3 phases. Needs to be fixed.      
#    $VoltPat {
#        $VoltValue = [double]$Matches[1] # convert the matched string to a double
#        if ($VoltValue -gt $maxV) {
#            $maxV = $VoltValue 
#            $maxVtime = $timestamp
#        }
#        $telegram = $telegram + $_ + "`r`n"
#    }

#    $AmpPat {
#        $AmperValue = [int]$Matches[1] # convert the matched string to an integer
#        if ($AmperValue -gt $maxA) {
#            $maxA = $AmperValue
#            $maxAtime = $timestamp
#        }
#        $telegram = $telegram + $_ + "`r`n"
#    }




        $FinalStat += $timestamp + "," + [bool]($senderChksInt -eq $chksum) + ","  +   $chksum + "`r`n"  # +  $senderChksInt.ToChar(
        $telegram  = ""
        $timestamp = ""
        if ([bool]($senderChksInt -ne $chksum) ) { $nFalseTelegram ++ }
        $nTelegrams ++

        }

    "0-0:1\.0\.0\((\d{12}).*$" {
        $Timestamp = $matches[1]
        $telegram = $telegram + $_ + "`r`n" 
        }





    
    default {$telegram = $telegram + $_ + "`r`n" }
}


}
$outCSV = $inpLog + ".csv"
Out-File -FilePath $outCSV  -InputObject $FinalStat
echo "$nFalseTelegram checksums are false from $nTelegrams telegrams in $inpLog"

