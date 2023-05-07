
# Checksum testing


$filePath = "C:\Users\gabor\OneDrive\Dokumentumok\KocsagU\NapelemVillany\P1\Sample P1 meter putty - 20230428.log"
$DSMRstream = Get-Content $filePath

$index = 0

while ( ($DSMRstream[$index] -ne '!') -and ($index -lt $DSMRstream.Count ))  {

if ($DSMRstream[$index] -eq "/") {
    $chksum = 0
    $TelegramStart = $index
}

        $chksum = $chksum -bxor ( $DSMRstream[$index] )
        for ($i = 0; $i -lt 8; $i++) {
            if ($chksum -band 1) {
                $chksum = ($chksum -shr 1) -bxor 0xA001
            } else {
                $chksum = $chksum -shr 1
            }
        }



    
$index++
}

    $SenderChks = $DSMRstream[ $index .. ($index+3) ]


    try {
        $senderChksInt = [UInt64]::Parse($SenderChks, [System.Globalization.NumberStyles]::HexNumber)
       
    } catch {
        throw "Unreadable CRC."
    }

write-output "$chksum , $senderChks, $senderChksInt"
