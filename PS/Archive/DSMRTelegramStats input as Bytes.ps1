


$inpLog = "C:\Users\gabor\OneDrive\Dokumentumok\KocsagU\NapelemVillany\P1\sample P1 meter putty - 20230502.log"

Remove-Variable -Name FileBytes


$FinalStat = ""
$telegram =""
$telegramPrevkWhIn = $null
$TelegramPrevkWhInTime = $null
#$telegramPrevTime = $null
$nTelegrams = 0
$nFalseTelegram = 0

$timePat = "0-0:1\.0\.0\((\d{12})[SW]\).*"

$VoltPat = '1-0:[357]2.7.0\((\d+\.\d+)\*V\)' # regular expression pattern to match the number
$AmpPat = '1-0:[357]1.7.0\((\d+)\*A\)' # regular expression pattern to match the number

$Volt3Pat = '1-0:32.7.0\((\d+\.\d+)\*V\)' # regular expression pattern to match the number
$Volt5Pat = '1-0:52.7.0\((\d+\.\d+)\*V\)' # regular expression pattern to match the number
$Volt7Pat = '1-0:72.7.0\((\d+\.\d+)\*V\)' # regular expression pattern to match the number

$Amp3Pat = '1-0:31.7.0\((\d+)\*A\)' # regular expression pattern to match the number
$Amp5Pat = '1-0:51.7.0\((\d+)\*A\)' # regular expression pattern to match the number
$Amp7Pat = '1-0:71.7.0\((\d+)\*A\)' # regular expression pattern to match the number

$kWInPat  = '1-0:1.7.0\((\d+\.\d+)\*kW\)' # regular expression pattern to match the number
$kWOutPat = '1-0:2.7.0\((\d+\.\d+)\*kW\)' # regular expression pattern to match the number

$kWhInPat  = '1-0:1.8.0\((\d+\.\d+)\*kWh\)'
$kWhOutPat = '1-0:2.8.0\((\d+\.\d+)\*kWh\)'

$errorlog ="Timestamp,Position,NoisyChar,`r`n" 



Add-type @" 
public class DSMRTelegramRecordType {
    public string timeString ;
    public double kWhIn ;
    public double kWhOut ;
    public float Voltage3 ;
    public float Voltage5 ;
    public float Voltage7 ;
    public int Amp3 ;
    public int Amp5 ;
    public int Amp7 ;
    public float kWIn ;
    public float kWOut ;
    public float kWInfromConsumption ;
    public string VoltStress ;
    public string AmpStress ;
}
"@ 


# create an array of records
$telegramRecords = New-Object System.Collections.Generic.List[DSMRTelegramRecordType]


   $maxV = [float]0 
   $maxA = [int]0
   $MaxATime = ""
   $MaxVTime = ""


$FileBytes = [System.IO.File]::ReadAllBytes($inpLog)

#  $text = [System.Text.Encoding]::Default.GetString($bytes)

$TelegramStartmarker = [byte][char]"/"

$TelegramEndmarker = [byte][char]("!")


$checksum = [uint16](0)
$c = [uint16](0)

$ChecksumLookup = New-Object uint16[](65536)


    for ( $c=0; $c -lt $ChecksumLookup.Length; $c++) {

            # checksum algorithm begins

        $checksum = $c   ##   Should be:   $c -bxor 0   but it equals $c

            for ($i = 0; $i -lt 8; $i++) {
                if ($checksum -band 1) {
                    $checksum = ($checksum -shr 1) -bxor 0xA001
                } else {
                    $checksum = $checksum -shr 1
                }
            }

       $ChecksumLookup[$c] = $checksum
        
    }








