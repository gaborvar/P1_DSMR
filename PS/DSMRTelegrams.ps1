
# DSMR P1 telegram from log file, checking checksums for each telegram. No parsing within telegram except timestamp extraction.
# Calculates checksum from each telegram and writes TRUE for a match or FALSE for incorrect checksum to a CSV file.
# Takes several minutes to process a daily worth of (24x360) telegrams. File operations could be optimised.
# CSV output is intended to be processed by Excel. See charts separately. 
# Can be extended with further parsing of the telegrams.

# Does not yet handle errors within telegrams with failed checksums. E.g. timestamp may be occasionally incorrect, blurring stats. 
# This is acceptable if error rate is low. For error rates > 10% per telegram (which corresponds less than 0.005% per byte) or larger you probably need to be more sophisticated error handling.


$inpLog = "C:\Users\gabor\Documents\GitHub\P1_DSMR\PS\sample P1 meter putty - 20230502.log"

$FinalStat=""
$telegram=""
$nTelegrams = 0
$nFalseTelegram = 0

$VoltPat = '1-0:[357]2.7.0\((\d+\.\d+)\*V\)' # regular expression pattern to match the number
$AmpPat = '1-0:[357]1.7.0\((\d+)\*A\)' # regular expression pattern to match the number



[uint16]$chksum = 0



$stream = New-Object System.IO.FileStream("C:\Users\gabor\OneDrive\Dokumentumok\KocsagU\NapelemVillany\P1\ChksumLookup.bin", [System.IO.FileMode]::Open)
$reader = New-Object System.IO.BinaryReader($stream)

$ChksumLookup = New-Object uint16[](65536)
for ($i = 0; $i -lt 65536; $i++) {
    $ChksumLookup[$i] = $reader.ReadUInt16()
}

$reader.Close()
$stream.Close()



# write-host "Max index after read: $i minus one"



Get-Content $inpLog | ForEach-Object {

switch -regex   ($_) {

    "(/.*$)" {   # start of telegram indicated by /

        $telegram = $Matches[1] + "`r`n"   # anything in the line before a "/" is dropped. Anything before this line is also dropped (a telegram fragment). Normally this drops nothing except when the closing "!" of the previous telegram was not found

        }

    "\!([0-9A-Fa-f]{4}).*$" {   # sender checksum indicated by ! and four hex numbers
     
        $telegram = $telegram + "!" 
        $SenderChks = $Matches[1]
        
        

        [uint16] $chksum = 0
        [byte] $byteValue = $null


#            $startTime = get-date 

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


            
            $chksum = $ChksumLookup[$chksum]   # alternative with lookup. Lookup takes 15 ms vs 100 ms for each incoming byte on a specific i7-7700 CPU @ 3.60GHz system.
            

#            {
#            $endTime = Get-Date

#            for ($i = 0; $i -lt 8; $i++) {                    calculation of the same checksum update with bitwise operations in a loop 
#                if ($chksum -band 1) {                       # slower but on memory constrained systems is may be preferred 
#                    $chksum = ($chksum -shr 1) -bxor 0xA001
#                } else {
#                    $chksum = $chksum -shr 1
#                }
#            }
#            }

#            $endArithmTime = get-date



   #      if ( $chksumLookedUp -ne $chksum ) {
   #         write-host  "With arithmetic: $chksum,   With lookup: $chksumLookedUp"
   #         }

        }

#                    $endTime = Get-Date
#             write-host "Exec time: $(($endTime - $startTime).milliseconds) ms; "      

#                    write-host "Lookup exec time: $(($endLookupTime - $startLookupTime).Ticks) ms; Arithmetic: $(($endArithmTime - $endLookupTime).Ticks) "


        try {
            $senderChksInt = [UInt16]::Parse($SenderChks, [System.Globalization.NumberStyles]::HexNumber)
       
        } catch {
            write-error "Unreadable CRC in telegram $timestamp."
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




        $FinalStat += $timestamp + "," 
        $nTelegrams ++
        
        if ([bool]($senderChksInt -ne $chksum) ) { 
        
            $nFalseTelegram ++
            $rateFalse = [math]::Round($nFalseTelegram / $nTelegrams *100 , 2)
            $FinalStat +=  "False,"  +   $chksum + "`r`n"  # +  $senderChksInt.ToChar(

            echo "Chksum error at $timestamp, rate of error: $rateFalse %"
            }
        else {
            $FinalStat +=  "True,"  +   $chksum + "`r`n"
            }

        $telegram  = ""
        $timestamp = ""

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