function UpdateStats ($StartIndex, $EndIndex) {

              # the current telegram should be syntactically correct from this point on, e.g. $timestamp should exist and be meaningful. If it weren't it would have failed the checksum test

            # create a single record 
            $telegramRec = [DSMRTelegramRecordType] @{
                kWhIn = [double]::NaN
                Voltage3 = [float]::NaN
                Voltage5 = [float]::NaN
                Voltage7 = [float]::NaN
                Amp3 = [int]::MinValue
                Amp5 = [int]::MinValue
                Amp7 = [int]::MinValue
                kWIn = [float]::MinValue
                kWOut = [float]::MinValue
                kWInfromConsumption = [float]::NaN
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
                 #   if ($TelegramRec.kW -gt 4000) { $telegramrec.StressMark = $true }
                    }

                } 




            # Convert the timedate field string of the telegram into time

            $TelegramTime = get-date -year ("20"+$timestamp.substring(0,2)) -month $timestamp.substring(2,2) -day $timestamp.substring(4,2) -hour $timestamp.Substring(6,2) -minute $timestamp.Substring(8,2)  -second $timestamp.Substring(10,2)  

            if ($TelegramPrevkWhInTime) {


                                  # we assume that time between the last two records were 10 seconds if the dates are less than 15 seconds apart.
                                  # for longer time periods we do not calculate power consumption from the two energy readings

                if ( ($TelegramTime.subtract($TelegramPrevkWhInTime)).totalseconds -lt 15 )   {

                    $TelegramRec.kWInfromConsumption = ( $TelegramRec.kWhIn - $TelegramPrevkWhIn ) * 360  # Assuming that each telegram is 10 seconds apart, calculating power from energy by deviding energy with time (1/360 hours)
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


            

    return 
    }



$i = 0


While ( $i -lt $fileBytes.Length) {

# skip any leading data before the start of the first full telegram.
$checksum = 0

    while ($FileBytes[$i] -ne $TelegramStartmarker ) {
        if ($i++ -ge $fileBytes.length) {

            break
            }
        }

    $TelegramStart =  $i

    $telegram =""

    while ($FileBytes[$i] -ne $TelegramEndmarker  ) {
    
        $checkSum = $ChecksumLookup[$checkSum -bxor $FileBytes[$i]] 

        $telegram += [char]$FileBytes[$i] 

            if ( $i++ -ge $fileBytes.length) {
            break

            }
   
        }

    if ( $i -ge $fileBytes.length) {
        break
        }



    $telegramEnd = $i
    $telegram += [char]$FileBytes[$i] 
    $checkSum = $ChecksumLookup[$checkSum -bxor $FileBytes[$i]] 

    if ($telegram -match $timePat ) {
    $timestamp = $Matches[1] 
        }


    $senderChecksDigits = [System.Text.Encoding]::ASCII.GetString($FileBytes[($telegramEnd+1) .. ($telegramEnd+4)])
    $nTelegrams++
    $FinalStat += $timestamp + "," 

    if ($checksum -eq [UInt16]::Parse($senderChecksDigits, [System.Globalization.NumberStyles]::HexNumber) ) { 
    


 
        $FinalStat +=  "True"  +    "`r`n"


    
        UpdateStats ($telegramStart, $telegramEnd)
    }

    else {
### fix trivial corruption in byte stream. E.g. a common error is the first byte of the telegram (/ or 47) arrives as 14 for some reason on the line.

            $nFalseTelegram ++
            $rateFalse = [math]::Round($nFalseTelegram / $nTelegrams *100 , 2)

            echo "Chksum error at $timestamp, rate of error: $rateFalse %"            

            $errorlog += $timestamp

            $pattern = '[\x00-\x09\x0B-\x0C\x0E-\x1F\x80-\xFE]'   # matches non-ASCII characters except CR, LF xFF which is legitimate in the custom text field of the telegram,
            $NoisyChars = $telegram | Select-String -Pattern $pattern -AllMatches | ForEach-Object { $_.Matches }      # select-string operates on all $telegram, not per line.
              
            foreach ($NChar in $NoisyChars) {
                Write-Host " Found non-ASCII character '$($NChar.Value)' at position $($NChar.Index)" 
                $errorlog += "," + $NChar.Index + "," +  [int]($NChar.Value[0])
                }
            $errorlog += "`r`n"


            $FinalStat +=  "False,"  +   $Noisychars.Length + "`r`n"  # +  $senderChksInt.ToChar(

            }


    

$i += 4
$telegramStart = $i

}

Remove-Variable -Name FileBytes


write-host $i



$outCSV = $inpLog + ".csv"
Out-File -FilePath $outCSV  -InputObject $FinalStat
echo "$nFalseTelegram checksums are false from $nTelegrams telegrams in $inpLog"

Out-File -FilePath ($inpLog + ".Noise.csv")  -InputObject $errorlog


$telegramRecords | Export-Csv -Path ($inpLog+"_semicolon.csv") -NoTypeInformation -UseCulture

$SummaryMax = "Maximum voltage: " + $maxV +  " on date " + $maxVtime.Substring(2,4) + " at " + $maxVtime.substring(6,4) + ".  Max current: " + $maxA + " A at " + $maxAtime.Substring(6,4) + " in log '"+ $inpLog +"'"
write-output $summaryMax

